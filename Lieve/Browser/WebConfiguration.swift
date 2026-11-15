import UIKit
import WebKit

enum WebConfiguration {
    static func make(userContentController: WKUserContentController) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.userContentController = userContentController

        // Archivio persistente: cookie, login e localStorage sopravvivono ai riavvii.
        config.websiteDataStore = .default()

        // Media: riproduzione inline, AirPlay e PiP gestiti dal player nativo di WebKit.
        config.allowsInlineMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        // Permette a YouTube di avviare il video successivo senza un nuovo tocco.
        config.mediaTypesRequiringUserActionForPlayback = []

        config.upgradeKnownHostsToHTTPS = true
        config.defaultWebpagePreferences.preferredContentMode = .mobile

        // User agent in stile Safari: alcuni servizi Google trattano diversamente
        // le WebView "anonime". Non modifica nulla del motore, solo l'identificazione.
        let major = UIDevice.current.systemVersion.split(separator: ".").first ?? "18"
        config.applicationNameForUserAgent = "Version/\(major).0 Mobile/15E148 Safari/604.1"

        return config
    }
}
