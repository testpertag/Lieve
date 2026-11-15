import Foundation

/// Preferenze utente (UserDefaults). Le viste usano @AppStorage con le stesse chiavi.
enum Preferences {
    static let adBlockKey = "adBlock"
    static let backgroundPlayKey = "backgroundPlay"
    static let autoPiPKey = "autoPiP"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            adBlockKey: true,
            backgroundPlayKey: true,
            autoPiPKey: false,
        ])
    }

    static var adBlock: Bool { UserDefaults.standard.bool(forKey: adBlockKey) }
    static var backgroundPlay: Bool { UserDefaults.standard.bool(forKey: backgroundPlayKey) }
    static var autoPiP: Bool { UserDefaults.standard.bool(forKey: autoPiPKey) }
}
