import CryptoKit
import Foundation
import Metal

/// Errors raised by the source texture store are deliberately typed.  A
/// descriptor that is incomplete or points at a source-text row is rejected
/// before a Metal allocation is made; there is no placeholder texture path.
enum GoldenEyeSourceTextureStoreV6Error: Error, CustomStringConvertible, Equatable {
    case emptyPlan
    case invalidDescriptor(String)
    case duplicateResourceHandle(UInt32)
    case duplicateLevel(UInt32, UInt32)
    case duplicatePalette(UInt32)
    case invalidRecord(UInt32, String)
    case wrongRecordCategory(UInt32, expected: String, actual: String)
    case missingRecord(UInt32, String)
    case metadataMismatch(UInt32, String)
    case sourceEvidenceMismatch(UInt32, String)
    case digestMismatch(UInt32, expected: String, actual: String)
    case sourceTextAlias(UInt32)
    case derivedPayloadWithoutEvidence(UInt32)
    case stagingOverflow
    case metal4Unavailable(String)
    case metalAllocationFailed(String)
    case commandEncodingFailed(String)
    case uploadAlreadyPresent(UInt32)
    case completionTimeout(UInt64)

    var description: String {
        switch self {
        case .emptyPlan:
            return "source texture V6 upload plan is empty"
        case .invalidDescriptor(let detail):
            return "invalid source texture V6 descriptor: \(detail)"
        case .duplicateResourceHandle(let handle):
            return "duplicate source texture V6 resource handle \(handle)"
        case .duplicateLevel(let resource, let level):
            return "duplicate source texture V6 mip level \(level) for resource \(resource)"
        case .duplicatePalette(let handle):
            return "duplicate source texture V6 palette for resource \(handle)"
        case .invalidRecord(let id, let detail):
            return "invalid source frontend record \(id): \(detail)"
        case .wrongRecordCategory(let id, let expected, let actual):
            return "source frontend record \(id) category \(actual), expected \(expected)"
        case .missingRecord(let id, let detail):
            return "source frontend record \(id) is missing: \(detail)"
        case .metadataMismatch(let id, let detail):
            return "source frontend record \(id) metadata mismatch: \(detail)"
        case .sourceEvidenceMismatch(let id, let detail):
            return "source frontend record \(id) source evidence mismatch: \(detail)"
        case .digestMismatch(let id, let expected, let actual):
            return "source frontend record \(id) decoded digest mismatch: expected \(expected), got \(actual)"
        case .sourceTextAlias(let id):
            return "source frontend record \(id) aliases source text"
        case .derivedPayloadWithoutEvidence(let id):
            return "source frontend record \(id) is derived without derivation evidence"
        case .stagingOverflow:
            return "source texture V6 staging size overflow"
        case .metal4Unavailable(let detail):
            return "Metal 4 source texture upload unavailable: \(detail)"
        case .metalAllocationFailed(let detail):
            return "Metal source texture allocation failed: \(detail)"
        case .commandEncodingFailed(let detail):
            return "Metal 4 source texture upload encoding failed: \(detail)"
        case .uploadAlreadyPresent(let handle):
            return "source texture V6 resource handle already uploaded: \(handle)"
        case .completionTimeout(let signal):
            return "source texture V6 completion event timed out at signal \(signal)"
        }
    }
}

/// A single decoded RGBA8 mip level.  It contains only copied values and
/// payload bytes; no source pointer, ROM address, or Metal object is retained.
struct GoldenEyeSourceTextureLevelUploadV6: Sendable, Equatable {
    let level: UInt32
    let width: UInt32
    let height: UInt32
    let payloadRecordID: UInt32
    let sourceOffset: UInt32
    let sourceRowHandle: UInt32
    let rawByteCount: UInt32
    let decodedByteCount: UInt32
    let decodedSHA256: String
    let decoded: Data
}

/// Source image chains do not necessarily follow Metal's implicit mip rule.
/// In particular, global IMAGE_* rows authored by the game use ceil-halving
/// (65, 33, 17, 9, 5, 3, 1).  The mode is copied into the upload plan so the
/// GPU representation can retain the authored dimensions instead of silently
/// rounding them down to Metal's floor-halved mip sizes.
enum GoldenEyeSourceTextureMipDimensionModeV6: UInt32, Sendable, Equatable {
    case floorHalving = 0
    case ceilHalving = 1
    case sourceAuthored = 2
}

/// CPU-only decoded RGBA8 palette evidence.  Palettes are kept separate from
/// texel textures because an N64 CI material can sample the same texel texture
/// with different TLUT state.  No Metal object is created until a CI shader
/// consumer is wired; ``resourceHandle`` remains the source texture handle.
struct GoldenEyeSourceTexturePaletteUploadV6: Sendable, Equatable {
    let resourceHandle: UInt32
    let entries: UInt32
    let payloadRecordID: UInt32
    let sourceOffset: UInt32
    let sourceRowHandle: UInt32
    let rawByteCount: UInt32
    let decodedByteCount: UInt32
    let decodedSHA256: String
    let decoded: Data
}

/// One source texture plus every source-declared mip level and optional TLUT.
/// Embedded/Rareware payloads carry complete mip chains; global image aliases
/// carry a validated base level and reference separate derived mip payloads.
/// The descriptor is suitable for pure upload-plan tests as well as the Metal
/// upload path. Production callers should obtain it through ``makePlan`` so
/// all catalog/model evidence is checked first.
struct GoldenEyeSourceTextureDescriptorV6: Sendable, Equatable {
    let modelName: String
    let family: String
    let resourceHandle: UInt32
    let width: UInt32
    let height: UInt32
    let mipLevels: UInt32
    let payloadRecordID: UInt32
    let payloadDecodedSHA256: String
    let sourceOffset: UInt32
    let sourceRowHandle: UInt32
    let sourceSpan: UInt32
    let levels: [GoldenEyeSourceTextureLevelUploadV6]
    let palette: GoldenEyeSourceTexturePaletteUploadV6?
    let mipDimensionMode: GoldenEyeSourceTextureMipDimensionModeV6

