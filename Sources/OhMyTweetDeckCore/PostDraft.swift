import Foundation

/// What the user wants to send, before it is fanned out to each service.
public struct PostDraft: Equatable, Sendable {
    public var text: String
    /// Publicly reachable image URL. Instagram and Threads' Graph APIs fetch the image
    /// themselves, so a local file cannot be sent directly.
    public var imageURL: URL?
    public var targets: Set<Service>

    public init(text: String, imageURL: URL? = nil, targets: Set<Service>) {
        self.text = text
        self.imageURL = imageURL
        self.targets = targets
    }
}

/// Why a draft cannot go to a given service. Checked before any network call.
public enum DraftProblem: Equatable, Sendable, CustomStringConvertible {
    case empty
    case tooLong(over: Int)
    case imageRequired
    case imageNotSupported
    case imageMustBeHTTPS

    public var description: String {
        switch self {
        case .empty: return "Nothing to post"
        case .tooLong(let over): return "\(over) over the limit"
        case .imageRequired: return "Needs a public image URL"
        case .imageNotSupported: return "Images are not sent via this route yet"
        case .imageMustBeHTTPS: return "Image URL must be https"
        }
    }
}

public enum DraftValidator {
    /// Problems that block posting `draft` to `service`. Empty means OK.
    public static func problems(_ draft: PostDraft, for service: Service) -> [DraftProblem] {
        var problems: [DraftProblem] = []
        let trimmed = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let remaining = TextMetrics.remaining(draft.text, for: service)
        if remaining < 0 { problems.append(.tooLong(over: -remaining)) }

        if let url = draft.imageURL, url.scheme?.lowercased() != "https" {
            problems.append(.imageMustBeHTTPS)
        }
        switch service {
        case .instagram:
            if draft.imageURL == nil { problems.append(.imageRequired) }
        case .x:
            // The web intent route only prefills text.
            if draft.imageURL != nil { problems.append(.imageNotSupported) }
            if trimmed.isEmpty { problems.append(.empty) }
        case .threads:
            if trimmed.isEmpty && draft.imageURL == nil { problems.append(.empty) }
        }
        return problems
    }
}
