import Foundation

/// Runtime metadata for the exact 14-demo/7-stage reachability allowlist.
/// It is intentionally separate from setup-wide dependencies: only this
/// catalog may authorize a future visible prop/effect/HUD lowerer.
struct GoldenEyeRamRomVisibleDependencyCatalogV6: Sendable, Equatable {
    struct Dependency: Sendable, Equatable {
        let category: String
        let symbol: String
        let dependencyKind: String
        let modelIndex: UInt32?
        let demoIDs: [UInt8]
        let stages: [String]
    }

    enum Error: Swift.Error, CustomStringConvertible {
        case missing
        case invalid(String)
        var description: String {
            switch self {
            case .missing: return "RAMROM visible dependency manifest is missing"
            case .invalid(let detail): return "RAMROM visible dependency manifest is invalid: \(detail)"
            }
        }
    }

    static let manifestFileName = "ramrom-visible-dependencies-v6-manifest.txt"
    let rootURL: URL
    let dependencies: [Dependency]
    let categoryNames: [String]

    var isComplete: Bool { dependencies.count == 953 && categoryNames.count == 16 }
    func count(category: String) -> Int { dependencies.reduce(into: 0) { if $1.category == category { $0 += 1 } } }

    static func load(rootURL: URL) throws -> Self {
        let manifest = rootURL.appendingPathComponent(manifestFileName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: manifest.path) else { throw Error.missing }
        let lines = try String(contentsOf: manifest, encoding: .utf8).split(whereSeparator: { $0 == "\n" || $0 == "\r" }).map(String.init)
        var values: [String: String] = [:]
        var dependencies: [Dependency] = []
        for line in lines {
            guard let equal = line.firstIndex(of: "=") else { throw Error.invalid("missing =") }
            let key = String(line[..<equal])
            let payload = String(line[line.index(after: equal)...])
            if key.hasPrefix("dependency_"), key.dropFirst("dependency_".count).allSatisfy({ $0.isNumber }) {
                let fields = Dictionary(uniqueKeysWithValues: payload.split(separator: "|").compactMap { item -> (String, String)? in
                    let pair = item.split(separator: ":", maxSplits: 1).map(String.init)
                    guard pair.count == 2 else { return nil }
                    return (pair[0], pair[1])
                })
                guard let category = fields["category"], let symbol = fields["symbol"],
                      let stageText = fields["stages"],
                      let demoText = fields["demo_ids"] else { throw Error.invalid("dependency row") }
                let kind = fields["dependency_kind"] ?? category
                let modelIndex = fields["model_index"].flatMap(UInt32.init)
                let demoIDs = demoText.split(separator: ",").compactMap { UInt8($0) }
                let stages = stageText.split(separator: ",").map(String.init)
                dependencies.append(Dependency(category: category, symbol: symbol, dependencyKind: kind, modelIndex: modelIndex, demoIDs: demoIDs, stages: stages))
            } else {
                values[key] = payload
            }
        }
        guard values["manifest_status"] == "PASS",
              values["dependency_count"] == "953",
              values["category_count"] == "16",
              dependencies.count == 953 else {
            throw Error.invalid("status/count")
        }
        let categoryNames = (values["categories"] ?? "").split(separator: ",").map(String.init)
        return Self(rootURL: rootURL.standardizedFileURL, dependencies: dependencies, categoryNames: categoryNames)
    }
}