    /// The array contains one slice per authored level. A one-level source
    /// duplicates its base slice because Metal requires an array texture to
    /// have at least two slices; the authoritative count is carried in the
    /// per-draw metadata.
    var metalArrayLength: UInt32 {
        // A 2D-array requires at least two slices on Metal. A single-level
        // source therefore duplicates its base slice once; the authoritative
        // count remains ``mipLevels`` in the per-draw metadata.
        return max(2, mipLevels)
    }

    init(
        modelName: String,
        family: String,
        resourceHandle: UInt32,
        width: UInt32,
        height: UInt32,
        mipLevels: UInt32,
        payloadRecordID: UInt32,
        payloadDecodedSHA256: String = "",
        sourceOffset: UInt32,
        sourceRowHandle: UInt32,
        sourceSpan: UInt32,
        levels: [GoldenEyeSourceTextureLevelUploadV6],
        palette: GoldenEyeSourceTexturePaletteUploadV6? = nil,
        mipDimensionMode: GoldenEyeSourceTextureMipDimensionModeV6? = nil
    ) {
        self.modelName = modelName
        self.family = family
        self.resourceHandle = resourceHandle
        self.width = width
        self.height = height
        self.mipLevels = mipLevels
        self.payloadRecordID = payloadRecordID
        self.payloadDecodedSHA256 = payloadDecodedSHA256
        self.sourceOffset = sourceOffset
        self.sourceRowHandle = sourceRowHandle
        self.sourceSpan = sourceSpan
        self.levels = levels
        self.palette = palette
        self.mipDimensionMode = mipDimensionMode
            ?? Self.inferMipDimensionMode(width: width, height: height, levels: levels)
    }

    private static func inferMipDimensionMode(
        width: UInt32,
        height: UInt32,
        levels: [GoldenEyeSourceTextureLevelUploadV6]
    ) -> GoldenEyeSourceTextureMipDimensionModeV6 {
        guard levels.contains(where: { $0.level == 1 }) else {
            return .floorHalving
        }
        let allFloor = levels.allSatisfy { level in
            level.level == 0 || (level.width == max(1, width >> level.level) && level.height == max(1, height >> level.level))
        }
        let allCeil = levels.allSatisfy { level in
            let divisor = UInt64(1) << min(level.level, 31)
            let expectedWidth = UInt32(max(1, (UInt64(width) + divisor - 1) / divisor))
            let expectedHeight = UInt32(max(1, (UInt64(height) + divisor - 1) / divisor))
            return level.level == 0 || (level.width == expectedWidth && level.height == expectedHeight)
        }
        if allFloor { return .floorHalving }
        if allCeil { return .ceilHalving }
        return .sourceAuthored
    }
}

struct GoldenEyeSourceTextureStagingRangeV6: Sendable, Equatable {
    let resourceHandle: UInt32
    let level: UInt32
    let offset: Int
    let byteCount: Int
}

/// CPU-only TLUT evidence.  This record deliberately has no staging offset:
/// until a CI fragment path consumes a palette, the decoded bytes remain
/// validation data and never become an unconsumed GPU allocation.
struct GoldenEyeSourceTexturePaletteEvidenceV6: Sendable, Equatable {
    let resourceHandle: UInt32
    let payloadRecordID: UInt32
    let entries: UInt32
    let decodedByteCount: Int
    let decodedSHA256: String
}

/// A deterministic, fully bounded upload plan.  Offsets are assigned in model
/// name/resource/level order and are always four-byte aligned, matching the
/// RGBA8 copy requirements of ``MTL4ComputeCommandEncoder.copy``.
struct GoldenEyeSourceTextureUploadPlanV6: Sendable, Equatable {
    let descriptors: [GoldenEyeSourceTextureDescriptorV6]
    let stagingByteCount: Int
    let levelRanges: [GoldenEyeSourceTextureStagingRangeV6]
    let paletteEvidence: [GoldenEyeSourceTexturePaletteEvidenceV6]

    static func make(
        descriptors: [GoldenEyeSourceTextureDescriptorV6]
    ) throws -> GoldenEyeSourceTextureUploadPlanV6 {
        guard !descriptors.isEmpty else { throw GoldenEyeSourceTextureStoreV6Error.emptyPlan }

        let ordered = descriptors.sorted {
            ($0.modelName, $0.resourceHandle) < ($1.modelName, $1.resourceHandle)
        }
        var handles = Set<UInt32>()
        var paletteHandles = Set<UInt32>()
        var levels: [GoldenEyeSourceTextureStagingRangeV6] = []
        var paletteEvidence: [GoldenEyeSourceTexturePaletteEvidenceV6] = []
        var offset = 0

        for descriptor in ordered {
            try validate(descriptor: descriptor)
            guard handles.insert(descriptor.resourceHandle).inserted else {
                throw GoldenEyeSourceTextureStoreV6Error.duplicateResourceHandle(descriptor.resourceHandle)
            }

            for level in descriptor.levels {
                let aligned = (offset + 3) & ~3
                let end = aligned.addingReportingOverflow(Int(level.decodedByteCount))
                guard !end.overflow, end.partialValue >= aligned else {
                    throw GoldenEyeSourceTextureStoreV6Error.stagingOverflow
                }
                levels.append(.init(
                    resourceHandle: descriptor.resourceHandle,
                    level: level.level,
                    offset: aligned,
                    byteCount: Int(level.decodedByteCount)
                ))
                offset = end.partialValue
            }

            if let palette = descriptor.palette {
                guard paletteHandles.insert(descriptor.resourceHandle).inserted else {
                    throw GoldenEyeSourceTextureStoreV6Error.duplicatePalette(descriptor.resourceHandle)
                }
                paletteEvidence.append(.init(
                    resourceHandle: descriptor.resourceHandle,
                    payloadRecordID: palette.payloadRecordID,
                    entries: palette.entries,
                    decodedByteCount: Int(palette.decodedByteCount),
                    decodedSHA256: palette.decodedSHA256
                ))
            }
        }

        return GoldenEyeSourceTextureUploadPlanV6(
            descriptors: ordered,
            stagingByteCount: offset,
            levelRanges: levels,
            paletteEvidence: paletteEvidence
        )
    }

