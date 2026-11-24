// Created: 2026-11-24
// Purpose: Spike - load X/Threads/Instagram in a narrow WKWebView with different UAs and snapshot.
// Dependencies: AppKit, WebKit
// Test Status: manual spike
import AppKit
import WebKit

let uas: [String: String?] = [
  "default": nil,
  "iphone": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1",
  "safari": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15",
]
let urls = ["x": "https://x.com/", "threads": "https://www.threads.com/", "instagram": "https://www.instagram.com/"]
let outDir = CommandLine.arguments[1]

final class Runner: NSObject, WKNavigationDelegate {
  var jobs: [(String, String, String?)] = []
  var web: WKWebView!
  var window: NSWindow!
  var current: (String, String, String?)?
  func start() {
    for (s, u) in urls { for (n, ua) in uas { jobs.append((s + "_" + n, u, ua)) } }
    window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
    window.orderFront(nil)
    next()
  }
  func next() {
    guard !jobs.isEmpty else { exit(0) }
    let j = jobs.removeFirst(); current = j
    let cfg = WKWebViewConfiguration(); cfg.websiteDataStore = .nonPersistent()
    web = WKWebView(frame: window.contentView!.bounds, configuration: cfg)
    web.customUserAgent = j.2
    web.navigationDelegate = self
    window.contentView = web
    web.load(URLRequest(url: URL(string: j.1)!))
    DispatchQueue.main.asyncAfter(deadline: .now() + 9) { self.snap() }
  }
  func snap() {
    let name = current!.0
    web.takeSnapshot(with: nil) { img, err in
      if let img, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
         let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
      }
      self.web.evaluateJavaScript("location.href + ' | ' + document.title") { r, _ in
        print(name, "->", r ?? "nil", err?.localizedDescription ?? "")
        self.next()
      }
    }
  }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let r = Runner()
DispatchQueue.main.async { r.start() }
app.run()
