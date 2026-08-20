import Foundation
import Metal

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

private func ceilFixture(
    name: String,
    handle: UInt32,
    widths: [UInt32]
) -> GoldenEyeSourceTextureDescriptorV6 {
    let heights = widths
    let levels = widths.enumerated().map { pair in
        let byteCount = Int(pair.element) * Int(heights[pair.offset]) * 4
        return GoldenEyeSourceTextureLevelUploadV6(
            level: UInt32(pair.offset),
            width: pair.element,
            height: heights[pair.offset],
            payloadRecordID: handle &+ UInt32(pair.offset) &+ 1,
            sourceOffset: UInt32(pair.offset * 256),
            sourceRowHandle: handle &+ 0x100,
            rawByteCount: UInt32(max(1, byteCount / 2)),
            decodedByteCount: UInt32(byteCount),
            decodedSHA256: "irregular-(pair.offset)",
            decoded: Data(repeating: UInt8(pair.offset + 1), count: byteCount)
        )
    }
    return GoldenEyeSourceTextureDescriptorV6(
        modelName: name,
        family: "global-image",
        resourceHandle: handle,
        width: widths[0],
        height: heights[0],
        mipLevels: UInt32(widths.count),
        payloadRecordID: handle &+ 0x400,
        sourceOffset: 0,
        sourceRowHandle: handle &+ 0x500,
        sourceSpan: UInt32(widths[0] * heights[0] * 2),
        levels: levels,
        mipDimensionMode: .ceilHalving
    )
}

private func floorFixture() -> GoldenEyeSourceTextureDescriptorV6 {
    let width: UInt32 = 32
    let levels = (0..<6).map { level -> GoldenEyeSourceTextureLevelUploadV6 in
        let dimension = max(1, width >> level)
        let byteCount = Int(dimension * dimension * 4)
        let payload = Data(repeating: 0x42, count: byteCount)
        let sourceLevel = UInt32(level)
        return GoldenEyeSourceTextureLevelUploadV6(
            level: sourceLevel,
            width: dimension,
            height: dimension,
            payloadRecordID: 0x2200 &+ sourceLevel,
            sourceOffset: sourceLevel * 128,
            sourceRowHandle: 0x2201,
            rawByteCount: UInt32(max(1, byteCount / 2)),
            decodedByteCount: UInt32(byteCount),
            decodedSHA256: "floor-(level)",
            decoded: payload
        )
    }
    return .init(
        modelName: "floor",
        family: "embedded",
        resourceHandle: 0x2202,
        width: width,
        height: width,
        mipLevels: 6,
        payloadRecordID: 0x2203,
        sourceOffset: 0,
        sourceRowHandle: 0x2204,
        sourceSpan: 4096,
        levels: levels,
        mipDimensionMode: .floorHalving
    )
}