    private static func validate(
        descriptor: GoldenEyeSourceTextureDescriptorV6
    ) throws {
        guard !descriptor.modelName.isEmpty, !descriptor.family.isEmpty else {
            throw GoldenEyeSourceTextureStoreV6Error.invalidDescriptor("empty model/family")
        }
        guard descriptor.resourceHandle != 0,
              descriptor.width > 0,
              descriptor.height > 0,
              descriptor.mipLevels > 0,
              descriptor.mipLevels <= 32,
              descriptor.sourceSpan > 0,
              descriptor.sourceRowHandle != 0,
              descriptor.payloadRecordID > 0 else {
            throw GoldenEyeSourceTextureStoreV6Error.invalidDescriptor(
                "\(descriptor.modelName) has zero or out-of-range source metadata"
            )
        }
        guard descriptor.levels.count == Int(descriptor.mipLevels) else {
            throw GoldenEyeSourceTextureStoreV6Error.invalidDescriptor(
                "\(descriptor.modelName) resource \(descriptor.resourceHandle) mip count"
            )
        }
        var seenLevels = Set<UInt32>()
        var aggregateBytes = 0
        var previousWidth = descriptor.width
        var previousHeight = descriptor.height
        for level in descriptor.levels {
            guard seenLevels.insert(level.level).inserted else {
                throw GoldenEyeSourceTextureStoreV6Error.duplicateLevel(
                    descriptor.resourceHandle,
                    level.level
                )
            }
            let expectedWidth: UInt32
            let expectedHeight: UInt32
            if level.level == 0 {
                expectedWidth = descriptor.width
                expectedHeight = descriptor.height
            } else {
                expectedWidth = Self.nextMipDimension(
                    previous: previousWidth,
                    mode: descriptor.mipDimensionMode
                )
                expectedHeight = Self.nextMipDimension(
                    previous: previousHeight,
                    mode: descriptor.mipDimensionMode
                )
            }
            let specialTail = descriptor.mipDimensionMode == .ceilHalving
                && previousWidth == 3 && previousHeight == 3
                && level.width == 1 && level.height == 1
            let authoredDimensions = descriptor.mipDimensionMode == .sourceAuthored
                && level.width > 0 && level.height > 0
                && level.width <= previousWidth && level.height <= previousHeight
            guard level.level < descriptor.mipLevels,
                  (level.width == expectedWidth && level.height == expectedHeight)
                    || specialTail || authoredDimensions,
                  level.payloadRecordID > 0,
                  level.sourceRowHandle != 0,
                  level.rawByteCount > 0 else {
                throw GoldenEyeSourceTextureStoreV6Error.invalidDescriptor(
                    "\(descriptor.modelName) resource \(descriptor.resourceHandle) level \(level.level) metadata"
                )
            }
            let pixels = Int(level.width).multipliedReportingOverflow(by: Int(level.height))
            guard !pixels.overflow else { throw GoldenEyeSourceTextureStoreV6Error.stagingOverflow }
            let rgbaBytes = pixels.partialValue.multipliedReportingOverflow(by: 4)
            guard !rgbaBytes.overflow,
                  rgbaBytes.partialValue == Int(level.decodedByteCount),
                  level.decoded.count == Int(level.decodedByteCount) else {
                throw GoldenEyeSourceTextureStoreV6Error.invalidDescriptor(
                    "\(descriptor.modelName) resource \(descriptor.resourceHandle) level \(level.level) RGBA8 size"
                )
            }
            let aggregate = aggregateBytes.addingReportingOverflow(Int(level.decodedByteCount))
            guard !aggregate.overflow else {
                throw GoldenEyeSourceTextureStoreV6Error.stagingOverflow
            }
            aggregateBytes = aggregate.partialValue
            previousWidth = level.width
            previousHeight = level.height
        }
        guard seenLevels == Set(0..<descriptor.mipLevels) else {
            throw GoldenEyeSourceTextureStoreV6Error.invalidDescriptor(
                "\(descriptor.modelName) resource \(descriptor.resourceHandle) level ordering"
            )
        }
        if let palette = descriptor.palette {
            guard palette.resourceHandle == descriptor.resourceHandle,
                  palette.entries > 0,
                  palette.payloadRecordID > 0,
                  palette.sourceRowHandle != 0,
                  palette.rawByteCount > 0 else {
                throw GoldenEyeSourceTextureStoreV6Error.invalidDescriptor(
                    "\(descriptor.modelName) resource \(descriptor.resourceHandle) palette metadata"
                )
            }
            let expected = Int(palette.entries).multipliedReportingOverflow(by: 4)
            guard !expected.overflow,
                  expected.partialValue == Int(palette.decodedByteCount),
                  palette.decoded.count == Int(palette.decodedByteCount) else {
                throw GoldenEyeSourceTextureStoreV6Error.invalidDescriptor(
                    "\(descriptor.modelName) resource \(descriptor.resourceHandle) palette RGBA8 size"
                )
            }
        }
        _ = aggregateBytes
    }

    private static func nextMipDimension(
        previous: UInt32,
        mode: GoldenEyeSourceTextureMipDimensionModeV6
    ) -> UInt32 {
        switch mode {
        case .floorHalving:
            return max(1, previous / 2)
        case .ceilHalving:
            // Some source image tables collapse the final 3x3 tile directly
            // to 1x1. Accept that typed tail alongside ordinary 3 -> 2
            // ceil-halving while rejecting unrelated dimension drift.
            if previous == 3 { return 2 }
            return max(1, (previous + 1) / 2)
        case .sourceAuthored:
            return max(1, previous / 2)
        }
    }
}

/// Context required by the Metal 4 upload path.  The residency set is owned
/// by the renderer/device state and must already be attached to the queue;
/// this store only batches allocations and commits them atomically.
@available(macOS 26.0, *)
struct GoldenEyeSourceTextureStoreV6MetalContext: @unchecked Sendable {
    let device: any MTLDevice
    let queue: any MTL4CommandQueue
    let residency: any MTLResidencySet
    let completionEvent: any MTLSharedEvent

    init(
        device: any MTLDevice,
        queue: any MTL4CommandQueue,
        residency: any MTLResidencySet,
        completionEvent: any MTLSharedEvent
    ) {
        self.device = device
        self.queue = queue
        self.residency = residency
        self.completionEvent = completionEvent
    }
}

