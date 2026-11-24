import Foundation
import Testing
@testable import OhMyTweetDeckCore

// MARK: - Test doubles

/// Replays canned responses in order and records every request.
final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
    private var responses: [(Int, String)]
    private(set) var requests: [URLRequest] = []
    private let lock = NSLock()

    init(_ responses: [(Int, String)]) { self.responses = responses }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (status, body) = lock.withLock { () -> (Int, String) in
            requests.append(request)
            return responses.isEmpty ? (500, "{}") : responses.removeFirst()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

let noSleep = ContainerPolling(interval: .zero, maxAttempts: 3, sleep: { _ in })

func formBody(_ request: URLRequest) -> [String: String] {
    let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
    var result: [String: String] = [:]
    for pair in body.split(separator: "&") {
        let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
        result[kv[0].removingPercentEncoding!] = kv.count > 1 ? kv[1].removingPercentEncoding! : ""
    }
    return result
}

// MARK: - Columns

@Suite struct ColumnTests {
    @Test func defaultDeckHasOneHomeColumnPerService() {
        let deck = Column.defaultDeck
        #expect(deck.map(\.service) == Service.allCases)
        #expect(deck.map(\.url.absoluteString) == [
            "https://x.com/home", "https://www.threads.com/", "https://www.instagram.com/",
        ])
    }

    @Test func customPathKeepsQueryString() {
        let column = Column(service: .x, feed: Feed(title: "Swift", path: "search?q=swift&f=live"))
        #expect(column.url.absoluteString == "https://x.com/search?q=swift&f=live")
    }

    @Test func widthIsClamped() {
        #expect(Column(service: .x, feed: Feed(title: "a", path: "/"), width: 10).width == Column.widthRange.lowerBound)
        #expect(Column(service: .x, feed: Feed(title: "a", path: "/"), width: 9999).width == Column.widthRange.upperBound)
    }

    @Test func storeRoundTripsAndFallsBackOnCorruption() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ColumnStore(fileURL: dir.appendingPathComponent("columns.json"))
        #expect(store.load().count == Column.defaultDeck.count) // missing file

        let columns = [Column(service: .threads, feed: Feed(title: "Activity", path: "/activity"), width: 420)]
        try store.save(columns)
        #expect(store.load() == columns)

        try Data("not json".utf8).write(to: store.fileURL)
        #expect(store.load().map(\.service) == Service.allCases)
        try? FileManager.default.removeItem(at: dir)
    }
}

// MARK: - Text metrics & validation

@Suite struct TextMetricsTests {
    @Test func xWeightsLatinOneAndHangulTwo() {
        #expect(TextMetrics.length(of: "hello", for: .x) == 5)
        #expect(TextMetrics.length(of: "안녕", for: .x) == 4)
    }

    @Test func xCountsURLsAs23() {
        #expect(TextMetrics.length(of: "see https://example.com/a/very/long/path/indeed", for: .x) == 4 + 23)
    }

    @Test func xCountsEmojiAsTwo() {
        #expect(TextMetrics.length(of: "👍", for: .x) == 2)
        #expect(TextMetrics.length(of: "👨‍👩‍👧", for: .x) == 2)
        #expect(TextMetrics.length(of: "#1", for: .x) == 2) // '#' and '1' are not emoji here
    }

    @Test func threadsCountsEmojiAsUTF8Bytes() {
        #expect(TextMetrics.length(of: "hi", for: .threads) == 2)
        #expect(TextMetrics.length(of: "hi👍", for: .threads) == 2 + 4)
        #expect(TextMetrics.length(of: "안녕", for: .threads) == 2)
    }

    @Test func instagramNeedsImageAndXIgnoresIt() {
        let textOnly = PostDraft(text: "hello", targets: [.x, .threads, .instagram])
        #expect(DraftValidator.problems(textOnly, for: .instagram) == [.imageRequired])
        #expect(DraftValidator.problems(textOnly, for: .x).isEmpty)
        #expect(DraftValidator.problems(textOnly, for: .threads).isEmpty)

        let withImage = PostDraft(text: "hello", imageURL: URL(string: "https://cdn.example.com/a.jpg"), targets: [.x])
        #expect(DraftValidator.problems(withImage, for: .x).isEmpty)
        #expect(DraftValidator.notes(withImage, for: .x).count == 1)
        #expect(DraftValidator.problems(withImage, for: .instagram).isEmpty)
    }

