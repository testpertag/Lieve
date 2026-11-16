import SwiftUI

struct SettingsSheet: View {
    let tab: BrowserTab
    let close: () -> Void
    @AppStorage(Preferences.adBlockKey) private var adBlock = true
    @AppStorage(Preferences.backgroundPlayKey) private var backgroundPlay = true
    @AppStorage(Preferences.autoPiPKey) private var autoPiP = false
    @State private var changed = false
    private var filters: FilterManager { FilterManager.shared }

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
            .onDisappear {
                guard changed else { return }
                filters.reapply()
                tab.reload()
            }
        }
    }
}
