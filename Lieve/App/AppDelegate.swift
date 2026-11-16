import UIKit

/// Avvio in UIKit puro: la schermata del browser non passa da SwiftUI,
/// così i gesti della WebView non competono con quelli di SwiftUI.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Preferences.registerDefaults()
        AudioSession.configure()
        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var tab: BrowserTab?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let tab = BrowserTab(url: AppConfig.homeURL)
        self.tab = tab

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = BrowserViewController(tab: tab)
        window.makeKeyAndVisible()
        self.window = window

        Task {
            await FilterManager.shared.prepare()
            tab.start()
            // Controllo aggiornamenti filtri a bassa priorità, al massimo una volta al giorno.
            try? await Task.sleep(for: .seconds(8))
            await FilterManager.shared.checkForUpdates(force: false)
        }
    }
}

enum AppConfig {
    static var homeURL: URL {
        #if DEBUG
        // Solo per i test nel simulatore: argomento di avvio -LieveStartURL <url>
        if let value = UserDefaults.standard.string(forKey: "LieveStartURL"), let url = URL(string: value) {
            return url
        }
        #endif
        return URL(string: "https://m.youtube.com/")!
    }

    /// Motore di ricerca per testo non riconosciuto come indirizzo.
    static func searchURL(for query: String) -> URL? {
        var components = URLComponents(string: "https://duckduckgo.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }
}
