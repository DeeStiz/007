import Foundation
import Metal

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

private func fixture(
    name: String,
    handle: UInt32,
    width: UInt32,
    height: UInt32,
    mipLevels: UInt32,
    withPalette: Bool
) -> GoldenEyeSourceTextureDescriptorV6 {
    var levels: [GoldenEyeSourceTextureLevelUploadV6] = []
    for level in 0..<mipLevels {
        let levelWidth = max(1, width >> level)
        let levelHeight = max(1, height >> level)
        let byteCount = Int(levelWidth) * Int(levelHeight) * 4
        levels.append(.init(
            level: level,
            width: levelWidth,
            height: levelHeight,
            payloadRecordID: handle &+ level &+ 1,
            sourceOffset: level * 64,
            sourceRowHandle: handle &+ 0x100,
            rawByteCount: UInt32(max(1, byteCount / 2)),
            decodedByteCount: UInt32(byteCount),
            decodedSHA256: "",
            decoded: Data(repeating: UInt8(truncatingIfNeeded: handle &+ level), count: byteCount)
        ))
    }
    let palette: GoldenEyeSourceTexturePaletteUploadV6?
    if withPalette {
        palette = .init(
            resourceHandle: handle,
            entries: 4,
            payloadRecordID: handle &+ 0x200,
            sourceOffset: 0,
            sourceRowHandle: handle &+ 0x300,
            rawByteCount: 8,
            decodedByteCount: 16,
            decodedSHA256: "",
            decoded: Data(repeating: 0x7f, count: 16)
        )
    } else {
        palette = nil
    }
    return .init(
        modelName: name,
        family: name,
        resourceHandle: handle,
        width: width,
        height: height,
        mipLevels: mipLevels,
        payloadRecordID: handle &+ 0x400,
        sourceOffset: 0,
        sourceRowHandle: handle &+ 0x500,
        sourceSpan: UInt32(max(1, Int(width) * Int(height))),
        levels: levels,
        palette: palette
    )
}

private func purePlanSmoke() throws -> GoldenEyeSourceTextureUploadPlanV6 {
    let fixtures = [
        fixture(name: "Legal", handle: 0x1001, width: 32, height: 32, mipLevels: 1, withPalette: false),
        fixture(name: "Nintendo", handle: 0x1002, width: 32, height: 32, mipLevels: 1, withPalette: false),
        fixture(name: "GoldenEye", handle: 0x1003, width: 32, height: 32, mipLevels: 6, withPalette: false),
        fixture(name: "Rareware", handle: 0x1004, width: 32, height: 32, mipLevels: 6, withPalette: false),
        fixture(name: "Wallet", handle: 0x1005, width: 64, height: 64, mipLevels: 7, withPalette: true),
    ]
    let plan = try GoldenEyeSourceTextureUploadPlanV6.make(descriptors: fixtures)
    check(plan.descriptors.map(\.modelName) == ["GoldenEye", "Legal", "Nintendo", "Rareware", "Wallet"], "deterministic descriptor order")
    check(plan.descriptors.count == 5, "fixture descriptor count")
    check(plan.levelRanges.count == 21, "fixture mip range count")
    check(plan.paletteEvidence.count == 1, "fixture palette evidence count")
    check(plan.levelRanges.allSatisfy { $0.offset % 4 == 0 }, "RGBA8 staging alignment")
    check(plan.stagingByteCount > 0, "fixture staging bytes")

    do {
        _ = try GoldenEyeSourceTextureUploadPlanV6.make(descriptors: [fixtures[0], fixtures[0]])
        preconditionFailure("duplicate source handles accepted")
    } catch let error as GoldenEyeSourceTextureStoreV6Error {
        guard case .duplicateResourceHandle = error else { throw error }
    }
    print("source-texture-store-v6 pure upload plans: PASS models=5 mips=\(plan.levelRanges.count)")
    return plan
}

private func loadModels(root: URL, names: [String]) throws -> [(name: String, model: GoldenEyeSourceModelV6)] {
    try names.map { name in
        let url = root.appendingPathComponent("\(name).gesm")
        return (name: name, model: try GoldenEyeSourceModelV6.load(
            data: Data(contentsOf: url, options: [.mappedIfSafe]),
            modelName: name
        ))
    }
}