/// Minimal Metal-resource provider seam shared by the source texture store
/// and the strict scene binding adapter.  Keeping it here lets the store's
/// standalone validation compile without pulling the renderer into the plan
/// or catalog test.
@available(macOS 26.0, *)
protocol GoldenEyeSourceTextureResourceProviderV6: AnyObject {
    func texture(handle: UInt32) -> (any MTLTexture)?
    func isResident(handle: UInt32) -> Bool
}

struct GoldenEyeSourceTextureUploadEvidenceV6: Sendable, Equatable {
    let signalValue: UInt64
    let textureCount: Int
    let levelCount: Int
    let validatedPaletteCount: Int
    let gpuPaletteCount: Int
    let stagingByteCount: Int
    let gpuTextureByteCount: Int
    let barrier: String
}

/// Native source texture resource store.  Private RGBA8 textures are created
/// from only validated payload records.  Each upload uses one write-combined
/// shared staging allocation and one Metal 4 compute encoder; resources are
/// added to persistent residency in one batch and the staging buffer is held
/// until the shared event proves GPU completion.
@available(macOS 26.0, *)
final class GoldenEyeSourceTextureStoreV6: @unchecked Sendable {
    private final class PendingBatch {
        let signalValue: UInt64
        let staging: any MTLBuffer
        let commandBuffer: any MTL4CommandBuffer
        let allocator: any MTL4CommandAllocator

        init(
            signalValue: UInt64,
            staging: any MTLBuffer,
            commandBuffer: any MTL4CommandBuffer,
            allocator: any MTL4CommandAllocator
        ) {
            self.signalValue = signalValue
            self.staging = staging
            self.commandBuffer = commandBuffer
            self.allocator = allocator
        }
    }

    private let context: GoldenEyeSourceTextureStoreV6MetalContext
    private let lock = NSLock()
    private var nextSignalValue: UInt64 = 1
    private var pending: [UInt64: PendingBatch] = [:]
    private var texturesByHandle: [UInt32: any MTLTexture] = [:]
    /// Handles become resident only after the texture allocations have been
    /// added to the persistent set and committed before queue submission.
    /// Keeping this explicit prevents a renderer from treating a mere Metal
    /// object lookup as proof that its allocation is GPU-visible.
    private var residentHandles: Set<UInt32> = []

    init(context: GoldenEyeSourceTextureStoreV6MetalContext) throws {
        guard context.device.supportsFamily(.metal4) else {
            throw GoldenEyeSourceTextureStoreV6Error.metal4Unavailable(context.device.name)
        }
        self.context = context
        context.completionEvent.label = "GoldenEye.V6.SourceTextureStore.Completion"
        context.residency.requestResidency()
    }

    /// Returns the private RGBA8 texture for a source resource handle.
    func texture(handle: UInt32) -> (any MTLTexture)? {
        lock.lock()
        defer { lock.unlock() }
        return texturesByHandle[handle]
    }

