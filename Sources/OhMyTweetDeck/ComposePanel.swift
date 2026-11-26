import AppKit
import SwiftUI

/// Borderless panel that still takes keyboard focus (borderless windows refuse key by default).
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Esc hides the panel (the draft stays in the model).
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    var onCancel: (() -> Void)?
}

/// Spotlight-style translucent compose panel, docked at the bottom centre of the deck window
/// (Figma: "Compose panel (⌘N) — Spotlight style", 771×187, 29 pt above the window bottom).
@MainActor
final class ComposePanelController {
    static let size = NSSize(width: 771, height: 187)
    static let bottomInset: CGFloat = 29
    static let cornerRadius: CGFloat = 22

    private let model: AppModel
    private var panel: KeyablePanel?

    init(model: AppModel) {
        self.model = model
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if let panel, panel.isVisible, panel.isKeyWindow { hide() } else { show() }
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if let deck = deckWindow() {
            if panel.parent !== deck {
                panel.parent?.removeChildWindow(panel)
                deck.addChildWindow(panel, ordered: .above)  // moves with the deck window
            }
            panel.setFrame(frame(in: deck), display: false)
        } else {
            panel.center()
        }
        panel.makeKeyAndOrderFront(nil)
        model.composeFocusRequest += 1
    }

    func hide() {
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        panel.parent.map { $0.makeKey() } ?? deckWindow()?.makeKey()
    }

    private func frame(in deck: NSWindow) -> NSRect {
        let d = deck.frame
        let w = min(Self.size.width, d.width - 32)
        return NSRect(x: (d.midX - w / 2).rounded(), y: d.minY + Self.bottomInset, width: w, height: Self.size.height)
    }

    /// The deck is the app's main window (the panel never becomes main).
    private func deckWindow() -> NSWindow? {
        NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible && !($0 is NSPanel) && $0.title == "Oh My TweetDeck" }
    }

    private func makePanel() -> KeyablePanel {
        let panel = KeyablePanel(contentRect: NSRect(origin: .zero, size: Self.size),
                                 styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                                 backing: .buffered, defer: true)
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.title = "New Post"
        panel.onCancel = { [weak self] in self?.hide() }

        let host = NSHostingView(rootView: ComposerView(onClose: { [weak self] in self?.hide() })
            .environmentObject(model))
        panel.contentView = Self.glass(around: host)
        return panel
    }
}

extension ComposePanelController {
    /// Liquid Glass (as Spotlight uses) on macOS 26+, a vibrant blur before that.
    fileprivate static func glass(around content: NSView) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.style = .regular
            glass.contentView = content
            return glass
        }
        let blur = NSVisualEffectView()
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = cornerRadius
        blur.layer?.cornerCurve = .continuous
        blur.layer?.masksToBounds = true
        blur.layer?.borderWidth = 1
        blur.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        content.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            content.topAnchor.constraint(equalTo: blur.topAnchor),
            content.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])
        return blur
    }
}
