import Foundation
import WebKit
import Observation

/// Carica, compila (una volta, con cache) e applica il pacchetto filtri alle WebView.
/// Avvio tipico: lettura di index.json + lookup delle liste già compilate → pochi millisecondi.
@MainActor
@Observable
final class FilterManager {
    static let shared = FilterManager()

    private(set) var version = 0
    private(set) var status = ""
    private(set) var isChecking = false
    var updatesEnabled: Bool { FilterSource.remoteURL != nil && FilterSource.publicKey != nil }

    @ObservationIgnored private var index: FilterIndex?
    @ObservationIgnored private var compiled: [String: WKContentRuleList] = [:]
    @ObservationIgnored private var prepared = false
    private let controllers = NSHashTable<WKUserContentController>.weakObjects()
    private let store: WKContentRuleListStore?

    private init() {
        store = WKContentRuleListStore.default()
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    // MARK: - Avvio

    func prepare() async {
        guard !prepared else { return }
        prepared = true

        var current = FilterDisk.readIndex()

        // Primo avvio o app aggiornata: il pacchetto incluso potrebbe essere più recente.
        if current == nil || current?.appBuild != appBuild {
            if let bundled = await FilterDisk.loadBundled() {
                if let installed = current, installed.version > bundled.pack.version {
                    let refreshed = FilterIndex(version: installed.version, contentHash: installed.contentHash,
                                                appBuild: appBuild, lists: installed.lists, scripts: installed.scripts)
                    FilterDisk.saveIndex(refreshed)
                    current = refreshed
                } else {
                    await install(bundled.pack, data: bundled.data)
                    return
                }
            }
        }

        guard let installedIndex = current else {
            status = "Nessun filtro disponibile"
            return
        }
        activate(installedIndex)
        await attachCompiledOrRebuild(installedIndex)
    }

    // MARK: - Applicazione alle WebView

    func register(_ controller: WKUserContentController) {
        controllers.add(controller)
        apply(to: controller)
    }

    /// Da chiamare quando cambiano le preferenze (seguito da un ricaricamento della pagina).
    func reapply() {
        for controller in controllers.allObjects { apply(to: controller) }
    }

    private func apply(to controller: WKUserContentController) {
        controller.removeAllUserScripts()
        controller.removeAllContentRuleLists()
        MediaBridge.shared.install(in: controller)

        let config = "{\"adblock\":\(Preferences.adBlock),\"background\":\(Preferences.backgroundPlay),"
            + "\"strategy\":\"\(Preferences.adStrategy)\"}"
        for script in index?.scripts ?? [] {
            let world: WKContentWorld = script.world == "page" ? .page : .lieve
            let source = script.source.replacingOccurrences(of: "__LIEVE_CFG__", with: config)
            controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart,
                                                  forMainFrameOnly: true, in: world))
        }

