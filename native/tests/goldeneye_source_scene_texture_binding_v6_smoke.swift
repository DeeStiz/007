import Foundation

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

private func descriptor(
    name: String,
    handle: UInt32,
    mipLevels: UInt32,
    palette: Bool
) -> GoldenEyeSourceTextureDescriptorV6 {
    let width: UInt32 = 32
    let height: UInt32 = 32
    let levels = (0..<mipLevels).map { level -> GoldenEyeSourceTextureLevelUploadV6 in
        let levelWidth = max(1, width >> level)
        let levelHeight = max(1, height >> level)
        let bytes = Int(levelWidth) * Int(levelHeight) * 4
        return .init(
            level: level,
            width: levelWidth,
            height: levelHeight,
            payloadRecordID: handle &+ 0x100 &+ level,
            sourceOffset: level * 64,
            sourceRowHandle: handle &+ 0x200,
            rawByteCount: UInt32(max(1, bytes / 2)),
            decodedByteCount: UInt32(bytes),
            decodedSHA256: String(format: "%08x-%02x", handle, level),
            decoded: Data(repeating: UInt8(truncatingIfNeeded: handle &+ level), count: bytes)
        )
    }
    let paletteValue: GoldenEyeSourceTexturePaletteUploadV6?
    if palette {
        paletteValue = .init(
            resourceHandle: handle,
            entries: 16,
            payloadRecordID: handle &+ 0x300,
            sourceOffset: 0,
            sourceRowHandle: handle &+ 0x400,
            rawByteCount: 32,
            decodedByteCount: 64,
            decodedSHA256: "palette-\(handle)",
            decoded: Data(repeating: 0xaa, count: 64)
        )
    } else {
        paletteValue = nil
    }
    return .init(
        modelName: name,
        family: name,
        resourceHandle: handle,
        width: width,
        height: height,
        mipLevels: mipLevels,
        payloadRecordID: handle &+ 0x500,
        sourceOffset: handle,
        sourceRowHandle: handle &+ 0x600,
        sourceSpan: UInt32(width * height * 2),
        levels: levels,
        palette: paletteValue
    )
}

@main
struct GoldenEyeSourceSceneTextureBindingV6Smoke {
    static func main() throws {
        let plan = try GoldenEyeSourceTextureUploadPlanV6.make(descriptors: [
            descriptor(name: "wallet", handle: 0x1003, mipLevels: 7, palette: true),
            descriptor(name: "legal", handle: 0x1001, mipLevels: 1, palette: false),
            descriptor(name: "goldeneye", handle: 0x1002, mipLevels: 6, palette: false),
        ])
        let table = try GoldenEyeSourceSceneTextureBindingTableV6(plan: plan)
        check(table.entries.map(\.resourceHandle) == [0x1001, 0x1002, 0x1003], "stable handle order")
        check(table.entries.count == 3, "one binding per source resource")
        check(table.entries[0].levelPayloadRecordIDs == [0x1101], "Legal base payload identity")
        check(table.entries[1].levelPayloadRecordIDs.count == 6, "GoldenEye complete mip identity")
        check(table.entries[2].levelPayloadRecordIDs.count == 7, "Wallet complete mip identity")
        check(table.entries[2].hasValidatedPalette, "Wallet TLUT evidence retained")
        check(table.entries[2].palettePayloadRecordID == 0x1303, "Wallet TLUT payload identity")
        check(
            GoldenEyeSourceSceneTextureBindingAdapterV6.paletteResourceHandle(for: 0x1003) == 0xa900_1003,
            "deterministic palette resource handle"
        )
        check(table.entries[0].levelDecodedSHA256 == ["00001001-00"], "decoded hash identity retained")

        do {
            _ = try table.metadata(for: 0xdead_beef)
            preconditionFailure("missing source texture handle was accepted")
        } catch let error as GoldenEyeSourceSceneTextureBindingV6Error {
            guard case .missingHandle(0xdead_beef) = error else { throw error }
        }

        let duplicate = GoldenEyeSourceTextureDescriptorV6(
            modelName: "duplicate",
            family: "duplicate",
            resourceHandle: 0x1001,
            width: 32,
            height: 32,
            mipLevels: 1,
            payloadRecordID: 0x9001,
            sourceOffset: 0,
            sourceRowHandle: 0x9002,
            sourceSpan: 2048,
            levels: [
                .init(
                    level: 0,
                    width: 32,
                    height: 32,
                    payloadRecordID: 0x9003,
                    sourceOffset: 0,
                    sourceRowHandle: 0x9004,
                    rawByteCount: 2048,
                    decodedByteCount: 4096,
                    decodedSHA256: "duplicate",
                    decoded: Data(repeating: 0, count: 4096)
                )
            ]
        )
        do {
            let duplicatePlan = try GoldenEyeSourceTextureUploadPlanV6.make(
                descriptors: plan.descriptors + [duplicate]
            )
            _ = try GoldenEyeSourceSceneTextureBindingTableV6(plan: duplicatePlan)
            preconditionFailure("duplicate source texture handle was accepted")
        } catch let error as GoldenEyeSourceTextureStoreV6Error {
            guard case .duplicateResourceHandle(0x1001) = error else { throw error }
        }

        print(
            "goldeneye_source_scene_texture_binding_v6_smoke: PASS "
                + "resources=\(table.entries.count) mips=\(table.entries.reduce(0) { $0 + $1.levelPayloadRecordIDs.count }) "
                + "palettes=\(table.entries.filter(\.hasValidatedPalette).count)"
        )
    }
}
