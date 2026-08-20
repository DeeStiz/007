#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif
import Foundation
import Metal

/// Errors from the strict Release source-scene texture seam.  A draw may only
/// bind a resource that is present in the validated upload plan and in the
/// store's committed residency set; there is no placeholder or first-material
/// fallback in this adapter.
enum GoldenEyeSourceSceneTextureBindingV6Error: Error, CustomStringConvertible, Equatable {
    case emptyTable
    case missingHandle(UInt32)
    case duplicateHandle(UInt32)
    case storeTextureMissing(UInt32)
    case storeTextureNotResident(UInt32)
    case textureMetadataMismatch(UInt32, String)
    case resourceMetadataMismatch(UInt32, String)

    var description: String {
        switch self {
        case .emptyTable:
            return "source-scene texture binding table is empty"
        case .missingHandle(let handle):
            return "source-scene texture binding handle 0x\(String(handle, radix: 16)) is missing"
        case .duplicateHandle(let handle):
            return "source-scene texture binding handle 0x\(String(handle, radix: 16)) is duplicated"
        case .storeTextureMissing(let handle):
            return "source texture store has no Metal texture for 0x\(String(handle, radix: 16))"
        case .storeTextureNotResident(let handle):
            return "source texture store has not committed residency for 0x\(String(handle, radix: 16))"
        case .textureMetadataMismatch(let handle, let detail):
            return "Metal texture metadata mismatch for 0x\(String(handle, radix: 16)): \(detail)"
        case .resourceMetadataMismatch(let handle, let detail):
            return "scene resource metadata mismatch for 0x\(String(handle, radix: 16)): \(detail)"
        }
    }
}

/// Fixed-value metadata for one source texture.  The table deliberately
/// retains every source mip payload identity and the validated TLUT payload
/// identity, while the Metal object remains private to the adapter binding.
struct GoldenEyeSourceSceneTextureBindingMetadataV6: Sendable, Equatable {
    let resourceHandle: UInt32
    let width: UInt32
    let height: UInt32
    let mipLevels: UInt32
    let sourceOffset: UInt32
    let sourceRowHandle: UInt32
    let sourceSpan: UInt32
    let mipDimensionMode: GoldenEyeSourceTextureMipDimensionModeV6
    let levelWidths: [UInt32]
    let levelHeights: [UInt32]
    let metalArrayLength: UInt32
    let levelPayloadRecordIDs: [UInt32]
    let levelDecodedSHA256: [String]
    let palettePayloadRecordID: UInt32?
    let paletteDecodedSHA256: String?

    var hasValidatedPalette: Bool {
        palettePayloadRecordID != nil && paletteDecodedSHA256 != nil
    }
}

/// A resolved draw binding.  This is an internal Swift/Metal value; it never
/// crosses the public C ABI.  ``texture`` is only exposed after the adapter
/// has checked its dimensions, mip count, shader-read usage, and residency.
@available(macOS 26.0, *)
struct GoldenEyeSourceSceneTextureBindingV6: @unchecked Sendable {
    let metadata: GoldenEyeSourceSceneTextureBindingMetadataV6
    let texture: any MTLTexture
}

/// Pure plan-backed metadata table used by the Release adapter and focused
/// tests.  Building this table from ``GoldenEyeSourceTextureUploadPlanV6``
/// means the renderer cannot accidentally resolve a neighboring material or
/// collapse a model to its first texture.
struct GoldenEyeSourceSceneTextureBindingTableV6: Sendable, Equatable {
    let entries: [GoldenEyeSourceSceneTextureBindingMetadataV6]

