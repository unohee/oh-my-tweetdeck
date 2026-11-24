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
            XComposeWebView(driver: driver, url: XWebIntent.composeURL(text: text))
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

@MainActor
final class XComposeDriver: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var status = "Loading x.com…"
    @Published var finished = false
    private var clicked = false
    private var timer: Timer?
    private var ticks = 0
    weak var webView: WKWebView?

    func start(_ webView: WKWebView) {
        self.webView = webView
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() { timer?.invalidate() }

    private func tick() {
        guard let webView, !finished else { return }
        ticks += 1
        let path = webView.url?.path ?? ""
        if path.contains("/login") || path.contains("/onboarding") || path.contains("/i/flow") {
            status = "Log in to X in this window, then post"
            return
        }
        if clicked {
            // After sending, x.com leaves the intent page (or removes the composer).
            if !path.hasPrefix("/intent/") { finish(); return }
            webView.evaluateJavaScript(XWebIntent.probeScript) { [weak self] result, _ in
                Task { @MainActor in if (result as? String) == "missing" { self?.finish() } }
            }
            return
        }
        webView.evaluateJavaScript(XWebIntent.probeScript) { [weak self] result, _ in
            Task { @MainActor in self?.handleProbe(result as? String) }
        }
    }

    private func handleProbe(_ state: String?) {
        guard let webView, !clicked else { return }
        switch state {
        case "ready":
            webView.evaluateJavaScript(XWebIntent.clickScript) { [weak self] result, _ in
                Task { @MainActor in
                    if (result as? Bool) == true {
                        self?.clicked = true
                        self?.status = "Sending…"
                    }
                }
            }
        case "disabled":
            status = "Post button disabled — check the text in the page"
        default:
            status = ticks > 30 ? "Press Post in the page" : "Waiting for composer…"
        }
    }

    private func finish() {
        stop()
        status = "Posted"
        finished = true
    }
}

struct XComposeWebView: NSViewRepresentable {
    let driver: XComposeDriver
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
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
