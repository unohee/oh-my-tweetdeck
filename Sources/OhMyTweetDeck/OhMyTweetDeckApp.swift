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
        .commands {
            // ⌘N toggles the compose panel instead of opening a second deck.
            CommandGroup(replacing: .newItem) {
                Button("New Post") { model.composePanel.toggle() }
                    .keyboardShortcut("n", modifiers: [.command])
            }
        }

        Settings {
            SettingsView().environmentObject(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by the app model so quitting can flush the login cookies first.
    static var flushOnQuit: (@MainActor () async -> Void)?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let flush = Self.flushOnQuit else { return .terminateNow }
        Task { @MainActor in
            await flush()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare SwiftPM executable (swift run); harmless in the .app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