    @Test func oneDraftWithTextAndImageIsPostableEverywhere() {
        let draft = PostDraft(text: "hello deck", imageURL: URL(string: "https://cdn.example.com/a.jpg"),
                              targets: Set(Service.allCases))
        for service in Service.allCases {
            #expect(DraftValidator.problems(draft, for: service).isEmpty, "\(service)")
        }
    }

    @Test func overLimitAndNonHTTPSAreReported() {
        let long = PostDraft(text: String(repeating: "a", count: 281), targets: [.x])
        #expect(DraftValidator.problems(long, for: .x) == [.tooLong(over: 1)])
        let http = PostDraft(text: "x", imageURL: URL(string: "http://a.com/b.jpg"), targets: [.instagram])
        #expect(DraftValidator.problems(http, for: .instagram) == [.imageMustBeHTTPS])
    }
}

// MARK: - Publishers (no network)

@Suite struct PublisherTests {
    @Test func threadsTextPostCreatesPollsAndPublishes() async throws {
        let transport = ScriptedTransport([
            (200, #"{"id":"C1"}"#),
            (200, #"{"status":"IN_PROGRESS"}"#),
            (200, #"{"status":"FINISHED"}"#),
            (200, #"{"id":"P1"}"#),
        ])
        let publisher = ThreadsPublisher(userID: "U1", accessToken: "tok", transport: transport, polling: noSleep)
        let receipt = try await publisher.publish(PostDraft(text: "a+b & c=d 안녕", targets: [.threads]))

        #expect(receipt == PublishReceipt(service: .threads, postID: "P1"))
        let r = transport.requests
        #expect(r.count == 4)
        #expect(r[0].url!.absoluteString == "https://graph.threads.com/v1.0/U1/threads")
        #expect(r[0].httpMethod == "POST")
        #expect(formBody(r[0]) == ["media_type": "TEXT", "text": "a+b & c=d 안녕"])
        #expect(r[0].value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(!(r[0].url!.absoluteString.contains("tok")))
        #expect(r[1].url!.absoluteString == "https://graph.threads.com/v1.0/C1?fields=status,error_message")
        #expect(r[3].url!.absoluteString == "https://graph.threads.com/v1.0/U1/threads_publish")
        #expect(formBody(r[3]) == ["creation_id": "C1"])
    }

    @Test func threadsContainerErrorSurfacesMessage() async {
        let transport = ScriptedTransport([
            (200, #"{"id":"C1"}"#),
            (200, #"{"status":"ERROR","error_message":"FAILED_DOWNLOADING_IMAGE"}"#),
        ])
        let publisher = ThreadsPublisher(userID: "U1", accessToken: "t", transport: transport, polling: noSleep)
        await #expect(throws: PublishError.containerFailed("FAILED_DOWNLOADING_IMAGE")) {
            try await publisher.publish(PostDraft(text: "x", targets: [.threads]))
        }
    }

    @Test func graphErrorIsDecoded() async {
        let transport = ScriptedTransport([(400, #"{"error":{"message":"Invalid OAuth access token","code":190}}"#)])
        let publisher = ThreadsPublisher(userID: "U1", accessToken: "t", transport: transport, polling: noSleep)
        await #expect(throws: GraphAPIError(status: 400, message: "Invalid OAuth access token", code: 190)) {
            try await publisher.publish(PostDraft(text: "x", targets: [.threads]))
        }
    }

    @Test func instagramImagePostFlow() async throws {
        let transport = ScriptedTransport([
            (200, #"{"id":"C9"}"#),
            (200, #"{"status_code":"FINISHED"}"#),
            (200, #"{"id":"M9"}"#),
        ])
        let publisher = InstagramPublisher(userID: "IG1", accessToken: "t", transport: transport, polling: noSleep)
        let draft = PostDraft(text: "caption", imageURL: URL(string: "https://cdn.example.com/p.jpg"), targets: [.instagram])
        let receipt = try await publisher.publish(draft)

        #expect(receipt.postID == "M9")
        let r = transport.requests
        #expect(r[0].url!.absoluteString == "https://graph.instagram.com/v23.0/IG1/media")
        #expect(formBody(r[0]) == ["image_url": "https://cdn.example.com/p.jpg", "caption": "caption"])
        #expect(r[2].url!.absoluteString == "https://graph.instagram.com/v23.0/IG1/media_publish")
    }

    @Test func instagramRejectsTextOnlyWithoutNetwork() async {
        let transport = ScriptedTransport([])
        let publisher = InstagramPublisher(userID: "IG1", accessToken: "t", transport: transport, polling: noSleep)
        await #expect(throws: PublishError.invalid([.imageRequired])) {
            try await publisher.publish(PostDraft(text: "hi", targets: [.instagram]))
        }
        #expect(transport.requests.isEmpty)
    }

    @Test func instagramContainerTimesOut() async {
        let transport = ScriptedTransport([
            (200, #"{"id":"C"}"#),
            (200, #"{"status_code":"IN_PROGRESS"}"#),
            (200, #"{"status_code":"IN_PROGRESS"}"#),
            (200, #"{"status_code":"IN_PROGRESS"}"#),
        ])
        let publisher = InstagramPublisher(userID: "IG1", accessToken: "t", transport: transport, polling: noSleep)
        let draft = PostDraft(text: "", imageURL: URL(string: "https://a.com/p.jpg"), targets: [.instagram])
        await #expect(throws: PublishError.containerTimedOut) { try await publisher.publish(draft) }
    }
}

// MARK: - X intent & fan-out

@Suite struct XIntentTests {
    @Test func composeURLEncodesReservedCharacters() {
        let url = XWebIntent.composeURL(text: "a+b & c=d #tag 안녕\nline2")
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        #expect(url.host == "x.com" && url.path == "/intent/post")
        #expect(comps.queryItems?.first?.value == "a+b & c=d #tag 안녕\nline2")
        #expect(url.absoluteString.contains("%2B"))
    }

    @Test func draftScriptEscapesAndNormalizesNeedle() {
        let script = XWebIntent.draftPresentScript(text: "  he said \"hi\"\n</script>  and   more ")
        #expect(script.contains(#"["he said \"hi\" <\/script> and more"]"#))
    }

    @Test func scriptsEmbedSelectorsAsJSON() {
        #expect(XWebIntent.clickScript.contains(#"[data-testid=\"tweetButton\"]"#))
        #expect(XWebIntent.jsArrayLiteral(["a\"b", "c\nd"]) == #"["a\"b","c\nd"]"#)
    }
}

struct StubPublisher: Publisher {
    let service: Service
    let fails: Bool
    func publish(_ draft: PostDraft) async throws -> PublishReceipt {
        if fails { throw PublishError.containerFailed("boom") }
        return PublishReceipt(service: service, postID: "id-\(service.rawValue)")
    }
}

@Suite struct CrossPosterTests {
    @Test func oneFailureDoesNotBlockOthersAndMissingIsReported() async {
        let draft = PostDraft(text: "hi", targets: [.x, .threads, .instagram])
        let outcomes = await CrossPoster().post(draft, using: [
            StubPublisher(service: .threads, fails: false),
            StubPublisher(service: .instagram, fails: true),
        ])
        guard case .posted(let receipt) = outcomes[.threads] else { Issue.record("threads"); return }
        #expect(receipt.postID == "id-threads")
        guard case .failed(let message) = outcomes[.instagram] else { Issue.record("ig"); return }
        #expect(message.contains("boom"))
        guard case .failed(let missing) = outcomes[.x] else { Issue.record("x"); return }
        #expect(missing.contains("Not configured"))
    }

    @Test func untargetedPublishersAreNotCalled() async {
        let outcomes = await CrossPoster().post(
            PostDraft(text: "hi", targets: [.threads]),
            using: [StubPublisher(service: .threads, fails: false), StubPublisher(service: .instagram, fails: true)])
        #expect(outcomes.keys.sorted { $0.rawValue < $1.rawValue } == [.threads])
    }

    @Test func inMemoryStoreBuildsOnlyCompletePublishers() {
        let store = InMemoryCredentialStore([.threadsUserID: "1", .threadsAccessToken: "t", .instagramUserID: "2"])
        #expect(store.configuredAPIPublishers().map(\.service) == [.threads])
    }
}

// MARK: - Smoke

@Suite struct SmokeCheckTests {
    @Test func smokeCheckPassesOnAHealthyBuild() {
        #expect(SmokeCheck.run().isEmpty)
    }
}
