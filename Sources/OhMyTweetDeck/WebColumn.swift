import AppKit
import OhMyTweetDeckCore
import SwiftUI
import WebKit

/// Desktop Safari UA. Measured 2026-11-24: with it all three sites render their responsive
/// narrow layout without "open the app" interstitials (the iPhone UA adds them).
let deckUserAgent =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15"

/// Owns one WKWebView per column so SwiftUI re-renders never reload a feed, and so every
/// web view shares the default (persistent) data store: logging in once per service is enough.
@MainActor
final class WebViewPool: NSObject, WKUIDelegate, WKNavigationDelegate {
    private var views: [UUID: WKWebView] = [:]
    let vault = CookieVault()
    private var pendingLoads: [UUID: URL] = [:]
    private var cookiesReady = false

    override init() {
        super.init()
        Task { @MainActor in
            await vault.restore()
            cookiesReady = true
            // Feeds were created while cookies were still being restored: load them now.
            for (id, url) in pendingLoads { views[id]?.load(URLRequest(url: url)) }
            pendingLoads.removeAll()
        }
    }

    private func load(_ view: WKWebView, id: UUID, url: URL) {
        if cookiesReady { view.load(URLRequest(url: url)) } else { pendingLoads[id] = url }
    }

    static func makeConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.isElementFullscreenEnabled = true
        config.mediaTypesRequiringUserActionForPlayback = .all
        return config
    }

    func webView(for column: Column) -> WKWebView {
        if let view = views[column.id] {
            if view.url == nil { load(view, id: column.id, url: column.url) }
            return view
        }
        let view = WKWebView(frame: .zero, configuration: Self.makeConfiguration())
        view.customUserAgent = deckUserAgent
        view.allowsBackForwardNavigationGestures = true
        view.uiDelegate = self
        view.navigationDelegate = self
        views[column.id] = view
        load(view, id: column.id, url: column.url)
        return view
    }

    func existing(_ id: UUID) -> WKWebView? { views[id] }

    func reload(_ column: Column, home: Bool) {
        guard let view = views[column.id] else { return }
        if home { view.load(URLRequest(url: column.url)) } else { view.reload() }
    }

    func discard(_ id: UUID) {
        views.removeValue(forKey: id)?.stopLoading()
    }

    // target=_blank and window.open: keep same-site pages in the column (login popups,
    // permalinks); send everything else to the default browser.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            if isDeckHost(url) { webView.load(URLRequest(url: url)) } else { NSWorkspace.shared.open(url) }
        }
        return nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        // Plain link clicks to unrelated sites open in the browser instead of hijacking a column.
        if navigationAction.navigationType == .linkActivated, navigationAction.targetFrame?.isMainFrame == true,
           let url = navigationAction.request.url, !isDeckHost(url) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    private func isDeckHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        // Login flows hop through these hosts (e.g. Threads → Instagram, Meta accounts center,
        // YouTube → Google accounts / consent).
        let allowed = ["x.com", "twitter.com", "threads.com", "threads.net", "instagram.com",
                       "youtube.com", "youtu.be", "google.com",
                       "facebook.com", "meta.com", "accountscenter.meta.com", "appleid.apple.com",
                       "accounts.google.com"]
        return allowed.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}

/// Hosts a pooled WKWebView inside SwiftUI.
struct WebColumnView: NSViewRepresentable {
    let column: Column
    let pool: WebViewPool

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        if container.subviews.first !== pool.existing(column.id) { attach(to: container) }
    }

    private func attach(to container: NSView) {
        container.subviews.forEach { $0.removeFromSuperview() }
        let web = pool.webView(for: column)
        web.removeFromSuperview()
        web.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(web)
        NSLayoutConstraint.activate([
            web.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            web.topAnchor.constraint(equalTo: container.topAnchor),
            web.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}
