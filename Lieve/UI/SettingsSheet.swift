import SwiftUI

struct SettingsSheet: View {
    let tab: BrowserTab
    let close: () -> Void
    @AppStorage(Preferences.adBlockKey) private var adBlock = true
    @AppStorage(Preferences.backgroundPlayKey) private var backgroundPlay = true
    @AppStorage(Preferences.autoPiPKey) private var autoPiP = false
    @AppStorage(Preferences.adStrategyKey) private var adStrategy = "skip"
    @State private var changed = false
    private var filters: FilterManager { FilterManager.shared }

    /// "3.2 s" dalla misura del ponte media ("3200 noads" / "3200 ads").
    private var lastStart: String {
        guard let raw = MediaState.shared.startMetric,
              let ms = Int(raw.split(separator: " ").first ?? "") else { return "—" }
        let seconds = String(format: "%.1f s", Double(ms) / 1000)
        return raw.hasSuffix("noads") ? seconds : seconds + " (con spot)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Blocco pubblicità", isOn: $adBlock)
                    Toggle("Riproduzione in background", isOn: $backgroundPlay)
                } footer: {
                    Text("Le modifiche si applicano ricaricando la pagina.")
                }

                Section {
                    Picker("Tecnica anti-pubblicità", selection: $adStrategy) {
                        Text("Salta gli spot (consigliata)").tag("skip")
                        Text("Richiesta senza annunci").tag("channel")
                        Text("Modalità anteprima").tag("inline")
                        Text("Entrambe").tag("both")
                        Text("Solo rimozione").tag("prune")
                    }
                    .disabled(!adBlock)
                    LabeledContent("Ultimo avvio video", value: lastStart)
                } header: {
                    Text("YouTube")
                } footer: {
                    Text("Se i video partono lenti, prova un'altra tecnica: chiudi le impostazioni, apri qualche video e confronta il tempo.")
                }

                Section {
                    Toggle("PiP automatico uscendo dall'app", isOn: $autoPiP)
                } footer: {
                    Text("Sperimentale. Si attiva anche aprendo il Centro di Controllo. In alternativa: schermo intero, poi torna alla Home.")
                }

                Section("Filtri") {
                    LabeledContent("Versione", value: filters.version == 0 ? "—" : String(filters.version))
                    if filters.updatesEnabled {
                        Button {
                            Task { await filters.checkForUpdates(force: true) }
                        } label: {
                            HStack {
                                Text("Controlla aggiornamenti")
                                if filters.isChecking { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(filters.isChecking)
                    } else {
                        Text("Aggiornamenti remoti non configurati: si usano i filtri inclusi nell'app.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if !filters.status.isEmpty {
                        Text(filters.status).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Impostazioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { close() }
                }
            }
            .onChange(of: adBlock) { changed = true }
            .onChange(of: backgroundPlay) { changed = true }
            .onChange(of: adStrategy) { changed = true }
            .onDisappear {
                guard changed else { return }
                filters.reapply()
                tab.reload()
            }
        }
    }
}
