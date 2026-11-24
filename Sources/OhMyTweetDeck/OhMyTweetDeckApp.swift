import AppKit
import Foundation
import OhMyTweetDeckCore
import SwiftUI

/// Entry point. `--smoke` runs the headless self-test and exits before NSApplication starts,
/// so it works in CI and over SSH; any other launch starts the SwiftUI app.
@main
enum Main {
    static func main() {
        if CommandLine.arguments.contains("--smoke") {
            exit(runSmoke())
        }
        OhMyTweetDeckApp.main()
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private static func runSmoke() -> Int32 {
        let failures = SmokeCheck.run()
        guard failures.isEmpty else {
            for failure in failures {
                FileHandle.standardError.write(Data("smoke FAIL: \(failure)\n".utf8))
            }
            print("OhMyTweetDeck \(version) smoke failed (\(failures.count))")
            return 1
        }
        print("OhMyTweetDeck \(version) smoke ok")
        return 0
    }
}

struct OhMyTweetDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Oh My TweetDeck") {
            DeckView()
                .environmentObject(model)
                .frame(minWidth: 800, minHeight: 500)
        }
        .defaultSize(width: 1500, height: 900)
        .windowToolbarStyle(.unifiedCompact)

        Settings {
            SettingsView().environmentObject(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare SwiftPM executable (swift run); harmless in the .app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
