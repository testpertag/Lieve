import Foundation

/// Preferenze utente (UserDefaults). Le viste usano @AppStorage con le stesse chiavi.
enum Preferences {
    static let adBlockKey = "adBlock"
    static let backgroundPlayKey = "backgroundPlay"
    static let autoPiPKey = "autoPiP"
    /// Tecnica anti-pubblicità su YouTube: "channel" | "inline" | "both" | "prune".
    static let adStrategyKey = "adStrategy"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            adBlockKey: true,
            backgroundPlayKey: true,
            autoPiPKey: false,
            adStrategyKey: "channel",
        ])
    }

    static var adBlock: Bool { UserDefaults.standard.bool(forKey: adBlockKey) }
    static var backgroundPlay: Bool { UserDefaults.standard.bool(forKey: backgroundPlayKey) }
    static var autoPiP: Bool { UserDefaults.standard.bool(forKey: autoPiPKey) }
    static var adStrategy: String {
        let value = UserDefaults.standard.string(forKey: adStrategyKey) ?? "channel"
        return ["channel", "inline", "both", "prune"].contains(value) ? value : "channel"
    }
}
