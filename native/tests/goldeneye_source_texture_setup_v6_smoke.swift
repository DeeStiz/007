import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

@main
struct GoldenEyeSourceTextureSetupV6Smoke {
    static func main() throws {
        let rootPath = CommandLine.arguments.dropFirst().first
            ?? ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_SOURCE_FRONTEND_ROOT"]
            ?? "build/native/source-frontend-v6"
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        let catalog = try GoldenEyeSourceFrontendCatalog.load(preparedAssetRoot: root)

        let legal = try loadModel(root: root, name: "legalpage")
        let nintendo = try loadModel(root: root, name: "nintendologo")
        let goldenEye = try loadModel(root: root, name: "goldeneyelogo")
        let wallet = try loadModel(root: root, name: "walletbond")

        let legalResult = try resolve(modelName: "legalpage", model: legal, catalog: catalog)
        let nintendoResult = try resolve(modelName: "nintendologo", model: nintendo, catalog: catalog)
        let goldenEyeResult = try resolve(modelName: "goldeneyelogo", model: goldenEye, catalog: catalog)
        let walletResult = try resolve(modelName: "walletbond", model: wallet, catalog: catalog)

        for result in [legalResult, nintendoResult, goldenEyeResult] {
            expect(!result.setups.isEmpty, "embedded model has no texture setups")
            expect(result.setups.allSatisfy { $0.kind == .standardTile }, "embedded model used custom-only setup")
            expect(result.setups.allSatisfy { !$0.tileState.derivedFromCustomCommand }, "embedded tile state was guessed")
            expect(result.setups.allSatisfy { $0.tileState.format != nil && $0.load.kind != .payload }, "embedded setup lost exact image/load state")
            expect(result.setups.allSatisfy { $0.levels.count > 0 && $0.levels.allSatisfy { $0.width > 0 && $0.height > 0 && $0.decodedByteCount > 0 } }, "embedded level evidence incomplete")
        }

        expect(!walletResult.setups.isEmpty, "Wallet has no gsSPUseTexture setups")
        expect(walletResult.setups.contains { $0.kind == .customGSetTex }, "Wallet did not resolve custom G_SETTEX")
        expect(!walletResult.aliases.isEmpty, "Wallet texture aliases missing")
        expect(walletResult.setups.allSatisfy { $0.tileState.derivedFromCustomCommand }, "Wallet custom setup used guessed standard tile state")
        expect(walletResult.setups.allSatisfy { $0.load.kind == .payload }, "Wallet custom setup lost payload load evidence")
        expect(walletResult.setups.allSatisfy { $0.levels.count == Int($0.maxLOD) + 1 }, "Wallet max LOD/level evidence mismatch")
        expect(walletResult.setups.contains { $0.palette != nil }, "Wallet TLUT identity was not resolved")
        expect(walletResult.setups.allSatisfy { $0.tileState.maskS <= 10 && $0.tileState.maskT <= 10 }, "Wallet mask out of source range")

        let repeatedWallet = try resolve(modelName: "walletbond", model: wallet, catalog: catalog)
        expect(repeatedWallet == walletResult, "texture setup hash/state is nondeterministic")

        let walletCommands = try commands(model: wallet, name: "walletbond")
        let withoutTextureState = walletCommands.filter { $0.macro != "gsSPTexture" }
        do {
            _ = try GoldenEyeSourceTextureSetupResolverV6.resolve(
                modelName: "walletbond", model: wallet, catalog: catalog, commands: withoutTextureState
            )
            preconditionFailure("missing gsSPTexture state unexpectedly accepted")
        } catch let error as GoldenEyeSourceTextureSetupV6Error {
            guard case .missingState = error else { throw error }
        }

        var malformed = walletCommands
        if let index = malformed.firstIndex(where: { $0.macro == "gsSPUseTexture" }) {
            let command = malformed[index]
            var args = command.arguments
            args[0] = 3
            malformed[index] = .init(sequence: command.sequence, displayListID: command.displayListID, ordinal: command.ordinal, macro: command.macro, arguments: args, word0: command.word0, word1: command.word1)
            do {
                _ = try GoldenEyeSourceTextureSetupResolverV6.resolve(modelName: "walletbond", model: wallet, catalog: catalog, commands: malformed)
                preconditionFailure("invalid address mode unexpectedly accepted")
            } catch let error as GoldenEyeSourceTextureSetupV6Error {
                guard case .invalidAddressMode = error else { throw error }
            }
        } else {
            preconditionFailure("Wallet fixture did not contain gsSPUseTexture")
        }

        if let first = walletCommands.first(where: { $0.macro == "gsSPUseTexture" }),
           let duplicateIndex = walletCommands.lastIndex(where: {
               $0.macro == "gsSPUseTexture" && $0.arguments.count == 9 && $0.arguments[8] == first.arguments[8]
           }) {
            var rawGSetTex = walletCommands
            let command = rawGSetTex[duplicateIndex]
            rawGSetTex[duplicateIndex] = .init(
                sequence: command.sequence,
                displayListID: command.displayListID,
                ordinal: command.ordinal,
                macro: "rawGfx",
                arguments: [],
                word0: command.word0,
                word1: command.word1
            )
            let rawResult = try GoldenEyeSourceTextureSetupResolverV6.resolve(
                modelName: "walletbond", model: wallet, catalog: catalog, commands: rawGSetTex
            )
            expect(rawResult.setups.contains { $0.sequence == command.sequence && $0.kind == .customGSetTex }, "raw G_SETTEX was not expanded")
        } else {
            preconditionFailure("Wallet fixture did not contain a repeated texture handle for raw G_SETTEX coverage")
        }

        print(
            "goldeneye_source_texture_setup_v6_smoke: PASS " +
                "embedded=\(legalResult.setups.count + nintendoResult.setups.count + goldenEyeResult.setups.count) " +
                "wallet=\(walletResult.setups.count) aliases=\(walletResult.aliases.count) " +
                "wallet_palettes=\(walletResult.setups.filter { $0.palette != nil }.count)"
        )
    }

    private static func loadModel(root: URL, name: String) throws -> GoldenEyeSourceModelV6 {
        let data = try Data(contentsOf: root.appendingPathComponent("\(name).gesm"), options: [.mappedIfSafe])
        return try GoldenEyeSourceModelV6.load(data: data, modelName: name)
    }

    private static func commands(model: GoldenEyeSourceModelV6, name: String) throws -> [GoldenEyeSourceTextureSetupCommandV6] {
        let compilation = GESourceModelCompilerV6.compile(model, modelName: name)
        guard let scene = compilation.scene else {
            throw compilation.diagnostics.first ?? GoldenEyeSourceTextureSetupV6Error.missingState(0, "source scene")
        }
        return scene.commands.enumerated().map { GoldenEyeSourceTextureSetupCommandV6(sequence: UInt32($0.offset), compiled: $0.element) }
    }

    private static func resolve(modelName: String, model: GoldenEyeSourceModelV6, catalog: GoldenEyeSourceFrontendCatalog) throws -> GoldenEyeSourceTextureSetupResultV6 {
        try GoldenEyeSourceTextureSetupResolverV6.resolve(
            modelName: modelName,
            model: model,
            catalog: catalog,
            commands: try commands(model: model, name: modelName)
        )
    }
}
