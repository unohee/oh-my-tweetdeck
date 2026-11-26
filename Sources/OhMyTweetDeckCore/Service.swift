import Foundation

/// A site the deck can show columns for. Only `postTargets` can be cross-posted to;
/// YouTube is watch-only.
public enum Service: String, Codable, CaseIterable, Identifiable, Sendable {
    case x
    case threads
    case instagram
    case youtube

    /// Services the composer posts to.
    public static let postTargets: [Service] = [.x, .threads, .instagram]

    public var isPostTarget: Bool { Self.postTargets.contains(self) }

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .x: return "X"
        case .threads: return "Threads"
        case .instagram: return "Instagram"
        case .youtube: return "YouTube"
        }
    }

    /// Web origin loaded by columns of this service.
    public var origin: URL {
        switch self {
        case .x: return URL(string: "https://x.com")!
        case .threads: return URL(string: "https://www.threads.com")!
        case .instagram: return URL(string: "https://www.instagram.com")!
        case .youtube: return URL(string: "https://www.youtube.com")!
        }
    }

    /// Accent color as 0xRRGGBB, used for column headers and composer toggles.
    public var accentRGB: UInt32 {
        switch self {
        case .x: return 0x1D9BF0
        case .threads: return 0x8E8E93
        case .instagram: return 0xE1306C
        case .youtube: return 0xFF0033
        }
    }

    /// Feed presets offered when adding a column. Any other page can be added as a custom path.
    public var feedPresets: [Feed] {
        switch self {
        case .x:
            return [
                Feed(title: "Home", path: "/home"),
                Feed(title: "Notifications", path: "/notifications"),
                Feed(title: "Explore", path: "/explore"),
                Feed(title: "Messages", path: "/messages"),
            ]
        case .threads:
            return [
                Feed(title: "Home", path: "/"),
                Feed(title: "Activity", path: "/activity"),
                Feed(title: "Search", path: "/search"),
            ]
        case .instagram:
            return [
                Feed(title: "Home", path: "/"),
                Feed(title: "Explore", path: "/explore/"),
                Feed(title: "Reels", path: "/reels/"),
                Feed(title: "Direct", path: "/direct/inbox/"),
            ]
        case .youtube:
            return [
                Feed(title: "Home", path: "/"),
                Feed(title: "Subscriptions", path: "/feed/subscriptions"),
                Feed(title: "Shorts", path: "/shorts"),
                Feed(title: "Watch later", path: "/playlist?list=WL"),
                Feed(title: "History", path: "/feed/history"),
            ]
        }
    }

    /// Whether a post to this service needs an image (Instagram has no text-only posts).
    public var requiresImage: Bool { self == .instagram }

    /// Maximum post length in this service's own counting unit (see `TextMetrics`).
    /// Zero for watch-only services.
    public var maxLength: Int {
        switch self {
        case .x: return 280
        case .threads: return 500
        case .instagram: return 2200
        case .youtube: return 0
        }
    }
}

/// A page shown by a column: a title and a path on the service origin
/// (e.g. `/home`, `/search?q=swift`, `/@someone`).
public struct Feed: Codable, Hashable, Sendable {
    public var title: String
    public var path: String

    public init(title: String, path: String) {
        self.title = title
        self.path = path.hasPrefix("/") ? path : "/" + path
    }
}
