import SwiftUI
import WebKit

/// Browser panel: WKWebView-backed. Loads the project's folder URL by
/// default; user can navigate via the URL bar. Refreshes cache on
/// Cmd+R / Cmd+L.
public struct BrowserPanelView: NSViewRepresentable {
    let tabID: String
    let initialURL: URL

    public func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor

        let webView = WKWebView(frame: .zero)
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        webView.load(URLRequest(url: initialURL))
        return container
    }

    public func updateNSView(_ nsView: NSView, context: Context) {}
}
