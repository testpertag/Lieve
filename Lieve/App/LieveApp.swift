import SwiftUI

@main
struct LieveApp: App {
    // Un'unica scheda. BrowserTab è già strutturata per eventuali schede multiple.
    @State private var tab: BrowserTab

    init() {
        Preferences.registerDefaults()
        AudioSession.configure()
        _tab = State(initialValue: BrowserTab(url: AppConfig.homeURL))
    }

    var body: some Scene {
        WindowGroup {
            BrowserView(tab: tab)
                .task {
                    await FilterManager.shared.prepare()
                    tab.start()
                    // Controllo aggiornamenti filtri a bassa priorità, al massimo una volta al giorno.
                    try? await Task.sleep(for: .seconds(8))
                    await FilterManager.shared.checkForUpdates(force: false)
                }
        }
    }
}

enum AppConfig {
    static var homeURL: URL {
        #if DEBUG
        // Solo per i test nel simulatore: xcrun simctl launch … -LieveStartURL <url>
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
