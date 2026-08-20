import Foundation

@main
struct GoldenEyeSourceFrontendCatalogV6Smoke {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let rootPath = arguments.first
            ?? ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_SOURCE_FRONTEND_ROOT"]
            ?? "build/native/source-frontend-v6"
        let expectedFailure = arguments.dropFirst().first
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)

        do {
            let catalog = try GoldenEyeSourceFrontendCatalog.load(preparedAssetRoot: root)
            if let expectedFailure {
                throw SmokeError.unexpectedSuccess(expectedFailure)
            }

            precondition(catalog.records.count > 1_150)
            precondition(catalog.manifest.counts["texture_payload"] ?? 0 > 0)
            precondition(catalog.manifest.counts["mip_payload"] ?? 0 > 0)
            precondition(catalog.manifest.counts["tlut_payload"] ?? 0 > 0)
            precondition(catalog.manifest.counts.count >= 31)
            precondition(catalog.sidecars.count == 8)
            precondition(catalog.sidecars.map(\.name) == [
                "chrwppk", "goldeneyelogo", "headbrosnansuit", "legalpage",
                "nintendologo", "rarewarelogo", "suitbond", "walletbond"
            ])
            precondition(catalog.manifest.runtimeROMAccess == false)
            precondition(catalog.manifest.sourcePathsAreRelative)
            precondition(catalog.manifest.romCopiedIntoCheckout == false)
            precondition(catalog.manifest.romCopiedIntoBundle == false)
            precondition(catalog.manifest.privatePayloadsCopiedIntoCheckout == false)
            precondition(catalog.manifest.privatePayloadsCopiedIntoBundle == false)
            precondition(catalog.packetSHA256.count == 64)
            precondition(catalog.sourceCatalogSHA256.count == 64)
            precondition(catalog.payloadSHA256.count == 64)

            for kind in GoldenEyeSourceFrontendResourceKind.allCases {
                precondition(!catalog.records(of: kind).isEmpty, "missing typed resource kind \(kind.rawValue)")
            }

            let model = try catalog.record(kind: .model, name: "legalpage", family: "legal")
            let modelBytes = try catalog.copyOut(.decoded, for: model)
            precondition(modelBytes.count == Int(model.decodedSize))
            precondition(modelBytes.count > 0)

            let image = try catalog.record(kind: .image, name: "COPYICON", family: "frontend")
            do {
                _ = try catalog.copyOut(.decoded, for: image)
                preconditionFailure("provenance-only image stream unexpectedly exposed pixel bytes")
            } catch let error as GoldenEyeSourceFrontendCatalogError {
                guard case .invalidValue = error else { throw error }
            }
            let globalTexture = try catalog.record(kind: .texture, name: "COPYICON.payload", family: "frontend")
            let globalTextureBytes = try catalog.copyOut(.decoded, for: globalTexture)
            precondition(globalTextureBytes.count == Int(globalTexture.decodedSize))

            let texture = try catalog.record(kind: .texture, name: "goldeneyelogo.texture_payload.0", family: "goldeneyelogo")
            let textureBytes = try catalog.copyOut(.raw, for: texture)
            precondition(textureBytes.count == Int(texture.rawSize))
            let textureByID = try catalog.copyOut(.decoded, recordID: texture.id)
            precondition(textureByID.count == Int(texture.decodedSize))

            let mip = try catalog.record(kind: .mip, name: "goldeneyelogo.texture.0.mip.0", family: "goldeneyelogo")
            let mipBytes = try catalog.copyOut(.decoded, for: mip)
            precondition(mipBytes.count == Int(mip.decodedSize))

            do {
                _ = try catalog.record(kind: .texture, name: "goldeneyelogo.texture.0", family: "goldeneye")
                preconditionFailure("source texture descriptor unexpectedly exposed as a consumable texture")
            } catch let error as GoldenEyeSourceFrontendCatalogError {
                guard case .recordNotFound = error else { throw error }
            }

            let palette = try catalog.record(kind: .tlut, name: "1555.tlut", family: "frontend")
            let paletteBytes = try catalog.copyOut(.decoded, for: palette)
            precondition(paletteBytes.count == Int(palette.decodedSize))

            let displayLists = catalog.lookup(kind: .displayList, name: "GFX_PRIMARY_0x66a0")
            precondition(displayLists.count == 2)
            do {
                _ = try catalog.record(kind: .displayList, name: "GFX_PRIMARY_0x66a0")
                preconditionFailure("ambiguous lookup should throw")
            } catch let error as GoldenEyeSourceFrontendCatalogError {
                guard case .ambiguousRecord = error else { throw error }
            }

            print(
                "goldeneye_source_frontend_catalog_v6_smoke: PASS " +
                    "records=\(catalog.records.count) categories=\(catalog.manifest.counts.count) typed_kinds=13"
            )
        } catch let error as GoldenEyeSourceFrontendCatalogError {
            if let expectedFailure {
                let message = error.description
                precondition(message.contains(expectedFailure), "expected \(expectedFailure), got \(message)")
                print("goldeneye_source_frontend_catalog_v6_smoke: PASS expected_failure=\(expectedFailure)")
                return
            }
            throw error
        } catch let error as SmokeError {
            throw error
        }

    }

    private enum SmokeError: Error, CustomStringConvertible {
        case unexpectedSuccess(String)

        var description: String {
            switch self {
            case let .unexpectedSuccess(expected):
                return "expected catalog failure but load succeeded: \(expected)"
            }
        }
    }
}
