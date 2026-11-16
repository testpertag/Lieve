import UIKit
import WebKit

@MainActor
final class WebViewDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
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
