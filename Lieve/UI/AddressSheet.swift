import SwiftUI

struct AddressSheet: View {
    let tab: BrowserTab
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @FocusState private var focused: Bool

    init(tab: BrowserTab) {
        self.tab = tab
        _text = State(initialValue: tab.url?.absoluteString ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Cerca o inserisci un indirizzo", text: $text)
                        .keyboardType(.webSearch)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .focused($focused)
                        .onSubmit(go)
                    if !text.isEmpty {
                        Button { text = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Cancella")
                    }
                }
                .padding(10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

                Button("Annulla") { dismiss() }
            }
            HStack {
                if !tab.title.isEmpty {
                    Text(tab.title).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button {
                    tab.goHome()
                    dismiss()
                } label: {
                    Label("YouTube", systemImage: "house")
                        .font(.footnote)
                }
            }
        }
        .padding()
        .presentationDetents([.height(150)])
        .presentationDragIndicator(.visible)
        .onAppear { focused = true }
    }

    private func go() {
        tab.load(text)
        dismiss()
    }
}
