import Foundation

private let expected: [String: [Int]] = [
    "chrwppk": [4, 4, 2, 35, 183, 50, 5, 18, 4],
    "goldeneyelogo": [3, 3, 1, 162, 1214, 438, 2, 7, 0],
    "headbrosnansuit": [4, 4, 2, 119, 878, 290, 5, 10, 5],
    "legalpage": [3, 3, 1, 58, 148, 24, 5, 5, 0],
    "nintendologo": [42, 42, 23, 821, 4313, 1363, 1, 1, 0],
    "rarewarelogo": [0, 0, 9, 389, 1724, 397, 6, 26, 0],
    "suitbond": [79, 79, 25, 554, 3034, 726, 14, 69, 14],
    "walletbond": [90, 90, 46, 982, 4205, 765, 84, 186, 2],
]
private let expectedStaticScenes: [String: (visibleNodes: Int, commands: Int)] = [
    "legalpage": (3, 58),
    "nintendologo": (42, 821),
    "goldeneyelogo": (3, 162),
    "walletbond": (27, 390),
]
private let expectedPacketHashes: [String: String] = [
    "chrwppk": "c4c91d48e80702b187e695b2a8926778395f7a8d4daa9bf638502566d506951a",
    "goldeneyelogo": "b73bb84432ad1cd2e821ccc339502a5900571643e0b956ca53d581a5abfee6c1",
    "headbrosnansuit": "abdc61c0874c1cb373a3d4da77f26649dc3e93247944245a8dd9bc534878d130",
    "legalpage": "da42f17da9654a83a7c0a7ab3fd3233cc6892434c07cd593227932fb2e545f22",
    "nintendologo": "a41b43bf4bab4200156296b31b061c858287076ad895abee1e4dcec640693d97",
    "rarewarelogo": "5b54353bb0f4dad0a7d314aaf8e6e9673d913d1137507e2f6ba338a0a40bb47d",
    "suitbond": "6f1603acd148325c49beaaf6c6911e9b4f5b15d81eda1574127ddf66bb77bae2",
    "walletbond": "20fde4c360df22c814d0e5c9ee15658e60cd2917f7b1b7820e8bf4ecc3bca29e",
]

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

