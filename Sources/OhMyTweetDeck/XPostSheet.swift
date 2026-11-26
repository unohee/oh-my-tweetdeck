import OhMyTweetDeckCore
import SwiftUI
import WebKit

/// Posts to X through the logged-in x.com session. Shows x.com's own intent composer
/// prefilled with the text; x.com's scripts sign and send the request. The app presses the
/// page's Post button once it is enabled, and the user can always press it themselves.
struct XPostSheet: View {
    let text: String
    /// JPEG to attach in x.com's composer before sending.
    var image: Data?
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
            XComposeWebView(driver: driver, text: text, image: image)
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
    var image: Data?
    /// `OMT_X_DRYRUN=1`: drive the page (text, attachment) but never press Post. For testing
    /// against the live site without publishing anything.
    let dryRun = ProcessInfo.processInfo.environment["OMT_X_DRYRUN"] == "1"
    private enum AttachState { case none, pending, injected, ready }
    private var attach = AttachState.none
    private var attachTicks = 0
    /// Cleared when the attachment could not be confirmed: never auto-send a post missing its image.
    private var autoSend = true
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
        attach = image == nil ? .none : .pending
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
            if attach == .pending || attach == .injected {
                stepAttachment(webView)
                return
            }
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

    /// Puts the image into the composer, then waits until x.com has uploaded it.
    private func stepAttachment(_ webView: WKWebView) {
        attachTicks += 1
        if attach == .pending, let image {
            status = "Attaching image…"
            let script = XWebIntent.attachScript(base64: image.base64EncodedString(), mimeType: "image/jpeg",
                                                 fileName: "image.jpg")
            webView.evaluateJavaScript(script) { [weak self] result, _ in
                Task { @MainActor in
                    guard let self, self.attach == .pending else { return }
                    if (result as? String) == "attached" { self.attach = .injected; self.attachTicks = 0 }
                    else if self.attachTicks > 40 { self.attach = .ready; self.autoSend = false }
                }
            }
        } else if attach == .injected {
            status = "Uploading image to X…"
            webView.evaluateJavaScript(XWebIntent.attachmentReadyScript) { [weak self] result, _ in
                Task { @MainActor in
                    guard let self, self.attach == .injected else { return }
                    if (result as? Bool) == true {
                        self.attach = .ready
                    } else if self.attachTicks > 120 {
                        self.attach = .ready
                        self.autoSend = false
                    }
                }
            }
        }
    }

    private func handleProbe(_ state: String?) {
        guard let webView, phase == .waiting else { return }
        if dryRun {
            status = state == "ready" ? "Dry run — ready, not sending" : "Dry run — \(state ?? "loading")"
            return
        }
        if !autoSend {
            status = "Check the image in the page, then press Post"
            return
        }
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
    var image: Data?
    var url: URL { XWebIntent.composeURL(text: text) }

    func makeNSView(context: Context) -> WKWebView {
        driver.text = text
        driver.image = image
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