    /// True only after ``upload`` has committed the texture allocation to the
    /// persistent residency set.  The source-scene Release adapter uses this
    /// alongside texture metadata checks for every draw resource.
    func isResident(handle: UInt32) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return residentHandles.contains(handle)
    }

    var textureCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return texturesByHandle.count
    }

    /// Uploads one complete plan.  Texel textures and the single staging
    /// buffer are added before one residency commit.  TLUT bytes remain
    /// CPU-validated evidence until a real CI fragment consumer is wired.
    @discardableResult
    func upload(
        plan: GoldenEyeSourceTextureUploadPlanV6
    ) throws -> GoldenEyeSourceTextureUploadEvidenceV6 {
        try reapCompletedBatches()
        guard context.device.supportsFamily(.metal4) else {
            throw GoldenEyeSourceTextureStoreV6Error.metal4Unavailable(context.device.name)
        }
        guard plan.stagingByteCount > 0 else {
            throw GoldenEyeSourceTextureStoreV6Error.emptyPlan
        }
        guard plan.stagingByteCount <= context.device.maxBufferLength else {
            throw GoldenEyeSourceTextureStoreV6Error.stagingOverflow
        }

        lock.lock()
        defer { lock.unlock() }
        for descriptor in plan.descriptors {
            if texturesByHandle[descriptor.resourceHandle] != nil {
                throw GoldenEyeSourceTextureStoreV6Error.uploadAlreadyPresent(descriptor.resourceHandle)
            }
        }

        var rangesByLevel: [String: GoldenEyeSourceTextureStagingRangeV6] = [:]
        for range in plan.levelRanges {
            rangesByLevel[Self.levelKey(range.resourceHandle, range.level)] = range
        }

        let options: MTLResourceOptions = [.storageModeShared, .cpuCacheModeWriteCombined]
        guard let staging = context.device.makeBuffer(
            length: plan.stagingByteCount,
            options: options
        ) else {
            throw GoldenEyeSourceTextureStoreV6Error.metalAllocationFailed("staging buffer")
        }
        staging.label = "GoldenEye.V6.SourceTextureStore.Batch.Staging"

        var createdTextures: [UInt32: any MTLTexture] = [:]

        for descriptor in plan.descriptors {
            // Metal's native mip chain is floor-halved and cannot represent
            // source-authored global-image levels. Keep every source level in
            // an explicit array slice at physical level zero; dimensions and
            // source mode travel in the bounded per-draw metadata.
            let textureDescriptor = MTLTextureDescriptor()
            textureDescriptor.textureType = .type2DArray
            textureDescriptor.arrayLength = Int(descriptor.metalArrayLength)
            textureDescriptor.mipmapLevelCount = 1
            textureDescriptor.pixelFormat = .rgba8Unorm
            textureDescriptor.width = Int(descriptor.width)
            textureDescriptor.height = Int(descriptor.height)
            textureDescriptor.storageMode = .private
            textureDescriptor.usage = .shaderRead
            guard let texture = context.device.makeTexture(descriptor: textureDescriptor) else {
                throw GoldenEyeSourceTextureStoreV6Error.metalAllocationFailed(
                    "texture \(descriptor.resourceHandle)"
                )
            }
            texture.label = "GoldenEye.V6.SourceTexture.\(descriptor.modelName).Resource.\(descriptor.resourceHandle)"
            createdTextures[descriptor.resourceHandle] = texture
        }

        for descriptor in plan.descriptors {
            for level in descriptor.levels {
                guard let range = rangesByLevel[Self.levelKey(descriptor.resourceHandle, level.level)] else {
                    throw GoldenEyeSourceTextureStoreV6Error.commandEncodingFailed("missing staging range")
                }
                level.decoded.withUnsafeBytes { bytes in
                    guard let baseAddress = bytes.baseAddress else { return }
                    staging.contents().advanced(by: range.offset).copyMemory(
                        from: baseAddress,
                        byteCount: bytes.count
                    )
                }
            }
        }

        // A batch owns one allocator and one reusable command buffer.  Both
        // are retained in PendingBatch until the shared event is signaled.
        let allocatorDescriptor = MTL4CommandAllocatorDescriptor()
        allocatorDescriptor.label = "GoldenEye.V6.SourceTextureStore.Batch.Allocator"
        guard let allocator = try? context.device.makeCommandAllocator(
            descriptor: allocatorDescriptor
        ), let commandBuffer = context.device.makeCommandBuffer() else {
            throw GoldenEyeSourceTextureStoreV6Error.commandEncodingFailed("command buffer/allocator")
        }
        commandBuffer.label = "GoldenEye.V6.SourceTextureStore.Batch.CommandBuffer"

        // Add every GPU allocation together and commit once, before command
        // submission.  The persistent queue residency set is attached by the
        // device-state owner; requestResidency above keeps future commits live.
        for texture in createdTextures.values { context.residency.addAllocation(texture) }
        context.residency.addAllocation(staging)
        context.residency.commit()

        commandBuffer.beginCommandBuffer(allocator: allocator)
        commandBuffer.useResidencySet(context.residency)
        commandBuffer.pushDebugGroup("GoldenEye.V6.SourceTextureStore.Batch")
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            commandBuffer.popDebugGroup()
            commandBuffer.endCommandBuffer()
            throw GoldenEyeSourceTextureStoreV6Error.commandEncodingFailed("compute encoder")
        }
        encoder.label = "GoldenEye.V6.SourceTextureStore.Batch.Copy"

        for descriptor in plan.descriptors {
            guard let texture = createdTextures[descriptor.resourceHandle] else {
                throw GoldenEyeSourceTextureStoreV6Error.commandEncodingFailed("texture map")
            }
            for level in descriptor.levels {
                guard let range = rangesByLevel[Self.levelKey(descriptor.resourceHandle, level.level)] else {
                    throw GoldenEyeSourceTextureStoreV6Error.commandEncodingFailed("level range")
                }
                encoder.copy(
                    sourceBuffer: staging,
                    sourceOffset: range.offset,
                    sourceBytesPerRow: Int(level.width) * 4,
                    sourceBytesPerImage: Int(level.width) * Int(level.height) * 4,
                    sourceSize: MTLSize(width: Int(level.width), height: Int(level.height), depth: 1),
                    destinationTexture: texture,
                    destinationSlice: Int(level.level),
                    destinationLevel: 0,
                    destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
                )
            }
        }

        // The copy operations execute at MTLStageBlit.  Publish their writes
        // to future fragment consumers on this queue at the device coherence
        // point.  This is the producer half of the Metal 4 transition; a
        // renderer may add a narrow fragment consumer barrier at pass start.
        encoder.barrier(
            afterStages: .blit,
            beforeQueueStages: .fragment,
            visibilityOptions: .device
        )
        encoder.endEncoding()
        commandBuffer.popDebugGroup()
        commandBuffer.endCommandBuffer()

        let signalValue = nextSignalValue
        guard signalValue != 0 else {
            throw GoldenEyeSourceTextureStoreV6Error.commandEncodingFailed("completion signal overflow")
        }
        nextSignalValue &+= 1
        context.queue.commit([commandBuffer])
        context.queue.signalEvent(context.completionEvent, value: signalValue)

        for (handle, texture) in createdTextures {
            texturesByHandle[handle] = texture
            residentHandles.insert(handle)
        }
        pending[signalValue] = PendingBatch(
            signalValue: signalValue,
            staging: staging,
            commandBuffer: commandBuffer,
            allocator: allocator
        )

        var gpuTextureByteCount = 0
        for descriptor in plan.descriptors {
            let pixels = Int(descriptor.width).multipliedReportingOverflow(
                by: Int(descriptor.height)
            )
            let bytesPerSlice = pixels.partialValue.multipliedReportingOverflow(by: 4)
            let bytes = bytesPerSlice.partialValue.multipliedReportingOverflow(
                by: Int(descriptor.metalArrayLength)
            )
            guard !pixels.overflow, !bytesPerSlice.overflow, !bytes.overflow else {
                throw GoldenEyeSourceTextureStoreV6Error.stagingOverflow
            }
            let total = gpuTextureByteCount.addingReportingOverflow(bytes.partialValue)
            guard !total.overflow else {
                throw GoldenEyeSourceTextureStoreV6Error.stagingOverflow
            }
            gpuTextureByteCount = total.partialValue
        }

        return GoldenEyeSourceTextureUploadEvidenceV6(
            signalValue: signalValue,
            textureCount: createdTextures.count,
            levelCount: plan.levelRanges.count,
            validatedPaletteCount: plan.paletteEvidence.count,
            gpuPaletteCount: 0,
            stagingByteCount: plan.stagingByteCount,
            gpuTextureByteCount: gpuTextureByteCount,
            barrier: "blit->fragment:device"
        )
    }

    /// Reaps completed batches.  Only staging is removed: source textures are
    /// persistent store resources and remain resident until shutdown.
    @discardableResult
    func reapCompletedBatches() throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        let completed = context.completionEvent.signaledValue
        let completedSignals = pending.keys.filter { $0 <= completed }.sorted()
        guard !completedSignals.isEmpty else { return 0 }
        for signal in completedSignals {
            if let batch = pending.removeValue(forKey: signal) {
                context.residency.removeAllocation(batch.staging)
            }
        }
        context.residency.commit()
        return completedSignals.count
    }

    /// Waits for every in-flight batch and then removes only staging
    /// allocations.  Persistent texture allocations intentionally remain in
    /// the residency set for renderer use after this call.
    func drain(timeoutMS: UInt64 = 2_000) throws {
        while true {
            lock.lock()
            let signals = pending.keys.sorted()
            lock.unlock()
            guard let signal = signals.first else { return }
            guard context.completionEvent.wait(untilSignaledValue: signal, timeoutMS: timeoutMS) else {
                throw GoldenEyeSourceTextureStoreV6Error.completionTimeout(signal)
            }
            _ = try reapCompletedBatches()
        }
    }

    /// Drains uploads and releases all store-owned texture allocations.  The
    /// caller must invoke this only after the renderer has stopped submitting
    /// draws that reference the returned textures; the method then removes
    /// every allocation in one residency commit.
    func shutdown(timeoutMS: UInt64 = 2_000) throws {
        try drain(timeoutMS: timeoutMS)
        lock.lock()
        defer { lock.unlock() }
        for texture in texturesByHandle.values {
            context.residency.removeAllocation(texture)
        }
        context.residency.commit()
        texturesByHandle.removeAll(keepingCapacity: false)
        residentHandles.removeAll(keepingCapacity: false)
    }

    private static func levelKey(_ resourceHandle: UInt32, _ level: UInt32) -> String {
        "\(resourceHandle):\(level)"
    }
}

