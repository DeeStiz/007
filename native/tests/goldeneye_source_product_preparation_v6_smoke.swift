import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), "goldeneye_source_product_preparation_v6_smoke: \(message)")
}

private let root = URL(
    fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/native/source-frontend-v6",
    isDirectory: true
)

@main
struct GoldenEyeSourceProductPreparationV6Smoke {
    static func main() throws {
        let preparation = try GoldenEyeSourceProductPreparationV6.load(rootURL: root)
        expect(preparation.catalog.manifest.externalROMSHA1 == GoldenEyeSourceFrontendCatalog.expectedExternalROMSHA1, "external ROM boundary")
        expect(preparation.catalog.manifest.runtimeROMAccess == false, "runtime ROM access disabled")
        expect(preparation.catalog.manifest.romCopiedIntoBundle == false, "ROM absent from bundle")
        expect(preparation.catalog.manifest.privatePayloadsCopiedIntoBundle == false, "private payloads absent from bundle")
        expect(Set(preparation.models.keys) == GoldenEyeSourceProductPreparationV6.requiredModelNames, "complete model set")
        let executed = GoldenEyeSourceProductModelExecutionResultV6.executed(
            model: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_LEGALPAGE),
            operation: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_DRAW)
        )
        expect(executed.isExecuted, "typed executed result")
        expect(GoldenEyeSourceProductFrameClassifierV6.isClearBlackOnly(
            renderOperations: [
                UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_FRAME_BEGIN),
                UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_CLEAR_BLACK),
            ],
            modelEventCount: 0,
            textEventCount: 0
        ), "clear-black classification")
        expect(!GoldenEyeSourceProductFrameClassifierV6.isClearBlackOnly(
            renderOperations: [UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_CLEAR_BLACK)],
            modelEventCount: 1,
            textEventCount: 0
        ), "model prevents clear-black classification")
        for name in GoldenEyeSourceProductPreparationV6.requiredModelNames.sorted() {
            let model = try preparation.model(named: name)
            expect(model.header.modelHandle != 0, "\(name) model handle")
            expect(!model.displayLists.isEmpty, "\(name) display lists")
            expect(!model.commands.isEmpty, "\(name) commands")
            expect(!model.textures.isEmpty, "\(name) textures")
        }

        do {
            _ = try GoldenEyeSourceProductPreparationV6.load(
                rootURL: URL(fileURLWithPath: "/definitely/not/a/prepared/source/root", isDirectory: true)
            )
            preconditionFailure("expected missing root failure")
        } catch {
            print("preparation-v6 missing-root rejection: PASS (\(error))")
        }

        print("goldeneye_source_product_preparation_v6_smoke: PASS models=\(preparation.models.count) records=\(preparation.catalog.records.count) packet=\(preparation.catalog.packetSHA256)")
    }
}
