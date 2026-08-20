import Foundation

@main
struct GoldenEyeSourceOtherModeDumpV6 {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/native/source-frontend-v6", isDirectory: true)
        let names = CommandLine.arguments.dropFirst().dropFirst().isEmpty
            ? ["legalpage", "nintendologo", "goldeneyelogo", "walletbond", "rarewarelogo"]
            : Array(CommandLine.arguments.dropFirst().dropFirst())
        for name in names {
            let model = try GoldenEyeSourceModelV6.load(
                data: Data(contentsOf: root.appendingPathComponent("\(name).gesm")),
                modelName: name
            )
            print("MODEL \(name) commands=\(model.commands.count)")
            for scalar in model.scalars.prefix(20) {
                let metadata = scalar.metadata.map { String($0, radix: 16) }.joined(separator: ",")
                print("  SCALAR owner=\(scalar.ownerID) kind=\(scalar.semantic) metadata=\(metadata)")
            }
            for index in model.commands.indices {
                let command = model.commands[index]
                let macro = command.semantic.split(separator: "(", maxSplits: 1).first.map(String.init) ?? command.semantic
                guard macro.contains("OtherMode") || macro.contains("TextureLOD") ||
                        macro.contains("TextureFilter") || macro.contains("CycleType") ||
                        macro.contains("RenderMode") || macro.contains("Combine") else { continue }
                let tokens = model.tokens(for: index).map { "\($0.text)[0x\(String($0.encodedValue, radix: 16))]" }.joined(separator: ",")
                print("  \(index) \(command.semantic) tokens=\(tokens)")
            }
        }
    }
}
