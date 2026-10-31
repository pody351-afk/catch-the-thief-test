import UIKit
import WebKit
import AVFoundation
import UniformTypeIdentifiers

/// Serves the bundled game (the "www" folder) at app://game/… so the page gets a stable origin:
/// localStorage persists, fetch()/WebRTC/getUserMedia behave like on a normal https site.
final class BundleSchemeHandler: NSObject, WKURLSchemeHandler {
    private let root: URL
    init(root: URL) { self.root = root }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL)); return
        }
        var path = url.path
        if path.isEmpty || path == "/" { path = "/index.html" }
        let file = root.appendingPathComponent(String(path.dropFirst())).standardizedFileURL
        // never serve anything outside the bundled folder
        guard file.path.hasPrefix(root.standardizedFileURL.path),
              let data = try? Data(contentsOf: file) else {
            let r = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            urlSchemeTask.didReceive(r); urlSchemeTask.didReceive(Data()); urlSchemeTask.didFinish(); return
        }
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let headers = ["Content-Type": mime, "Content-Length": String(data.count), "Cache-Control": "no-cache"]
        let r = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        urlSchemeTask.didReceive(r)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

final class GameViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private var webView: WKWebView!
    private var schemeHandler: BundleSchemeHandler?

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }

    override func loadView() {
        // game sounds play like a game (even with the silent switch on); WebKit switches the session
        // to recording by itself when the player turns voice chat on
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .default()
        if let www = Bundle.main.url(forResource: "www", withExtension: nil) {
            let h = BundleSchemeHandler(root: www)
            schemeHandler = h
            config.setURLSchemeHandler(h, forURLScheme: "app")
        }
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 23/255, green: 32/255, blue: 51/255, alpha: 1)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if schemeHandler != nil, let start = URL(string: "app://game/index.html") {
            webView.load(URLRequest(url: start))
        } else if let www = Bundle.main.url(forResource: "www", withExtension: nil) {
            webView.loadFileURL(www.appendingPathComponent("index.html"), allowingReadAccessTo: www)
        }
    }

    // Links that leave the game (privacy policy, itch page, mailto: "Report player", share links)
    // open in Safari / Mail instead of replacing the game.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
            decisionHandler(.allow); return
        }
        if scheme == "app" || scheme == "about" || scheme == "blob" || scheme == "data" || scheme == "file" {
            decisionHandler(.allow); return
        }
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        if scheme == "http" || scheme == "https" {
            if navigationAction.navigationType == .linkActivated || isMainFrame {
                UIApplication.shared.open(url); decisionHandler(.cancel); return
            }
            decisionHandler(.allow); return
        }
        // mailto:, tel:, sms:, itms-apps: …
        UIApplication.shared.open(url)
        decisionHandler(.cancel)
    }

    // target=_blank / window.open
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { UIApplication.shared.open(Self.external(url)) }
        return nil
    }

    // In-game voice chat: iOS shows its own microphone prompt (NSMicrophoneUsageDescription) the first time.
    @available(iOS 15.0, *)
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(type == .microphone ? .grant : .deny)
    }

    // JS alert/confirm (if the game ever uses them) as native dialogs
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(a, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(a, animated: true)
    }

    /// Bundled pages opened "in a new tab" (e.g. privacy.html) are shown from the game's website in Safari.
    static func external(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "app" else { return url }
        return URL(string: "https://catch-the-thief.pages.dev" + url.path) ?? url
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }
}
