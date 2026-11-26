import Foundation

/// What the user wants to send, before it is fanned out to each service.
public struct PostDraft: Equatable, Sendable {
    public var text: String
    /// Publicly reachable image URL. Instagram and Threads' Graph APIs fetch the image
    /// themselves, so a local file cannot be sent directly.
    public var imageURL: URL?
    /// Local image file. X gets the file itself; Threads and Instagram get it through the
    /// user's object storage (uploaded just before posting, then `imageURL` is set).
    public var attachment: URL?
    public var targets: Set<Service>

    public init(text: String, imageURL: URL? = nil, attachment: URL? = nil, targets: Set<Service>) {
        self.text = text
        self.imageURL = imageURL
        self.attachment = attachment
        self.targets = targets
    }

    /// True when the draft carries an image in either form.
    public var hasImage: Bool { imageURL != nil || attachment != nil }
}

/// Why a draft cannot go to a given service. Checked before any network call.
public enum DraftProblem: Equatable, Sendable, CustomStringConvertible {
    case empty
    case tooLong(over: Int)
    case imageRequired
    case imageMustBeHTTPS
    case imageStorageMissing
    case notPostable

    public var description: String {
        switch self {
        case .empty: return "Nothing to post"
        case .tooLong(let over): return "\(over) over the limit"
        case .imageRequired: return "Needs a public image URL"
        case .imageMustBeHTTPS: return "Image URL must be https"
        case .imageStorageMissing: return "Set up image storage in Accounts to send a file here"
        case .notPostable: return "Watch-only service"
        }
    }
}

public enum DraftValidator {
    /// Problems that block posting `draft` to `service`. Empty means OK.
    /// `canUpload`: object storage is configured, so a local attachment can become a public URL.
    public static func problems(_ draft: PostDraft, for service: Service, canUpload: Bool = true) -> [DraftProblem] {
        guard service.isPostTarget else { return [.notPostable] }
        var problems: [DraftProblem] = []
        let trimmed = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let remaining = TextMetrics.remaining(draft.text, for: service)
        if remaining < 0 { problems.append(.tooLong(over: -remaining)) }

        if let url = draft.imageURL, url.scheme?.lowercased() != "https" {
            problems.append(.imageMustBeHTTPS)
        }
        // Graph API services need a URL; a file alone only works if it can be uploaded.
        let needsUpload = service != .x && draft.imageURL == nil && draft.attachment != nil
        if needsUpload && !canUpload { problems.append(.imageStorageMissing) }
        switch service {
        case .instagram:
            if !draft.hasImage { problems.append(.imageRequired) }
        case .x:
            if trimmed.isEmpty && draft.attachment == nil { problems.append(.empty) }
        case .threads:
            if trimmed.isEmpty && !draft.hasImage { problems.append(.empty) }
        case .youtube:
            break  // unreachable: rejected above
        }
        return problems
    }

    /// Non-blocking caveats shown next to a target, e.g. parts of the draft it will drop.
    public static func notes(_ draft: PostDraft, for service: Service) -> [String] {
        // X attaches local files only; a URL-only image is not fetched there.
        if service == .x && draft.imageURL != nil && draft.attachment == nil {
            return ["Text only — attach a file to include the image on X"]
        }
        return []
    }
}