private let smokeArguments = Array(CommandLine.arguments.dropFirst())
let root = URL(fileURLWithPath: smokeArguments.first ?? "build/native/source-frontend-v6", isDirectory: true)
@main
struct GoldenEyeSourceModelV6Smoke {
    static func main() throws {
        var models: [String: GoldenEyeSourceModelV6] = [:]
        var macros = Set<String>()

for name in expected.keys.sorted() {
    let url = root.appendingPathComponent("\(name).gesm")
    let data = try Data(contentsOf: url)
    let model = try GoldenEyeSourceModelV6.load(data: data, modelName: name)
    let counts = model.header.counts
    let actual = [counts.nodes, counts.scalars, counts.displayLists, counts.commands, counts.tokens, counts.vertices, counts.textures, counts.mips, counts.tluts]
    check(actual == expected[name]!, "\(name) exact counts: \(actual)")
    let packetHash = model.header.packetHash.map { String(format: "%02x", $0) }.joined()
    check(packetHash == expectedPacketHashes[name]!, "\(name) final packet hash")
    check(model.header.recordCount == counts.recordCount, "\(name) record count")
    check(model.nodes.count == counts.nodes && model.commands.count == counts.commands, "\(name) row counts")
    check(model.displayLists.allSatisfy { $0.commandCount > 0 }, "\(name) nonempty lists")
    for command in model.commands {
        guard let open = command.semantic.firstIndex(of: "(") else { preconditionFailure("missing macro \(name)") }
        macros.insert(String(command.semantic[..<open]))
        check(command.macroHandle != 0, "\(name) command macro handle")
        check(model.tokens(for: model.commands.firstIndex(of: command) ?? 0).count == Int(command.tokenCount), "\(name) token span")
    }
    for token in model.tokens {
        check(!token.text.contains("address") && !token.text.contains("pointer") && !token.text.contains("@"), "\(name) sanitized token")
    }
    for value in model.stringTable {
        check(!value.contains("address") && !value.contains("pointer") && !value.contains("@"), "\(name) sanitized string table")
    }
    for node in model.nodes {
        check(model.node(id: node.id) == node, "\(name) node lookup")
        check(node.kind != .unknown, "\(name) unknown ModelNode opcode")
    }
    for list in model.displayLists {
        check(model.displayList(handle: list.handle) == list, "\(name) display-list lookup")
    }
    for texture in model.textures {
        check(model.texture(handle: texture.resourceHandle) == texture, "\(name) texture lookup")
    }
    models[name] = model
        print("source-model-v6: \(name) counts=\(actual) packet=\(model.header.packetHash.map { String(format: "%02x", $0) }.joined()) PASS")
}

let nodeKinds = Set(models.values.flatMap { $0.nodes.map(\.kind) })
check(GoldenEyeSourceModelV6.NodeKind.requiredM7.isSubset(of: nodeKinds),
      "M7 required ModelNode families missing: \(GoldenEyeSourceModelV6.NodeKind.requiredM7.subtracting(nodeKinds))")
let nodeKindCounts = GoldenEyeSourceModelV6.NodeKind.allCases.compactMap { kind -> String? in
    let count = models.values.reduce(0) { total, model in
        total + model.nodes.filter { $0.kind == kind }.count
    }
    return count == 0 ? nil : "\(kind.rawValue)=\(count)"
}.joined(separator: ",")
print("source-model-v6 M7 node families: \(nodeKindCounts) required=\(GoldenEyeSourceModelV6.NodeKind.requiredM7.count) PASS")

let supported = GESourceModelCompilerV6.supportedMacros
check(macros.isSubset(of: supported), "exercised macro coverage unknown=\(macros.subtracting(supported))")
check(macros.isSuperset(of: GESourceModelCompilerV6.requiredSourceMacros), "exercised macro coverage missing=\(GESourceModelCompilerV6.requiredSourceMacros.subtracting(macros))")
check(macros.count == 24 || macros.count == 25, "macro family count")

if smokeArguments.count > 1 {
    var rows: [String] = []
    rows.append("model\tcommand\tmacro\tsemantic\tword0\tword1\targc\targuments")
    for name in expected.keys.sorted() {
        let model = models[name]!
        for commandIndex in model.commands.indices {
            guard let encoded = GESourceModelCompilerV6.encodedWords(model: model, commandIndex: commandIndex) else {
                preconditionFailure("old GBI encoding unavailable: \(name) command \(commandIndex)")
            }
            let arguments = encoded.arguments.map { String($0) }.joined(separator: "\t")
            rows.append("\(name)\t\(commandIndex)\t\(encoded.macro)\t\(model.commands[commandIndex].semantic)\t\(encoded.word0)\t\(encoded.word1)\t\(encoded.arguments.count)\t\(arguments)")
        }
    }
    let manifestURL = URL(fileURLWithPath: smokeArguments[1])
    try rows.joined(separator: "\n").appending("\n").write(to: manifestURL, atomically: true, encoding: .utf8)
    print("source-model-v6 word manifest: rows=\(rows.count - 1) path=\(manifestURL.path) PASS")
}

for name in ["legalpage", "nintendologo", "goldeneyelogo", "walletbond"] {
    let model = models[name]!
    let result = GESourceModelCompilerV6.compile(model, modelName: name, switchInputs: [:])
    check(result.status == .complete, "\(name) compiler status")
    check(result.diagnostics.isEmpty, "\(name) compiler diagnostics: \(result.diagnostics)")
    check(result.scene != nil, "\(name) scene")
    check(result.scene?.unsupportedCount == 0, "\(name) unsupported commands")
    check(result.scene?.commands.isEmpty == false, "\(name) compiled commands")
    check(result.scene?.visibleNodeIDs.isEmpty == false, "\(name) visible nodes")
    check(result.scene?.visibleNodeIDs.count == expectedStaticScenes[name]!.visibleNodes, "\(name) source/BSP visible ownership actual=\(result.scene?.visibleNodeIDs.count ?? -1)")
    check(result.scene?.commands.count == expectedStaticScenes[name]!.commands, "\(name) selected display-list ownership actual=\(result.scene?.commands.count ?? -1)")
    check(result.scene?.displayListHandles.count == result.scene?.displayLists.count, "\(name) display-list resource table")
    check(result.scene?.vertexGroupHandles.isEmpty == false && result.scene?.textureHandles.count == model.textures.count, "\(name) vertex/texture resource tables")
    let second = GESourceModelCompilerV6.compile(model, modelName: name, switchInputs: [:])
    check(second.scene?.semanticHash == result.scene?.semanticHash, "\(name) deterministic compiler hash")
    print("source-model-v6 compiler: \(name) visible=\(result.scene!.visibleNodeIDs.count) commands=\(result.scene!.commands.count) hash=\(result.scene!.semanticHash) PASS")
}

let sourceWordFixtures: [String: (high: UInt32, low: UInt32, combine: UInt32)] = [
    "legalpage": (0x00502048, 0x00000000, 0xfffe793c),
    "nintendologo": (0x00502048, 0x00000000, 0xfffff9fc),
    "goldeneyelogo": (0x0c182048, 0x00100000, 0x1f1093ff),
]
for (name, fixture) in sourceWordFixtures {
    let model = models[name]!
    guard let highCommand = model.commands.first(where: { $0.semantic.hasPrefix("gsSPSetOtherMode(G_SETOTHERMODE_L") }),
          let lowCommand = model.commands.first(where: { $0.semantic.hasPrefix("gsSPSetOtherMode(G_SETOTHERMODE_H") }),
          let combineCommand = model.commands.first(where: { $0.semantic.hasPrefix("gsDPSetCombine(") }),
          let highIndex = model.commands.firstIndex(of: highCommand),
          let lowIndex = model.commands.firstIndex(of: lowCommand),
          let combineIndex = model.commands.firstIndex(of: combineCommand),
          let highWords = GESourceModelCompilerV6.encodedWords(model: model, commandIndex: highIndex),
          let lowWords = GESourceModelCompilerV6.encodedWords(model: model, commandIndex: lowIndex),
          let combineWords = GESourceModelCompilerV6.encodedWords(model: model, commandIndex: combineIndex) else {
        preconditionFailure("source word fixture unavailable: \(name)")
    }
    check(highWords.word1 == fixture.high, "\(name) source L other-mode fixture")
    check(lowWords.word1 == fixture.low, "\(name) source H other-mode fixture")
    check(combineWords.word1 == fixture.combine, "\(name) source combine fixture")
    print("source-model-v6 source-word fixture: \(name) PASS")
}

for name in ["rarewarelogo", "headbrosnansuit", "suitbond", "chrwppk"] {
    let result = GESourceModelCompilerV6.compile(models[name]!, modelName: name)
    check(result.status == .dynamicDependency, "\(name) dynamic status")
    check(result.scene == nil, "\(name) no fallback scene")
    check(result.diagnostics.contains { if case .dynamicDependency = $0 { return true }; return false }, "\(name) typed dynamic diagnostic")
    print("source-model-v6 compiler: \(name) dynamic diagnostic=\(result.diagnostics[0]) PASS")
}

if let switchNode = models["walletbond"]!.nodes.first(where: { $0.opcodeHandle == 0x258d_b802 }) {
    let walletSwitches = models["walletbond"]!.nodes.filter { $0.opcodeHandle == 0x258d_b802 }
    let allZero = Dictionary(uniqueKeysWithValues: walletSwitches.map { ($0.id, UInt32(0)) })
    let selected = GESourceModelCompilerV6.compile(models["walletbond"]!, modelName: "walletbond", switchInputs: allZero)
    check(selected.scene?.visibleNodeIDs.count == expectedStaticScenes["walletbond"]!.visibleNodes, "wallet all-zero switch fixture visible")
    check(selected.scene?.commands.count == expectedStaticScenes["walletbond"]!.commands, "wallet all-zero switch fixture commands")
    let malformed = GESourceModelCompilerV6.compile(models["walletbond"]!, modelName: "walletbond", switchInputs: [switchNode.id: 1])
    check(malformed.scene == nil, "switch malformed scene fallback")
    check(malformed.diagnostics.contains { if case .malformedSwitch = $0 { return true }; return false }, "switch malformed typed diagnostic")
    print("source-model-v6 switch guard: PASS")
}

// Header, packet-hash, and truncation guards must fail closed.
let legalURL = root.appendingPathComponent("legalpage.gesm")
let legalData = try Data(contentsOf: legalURL)
var reserved = legalData
reserved[128] = 1
do { _ = try GoldenEyeSourceModelV6.load(data: reserved, modelName: "legalpage"); preconditionFailure("reserved header accepted") } catch { print("source-model-v6 reserved guard: PASS") }
var tampered = legalData
tampered[GoldenEyeSourceModelV6.headerSize] ^= 0x01
do { _ = try GoldenEyeSourceModelV6.load(data: tampered, modelName: "legalpage"); preconditionFailure("packet hash accepted") } catch { print("source-model-v6 packet hash guard: PASS") }
do { _ = try GoldenEyeSourceModelV6.load(data: Data(legalData.dropLast()), modelName: "legalpage"); preconditionFailure("truncation accepted") } catch { print("source-model-v6 truncation guard: PASS") }

        print("source-model-v6 validation: PASS models=\(models.count) macros=\(macros.count)")
    }
}
