import Foundation

/// Result of a successful publish.
public struct PublishReceipt: Equatable, Sendable {
    public var service: Service
    /// Platform media/post id, when the route returns one.
    public var postID: String?
}

/// Sends a draft to one service.
public protocol Publisher: Sendable {
    var service: Service { get }
    func publish(_ draft: PostDraft) async throws -> PublishReceipt
}

public enum PublishError: Error, Equatable, CustomStringConvertible {
    case invalid([DraftProblem])
    case notConfigured(String)
    case containerFailed(String)
    case containerTimedOut
    case cancelled

    public var description: String {
        switch self {
        case .invalid(let problems): return problems.map(\.description).joined(separator: ", ")
        case .notConfigured(let what): return "Not configured: \(what)"
        case .containerFailed(let status): return "Media container failed: \(status)"
        case .containerTimedOut: return "Media container was not ready in time"
        case .cancelled: return "Cancelled"
        }
    }
}

/// Polling policy for Graph API media containers, injectable so tests do not sleep.
public struct ContainerPolling: Sendable {
    public var interval: Duration
    public var maxAttempts: Int
    public var sleep: @Sendable (Duration) async throws -> Void

    public init(interval: Duration = .seconds(2), maxAttempts: Int = 30,
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.interval = interval
        self.maxAttempts = maxAttempts
        self.sleep = sleep
    }
}

// MARK: - Threads

/// Official Threads API: create a container, wait until it is FINISHED, then publish.
/// Docs: https://developers.facebook.com/docs/threads/posts
public struct ThreadsPublisher: Publisher {
    public let service = Service.threads
    let userID: String
    let client: GraphClient
    let polling: ContainerPolling

    public static let defaultBase = URL(string: "https://graph.threads.com/v1.0")!

    public init(userID: String, accessToken: String, transport: HTTPTransport = URLSession.shared,
                base: URL = ThreadsPublisher.defaultBase, polling: ContainerPolling = .init()) {
        self.userID = userID
        self.client = GraphClient(base: base, accessToken: accessToken, transport: transport)
        self.polling = polling
    }

    public func publish(_ draft: PostDraft) async throws -> PublishReceipt {
        let problems = DraftValidator.problems(draft, for: .threads)
        guard problems.isEmpty else { throw PublishError.invalid(problems) }

        var form: [String: String] = [:]
        if !draft.text.isEmpty { form["text"] = draft.text }
        if let image = draft.imageURL {
            form["media_type"] = "IMAGE"
            form["image_url"] = image.absoluteString
        } else {
            form["media_type"] = "TEXT"
        }
        let container = try await client.post("\(userID)/threads", form: form)
        guard let containerID = container["id"] as? String else {
            throw PublishError.containerFailed("no container id")
        }
        try await waitUntilFinished(containerID)
        let published = try await client.post("\(userID)/threads_publish", form: ["creation_id": containerID])
        return PublishReceipt(service: .threads, postID: published["id"] as? String)
    }

    private func waitUntilFinished(_ containerID: String) async throws {
        for attempt in 0..<polling.maxAttempts {
            let status = try await client.get(containerID, query: ["fields": "status,error_message"])
            switch status["status"] as? String {
            case "FINISHED": return
            case "ERROR", "EXPIRED":
                throw PublishError.containerFailed(
                    (status["error_message"] as? String) ?? (status["status"] as? String ?? "ERROR"))
            default:
                if attempt + 1 < polling.maxAttempts { try await polling.sleep(polling.interval) }
            }
        }
        throw PublishError.containerTimedOut
    }
}

// MARK: - Instagram

/// Instagram API with Instagram Login (professional accounts only). Image posts only:
/// the image must be a public JPEG URL that Meta fetches.
/// Docs: https://developers.facebook.com/docs/instagram-platform/content-publishing
public struct InstagramPublisher: Publisher {
    public let service = Service.instagram
    let userID: String
    let client: GraphClient
    let polling: ContainerPolling

    public static let defaultBase = URL(string: "https://graph.instagram.com/v23.0")!

    public init(userID: String, accessToken: String, transport: HTTPTransport = URLSession.shared,
                base: URL = InstagramPublisher.defaultBase, polling: ContainerPolling = .init()) {
        self.userID = userID
        self.client = GraphClient(base: base, accessToken: accessToken, transport: transport)
        self.polling = polling
    }