    init(plan: GoldenEyeSourceTextureUploadPlanV6) throws {
        guard !plan.descriptors.isEmpty else {
            throw GoldenEyeSourceSceneTextureBindingV6Error.emptyTable
        }
        var handles = Set<UInt32>()
        var entries: [GoldenEyeSourceSceneTextureBindingMetadataV6] = []
        entries.reserveCapacity(plan.descriptors.count)
        for descriptor in plan.descriptors {
            guard handles.insert(descriptor.resourceHandle).inserted else {
                throw GoldenEyeSourceSceneTextureBindingV6Error.duplicateHandle(
                    descriptor.resourceHandle
                )
            }
            let levels = descriptor.levels.sorted { $0.level < $1.level }
            guard levels.count == Int(descriptor.mipLevels),
                  levels.count <= 7,
                  levels.map(\.level) == Array(0..<descriptor.mipLevels),
                  descriptor.metalArrayLength > 1,
                  descriptor.metalArrayLength < 2_048 else {
                throw GoldenEyeSourceSceneTextureBindingV6Error.textureMetadataMismatch(
                    descriptor.resourceHandle,
                    "source level/array metadata"
                )
            }
            entries.append(.init(
                resourceHandle: descriptor.resourceHandle,
                width: descriptor.width,
                height: descriptor.height,
                mipLevels: descriptor.mipLevels,
                sourceOffset: descriptor.sourceOffset,
                sourceRowHandle: descriptor.sourceRowHandle,
                sourceSpan: descriptor.sourceSpan,
                mipDimensionMode: descriptor.mipDimensionMode,
                levelWidths: levels.map(\.width),
                levelHeights: levels.map(\.height),
                metalArrayLength: descriptor.metalArrayLength,
                levelPayloadRecordIDs: levels.map(\.payloadRecordID),
                levelDecodedSHA256: levels.map(\.decodedSHA256),
                palettePayloadRecordID: descriptor.palette?.payloadRecordID,
                paletteDecodedSHA256: descriptor.palette?.decodedSHA256
            ))
        }
        self.entries = entries.sorted { $0.resourceHandle < $1.resourceHandle }
    }

    func metadata(for handle: UInt32) throws -> GoldenEyeSourceSceneTextureBindingMetadataV6 {
        guard let entry = entries.first(where: { $0.resourceHandle == handle }) else {
            throw GoldenEyeSourceSceneTextureBindingV6Error.missingHandle(handle)
        }
        return entry
    }
}

/// Strict Release resolver joining GESM/resource handles to the texture store.
/// It validates the complete plan once at construction, then validates the
/// copied scene resource again at each draw boundary.  All source levels are
/// resident slices of one 2D-array allocation; the array preserves authored
/// ceil-halving chains that Metal's implicit mip dimensions cannot represent.
@available(macOS 26.0, *)
final class GoldenEyeSourceSceneTextureBindingAdapterV6: @unchecked Sendable {
    private static let paletteResourcePrefix: UInt32 = 0xA900_0000
    private let store: any GoldenEyeSourceTextureResourceProviderV6
    let table: GoldenEyeSourceSceneTextureBindingTableV6

    init(
        store: any GoldenEyeSourceTextureResourceProviderV6,
        plan: GoldenEyeSourceTextureUploadPlanV6
    ) throws {
        self.store = store
        self.table = try GoldenEyeSourceSceneTextureBindingTableV6(plan: plan)
        for metadata in table.entries {
            guard let texture = store.texture(handle: metadata.resourceHandle) else {
                throw GoldenEyeSourceSceneTextureBindingV6Error.storeTextureMissing(
                    metadata.resourceHandle
                )
            }
            guard store.isResident(handle: metadata.resourceHandle) else {
                throw GoldenEyeSourceSceneTextureBindingV6Error.storeTextureNotResident(
                    metadata.resourceHandle
                )
            }
            try Self.validate(texture: texture, metadata: metadata)
        }
    }

    var resourceCount: Int { table.entries.count }

    var validatedPaletteCount: Int {
        table.entries.reduce(into: 0) { count, entry in
            if entry.hasValidatedPalette { count += 1 }
        }
    }

    func metadata(for handle: UInt32) throws -> GoldenEyeSourceSceneTextureBindingMetadataV6 {
        try table.metadata(for: handle)
    }

