// Compila ogni lista del pacchetto con il vero compilatore WebKit (macOS) e
// individua per bisezione le singole regole rifiutate.
// Uso (solo macOS): swift filters/tools/check_rules.swift dist/pack.lvp bad-rules.json
// Output: { "idLista": [indici delle regole da scartare] }. Exit 1 se una lista "critical" fallisce.
import Foundation
import WebKit

struct Pack: Decodable {
    struct RuleList: Decodable { let id: String; let critical: Bool; let json: String }
    let ruleLists: [RuleList]
}

let args = CommandLine.arguments
guard args.count == 3 else { print("uso: check_rules.swift pack.lvp out.json"); exit(2) }
let data = try Data(contentsOf: URL(fileURLWithPath: args[1]))
let body = data.subdata(in: (data.startIndex + 68)..<data.endIndex)
let json = try (body as NSData).decompressed(using: .zlib) as Data
let pack = try JSONDecoder().decode(Pack.self, from: json)

let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lieve-rules-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
let store = WKContentRuleListStore(url: dir)!

@MainActor
func compileError(_ rules: [Any]) async -> String? {
    let text = String(data: try! JSONSerialization.data(withJSONObject: rules), encoding: .utf8)!
    return await withCheckedContinuation { cont in
        store.compileContentRuleList(forIdentifier: "check", encodedContentRuleList: text) { _, error in
            cont.resume(returning: error.map { "\($0)" })
        }
    }
}

@MainActor
func badIndices(_ rules: [Any], offset: Int) async -> [Int] {
    if rules.isEmpty || (await compileError(rules)) == nil { return [] }
    if rules.count == 1 { return [offset] }
    let mid = rules.count / 2
    return await badIndices(Array(rules[..<mid]), offset: offset)
        + badIndices(Array(rules[mid...]), offset: offset + mid)
}

var report: [String: [Int]] = [:]
var criticalFailure = false
for list in pack.ruleLists {
    let rules = try JSONSerialization.jsonObject(with: Data(list.json.utf8)) as! [Any]
    let start = Date()
    if let error = await compileError(rules) {
        let bad = await badIndices(rules, offset: 0)
        print("✗ \(list.id): \(rules.count) regole, \(bad.count) rifiutate — \(error)")
        for i in bad.prefix(5) {
            let one = String(data: try JSONSerialization.data(withJSONObject: rules[i]), encoding: .utf8)!
            print("    #\(i) \(one.prefix(200))")
        }
        if list.critical { criticalFailure = true }
        if bad.isEmpty { print("    errore a livello di lista, nessuna regola singola colpevole") }
        report[list.id] = bad
    } else {
        print("✓ \(list.id): \(rules.count) regole compilate in \(String(format: "%.2f", Date().timeIntervalSince(start))) s")
    }
}
try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]).write(to: URL(fileURLWithPath: args[2]))
try? FileManager.default.removeItem(at: dir)
exit(criticalFailure ? 1 : 0)