    public func publish(_ draft: PostDraft) async throws -> PublishReceipt {
        let problems = DraftValidator.problems(draft, for: .instagram)
        guard problems.isEmpty, let image = draft.imageURL else { throw PublishError.invalid(problems) }

        let container = try await client.post(
            "\(userID)/media", form: ["image_url": image.absoluteString, "caption": draft.text])
        guard let containerID = container["id"] as? String else {
            throw PublishError.containerFailed("no container id")
        }
        for attempt in 0..<polling.maxAttempts {
            let status = try await client.get(containerID, query: ["fields": "status_code"])
            let code = status["status_code"] as? String
            if code == "FINISHED" { break }
            if code == "ERROR" || code == "EXPIRED" { throw PublishError.containerFailed(code!) }
            if attempt + 1 == polling.maxAttempts { throw PublishError.containerTimedOut }
            try await polling.sleep(polling.interval)
        }
        let published = try await client.post("\(userID)/media_publish", form: ["creation_id": containerID])
        return PublishReceipt(service: .instagram, postID: published["id"] as? String)
    }
}

// MARK: - X

/// X has no free posting API, so the app posts through the user's logged-in x.com session:
/// it opens the web intent composer prefilled with the text, and x.com's own scripts send
/// the request (including the signed transaction header). This type only builds the URL
/// and the in-page scripts; the app drives them in a visible web view.
public enum XWebIntent {
    public static func composeURL(text: String) -> URL {
        var components = URLComponents(string: "https://x.com/intent/post")!
        components.queryItems = [URLQueryItem(name: "text", value: text)]
        // URLComponents leaves '+' and '&'-safe chars; encode '+' so x.com does not read it as space.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }

    /// Selectors for the composer's send button. Read from the live DOM; x.com changes them,
    /// so the app treats "not found" as "let the user click it".
    public static let sendButtonSelectors = [
        "[data-testid=\"tweetButton\"]",
        "[data-testid=\"tweetButtonInline\"]",
    ]

    /// JS returning "ready" when the send button exists and is enabled, "disabled" when it
    /// exists but is disabled, "missing" otherwise.
    public static var probeScript: String {
        """
        (() => {
          const sels = \(jsArrayLiteral(sendButtonSelectors));
          for (const s of sels) {
            const b = document.querySelector(s);
            if (b) return (b.disabled || b.getAttribute('aria-disabled') === 'true') ? 'disabled' : 'ready';
          }
          return 'missing';
        })()
        """
    }

    /// JS that clicks the send button. Returns true when a button was clicked.
    public static var clickScript: String {
        """
        (() => {
          const sels = \(jsArrayLiteral(sendButtonSelectors));
          for (const s of sels) {
            const b = document.querySelector(s);
            if (b && !b.disabled && b.getAttribute('aria-disabled') !== 'true') { b.click(); return true; }
          }
          return false;
        })()
        """
    }

    /// Encodes strings as a JS array literal via JSON, so quotes and newlines cannot break out.
    static func jsArrayLiteral(_ values: [String]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: values)
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Fan-out

/// Outcome of a cross-post for one service.
public enum PostOutcome: Sendable {
    case posted(PublishReceipt)
    case failed(String)
}

/// Sends one draft to several publishers concurrently. A failure on one service never
/// blocks the others; every target gets an outcome.
public struct CrossPoster: Sendable {
    public init() {}

    public func post(_ draft: PostDraft, using publishers: [Publisher]) async -> [Service: PostOutcome] {
        let selected = publishers.filter { draft.targets.contains($0.service) }
        var outcomes: [Service: PostOutcome] = [:]
        for missing in draft.targets.subtracting(selected.map(\.service)) {
            outcomes[missing] = .failed(PublishError.notConfigured(missing.displayName).description)
        }
        await withTaskGroup(of: (Service, PostOutcome).self) { group in
            for publisher in selected {
                group.addTask {
                    do {
                        return (publisher.service, .posted(try await publisher.publish(draft)))
                    } catch {
                        return (publisher.service, .failed(String(describing: error)))
                    }
                }
            }
            for await (service, outcome) in group { outcomes[service] = outcome }
        }
        return outcomes
    }
}
