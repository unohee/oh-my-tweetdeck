// Created: 2026-11-26
// Purpose: Run AutoRefresh.probeScript in a real WKWebView against local pages and print the PageState JSON.
// Dependencies: WebKit; probe text copied from Sources/OhMyTweetDeckCore/AutoRefresh.swift via argv[1]
// Test Status: manual
import AppKit
import WebKit

let probe = try! String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
let tall = "<div style='height:5000px'>feed</div>"
let cases: [(String, String, String)] = [
    ("idle", "<body>\(tall)</body>", ""),
    ("scrolled", "<body>\(tall)</body>", "window.scrollTo(0, 900)"),
    ("innerMain", "<body><main style='height:300px;overflow:auto'>\(tall)</main></body>", "document.querySelector('main').scrollTop = 700"),
    ("draft", "<body><div contenteditable='true'>half a reply</div>\(tall)</body>", ""),
    ("focused", "<body><input id=s>\(tall)</body>", "document.getElementById('s').focus()"),
    ("modal", "<body><div role=dialog aria-modal=true>x</div></body>", ""),
]
@MainActor final class Runner: NSObject, WKNavigationDelegate {
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    var i = 0
    func next() {
        guard i < cases.count else { exit(0) }
        web.navigationDelegate = self
        web.loadHTMLString(cases[i].1, baseURL: nil)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let (name, _, setup) = cases[i]
        webView.evaluateJavaScript(setup.isEmpty ? "0" : setup) { _, _ in
            webView.evaluateJavaScript(probe) { r, e in
                print(name, r as? String ?? "error \(String(describing: e))")
                self.i += 1
                self.next()
            }
        }
    }
}
let app = NSApplication.shared
MainActor.assumeIsolated {
    let runner = Runner()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = runner.web
    objc_setAssociatedObject(app, "runner", runner, .OBJC_ASSOCIATION_RETAIN)
    objc_setAssociatedObject(app, "window", window, .OBJC_ASSOCIATION_RETAIN)
    runner.next()
}
DispatchQueue.main.asyncAfter(deadline: .now() + 20) { print("timeout"); exit(1) }
app.run()
