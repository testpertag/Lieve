import UIKit
import WebKit

@MainActor
final class WebViewDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    private weak var webView: WKWebView?

    func attach(to webView: WKWebView) {
        self.webView = webView
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(pullToRefresh(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refresh
    }

    @objc private func pullToRefresh(_ sender: UIRefreshControl) {
        webView?.reload()
    }

    private func endRefreshing(_ webView: WKWebView) {
        webView.scrollView.refreshControl?.endRefreshing()
    }

    // MARK: - Navigazione

    private static let webSchemes: Set<String> = ["http", "https", "about", "blob", "data", "javascript"]

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url,
              let scheme = url.scheme?.lowercased(),
              !Self.webSchemes.contains(scheme) else { return .allow }
        // tel:, mailto:, maps:, itms-apps: ecc. vengono passati al sistema.
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        return .cancel
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { endRefreshing(webView) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { endRefreshing(webView) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { endRefreshing(webView) }

    /// Se iOS chiude il processo web per liberare memoria, ricarichiamo la pagina
    /// invece di lasciare una schermata bianca.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    // MARK: - UI

    /// I link target=_blank vengono aperti nella stessa scheda (MVP a scheda singola).
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}