    /// Matches the deterministic palette resource handle emitted by the
    /// source GBI builder.  It is used only to verify the copied scene
    /// resource table; palette bytes themselves remain in the validated RGBA8
    /// setup evidence used to produce each texture level.
    static func paletteResourceHandle(
        for textureHandle: UInt32,
        occupiedHandles: Set<UInt32> = []
    ) -> UInt32 {
        var prefix = paletteResourcePrefix & 0xff00_0000
        var candidate = prefix | (textureHandle & 0x00ff_ffff)
        // A source texture hash may itself occupy the A9 namespace. The
        // builder advances the high byte in that typed collision case; mirror
        // that bounded rule so the adapter finds the exact emitted resource.
        while occupiedHandles.contains(candidate) {
            prefix &+= 0x0100_0000
            if prefix == 0 { return 0 }
            candidate = prefix | (textureHandle & 0x00ff_ffff)
        }
        return candidate
    }

    func binding(for resource: GESourceResourceV6) throws -> GoldenEyeSourceSceneTextureBindingV6 {
        let handle = resource.handle
        let metadata = try table.metadata(for: handle)
        guard resource.resource_kind == UInt32(GE_SOURCE_RESOURCE_V6_TEXTURE) else {
            throw GoldenEyeSourceSceneTextureBindingV6Error.resourceMetadataMismatch(
                handle,
                "resource kind \(resource.resource_kind) is not texture"
            )
        }
        guard resource.flags & UInt32(GE_SOURCE_RESOURCE_V6_FLAG_RESIDENT) != 0,
              resource.flags & UInt32(GE_SOURCE_RESOURCE_V6_FLAG_SOURCE_ORDERED) != 0 else {
            throw GoldenEyeSourceSceneTextureBindingV6Error.resourceMetadataMismatch(
                handle,
                "resource is not resident/source-ordered"
            )
        }
        guard resource.source_id == metadata.sourceRowHandle,
              resource.width == metadata.width,
              resource.height == metadata.height,
              resource.mip_count == metadata.mipLevels,
              resource.level_count == metadata.mipLevels,
              resource.byte_size == metadata.sourceSpan else {
            throw GoldenEyeSourceSceneTextureBindingV6Error.resourceMetadataMismatch(
                handle,
                "source row/dimensions/mip count/span"
            )
        }
        if metadata.mipLevels > 1,
           resource.flags & UInt32(GE_SOURCE_RESOURCE_V6_FLAG_MIP_CHAIN) == 0 {
            throw GoldenEyeSourceSceneTextureBindingV6Error.resourceMetadataMismatch(
                handle,
                "mip-chain flag is missing"
            )
        }
        guard let texture = store.texture(handle: handle) else {
            throw GoldenEyeSourceSceneTextureBindingV6Error.storeTextureMissing(handle)
        }
        guard store.isResident(handle: handle) else {
            throw GoldenEyeSourceSceneTextureBindingV6Error.storeTextureNotResident(handle)
        }
        try Self.validate(texture: texture, metadata: metadata)
        return GoldenEyeSourceSceneTextureBindingV6(metadata: metadata, texture: texture)
    }

    private static func validate(
        texture: any MTLTexture,
        metadata: GoldenEyeSourceSceneTextureBindingMetadataV6
    ) throws {
        guard texture.width == Int(metadata.width),
              texture.height == Int(metadata.height),
              texture.mipmapLevelCount == 1,
              texture.textureType == .type2DArray,
              texture.arrayLength == Int(metadata.metalArrayLength) else {
            throw GoldenEyeSourceSceneTextureBindingV6Error.textureMetadataMismatch(
                metadata.resourceHandle,
                "array dimensions/mipmap count"
            )
        }
        guard texture.pixelFormat == .rgba8Unorm,
              texture.usage.contains(.shaderRead),
              texture.storageMode == .private else {
            throw GoldenEyeSourceSceneTextureBindingV6Error.textureMetadataMismatch(
                metadata.resourceHandle,
                "requires private rgba8 shader-read texture"
            )
        }
    }
}
