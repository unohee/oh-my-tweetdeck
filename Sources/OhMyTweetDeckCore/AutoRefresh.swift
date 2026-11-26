import Foundation

/// Periodic feed refresh. Reloading a web feed throws away the reader's scroll position and
/// anything typed into the page, so a column is reloaded only when it is due *and* idle:
/// on its home page, scrolled to the top, nothing typed, no media playing, no dialog open.
/// A column that is busy is simply checked again on the next tick.
public enum AutoRefresh {
    /// Choices offered in the deck toolbar, in seconds. 0 turns auto-refresh off.
    public static let intervals: [Int] = [0, 60, 120, 300, 600, 900]
    public static let defaultInterval = 300
    /// UserDefaults key holding the interval in seconds.
    public static let defaultsKey = "autoRefreshSeconds"
    /// How often the deck checks which columns are due.
    public static let tick: TimeInterval = 30
    /// A load finishes a moment after the tick that started it, so without some slack a
    /// 60 s interval would only come due on the tick after next (90 s).
    public static let dueSlack: TimeInterval = 5
    /// Scrolled further down than this (points) means the user is reading: wait.
    public static let topSlack: Double = 120

    public static func label(_ seconds: Int) -> String {
        if seconds <= 0 { return "Off" }
        if seconds < 60 { return "Every \(seconds) s" }
        let minutes = seconds / 60
        return minutes == 1 ? "Every minute" : "Every \(minutes) min"
    }

    /// Interval stored in `defaults`, or the default when it was never set. `integer(forKey:)`
    /// also parses the string a `-autoRefreshSeconds 60` launch argument puts there.
    public static func interval(in defaults: UserDefaults) -> Int {
        defaults.object(forKey: defaultsKey) == nil ? defaultInterval : defaults.integer(forKey: defaultsKey)
    }

    /// What the probe script reports about a page.
    public struct PageState: Codable, Equatable, Sendable {
        /// Largest scroll offset of the window or the page's main region, in points.
        public var scrollTop: Double
        /// Focus is in a text field, or an editor holds unsent text.
        public var editing: Bool
        /// A video or audio element is playing with sound. Feeds autoplay muted clips; those
        /// do not count, or a clip at the top of the feed would block refreshes forever.
        public var playing: Bool
        /// A modal dialog (composer, photo viewer, menu sheet) is open.
        public var modal: Bool

        public init(scrollTop: Double = 0, editing: Bool = false, playing: Bool = false, modal: Bool = false) {
            self.scrollTop = scrollTop
            self.editing = editing
            self.playing = playing
            self.modal = modal
        }

        /// Decodes the JSON string the probe script returns; nil when it is not one.
        public static func decode(_ json: String?) -> PageState? {
            guard let json else { return nil }
            return try? JSONDecoder().decode(PageState.self, from: Data(json.utf8))
        }
    }

    public enum Decision: Equatable, Sendable {
        case refresh
        case off, notDue, loading, awayFromHome, unknownPage, scrolled, editing, playing, modal
    }

    /// Whether a column may be reloaded now. Cheap checks come first so the page is probed
    /// only for due columns; pass `page: nil` to ask "is it due?" before probing.
    public static func decide(interval: Int, lastLoad: Date?, now: Date, isLoading: Bool,
                              current: URL?, home: URL, page: PageState?) -> Decision {
        guard interval > 0 else { return .off }
        if let lastLoad, now.timeIntervalSince(lastLoad) < Double(interval) - dueSlack { return .notDue }
        if isLoading { return .loading }
        if let current, !isHome(current, home: home) { return .awayFromHome }
        guard let page else { return .unknownPage }
        if page.editing { return .editing }
        if page.modal { return .modal }
        if page.playing { return .playing }
        if page.scrollTop > topSlack { return .scrolled }
        return .refresh
    }

    /// True when `url` is the column's home page. Paths compare without a trailing slash;
    /// the query counts only when the home URL has one (a search column), so tracking
    /// parameters a site appends do not stop the refresh.
    public static func isHome(_ url: URL, home: URL) -> Bool {
        func path(_ u: URL) -> String {
            let p = u.path
            return p.count > 1 && p.hasSuffix("/") ? String(p.dropLast()) : (p.isEmpty ? "/" : p)
        }
        guard path(url) == path(home) else { return false }
        guard let query = home.query, !query.isEmpty else { return true }
        return url.query == query
    }

    /// Returns a JSON string decodable as `PageState`.
    public static let probeScript = """
    (() => {
      const main = Array.from(document.querySelectorAll('main, [role="main"]'), e => e.scrollTop);
      const scrollTop = Math.max(window.scrollY || 0, document.scrollingElement ? document.scrollingElement.scrollTop : 0, ...main);
      const a = document.activeElement;
      const focused = !!a && (a.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(a.tagName));
      const draft = Array.from(document.querySelectorAll('textarea, [contenteditable="true"]'))
        .find(e => ((e.value !== undefined ? e.value : e.innerText) || '').trim().length > 0);
      const drafts = !!draft;
      const tag = e => e ? e.tagName + '[' + (e.getAttribute('aria-label') || e.getAttribute('name') || e.id || '') + ']' : '';
      const playing = Array.from(document.querySelectorAll('video, audio'))
        .some(m => !m.paused && !m.ended && !m.muted && m.volume > 0);
      const modal = !!document.querySelector('[aria-modal="true"], dialog[open]');
      // `why` is for debug logs only; PageState ignores it.
      const why = (focused ? 'focus ' + tag(a) + ' ' : '') + (drafts ? 'draft ' + tag(draft) : '');
      return JSON.stringify({ scrollTop, editing: focused || drafts, playing, modal, why });
    })()
    """
}
