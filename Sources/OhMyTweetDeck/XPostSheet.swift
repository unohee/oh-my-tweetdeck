import OhMyTweetDeckCore
import SwiftUI
import WebKit

/// Posts to X through the logged-in x.com session. Shows x.com's own intent composer
/// prefilled with the text; x.com's scripts sign and send the request. The app presses the
/// page's Post button once it is enabled, and the user can always press it themselves.
struct XPostSheet: View {
    let text: String
    let onFinish: (AppModel.OutcomeState) -> Void
    @StateObject private var driver = XComposeDriver()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Circle().fill(Color(rgb: Service.x.accentRGB)).frame(width: 8, height: 8)
                Text("Posting to X").font(.headline)
                Spacer()
                Text(driver.status).font(.caption).foregroundStyle(.secondary)
            }
            .padding(10)
            Divider()
            XComposeWebView(driver: driver, text: text)
                .frame(minWidth: 520, minHeight: 560)
            Divider()
            HStack {
                Button("Cancel") { onFinish(.failed("Cancelled")) }
                Spacer()
                Button("Mark as posted") { onFinish(.posted(nil)) }
                    .help("Use this if you pressed Post in the page and it went through")
            }
            .padding(10)
        }
        .onDisappear { driver.stop() }
        .onChange(of: driver.finished) { _, finished in
            if finished { onFinish(.posted(nil)) }
        }
    }
}

/// Drives the x.com intent page: waits for the Post button, presses it exactly once, then
/// waits until the draft text has left every compose editor for several consecutive probes.
@MainActor
final class XComposeDriver: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var status = "Loading x.com…"
    @Published var finished = false
    /// Set by the sheet before the web view loads.
    var text = ""
    private enum Phase { case waiting, clicking, sent }
    private var phase = Phase.waiting
    private var timer: Timer?
    private var ticks = 0
    private var ticksSinceClick = 0
    private var goneStreak = 0
    weak var webView: WKWebView?

    /// Consecutive "draft gone" probes (0.5 s apart) required before calling it posted.
    private let requiredGoneStreak = 3

    func start(_ webView: WKWebView) {
        self.webView = webView
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let webView, !finished else { return }
        ticks += 1
        let path = webView.url?.path ?? ""
        if path.contains("/login") || path.contains("/onboarding") || path.contains("/i/flow") {
            status = "Log in to X in this window"
            return
        }
        switch phase {
        case .waiting:
            webView.evaluateJavaScript(XWebIntent.probeScript) { [weak self] result, _ in
                Task { @MainActor in self?.handleProbe(result as? String) }
            }
        case .clicking:
            return
        case .sent:
            ticksSinceClick += 1
            webView.evaluateJavaScript(XWebIntent.draftPresentScript(text: text)) { [weak self] result, error in
                Task { @MainActor in self?.handleDraftProbe(error == nil ? result as? Bool : nil) }
            }
        }
    }

    private func handleProbe(_ state: String?) {
        guard let webView, phase == .waiting else { return }
        switch state {
        case "ready":
            // Flip the phase before the async click so a second probe can never click again.
            phase = .clicking
            status = "Sending…"
            webView.evaluateJavaScript(XWebIntent.clickScript) { [weak self] result, _ in
                Task { @MainActor in
                    guard let self else { return }
                    if (result as? Bool) == true {
                        self.phase = .sent
                    } else {
                        self.phase = .waiting
                        self.status = "Press Post in the page"
                    }
                }
            }
        case "disabled":
            status = "Post button disabled — check the text in the page"
        default:
            status = ticks > 30 ? "Press Post in the page" : "Waiting for composer…"
        }
    }

    private func handleDraftProbe(_ present: Bool?) {
        // nil = the page was navigating; neither evidence of success nor of failure.
        guard let present else { return }
        goneStreak = present ? 0 : goneStreak + 1
        if goneStreak >= requiredGoneStreak {
            finish()
        } else if ticksSinceClick > 40 {
            status = "Still in the composer — check the page for an error"
        }
    }

    private func finish() {
        stop()
        status = "Posted"
        // Leave the page alone briefly so x.com finishes any follow-up requests before teardown.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.finished = true }
    }
}

struct XComposeWebView: NSViewRepresentable {
    let driver: XComposeDriver
    let text: String
    var url: URL { XWebIntent.composeURL(text: text) }

    func makeNSView(context: Context) -> WKWebView {
        driver.text = text
        let web = WKWebView(frame: .zero, configuration: WebViewPool.makeConfiguration())
        web.customUserAgent = deckUserAgent
        web.navigationDelegate = driver
        web.load(URLRequest(url: url))
        driver.start(web)
        return web
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: ()) {
        nsView.stopLoading()
    }
}