        guard Preferences.adBlock else { return }
        for ref in index?.lists ?? [] {
            if let list = compiled[ref.identifier] { controller.add(list) }
        }
    }

    private func attach(_ list: WKContentRuleList, identifier: String) {
        compiled[identifier] = list
        guard Preferences.adBlock else { return }
        for controller in controllers.allObjects { controller.add(list) }
    }

    private func activate(_ newIndex: FilterIndex) {
        index = newIndex
        version = newIndex.version
        let valid = Set(newIndex.lists.map(\.identifier))
        compiled = compiled.filter { valid.contains($0.key) }
        reapply()
    }

    // MARK: - Installazione e compilazione

    private func install(_ pack: FilterPack, data: Data) async {
        let newIndex = FilterIndex(
            version: pack.version, contentHash: pack.contentHash, appBuild: appBuild,
            lists: pack.ruleLists.map { .init(identifier: $0.identifier, critical: $0.critical) },
            scripts: pack.scripts)
        do {
            try await FilterDisk.save(packData: data, index: newIndex)
        } catch {
            status = "Impossibile salvare i filtri"
            return
        }
        activate(newIndex)
        await compile(pack.ruleLists)
    }

    /// All'avvio: recupera le liste già compilate; ricompila solo quelle mancanti.
    private func attachCompiledOrRebuild(_ current: FilterIndex) async {
        var missing: Set<String> = []
        for ref in current.lists {
            if let list = await lookUp(ref.identifier) {
                attach(list, identifier: ref.identifier)
            } else {
                missing.insert(ref.identifier)
            }
        }
        guard !missing.isEmpty, let pack = await FilterDisk.loadInstalled() else { return }
        await compile(pack.ruleLists.filter { missing.contains($0.identifier) })
    }

    /// Le liste "critical" (YouTube, piccole) vengono attese; le altre proseguono in background,
    /// una alla volta per contenere i picchi di memoria.
    private func compile(_ lists: [FilterPack.RuleList]) async {
        for list in lists where list.critical {
            await compileOne(list)
        }
        let others = lists.filter { !$0.critical }
        guard !others.isEmpty else { cleanUpStore(); return }
        Task {
            for list in others { await self.compileOne(list) }
            self.cleanUpStore()
        }
    }

    private func compileOne(_ list: FilterPack.RuleList) async {
        if let existing = await lookUp(list.identifier) {
            attach(existing, identifier: list.identifier)
            return
        }
        guard let store else { return }
        let result: WKContentRuleList? = await withCheckedContinuation { cont in
            store.compileContentRuleList(forIdentifier: list.identifier,
                                         encodedContentRuleList: list.json) { compiled, error in
                #if DEBUG
                if let error { print("Filtri: \(list.id) non compilata: \(error)") }
                #endif
                cont.resume(returning: compiled)
            }
        }
        if let result { attach(result, identifier: list.identifier) }
    }

    private func lookUp(_ identifier: String) async -> WKContentRuleList? {
        guard let store else { return nil }
        return await withCheckedContinuation { cont in
            store.lookUpContentRuleList(forIdentifier: identifier) { list, _ in
                cont.resume(returning: list)
            }
        }
    }

    /// Rimuove dalla cache WebKit le liste di versioni precedenti.
    private func cleanUpStore() {
        guard let store, let index else { return }
        let valid = Set(index.lists.map(\.identifier))
        store.getAvailableContentRuleListIdentifiers { identifiers in
            for id in identifiers ?? [] where id.hasPrefix("lieve.") && !valid.contains(id) {
                store.removeContentRuleList(forIdentifier: id) { _ in }
            }
        }
    }

    // MARK: - Aggiornamenti remoti (opzionali, firmati)

    func checkForUpdates(force: Bool) async {
        guard let url = FilterSource.remoteURL, let key = FilterSource.publicKey, !isChecking else { return }
        let defaults = UserDefaults.standard
        if !force, let last = defaults.object(forKey: "filters.lastCheck") as? Date,
           Date().timeIntervalSince(last) < 86_400 { return }

        isChecking = true
        defer { isChecking = false }
        status = "Controllo in corso…"

        do {
            // 1) Impronta (pochi byte): se coincide, nessun download.
            let (hashData, hashResponse) = try await FilterSource.session.data(from: url.appendingPathExtension("hash"))
            defaults.set(Date(), forKey: "filters.lastCheck")
            if (hashResponse as? HTTPURLResponse)?.statusCode == 200,
               let remote = String(data: hashData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               remote == index?.contentHash {
                status = "Filtri aggiornati"
                return
            }

            // 2) Pacchetto completo, verificato con la chiave pubblica inclusa nell'app.
            let (data, response) = try await FilterSource.session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 40_000_000 else {
                status = "Server dei filtri non raggiungibile"
                return
            }
            let pack = try await Task.detached(priority: .utility) {
                try PackFile.decode(data, publicKey: key)
            }.value
            guard pack.version > version else {
                status = "Filtri aggiornati"
                return
            }
            await install(pack, data: data)
            status = "Aggiornati alla versione \(pack.version)"
        } catch PackError.badSignature {
            status = "Firma non valida: aggiornamento scartato"
        } catch {
            status = "Aggiornamento non riuscito"
        }
    }
}

extension WKContentWorld {
    /// Mondo isolato dell'app: condivide il DOM ma non le variabili con la pagina.
    @MainActor static var lieve: WKContentWorld { .world(name: "lieve") }
}
