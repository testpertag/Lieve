import Foundation

enum URLInput {
    /// Trasforma il testo della barra in un URL: indirizzo completo, dominio nudo o ricerca.
    static func url(from raw: String) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let url = URL(string: text),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https",
           url.host != nil {
            return url
        }

        if !text.contains(" "), text.contains("."),
           let url = URL(string: "https://" + text), url.host != nil {
            return url
        }

        return AppConfig.searchURL(for: text)
    }
}