extension GoldenEyeSourceTextureUploadPlanV6 {
    /// Builds a strict plan from the final catalog and the copied GESM source
    /// model descriptors.  The method never searches outside the supplied
    /// catalog and never opens a ROM or a source path.
    static func make(
        catalog: GoldenEyeSourceFrontendCatalog,
        models: [(name: String, model: GoldenEyeSourceModelV6)]
    ) throws -> GoldenEyeSourceTextureUploadPlanV6 {
        guard !models.isEmpty else { throw GoldenEyeSourceTextureStoreV6Error.emptyPlan }
        var descriptors: [GoldenEyeSourceTextureDescriptorV6] = []

        for pair in models.sorted(by: { $0.name < $1.name }) {
            for texture in pair.model.textures {
                let payload = try requirePayloadRecord(
                    catalog: catalog,
                    id: texture.payloadRecordID,
                    category: "texture_payload",
                    context: "\(pair.name) texture \(texture.index)"
                )
                let payloadMetadata = try objectMetadata(payload)
                let payloadWidth = try uint(payloadMetadata, key: "width", record: payload.id)
                let payloadHeight = try uint(payloadMetadata, key: "height", record: payload.id)
                let payloadLevels = try uint(payloadMetadata, key: "mip_levels", record: payload.id)
                let payloadOffset = try uint(payloadMetadata, key: "source_offset", record: payload.id)
                let payloadRow = try string(payloadMetadata, key: "source_row", record: payload.id)
                let globalBaseLevel = payload.flags.contains("GLOBAL_TEXTURE_PAYLOAD")
                    || payload.flags.contains("DECODED_RGBA8_BASE_LEVEL")
                let payloadSpan = globalBaseLevel
                    ? payload.rawSize
                    : try uint(payloadMetadata, key: "source_span", record: payload.id)
                try requireFlags(
                    payload,
                    requiredAny: ["EMBEDDED_TEXELS", "RAREWARE_TEXELS", "GLOBAL_TEXTURE_PAYLOAD"]
                )
                try requireRGBAFlags(payload)
                try rejectSourceTextAlias(payload)
                guard payloadWidth == texture.width,
                      payloadHeight == texture.height,
                      payloadLevels == texture.mipCount,
                      payloadOffset == texture.sourceOffset,
                      payloadSpan == texture.sourceSpan,
                      fnv32ResourceRow(modelName: pair.name, row: payloadRow) == texture.sourceRowHandle else {
                    throw GoldenEyeSourceTextureStoreV6Error.sourceEvidenceMismatch(
                        payload.id,
                        "texture source offset/span/row or dimensions"
                    )
                }
                guard payloadSpan >= payload.rawSize else {
                    throw GoldenEyeSourceTextureStoreV6Error.sourceEvidenceMismatch(
                        payload.id,
                        "source span is smaller than raw payload"
                    )
                }

                var levels: [GoldenEyeSourceTextureLevelUploadV6] = []
                var reconstructed = Data()
                for levelIndex in 0..<texture.mipCount {
                    let mipIndex = Int(texture.mipStart) + Int(levelIndex)
                    guard mipIndex >= 0, mipIndex < pair.model.mips.count else {
                        throw GoldenEyeSourceTextureStoreV6Error.invalidDescriptor(
                            "\(pair.name) texture \(texture.index) mip range"
                        )
                    }
                    let mip = pair.model.mips[mipIndex]
                    guard mip.textureIndex == texture.index,
                          mip.level == levelIndex,
                          mip.resourceHandle == texture.resourceHandle,
                          mip.sourceRecordID == texture.payloadRecordID else {
                        throw GoldenEyeSourceTextureStoreV6Error.sourceEvidenceMismatch(
                            mip.payloadRecordID,
                            "GESM mip relationship"
                        )
                    }
                    let mipRecord: GoldenEyeSourceFrontendRecord
                    let metadata: [String: GoldenEyeSourceFrontendJSONValue]
                    let width: UInt32
                    let height: UInt32
                    let level: UInt32
                    let sourceOffset: UInt32
                    let sourceRow: String
                    if globalBaseLevel && levelIndex == 0 {
                        guard mip.payloadRecordID == payload.id else {
                            throw GoldenEyeSourceTextureStoreV6Error.sourceEvidenceMismatch(
                                mip.payloadRecordID,
                                "global base mip must reference texture payload"
                            )
                        }
                        mipRecord = payload
                        metadata = payloadMetadata
                        width = payloadWidth
                        height = payloadHeight
                        level = 0
                        sourceOffset = payloadOffset
                        sourceRow = payloadRow
                        try requireFlags(mipRecord, requiredAny: ["GLOBAL_TEXTURE_PAYLOAD"])
                    } else {
                        mipRecord = try requirePayloadRecord(
                            catalog: catalog,
                            id: mip.payloadRecordID,
                            category: "mip_payload",
                            context: "\(pair.name) texture \(texture.index) mip \(levelIndex)"
                        )
                        metadata = try objectMetadata(mipRecord)
                        width = try uint(metadata, key: "width", record: mipRecord.id)
                        height = try uint(metadata, key: "height", record: mipRecord.id)
                        level = try uint(metadata, key: "level", record: mipRecord.id)
                        sourceOffset = try uint(metadata, key: "source_offset", record: mipRecord.id)
                        sourceRow = try string(metadata, key: "source_row", record: mipRecord.id)
                        try requireFlags(mipRecord, requiredAny: ["EMBEDDED_MIP", "GLOBAL_IMAGE_MIP", "RAREWARE_MIP"])
                        try requireDerivedEvidence(mipRecord, metadata: metadata)
                    }
                    try requireRGBAFlags(mipRecord)
                    try rejectSourceTextAlias(mipRecord)
                    guard width == mip.width,
                          height == mip.height,
                          level == mip.level,
                          sourceOffset == mip.sourceOffset,
                          fnv32ResourceRow(modelName: pair.name, row: sourceRow) == mip.sourceRowHandle,
                          mip.rawByteCount == mipRecord.rawSize,
                          mip.decodedByteCount == mipRecord.decodedSize else {
                        throw GoldenEyeSourceTextureStoreV6Error.sourceEvidenceMismatch(
                            mipRecord.id,
                            "mip dimensions/source bytes/row"
                        )
                    }
                    let decoded = try catalog.copyOut(.decoded, recordID: mipRecord.id)
                    let expectedBytes = try rgbaByteCount(width: width, height: height, record: mipRecord.id)
                    guard decoded.count == expectedBytes,
                          decoded.count == Int(mip.decodedByteCount) else {
                        throw GoldenEyeSourceTextureStoreV6Error.metadataMismatch(
                            mipRecord.id,
                            "decoded RGBA8 byte count"
                        )
                    }
                    let digest = sha256(decoded)
                    guard digest == mipRecord.decodedSHA256 else {
                        throw GoldenEyeSourceTextureStoreV6Error.digestMismatch(
                            mipRecord.id,
                            expected: mipRecord.decodedSHA256,
                            actual: digest
                        )
                    }
                    reconstructed.append(decoded)
                    levels.append(.init(
                        level: mip.level,
                        width: mip.width,
                        height: mip.height,
                        payloadRecordID: mipRecord.id,
                        sourceOffset: mip.sourceOffset,
                        sourceRowHandle: mip.sourceRowHandle,
                        rawByteCount: mip.rawByteCount,
                        decodedByteCount: mip.decodedByteCount,
                        decodedSHA256: mipRecord.decodedSHA256,
                        decoded: decoded
                    ))
                }

                let payloadDecoded = try catalog.copyOut(.decoded, recordID: payload.id)
                let expectedPayload = globalBaseLevel
                    ? (levels.first?.decoded ?? Data())
                    : reconstructed
                guard payloadDecoded == expectedPayload else {
                    throw GoldenEyeSourceTextureStoreV6Error.digestMismatch(
                        payload.id,
                        expected: payload.decodedSHA256,
                        actual: sha256(reconstructed)
                    )
                }
                guard sha256(payloadDecoded) == payload.decodedSHA256 else {
                    throw GoldenEyeSourceTextureStoreV6Error.digestMismatch(
                        payload.id,
                        expected: payload.decodedSHA256,
                        actual: sha256(payloadDecoded)
                    )
                }

                var palette: GoldenEyeSourceTexturePaletteUploadV6?
                if texture.tlutIndex != GoldenEyeSourceModelV6.nullHandle {
                    guard texture.tlutIndex < UInt32(pair.model.tluts.count) else {
                        throw GoldenEyeSourceTextureStoreV6Error.invalidDescriptor(
                            "\(pair.name) texture \(texture.index) TLUT index"
                        )
                    }
                    let tlut = pair.model.tluts[Int(texture.tlutIndex)]
                    guard tlut.textureIndex == texture.index,
                          tlut.resourceHandle == texture.resourceHandle,
                          tlut.sourceRecordID == texture.payloadRecordID else {
                        throw GoldenEyeSourceTextureStoreV6Error.sourceEvidenceMismatch(
                            tlut.payloadRecordID,
                            "GESM TLUT relationship"
                        )
                    }
                    let paletteRecord = try requirePayloadRecord(
                        catalog: catalog,
                        id: tlut.payloadRecordID,
                        category: "tlut_payload",
                        context: "\(pair.name) texture \(texture.index) TLUT"
                    )
                    let metadata = try objectMetadata(paletteRecord)
                    let entries = try uint(metadata, key: "entries", record: paletteRecord.id)
                    let sourceOffset = try uint(metadata, key: "source_offset", record: paletteRecord.id)
                    let sourceRow = try string(metadata, key: "source_row", record: paletteRecord.id)
                    try requireFlags(paletteRecord, requiredAny: ["PD_TLUT"])
                    try requireRGBAFlags(paletteRecord)
                    try rejectSourceTextAlias(paletteRecord)
                    guard sourceOffset >= tlut.sourceOffset,
                          UInt64(sourceOffset) + UInt64(paletteRecord.rawSize)
                            <= UInt64(texture.sourceSpan),
                          fnv32ResourceRow(modelName: pair.name, row: sourceRow) == tlut.sourceRowHandle,
                          tlut.rawByteCount == paletteRecord.rawSize else {
                        throw GoldenEyeSourceTextureStoreV6Error.sourceEvidenceMismatch(
                            paletteRecord.id,
                            "TLUT source offset/span/row/raw size"
                        )
                    }
                    let decoded = try catalog.copyOut(.decoded, recordID: paletteRecord.id)
                    let expectedBytes = try rgbaByteCount(width: entries, height: 1, record: paletteRecord.id)
                    guard decoded.count == expectedBytes,
                          decoded.count == Int(paletteRecord.decodedSize) else {
                        throw GoldenEyeSourceTextureStoreV6Error.metadataMismatch(
                            paletteRecord.id,
                            "decoded TLUT RGBA8 byte count"
                        )
                    }
                    let digest = sha256(decoded)
                    guard digest == paletteRecord.decodedSHA256 else {
                        throw GoldenEyeSourceTextureStoreV6Error.digestMismatch(
                            paletteRecord.id,
                            expected: paletteRecord.decodedSHA256,
                            actual: digest
                        )
                    }
                    palette = .init(
                        resourceHandle: texture.resourceHandle,
                        entries: entries,
                        payloadRecordID: paletteRecord.id,
                        sourceOffset: sourceOffset,
                        sourceRowHandle: tlut.sourceRowHandle,
                        rawByteCount: tlut.rawByteCount,
                        decodedByteCount: paletteRecord.decodedSize,
                        decodedSHA256: paletteRecord.decodedSHA256,
                        decoded: decoded
                    )
                }

                descriptors.append(.init(
                    modelName: pair.name,
                    family: payload.family,
                    resourceHandle: texture.resourceHandle,
                    width: texture.width,
                    height: texture.height,
                    mipLevels: texture.mipCount,
                    payloadRecordID: payload.id,
                    payloadDecodedSHA256: payload.decodedSHA256,
                    sourceOffset: texture.sourceOffset,
                    sourceRowHandle: texture.sourceRowHandle,
                    sourceSpan: texture.sourceSpan,
                    levels: levels,
                    palette: palette
                ))
            }
        }
        return try make(descriptors: descriptors)
    }

