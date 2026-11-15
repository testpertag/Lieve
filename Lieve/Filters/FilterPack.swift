import Foundation
import CryptoKit

/// Pacchetto filtri: regole WebKit + script. Formato prodotto da filters/tools/build_pack.py.
struct FilterPack: Decodable, Sendable {
    struct RuleList: Decodable, Sendable {
        let id: String
        let hash: String
        let critical: Bool
        let json: String
        /// L'hash nel nome evita di ricompilare le liste invariate.
        var identifier: String { "lieve.\(id).\(hash)" }
    }

    struct Script: Codable, Sendable {
        let id: String
        let world: String      // "page" | "lieve"
        let source: String
    }

    let format: Int
    let version: Int
    let contentHash: String
    let ruleLists: [RuleList]
    let scripts: [Script]
}

/// Indice leggero salvato su disco: all'avvio basta questo, senza decodificare le regole.
struct FilterIndex: Codable, Sendable {
    struct ListRef: Codable, Sendable {
        let identifier: String
        let critical: Bool
    }

    let version: Int
    let contentHash: String
    let appBuild: String
    let lists: [ListRef]
    let scripts: [FilterPack.Script]
}

enum PackError: Error {
    case badMagic, badSignature, unsupportedFormat
}

/// File .lvp = "LVP1" | firma Ed25519 (64 byte) | JSON compresso DEFLATE.
enum PackFile {
    private static let magic = Data("LVP1".utf8)
    private static let signatureLength = 64

    /// publicKey nil = pacchetto incluso nell'app (già protetto dalla firma dell'app).
    static func decode(_ data: Data, publicKey: Data?) throws -> FilterPack {
        let start = data.startIndex
        let headerEnd = start + magic.count + signatureLength
        guard data.count > magic.count + signatureLength,
              data.subdata(in: start..<(start + magic.count)) == magic else { throw PackError.badMagic }

        let signature = data.subdata(in: (start + magic.count)..<headerEnd)
        let body = data.subdata(in: headerEnd..<data.endIndex)

        if let publicKey {
            let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
            guard key.isValidSignature(signature, for: body) else { throw PackError.badSignature }
        }

        let json = try (body as NSData).decompressed(using: .zlib) as Data
        let pack = try JSONDecoder().decode(FilterPack.self, from: json)
        guard pack.format == 1 else { throw PackError.unsupportedFormat }
        return pack
    }
}

/// Origine degli aggiornamenti, configurata in fase di build (Info.plist).
enum FilterSource {
    static var remoteURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "LieveFiltersURL") as? String,
              value.hasPrefix("https://"),
              let url = URL(string: value) else { return nil }
        return url
    }

    static var publicKey: Data? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "LieveFiltersPublicKey") as? String,
              let data = Data(base64Encoded: value), data.count == 32 else { return nil }
        return data
    }

    /// Sessione senza cookie né cache: la richiesta non porta alcun dato di navigazione.
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()
}

/// Lettura/scrittura su disco, sempre fuori dal main thread per i file grandi.
enum FilterDisk {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Filters", isDirectory: true)
    }
    static var packURL: URL { directory.appendingPathComponent("pack.lvp") }
    static var indexURL: URL { directory.appendingPathComponent("index.json") }

    /// File piccolo (pochi KB): lettura sincrona accettabile.
    static func readIndex() -> FilterIndex? {
        guard let data = try? Data(contentsOf: indexURL) else { return nil }
        return try? JSONDecoder().decode(FilterIndex.self, from: data)
    }

    static func save(packData: Data, index: FilterIndex) async throws {
        try await Task.detached(priority: .utility) {
            try FileManager.default.createDirectory(at: FilterDisk.directory, withIntermediateDirectories: true)
            try packData.write(to: FilterDisk.packURL, options: .atomic)
            try JSONEncoder().encode(index).write(to: FilterDisk.indexURL, options: .atomic)
        }.value
    }

    static func saveIndex(_ index: FilterIndex) {
        try? JSONEncoder().encode(index).write(to: indexURL, options: .atomic)
    }

    static func loadBundled() async -> (pack: FilterPack, data: Data)? {
        guard let url = Bundle.main.url(forResource: "FilterPack", withExtension: "lvp") else { return nil }
        return try? await Task.detached(priority: .userInitiated) {
            let data = try Data(contentsOf: url)
            let pack = try PackFile.decode(data, publicKey: nil)
            return (pack: pack, data: data)
        }.value
    }

    /// Il pacchetto installato è già stato verificato al momento dell'installazione.
    static func loadInstalled() async -> FilterPack? {
        try? await Task.detached(priority: .userInitiated) {
            try PackFile.decode(Data(contentsOf: FilterDisk.packURL), publicKey: nil)
        }.value
    }
}