@available(macOS 26.0, *)
private func boundedMetalSmoke(
    plan: GoldenEyeSourceTextureUploadPlanV6
) throws {
    guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4) else {
        print("source-texture-store-v6 Metal upload smoke: SKIP no Metal 4 device")
        return
    }
    let queueDescriptor = MTL4CommandQueueDescriptor()
    guard let queue = try? device.makeMTL4CommandQueue(descriptor: queueDescriptor) else {
        print("source-texture-store-v6 Metal upload smoke: SKIP no Metal 4 queue")
        return
    }
    let residencyDescriptor = MTLResidencySetDescriptor()
    guard let residency = try? device.makeResidencySet(descriptor: residencyDescriptor),
          let event = device.makeSharedEvent() else {
        print("source-texture-store-v6 Metal upload smoke: SKIP residency/event unavailable")
        return
    }
    queue.addResidencySet(residency)
    let context = GoldenEyeSourceTextureStoreV6MetalContext(
        device: device,
        queue: queue,
        residency: residency,
        completionEvent: event
    )
    let store = try GoldenEyeSourceTextureStoreV6(context: context)
    let evidence = try store.upload(plan: plan)
    check(store.textureCount == plan.descriptors.count, "Metal texture count")
    check(evidence.validatedPaletteCount == plan.paletteEvidence.count, "CPU palette evidence count")
    check(evidence.gpuPaletteCount == 0, "unconsumed palette GPU allocation")
    check(evidence.barrier == "blit->fragment:device", "Metal visibility evidence")
    try store.shutdown(timeoutMS: 5_000)
    check(store.textureCount == 0, "Metal shutdown resource release")
    print(
        "source-texture-store-v6 Metal upload smoke: PASS "
            + "textures=\(evidence.textureCount) levels=\(evidence.levelCount) "
            + "validated_palettes=\(evidence.validatedPaletteCount) "
            + "gpu_palettes=\(evidence.gpuPaletteCount) bytes=\(evidence.stagingByteCount)"
    )
}

@main
struct GoldenEyeSourceTextureStoreV6Smoke {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let root = URL(
            fileURLWithPath: arguments.first
                ?? ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_SOURCE_FRONTEND_ROOT"]
                ?? "build/native/source-frontend-v6",
            isDirectory: true
        )
        let fixturePlan = try purePlanSmoke()
        if arguments.contains("--fixtures-only") {
            if #available(macOS 26.0, *) {
                try boundedMetalSmoke(plan: fixturePlan)
            } else {
                print("source-texture-store-v6 Metal upload smoke: SKIP macOS 26 required")
            }
            print("goldeneye_source_texture_store_v6_smoke: PASS fixtures-only")
            return
        }

        let sourceNames = [
            "chrwppk", "goldeneyelogo", "headbrosnansuit", "legalpage",
            "nintendologo", "rarewarelogo", "suitbond", "walletbond"
        ]
        let sourceModels = try loadModels(root: root, names: sourceNames)
        let catalog = try GoldenEyeSourceFrontendCatalog.load(preparedAssetRoot: root)
        let sourcePlan = try GoldenEyeSourceTextureUploadPlanV6.make(
            catalog: catalog,
            models: sourceModels
        )
        check(sourcePlan.descriptors.count > 0, "source descriptor count")
        check(sourcePlan.levelRanges.count > 0, "source mip count")
        let sourceHandles = sourcePlan.descriptors.map(\.resourceHandle)
        check(sourceHandles.count == 122, "all-eight source texture count")
        check(sourcePlan.levelRanges.count == 322, "all-eight source mip count")
        check(sourcePlan.paletteEvidence.count == 25, "all-eight CPU TLUT evidence count")
        check(Set(sourceHandles).count == sourceHandles.count, "all-eight texture handles are unique/joinable")
        let sourceModelNames = Array(Set(sourcePlan.descriptors.map(\.modelName))).sorted()
        print(
            "source-texture-store-v6 source plan: PASS "
                + "models=\(sourceModelNames.joined(separator: ",")) "
                + "textures=\(sourcePlan.descriptors.count) levels=\(sourcePlan.levelRanges.count) "
                + "validated_palettes=\(sourcePlan.paletteEvidence.count) "
                + "unique_handles=\(Set(sourceHandles).count)"
        )

        if ProcessInfo.processInfo.environment["GOLDENEYE_SKIP_METAL_UPLOAD_SMOKE"] != "1" {
            if #available(macOS 26.0, *) {
                let paletteFixture = fixture(
                    name: "Wallet",
                    handle: 0x7f00_1005,
                    width: 64,
                    height: 64,
                    mipLevels: 7,
                    withPalette: true
                )
                try boundedMetalSmoke(
                    plan: try GoldenEyeSourceTextureUploadPlanV6.make(
                        descriptors: sourcePlan.descriptors + [paletteFixture]
                    )
                )
            } else {
                print("source-texture-store-v6 Metal upload smoke: SKIP macOS 26 required")
            }
        }
        print("goldeneye_source_texture_store_v6_smoke: PASS")
    }
}
