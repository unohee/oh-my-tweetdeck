import Foundation

/// Headless self-test behind the app's `--smoke` launch argument.
///
/// It exercises the core logic a deployed build depends on, without opening a window, touching
/// the Keychain, or using the network, so CI and the post-deploy smoke check can prove a binary
/// works on a machine nobody is looking at.
public enum SmokeCheck {
    /// Runs every check and returns the failures; an empty array means the build is healthy.
    public static func run() -> [String] {
        var failures: [String] = []
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { failures.append(message) }
        }

        // Column layout persistence: save and reload through a throwaway directory.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("omt-smoke-\(UUID().uuidString)", isDirectory: true)
        let store = ColumnStore(fileURL: dir.appendingPathComponent("columns.json"))
        let columns = [Column(service: .threads, feed: Feed(title: "Activity", path: "/activity"), width: 420)]
        do {
            try store.save(columns)
            expect(store.load() == columns, "column store did not round-trip")
        } catch {
            failures.append("column store save failed: \(error)")
        }
        try? FileManager.default.removeItem(at: dir)
        expect(Column.defaultDeck.map(\.service) == Service.allCases, "default deck is not one column per service")

        // Per-service length counting.
        expect(TextMetrics.length(of: "안녕", for: .x) == 4, "X weighted length for Hangul is wrong")
        expect(TextMetrics.length(of: "https://example.com/a/b/c", for: .x) == 23, "X URL weight is wrong")
        expect(TextMetrics.length(of: "hi👍", for: .threads) == 6, "Threads emoji byte counting is wrong")

        // Draft validation and the X intent URL.
        let draft = PostDraft(text: "hello", targets: Set(Service.allCases))
        expect(DraftValidator.problems(draft, for: .instagram) == [.imageRequired], "Instagram must require an image")
        expect(DraftValidator.problems(draft, for: .x).isEmpty, "X text draft should be valid")
        expect(XWebIntent.composeURL(text: "a+b").absoluteString.contains("%2B"), "X intent URL does not encode '+'")

        return failures
    }
}
