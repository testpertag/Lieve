import UIKit
import WebKit
import Observation

/// Stato di una scheda. Lo stato viene aggiornato tramite KVO (event-driven, nessun polling)
/// e @Observable fa sì che SwiftUI ridisegni solo le viste che leggono la proprietà cambiata.
@MainActor
@Observable
final class BrowserTab {
    private(set) var title = ""
    private(set) var url: URL?
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var isLoading = false
    private(set) var progress = 0.0

    let webView: WKWebView
    private let delegate: WebViewDelegate
    private let initialURL: URL
    @ObservationIgnored private var started = false
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    /// Notifica per l'interfaccia UIKit: chiamata dopo ogni cambio di stato.
    @ObservationIgnored var onChange: (() -> Void)?

    init(url: URL) {
        let controller = WKUserContentController()
        // Script e regole disponibili vengono installati subito; il resto arriva con prepare().
        FilterManager.shared.register(controller)

        let webView = WKWebView(frame: .zero, configuration: WebConfiguration.make(userContentController: controller))
        webView.allowsBackForwardNavigationGestures = true   // swipe dai bordi
        webView.allowsLinkPreview = true
        // Evita il lampo bianco prima del primo disegno in modalità scura.
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.underPageBackgroundColor = .systemBackground

        self.webView = webView
        self.delegate = WebViewDelegate()
        self.initialURL = url
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate
        MediaBridge.shared.register(webView)

        startObserving()
    }

    /// Primo caricamento, dopo che i filtri sono pronti (così la prima pagina è già filtrata).
    func start() {
        guard !started else { return }
        started = true
        webView.load(URLRequest(url: initialURL))
    }

    // MARK: - Azioni

    func load(_ input: String) {
        guard let target = URLInput.url(from: input) else { return }
        webView.load(URLRequest(url: target))
    }

    func goHome() { webView.load(URLRequest(url: AppConfig.homeURL)) }
    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }
    func reloadOrStop() {
        if isLoading { webView.stopLoading() } else { webView.reload() }
    }

    func togglePictureInPicture(completion: @escaping (PiPResult) -> Void) {
        MediaBridge.shared.togglePictureInPicture(in: webView, completion: completion)
    }

    // MARK: - KVO

    private func startObserving() {
        observations = [
            bind(\.title) { $0.title = $1 ?? "" },
            bind(\.url) { $0.url = $1 },
            bind(\.canGoBack) { $0.canGoBack = $1 },
            bind(\.canGoForward) { $0.canGoForward = $1 },
            bind(\.isLoading) { $0.isLoading = $1 },
            bind(\.estimatedProgress) { $0.progress = $1 },
        ]
    }

    private func bind<Value>(
        _ keyPath: KeyPath<WKWebView, Value>,
        _ apply: @escaping @MainActor (BrowserTab, Value) -> Void
    ) -> NSKeyValueObservation {
        webView.observe(keyPath, options: [.initial, .new]) { [weak self] webView, _ in
            // WebKit notifica queste proprietà sempre sul main thread.
            MainActor.assumeIsolated {
                guard let self else { return }
                let value = webView[keyPath: keyPath]
                apply(self, value)
                self.onChange?()
            }
        }
    }
}