@available(macOS 26.0, *)
private func metalSmoke(plan: GoldenEyeSourceTextureUploadPlanV6) throws {
    guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4) else {
        print("goldeneye_source_irregular_mip_v6 Metal: SKIP no Metal 4 device")
        return
    }
    let queueDescriptor = MTL4CommandQueueDescriptor()
    guard let queue = try? device.makeMTL4CommandQueue(descriptor: queueDescriptor) else {
        print("goldeneye_source_irregular_mip_v6 Metal: SKIP no Metal 4 queue")
        return
    }
    let residencyDescriptor = MTLResidencySetDescriptor()
    guard let residency = try? device.makeResidencySet(descriptor: residencyDescriptor),
          let event = device.makeSharedEvent() else {
        print("goldeneye_source_irregular_mip_v6 Metal: SKIP residency/event unavailable")
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
    guard let irregular = plan.descriptors.first(where: { $0.mipDimensionMode == .ceilHalving }),
          let floor = plan.descriptors.first(where: { $0.mipDimensionMode == .floorHalving }),
          let irregularTexture = store.texture(handle: irregular.resourceHandle),
          let floorTexture = store.texture(handle: floor.resourceHandle) else {
        preconditionFailure("uploaded irregular/floor textures are missing")
    }
    check(irregularTexture.textureType == .type2DArray, "irregular texture array type")
    check(irregularTexture.width == 65 && irregularTexture.height == 65, "irregular dimensions")
    check(irregularTexture.arrayLength == 7 && irregularTexture.mipmapLevelCount == 1, "irregular array layout")
    check(floorTexture.width == 32 && floorTexture.height == 32, "floor path dimensions")
    check(floorTexture.arrayLength == 6 && floorTexture.mipmapLevelCount == 1, "floor array layout")
    let expectedGPUBytes = (65 * 65 * 4 * 7) + (32 * 32 * 4 * 6)
    check(evidence.levelCount == 13 && evidence.stagingByteCount == plan.stagingByteCount, "bounded array upload")
    check(evidence.gpuTextureByteCount == expectedGPUBytes, "GPU byte accounting")
    try store.shutdown(timeoutMS: 5_000)
    print("goldeneye_source_irregular_mip_v6 Metal: PASS levels=13 slices=7")
}

@main
struct GoldenEyeSourceIrregularMipV6Smoke {
    static func main() throws {
        let irregular = ceilFixture(
            name: "wallet-mi6",
            handle: 0x6500,
            widths: [65, 33, 17, 9, 5, 3, 1]
        )
        let floor = floorFixture()
        let plan = try GoldenEyeSourceTextureUploadPlanV6.make(descriptors: [irregular, floor])
        let authored = plan.descriptors.first { $0.modelName == "wallet-mi6" }
        check(authored?.mipDimensionMode == .ceilHalving, "ceil mode is inferred/retained")
        check(authored?.metalArrayLength == 7, "ceil array length")
        check(authored?.levels.map(\.width) == [65, 33, 17, 9, 5, 3, 1], "authored widths preserved")
        check(authored?.levels.map(\.height) == [65, 33, 17, 9, 5, 3, 1], "authored heights preserved")
        check(plan.levelRanges.count == 13, "all authored levels have bounded ranges")

        var tamperedLevels = irregular.levels
        tamperedLevels[1] = .init(
            level: 1,
            width: 32,
            height: 33,
            payloadRecordID: tamperedLevels[1].payloadRecordID,
            sourceOffset: tamperedLevels[1].sourceOffset,
            sourceRowHandle: tamperedLevels[1].sourceRowHandle,
            rawByteCount: tamperedLevels[1].rawByteCount,
            decodedByteCount: tamperedLevels[1].decodedByteCount,
            decodedSHA256: tamperedLevels[1].decodedSHA256,
            decoded: tamperedLevels[1].decoded
        )
        do {
            _ = try GoldenEyeSourceTextureUploadPlanV6.make(descriptors: [
                .init(
                    modelName: irregular.modelName,
                    family: irregular.family,
                    resourceHandle: irregular.resourceHandle,
                    width: irregular.width,
                    height: irregular.height,
                    mipLevels: irregular.mipLevels,
                    payloadRecordID: irregular.payloadRecordID,
                    sourceOffset: irregular.sourceOffset,
                    sourceRowHandle: irregular.sourceRowHandle,
                    sourceSpan: irregular.sourceSpan,
                    levels: tamperedLevels,
                    mipDimensionMode: .ceilHalving
                )
            ])
            preconditionFailure("tampered authored dimensions accepted")
        } catch let error as GoldenEyeSourceTextureStoreV6Error {
            guard case .invalidDescriptor = error else { throw error }
        }

        if #available(macOS 26.0, *) {
            try metalSmoke(plan: plan)
        } else {
            print("goldeneye_source_irregular_mip_v6 Metal: SKIP macOS 26 required")
        }
        print("goldeneye_source_irregular_mip_v6_smoke: PASS dimensions=65,33,17,9,5,3,1")
    }
}
