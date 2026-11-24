import AppKit
import SwiftUI

@main
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
