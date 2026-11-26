import Foundation

/// One deck column: a service page rendered in its own web view.
public struct Column: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var service: Service
    public var feed: Feed
    /// Stored width in points. Kept for saved decks; the deck now shares the window
    /// width equally (see `DeckLayout`).
    public var width: Double

    public static let widthRange: ClosedRange<Double> = 300...700
    public static let defaultWidth: Double = 380

    public init(id: UUID = UUID(), service: Service, feed: Feed, width: Double = Column.defaultWidth) {
        self.id = id
        self.service = service
        self.feed = feed
        self.width = min(max(width, Column.widthRange.lowerBound), Column.widthRange.upperBound)
    }

    /// Absolute URL the column loads.
    public var url: URL {
        // Feed.path may contain a query string, so resolve relative to the origin.
        URL(string: feed.path, relativeTo: service.origin)!.absoluteURL
    }

    /// The deck a first launch starts with: home of every service side by side.
    public static var defaultDeck: [Column] {
        Service.postTargets.map { Column(service: $0, feed: $0.feedPresets[0]) }
    }
}

/// Persists the column layout as JSON. Reads never throw: a missing or corrupt file
/// yields the default deck so the app always starts.
public struct ColumnStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `~/Library/Application Support/<bundle id>/columns.json`.
    public static func standard(bundleID: String) -> ColumnStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ColumnStore(fileURL: base.appendingPathComponent(bundleID).appendingPathComponent("columns.json"))
    }

    public func load() -> [Column] {
        guard let data = try? Data(contentsOf: fileURL),
              let columns = try? JSONDecoder().decode([Column].self, from: data),
              !columns.isEmpty
        else { return Column.defaultDeck }
        return columns
    }

    public func save(_ columns: [Column]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Atomic write so a crash mid-save cannot leave a truncated layout.
        try encoder.encode(columns).write(to: fileURL, options: .atomic)
    }
}

/// How the deck splits the window between its columns.
public enum DeckLayout {
    /// Narrowest a column gets before the deck scrolls sideways instead of shrinking it.
    public static let minColumnWidth: Double = 300

    /// Columns share `available` equally; below `minColumnWidth` each they keep that width
    /// and the deck scrolls.
    public static func columnWidth(available: Double, count: Int, spacing: Double = 1,
                                   minWidth: Double = minColumnWidth) -> Double {
        guard count > 0 else { return minWidth }
        let share = (available - spacing * Double(count - 1)) / Double(count)
        return max(minWidth, share.rounded(.down))
    }
}