    private static func requirePayloadRecord(
        catalog: GoldenEyeSourceFrontendCatalog,
        id: UInt32,
        category: String,
        context: String
    ) throws -> GoldenEyeSourceFrontendRecord {
        guard let record = catalog.record(id: id) else {
            throw GoldenEyeSourceTextureStoreV6Error.missingRecord(id, context)
        }
        guard record.category == category else {
            throw GoldenEyeSourceTextureStoreV6Error.wrongRecordCategory(
                id,
                expected: category,
                actual: record.category
            )
        }
        return record
    }

    private static func objectMetadata(
        _ record: GoldenEyeSourceFrontendRecord
    ) throws -> [String: GoldenEyeSourceFrontendJSONValue] {
        guard case let .object(object) = record.metadata else {
            throw GoldenEyeSourceTextureStoreV6Error.invalidRecord(record.id, "metadata is not an object")
        }
        return object
    }

    private static func uint(
        _ metadata: [String: GoldenEyeSourceFrontendJSONValue],
        key: String,
        record: UInt32
    ) throws -> UInt32 {
        guard case let .integer(value)? = metadata[key], value >= 0, value <= Int64(UInt32.max) else {
            throw GoldenEyeSourceTextureStoreV6Error.metadataMismatch(record, "missing/integer \(key)")
        }
        return UInt32(value)
    }

