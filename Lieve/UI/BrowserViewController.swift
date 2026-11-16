import UIKit
import SwiftUI
import WebKit

/// Schermata principale in UIKit: WebView a tutto schermo, barra di caricamento,
/// menu flottante e avvisi. I fogli (indirizzo, impostazioni) restano in SwiftUI,
/// presentati come controller separati.
final class BrowserViewController: UIViewController {
    private let browserTab: BrowserTab
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private var menu: FloatingMenu?
    private let toast = UILabel()
    private let toastContainer = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private var toastTask: Task<Void, Never>?

    init(browserTab: BrowserTab) {
        self.browserTab = browserTab
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) non supportato") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let webView = browserTab.webView
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.progressTintColor = .systemRed
        progressView.trackTintColor = .clear
        progressView.isUserInteractionEnabled = false
        view.addSubview(progressView)
        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 2),
        ])

        buildToast()

        let menu = FloatingMenu(host: view)
        menu.onAction = { [weak self] action in self?.handle(action) }
        self.menu = menu

        browserTab.onChange = { [weak self] in self?.refresh() }
        MediaState.shared.onChange = { [weak self] in self?.refresh() }
        refresh()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        menu?.layout()
    }

    // MARK: - Stato

    private func refresh() {
        menu?.update(canGoBack: browserTab.canGoBack, canGoForward: browserTab.canGoForward,
                     isLoading: browserTab.isLoading, videoPlaying: MediaState.shared.videoPlaying)
        progressView.setProgress(Float(browserTab.progress), animated: browserTab.isLoading)
        UIView.animate(withDuration: 0.2) { self.progressView.alpha = self.browserTab.isLoading ? 1 : 0 }
    }

    // MARK: - Azioni

    private func handle(_ action: FloatingMenu.Action) {
        switch action {
        case .back: browserTab.goBack()
        case .forward: browserTab.goForward()
        case .reload: browserTab.reloadOrStop()
        case .address: presentAddress()
        case .pip: togglePiP()
        case .settings: presentSettings()
        }
    }

    private func presentAddress() {
        let controller = UIHostingController(rootView: AddressSheet(tab: browserTab) { [weak self] in
            self?.dismiss(animated: true)
        })
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.custom { _ in 150 }]
            sheet.prefersGrabberVisible = true
        }
        present(controller, animated: true)
    }

    private func presentSettings() {
        let controller = UIHostingController(rootView: SettingsSheet(tab: browserTab) { [weak self] in
            self?.dismiss(animated: true)
        })
        present(controller, animated: true)
    }

    private func togglePiP() {
        browserTab.togglePictureInPicture { [weak self] result in
            switch result {
            case .entered, .exited, .skip: break
            case .noVideo: self?.showToast("Nessun video nella pagina")
            case .unsupported: self?.showToast("Il sito non consente il PiP qui: prova da schermo intero")
            case .failed: self?.showToast("Picture-in-Picture non disponibile")
            }
        }
    }

    // MARK: - Avvisi

    private func buildToast() {
        toastContainer.clipsToBounds = true
        toastContainer.layer.cornerRadius = 16
        toastContainer.alpha = 0
        toastContainer.isUserInteractionEnabled = false
        toastContainer.translatesAutoresizingMaskIntoConstraints = false
        toast.font = .preferredFont(forTextStyle: .footnote)
        toast.numberOfLines = 2
        toast.textAlignment = .center
        toast.translatesAutoresizingMaskIntoConstraints = false
        toastContainer.contentView.addSubview(toast)
        view.addSubview(toastContainer)
        NSLayoutConstraint.activate([
            toast.leadingAnchor.constraint(equalTo: toastContainer.contentView.leadingAnchor, constant: 14),
            toast.trailingAnchor.constraint(equalTo: toastContainer.contentView.trailingAnchor, constant: -14),
            toast.topAnchor.constraint(equalTo: toastContainer.contentView.topAnchor, constant: 8),
            toast.bottomAnchor.constraint(equalTo: toastContainer.contentView.bottomAnchor, constant: -8),
            toastContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toastContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            toastContainer.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -32),
        ])
    }

    private func showToast(_ message: String) {
        toast.text = message
        toastTask?.cancel()
        UIView.animate(withDuration: 0.2) { self.toastContainer.alpha = 1 }
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled, let self else { return }
            UIView.animate(withDuration: 0.3) { self.toastContainer.alpha = 0 }
        }
    }
}