    private static func string(
        _ metadata: [String: GoldenEyeSourceFrontendJSONValue],
        key: String,
        record: UInt32
    ) throws -> String {
        guard case let .string(value)? = metadata[key], !value.isEmpty else {
            throw GoldenEyeSourceTextureStoreV6Error.metadataMismatch(record, "missing/string \(key)")
        }
        return value
    }

    private static func requireFlags(
        _ record: GoldenEyeSourceFrontendRecord,
        requiredAny: [String]
    ) throws {
        guard requiredAny.contains(where: record.flags.contains) else {
            throw GoldenEyeSourceTextureStoreV6Error.invalidRecord(
                record.id,
                "missing payload provenance flag \(requiredAny.joined(separator: ","))"
            )
        }
    }

    private static func requireRGBAFlags(
        _ record: GoldenEyeSourceFrontendRecord
    ) throws {
        guard record.flags.contains("DECODED_RGBA8")
                || record.flags.contains("DECODED_RGBA8_LEVELS")
                || record.flags.contains("DECODED_RGBA8_BASE_LEVEL")
                || record.flags.contains("DECODED_RGBA8_ENTRIES") else {
            throw GoldenEyeSourceTextureStoreV6Error.invalidRecord(
                record.id,
                "missing decoded RGBA8 flag"
            )
        }
    }

    private static func rejectSourceTextAlias(
        _ record: GoldenEyeSourceFrontendRecord
    ) throws {
        guard !record.flags.contains("SOURCE_TEXT"),
              record.sourceSHA256 != record.decodedSHA256,
              record.sourceSize != record.decodedSize else {
            throw GoldenEyeSourceTextureStoreV6Error.sourceTextAlias(record.id)
        }
    }

    private static func requireDerivedEvidence(
        _ record: GoldenEyeSourceFrontendRecord,
        metadata: [String: GoldenEyeSourceFrontendJSONValue]
    ) throws {
        let flag = record.flags.contains("DERIVED_FROM_SOURCE_BASE")
        let value: Bool?
        if case let .boolean(derived)? = metadata["derived_from_base"] {
            value = derived
        } else {
            value = nil
        }
        guard flag == (value == true) else {
            throw GoldenEyeSourceTextureStoreV6Error.derivedPayloadWithoutEvidence(record.id)
        }
    }

    private static func rgbaByteCount(
        width: UInt32,
        height: UInt32,
        record: UInt32
    ) throws -> Int {
        let pixels = Int(width).multipliedReportingOverflow(by: Int(height))
        guard !pixels.overflow else {
            throw GoldenEyeSourceTextureStoreV6Error.metadataMismatch(record, "dimension overflow")
        }
        let bytes = pixels.partialValue.multipliedReportingOverflow(by: 4)
        guard !bytes.overflow else {
            throw GoldenEyeSourceTextureStoreV6Error.metadataMismatch(record, "RGBA8 byte overflow")
        }
        return bytes.partialValue
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func fnv32ResourceRow(modelName: String, row: String) -> UInt32 {
        var value: UInt32 = 2_166_136_261
        let text = "\(modelName):texture_row:\(row)"
        for byte in text.utf8 { value = (value ^ UInt32(byte)) &* 16_777_619 }
        return value == 0 ? 1 : value
    }
}

@available(macOS 26.0, *)
extension GoldenEyeSourceTextureStoreV6: GoldenEyeSourceTextureResourceProviderV6 {}
