#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif
import Foundation

struct GoldenEyeGBISceneFrameContextV6: Sendable, Equatable {
    let nativeTick: UInt64
    let referenceTick: UInt64
    /// Source-local menu/game timer.  This is intentionally separate from
    /// referenceTick: the frontend may reset or advance its timer at a
    /// screen transition while the global cadence continues.
    let sourceTimer: UInt32?
    let pairPhase: UInt32
    let screen: UInt32
    let subphase: UInt32
    let viewportWidth: UInt32
    let viewportHeight: UInt32
    let logicalWidth: UInt32
    let logicalHeight: UInt32

    init(
        nativeTick: UInt64,
        referenceTick: UInt64,
        sourceTimer: UInt32? = nil,
        pairPhase: UInt32,
        screen: UInt32,
        subphase: UInt32 = 0,
        viewportWidth: UInt32,
        viewportHeight: UInt32,
        logicalWidth: UInt32 = 440,
        logicalHeight: UInt32 = 330
    ) throws {
        guard nativeTick > 0, pairPhase <= 1,
              viewportWidth > 0, viewportHeight > 0,
              logicalWidth > 0, logicalHeight > 0,
              screen <= UInt32(GE_SOURCE_FRAME_V6_SCREEN_MAX) else {
            throw GoldenEyeGBISceneBuilderV6Error.invalidFrameContext
        }
        self.nativeTick = nativeTick
        self.referenceTick = referenceTick
        self.sourceTimer = sourceTimer
        self.pairPhase = pairPhase
        self.screen = screen
        self.subphase = subphase
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
        self.logicalWidth = logicalWidth
        self.logicalHeight = logicalHeight
    }
}

/// Generic value-only handoff for a dynamic source producer.  The producer
/// may supply an outer-state-expanded scene, exact vertex-resource aliases,
/// and additional typed image handles; the GBI bridge never identifies a
/// screen module or reconstructs those values from a model name.
struct GoldenEyeGBIResolvedSceneInputV6 {
    let scene: GESourceSceneV6
    let vertexResources: [GEGBISourceVertexResourceV6]?
    let additionalTextureHandles: [UInt32]

    init(
        scene: GESourceSceneV6,
        vertexResources: [GEGBISourceVertexResourceV6]? = nil,
        additionalTextureHandles: [UInt32] = []
    ) {
        self.scene = scene
        self.vertexResources = vertexResources
        self.additionalTextureHandles = additionalTextureHandles
    }
}

enum GoldenEyeGBISceneBuilderV6Error: Error, Sendable, Equatable,
    CustomStringConvertible
{
    case dynamicDependency(String)
    case invalidMatrixResource(UInt32)
    case invalidViewportResource(UInt32)
    case invalidFrameContext
    case missingMatrix(UInt32)
    case missingProjectionRole
    case missingViewportRole(UInt32)
    case matrixRoleMismatch(UInt32)
    case projectionComposition(String)
    case missingTexture(UInt32)
    case missingVertexGroup(UInt32)
    case duplicateHandle(String, UInt32)
    case resourceCapacity(String)
    case packetCapacity(String)
    case decoderFailure(UInt32, opcode: UInt32, offset: UInt32)
    case invalidSourceVertex(UInt32)
    case invalidSourceTexture(UInt32)
    case unknownImageFormat(UInt32)
    case unsupportedWrap(UInt32)
    case unsupportedRenderMode(UInt32)
    case invalidState(UInt32, String)
    case unsupportedState(UInt32, String)
    case missingSourceNodeTransform(UInt32, String)
    case fallbackSourceNodeTransform(UInt32, UInt32, UInt32)
    case sceneValidation(String)

    var description: String {
        switch self {
        case .dynamicDependency(let value): return "dynamic source dependency: \(value)"
        case .invalidMatrixResource(let handle): return "invalid matrix resource \(handle)"
        case .invalidViewportResource(let handle): return "invalid viewport resource \(handle)"
        case .invalidFrameContext: return "invalid source frame context"
        case .missingMatrix(let handle): return "missing matrix resource 0x\(String(handle, radix: 16))"
        case .missingProjectionRole: return "source projection matrix role is missing"
        case .missingViewportRole(let handle): return "source viewport resource is missing 0x\(String(handle, radix: 16))"
        case .matrixRoleMismatch(let handle): return "source matrix role does not match 0x\(String(handle, radix: 16))"
        case .projectionComposition(let value): return "source projection composition failed: \(value)"
        case .missingTexture(let handle): return "missing texture resource 0x\(String(handle, radix: 16))"
        case .missingVertexGroup(let handle): return "missing vertex group 0x\(String(handle, radix: 16))"
        case .duplicateHandle(let kind, let handle): return "duplicate \(kind) handle 0x\(String(handle, radix: 16))"
        case .resourceCapacity(let value): return "source resource capacity: \(value)"
        case .packetCapacity(let value): return "GBI packet capacity: \(value)"
        case .decoderFailure(let status, let opcode, let offset): return "GBI decoder status \(status) at 0x\(String(offset, radix: 16)) opcode 0x\(String(opcode, radix: 16))"
        case .invalidSourceVertex(let index): return "invalid source vertex \(index)"
        case .invalidSourceTexture(let index): return "invalid source texture \(index)"
        case .unknownImageFormat(let index): return "unknown source image format for texture 0x\(String(index, radix: 16))"
        case .unsupportedWrap(let value): return "unsupported source wrap selector \(value)"
        case .unsupportedRenderMode(let value): return "unsupported source render mode 0x\(String(value, radix: 16))"
        case .invalidState(let state, let reason): return "invalid state \(state): \(reason)"
        case .unsupportedState(let state, let reason): return "unsupported state \(state): \(reason)"
        case .missingSourceNodeTransform(let offset, let model):
            return "missing exact source node transform for \(model) at command 0x\(String(offset, radix: 16))"
        case .fallbackSourceNodeTransform(let offset, let list, let matrix):
            return "fallback source node transform consumed at command 0x\(String(offset, radix: 16)) list \(list) modelview 0x\(String(matrix, radix: 16))"
        case .sceneValidation(let value): return "source scene validation: \(value)"
        }
    }
}

struct GoldenEyeGBISceneBuildResultV6: @unchecked Sendable {
    let snapshot: GoldenEyeSourceSceneSnapshotV6
    let packetDialect: UInt32
    let packetCommandCount: UInt32
    let packetListCount: UInt32
    let packetVertexCount: UInt32
    let packetImageCount: UInt32
    let sourceCommandWordHash: UInt64
    let packetCommandWordHash: UInt64
    let packetSourceCommandWordHash: UInt64
    /// Guarded source texture setup records copied into this immutable build
    /// result.  The Metal consumer may use these records for exact material,
    /// mip, TLUT, and custom G_SETTEX state without reopening source files.
    let textureSetups: [GoldenEyeSourceTextureSetupV6]
    let vertexResourceTotal: UInt32
    let vertexResourcePageCount: UInt32
    let vertexResourceManifestHash: UInt64
    let projectionConsumption: GoldenEyeGBIProjectionConsumptionEvidenceV6
    let decoderStatus: UInt32
    let decoderDraws: [GEGBIDrawV6]
    let stateWordEvidence: [GoldenEyeGBIStateWordEvidenceV6]
    let decoderUnsupportedCount: UInt32
    let unsupportedVisibleCount: UInt32
    let unsupportedReasons: [String]
    let presentable: Bool
    let commandCount: UInt32
    let triangleCount: UInt32
    let sourceTriangleSlotCount: UInt32
    let decoderStateCount: UInt32
    let resourceCount: UInt32
    let eventHash: UInt64
    let stateHash: UInt64
    /// Decoded per-state geometry mode and source model-view values copied
    /// from the C GBI state snapshots. These are consumed by lighting/texgen;
    /// they are never reconstructed from screen IDs or render flags.
    let geometryModesByState: [UInt32: UInt32]
    let modelViewQ16ByState: [UInt32: [Int32]]
    let exactNodeTransformDrawCount: UInt32
    let fallbackNodeTransformDrawCount: UInt32
    let exactNodeTransformHandles: [UInt32]
}

struct GoldenEyeGBIStateWordEvidenceV6: Sendable, Equatable {
    let stateIndex: UInt32
    let otherModeH: UInt32
    let otherModeL: UInt32
    let combineW0: UInt32
    let combineW1: UInt32
}

/// Explicit proof that source projection and viewport values reached one or
/// more combined clip transforms consumed by every emitted draw.  A non-empty
/// provider array is not evidence of use: every source draw must reference a
/// validated clip-composite transform.
struct GoldenEyeGBIProjectionConsumptionEvidenceV6: Sendable, Equatable {
    let sourceProjectionHandle: UInt32
    let sourceViewportHandle: UInt32
    let emittedProjectionTransformCount: UInt32
    let emittedViewportTransformCount: UInt32
    let combinedClipTransformHandle: UInt32
    let combinedClipTransformHandles: [UInt32]
    let requiredDrawCount: UInt32
    let consumedDrawCount: UInt32

    var isComplete: Bool {
        requiredDrawCount == 0 || (
            sourceProjectionHandle != 0 &&
            sourceViewportHandle != 0 &&
            emittedProjectionTransformCount > 0 &&
            emittedViewportTransformCount > 0 &&
            combinedClipTransformHandle != 0 &&
            !combinedClipTransformHandles.isEmpty &&
            consumedDrawCount == requiredDrawCount
        )
    }
}

/// Converts a final GESM model into the bounded classic GE/F3D packet, runs
/// the C decoder, and copies only immutable source values into the V6 scene
/// records.  The decoder remains the authority for command order, cache loads,
/// nested-list traversal, and state snapshots; this adapter never invents a
/// GBI command or stores a pointer.
struct GoldenEyeSourceDynamicRenderSetupContextV6: Sendable, Equatable {
    let primaryRawMode: UInt32
    let secondaryRawMode: UInt32
    let depthEnabled: Bool

    static let gunbarrel = Self(
        primaryRawMode: 0xC411_2048,
        secondaryRawMode: 0xC410_41C8,
        depthEnabled: false
    )
    static let cast = Self(
        primaryRawMode: 0xC411_2078,
        secondaryRawMode: 0xC410_49D8,
        depthEnabled: true
    )

    /// Cast body/head packets use the authored Type-4 pair above, while some
    /// source weapon Model.c packets carry their own render-mode pair (for
    /// example chrfnp90). Keep the exact source words when they are present;
    /// the guarded Cast defaults remain only the bounded fallback for packets
    /// without an explicit render-mode command.
    static func cast(
        forModel model: GoldenEyeSourceModelV6,
        scene: GESourceSceneV6
    ) -> Self {
        let visible = Set(scene.visibleNodeIDs)
        let secondaryIDs = Set(model.nodes.compactMap { node -> UInt32? in
            guard visible.contains(node.id),
                  node.secondaryDisplayListID != GoldenEyeSourceModelV6.nullHandle else {
                return nil
            }
            return node.secondaryDisplayListID
        })
        var primary: UInt32?
        var secondary: UInt32?
        for command in scene.commands where
            command.macro == "gsDPSetRenderMode"
                || command.macro == "gsSPSetOtherMode" {
            guard command.word1 != 0,
                  command.word1 & 0xC000_0000 == 0xC000_0000 else { continue }
            if secondaryIDs.contains(command.displayListID)
                || (primary != nil && command.word1 != primary) {
                secondary = secondary ?? command.word1
            } else {
                primary = primary ?? command.word1
            }
        }
        return Self(
            primaryRawMode: primary ?? Self.cast.primaryRawMode,
            secondaryRawMode: secondary ?? Self.cast.secondaryRawMode,
            depthEnabled: Self.cast.depthEnabled
        )
    }
}

enum GoldenEyeGBISceneBuilderV6 {
    private final class VertexAddressRangeCache: @unchecked Sendable {
        let lock = NSLock()
        var values: [String: [UInt32: (groupHandle: UInt32, first: Int, count: Int)]] = [:]
    }

    private struct DecodedPacketCacheEntry {
        let packet: UnsafeMutablePointer<GEGBISourcePacketV6>
        let decoder: UnsafeMutablePointer<GEGBIResultV6>
        let vertexResources: [GEGBISourceVertexResourceV6]
        let provenance: [GEGBIVertexLoadProvenanceV6]
        let sourceCommandHash: UInt64
        let vertexResourceTotal: Int
        let vertexResourcePageCount: Int
        let vertexResourceManifestHash: UInt64
        let staticData: DecodedPacketStaticData
    }

    /// Immutable work derived solely from the source packet/decoder and its
    /// material setup.  Dynamic builds still lower poses, matrices, and
    /// transformed vertices every tick; this cache only removes repeated
    /// source-command/state/texture/provenance walks from that path.
    private struct DecodedPacketStaticData {
        let textureByHandle: [UInt32: GoldenEyeSourceModelV6.Texture]
        let resources: [GESourceResourceV6]
        let draws: [DecodedDrawMetadata]
    }

    private struct DecodedTextureCoordinateCommands {
        let texture: GEGBISourceCommandV6
        let tile: GEGBISourceCommandV6
        let tileSize: GEGBISourceCommandV6
    }

    private struct LoweredTextureCoordinate {
        let localS: Int64
        let localT: Int64
        let levelWidth: UInt32
        let levelHeight: UInt32
    }

    private struct LoweredStateKey: Hashable {
        let stateIndex: UInt32
        let setupHash: UInt64
        let setupSequence: UInt32
        let setupDisplayListID: UInt32
        let setupOrdinal: UInt32
    }

    private struct DecodedDrawMetadata {
        let draw: GEGBIDrawV6
        let state: GEGBIStateV6
        let sourceCommand: GESourceCompiledCommandV6?
        let textureSetup: GoldenEyeSourceTextureSetupV6?
        let loweredState: LoweredState
        let coordinateCommands: DecodedTextureCoordinateCommands?
        let textureCoordinates: [LoweredTextureCoordinate]?
        let vertexLoadMatrixBySlot: [UInt32: UInt32]
    }

    private final class DecodedPacketCache: @unchecked Sendable {
        let lock = NSLock()
        var values: [String: DecodedPacketCacheEntry] = [:]
    }

    private static let vertexAddressRangeCache = VertexAddressRangeCache()
    private static let decodedPacketCache = DecodedPacketCache()
    private static let syntheticRootHandle: UInt32 = 0xAF00_0001
    private static let modelResourcePrefix: UInt32 = 0xA100_0000
    private static let transformModelPrefix: UInt32 = 0xA200_0000
    private static let transformProjectionPrefix: UInt32 = 0xA300_0000
    private static let transformViewportPrefix: UInt32 = 0xA400_0000
    private static let transformClipPrefix: UInt32 = 0xAA00_0000
    private static let transformNodeClipPrefix: UInt32 = 0xAD00_0000
    private static let vertexPrefix: UInt32 = 0xA500_0000
    private static let indexPrefix: UInt32 = 0xA600_0000
    private static let statePrefix: UInt32 = 0xA700_0000
    private static let drawPrefix: UInt32 = 0xA800_0000
    // Keep palettes in a namespace disjoint from the source texture handles;
    // the binding adapter derives this same prefix at draw time.
    // Keep the palette namespace distinct from source texture handles.  The
    // strict Metal adapter derives the same deterministic A9|low24 handle.
    private static let palettePrefix: UInt32 = 0xA900_0000
    private static let vertexLoadPrefix: UInt32 = 0xAC00_0000
    // Typed source metadata for the hand-authored Rareware segment.  This is
    // deliberately local to the generic builder; it does not import or
    // depend on the Rareware frame module.
    private static let rarewareModelHandle: UInt32 = 0xC93F_B7E2

    static func build(
        model: GoldenEyeSourceModelV6,
        modelName: String,
        switchInputs: [UInt32: UInt32] = [:],
        bspInputs: [UInt32: UInt32] = [:],
        matrices: [GoldenEyeGBIMatrixResourceV6],
        viewports: [GoldenEyeGBIViewportResourceV6],
        matrixRoles: [GoldenEyeSourceMatrixRoleSidecarV6] = [],
        frame: GoldenEyeGBISceneFrameContextV6,
        dynamicResolver: GESourceModelDynamicResolverV6? = nil,
        animationPoses: [GESourceAnimationPoseV6] = [],
        transformContext: GoldenEyeSourceNodeTransformContextV6? = nil,
        renderSetupContext: GoldenEyeSourceDynamicRenderSetupContextV6? = nil,
        textureSetups: [GoldenEyeSourceTextureSetupV6] = [],
        resolvedScene: GoldenEyeGBIResolvedSceneInputV6? = nil,
        omittedDisplayListIDs: Set<UInt32> = [],
        switchInputsAreVisibility: Bool = false
    ) throws -> GoldenEyeGBISceneBuildResultV6 {
        let selectedScene: GESourceSceneV6
        if let resolvedScene {
            // The caller has already run the authoritative compiler for this
            // exact model and supplied the resulting source scene.  Reusing
            // it avoids compiling every dynamic Gunbarrel/Cast model twice
            // per native tick.  The model handle is the bounded linkage guard
            // that prevents a stale scene from being applied to another row.
            guard resolvedScene.scene.modelHandle == model.header.modelHandle else {
                throw GoldenEyeGBISceneBuilderV6Error.dynamicDependency(
                    "resolved scene model handle mismatch"
                )
            }
            selectedScene = resolvedScene.scene
        } else {
            let compilation = GESourceModelCompilerV6.compile(
                model,
                modelName: modelName,
                switchInputs: switchInputs,
                bspInputs: bspInputs,
                dynamicResolver: dynamicResolver,
                switchInputsAreVisibility: switchInputsAreVisibility
            )
            guard compilation.status == .complete else {
                throw GoldenEyeGBISceneBuilderV6Error.dynamicDependency(
                    compilation.diagnostics.map(\.description).joined(separator: "; ")
                )
            }
            guard let compiledScene = compilation.scene, compilation.diagnostics.isEmpty else {
                throw GoldenEyeGBISceneBuilderV6Error.dynamicDependency(
                    compilation.diagnostics.map(\.description).joined(separator: "; ")
                )
            }
            selectedScene = compiledScene
        }
        // The compiler's scene is the authoritative traversal-selected route.
        // Do not replace it with the model-wide command stream: a synthetic
        // root must call only the lists selected by switch/BSP traversal, or
        // hidden Wallet nodes become visible and alter command/state counts.
        let sourceScene = omittedDisplayListIDs.isEmpty
            ? selectedScene
            : sceneByOmittingDisplayLists(selectedScene, omitted: omittedDisplayListIDs)
        // A resolved scene already contains its producer-owned setup words.
        // Do not infer gunbarrel validation merely because a dynamic resolver
        // is present: the Rareware LOD producer is dynamic too, but its outer
        // setup has different authored modes.  The gunbarrel default remains
        // confined to the scene-injection path below; cast and other dynamic
        // producers pass their explicit context.
        let effectiveRenderSetupContext = renderSetupContext
        let scene: GESourceSceneV6
        if let resolvedScene {
            if let context = effectiveRenderSetupContext,
               !resolvedScene.scene.commands.contains(where: {
                   $0.ordinal & 0x8000_0000 != 0
               }) {
                scene = gunbarrelSceneWithRenderSetup(
                    model: model,
                    modelName: modelName,
                    scene: resolvedScene.scene,
                    context: context
                )
            } else {
                scene = resolvedScene.scene
            }
        } else if dynamicResolver != nil {
            // The guarded character/weapon packets intentionally contain the
            // source display-list bodies only.  modelRenderNodeDl applies the
            // per-part Type-4 state immediately before each primary/secondary
            // call, so inject that value-only producer here rather than
            // allowing the C decoder to inherit an uninitialised zero state.
            scene = gunbarrelSceneWithRenderSetup(
                model: model,
                modelName: modelName,
                scene: sourceScene,
                context: effectiveRenderSetupContext ?? .gunbarrel
            )
        } else {
            scene = sourceScene
        }
        guard scene.commands.count <= Int(GE_SOURCE_GBI_V6_MAX_COMMANDS),
              scene.displayLists.count <= Int(GE_SOURCE_GBI_V6_MAX_LISTS),
              model.vertices.count <= Int(GE_SOURCE_GBI_V6_MAX_VERTICES),
              model.vertices.count <= Int(GE_SOURCE_GBI_V6_MAX_VERTEX_CACHE) * 64 else {
            throw GoldenEyeGBISceneBuilderV6Error.packetCapacity("model/list/command/vertex count")
        }

        try validateInputResources(matrices: matrices, viewports: viewports)
        try validateTextureSetups(textureSetups, modelName: modelName, model: model)
        let sourceCommandHash = sourceCommandWordHash(scene)
        let textureSetupHash = hashTextureSetups(textureSetups)
        let additionalTextureHandles = resolvedScene?.additionalTextureHandles ?? []
        let cacheKey = modelName + ":" +
            model.header.packetHash.map { String(format: "%02x", $0) }.joined() + ":" +
            String(scene.semanticHash, radix: 16) + ":source=" +
            String(sourceCommandHash, radix: 16) + ":setup=" +
            String(textureSetupHash, radix: 16) + ":extra=" +
            additionalTextureHandles.sorted().map { String($0, radix: 16) }.joined(separator: ",") + ":dims=" +
            String(frame.logicalWidth, radix: 16) + "," + String(frame.logicalHeight, radix: 16) + ":" +
            String(effectiveRenderSetupContext?.primaryRawMode ?? 0, radix: 16) + ":" +
            String(effectiveRenderSetupContext?.secondaryRawMode ?? 0, radix: 16) + ":m=" +
            matrices.map(\.handle).sorted().map { String($0, radix: 16) }.joined(separator: ",") + ":v=" +
            viewports.map(\.handle).sorted().map { String($0, radix: 16) }.joined(separator: ",")
        let cachedEntryForBuild: DecodedPacketCacheEntry?
        decodedPacketCache.lock.lock()
        cachedEntryForBuild = decodedPacketCache.values[cacheKey]
        decodedPacketCache.lock.unlock()
        let vertexResources: [GEGBISourceVertexResourceV6]
        if let cachedEntryForBuild {
            vertexResources = cachedEntryForBuild.vertexResources
        } else if let supplied = resolvedScene?.vertexResources {
            try validateVertexResourceOverrides(supplied, modelVertexCount: model.vertices.count)
            vertexResources = supplied
        } else {
            vertexResources = try makeVertexResources(
                model: model,
                modelName: modelName,
                scene: scene,
                preferListMetadataForDynamicModel: dynamicResolver != nil
            )
        }
        guard vertexResources.count <= Int(GE_SOURCE_GBI_V6_MAX_VERTEX_RESOURCE_TOTAL) else {
            throw GoldenEyeGBISceneBuilderV6Error.packetCapacity("vertex resource total")
        }

        let packetPointer: UnsafeMutablePointer<GEGBISourcePacketV6>
        let decoderPointer: UnsafeMutablePointer<GEGBIResultV6>
        let vertexLoadProvenance: [GEGBIVertexLoadProvenanceV6]
        let cachedVertexResources: [GEGBISourceVertexResourceV6]
        let cachedVertexPageCount: Int
        let cachedVertexManifestHash: UInt64
        let staticData: DecodedPacketStaticData

        if let cachedEntry = cachedEntryForBuild {
            packetPointer = cachedEntry.packet
            decoderPointer = cachedEntry.decoder
            vertexLoadProvenance = cachedEntry.provenance
            cachedVertexResources = cachedEntry.vertexResources
            cachedVertexPageCount = cachedEntry.vertexResourcePageCount
            cachedVertexManifestHash = cachedEntry.vertexResourceManifestHash
            staticData = cachedEntry.staticData
        } else {
            // GEGBISourcePacketV6 and GEGBIResultV6 remain heap-owned for the
            // lifetime of this static topology cache.  The cached C decoder
            // consumes only command/resource handles; frame-local matrix
            // values and poses are supplied to `convert` below.
            packetPointer = try makePacket(
                model: model,
                modelName: modelName,
                scene: scene,
                matrices: matrices,
                viewports: viewports,
                vertexResources: vertexResources,
                additionalTextureHandles: resolvedScene?.additionalTextureHandles ?? []
            )
            decoderPointer = UnsafeMutablePointer<GEGBIResultV6>.allocate(capacity: 1)
            let baseVertexResourceCount = min(vertexResources.count, Int(GE_SOURCE_GBI_V6_MAX_VERTEX_RESOURCES))
            var vertexPages = try makeVertexResourcePages(
                resources: vertexResources,
                baseCount: baseVertexResourceCount
            )
            let vertexManifestHash = vertexResourceManifestHash(
                baseResources: Array(vertexResources.prefix(baseVertexResourceCount)),
                pages: vertexPages
            )
            for index in vertexPages.indices {
                vertexPages[index].manifest_hash = vertexManifestHash
            }
            let pagePointer: UnsafeMutablePointer<GEGBISourceVertexResourcePageV6>?
            if vertexPages.isEmpty {
                pagePointer = nil
            } else {
                let pointer = UnsafeMutablePointer<GEGBISourceVertexResourcePageV6>.allocate(capacity: vertexPages.count)
                vertexPages.withUnsafeBufferPointer { buffer in
                    pointer.initialize(from: buffer.baseAddress!, count: vertexPages.count)
                }
                pagePointer = pointer
            }
            let provenanceCapacity = Int(GE_SOURCE_GBI_V6_MAX_VERTEX_LOAD_PROVENANCE)
            let provenancePointer = UnsafeMutablePointer<GEGBIVertexLoadProvenanceV6>
                .allocate(capacity: provenanceCapacity)
            var provenanceCount: UInt32 = 0
            let decoderStatus = ge_source_gbi_decode_v6_into_with_vertex_pages_and_provenance(
                packetPointer,
                pagePointer,
                UInt32(vertexPages.count),
                decoderPointer,
                provenancePointer,
                UInt32(provenanceCapacity),
                &provenanceCount
            )
            if let pagePointer {
                pagePointer.deinitialize(count: vertexPages.count)
                pagePointer.deallocate()
            }
            guard decoderStatus == GE_STATUS_OK else {
                let opcode = decoderPointer.pointee.error_opcode
                let offset = decoderPointer.pointee.error_offset
                provenancePointer.deallocate()
                decoderPointer.deallocate()
                packetPointer.deallocate()
                throw GoldenEyeGBISceneBuilderV6Error.decoderFailure(
                    UInt32(decoderStatus),
                    opcode: opcode,
                    offset: offset
                )
            }
            guard decoderPointer.pointee.unsupported_count == 0,
                  provenanceCount <= UInt32(provenanceCapacity) else {
                let opcode = decoderPointer.pointee.error_opcode
                let offset = decoderPointer.pointee.error_offset
                provenancePointer.deallocate()
                decoderPointer.deallocate()
                packetPointer.deallocate()
                throw GoldenEyeGBISceneBuilderV6Error.decoderFailure(
                    UInt32(GE_STATUS_UNSUPPORTED_COMMAND), opcode: opcode, offset: offset
                )
            }
            let provenance = Array(
                UnsafeBufferPointer(start: provenancePointer, count: Int(provenanceCount))
            )
            provenancePointer.deallocate()
            let aliases = try textureAliases(scene: scene, modelName: modelName, model: model)
            let staticDataValue = try makeDecodedPacketStaticData(
                model: model,
                scene: scene,
                packetPointer: packetPointer,
                decoderPointer: decoderPointer,
                textureAliases: aliases,
                textureSetups: textureSetups,
                logicalWidth: frame.logicalWidth,
                logicalHeight: frame.logicalHeight,
                vertexLoadProvenance: provenance
            )
            let value = DecodedPacketCacheEntry(
                packet: packetPointer,
                decoder: decoderPointer,
                vertexResources: vertexResources,
                provenance: provenance,
                sourceCommandHash: sourceCommandHash,
                vertexResourceTotal: vertexResources.count,
                vertexResourcePageCount: vertexPages.count,
                vertexResourceManifestHash: vertexManifestHash,
                staticData: staticDataValue
            )
            staticData = value.staticData
            decodedPacketCache.lock.lock()
            decodedPacketCache.values[cacheKey] = value
            decodedPacketCache.lock.unlock()
            vertexLoadProvenance = provenance
            cachedVertexResources = vertexResources
            cachedVertexPageCount = vertexPages.count
            cachedVertexManifestHash = vertexManifestHash
        }

        let effectiveMatrixRoles = matrixRoles.isEmpty
            ? try matrixRoleSidecars(from: matrices)
            : matrixRoles
        let converted = try convert(
            model: model,
            modelName: modelName,
            scene: scene,
            packetPointer: packetPointer,
            decoderPointer: decoderPointer,
            sourceCommandWordHash: sourceCommandHash,
            vertexResourceTotal: cachedVertexResources.count,
            vertexResourcePageCount: cachedVertexPageCount,
            vertexResourceManifestHash: cachedVertexManifestHash,
            matrices: matrices,
            viewports: viewports,
            matrixRoles: effectiveMatrixRoles,
            frame: frame,
            animationPoses: animationPoses,
            vertexLoadProvenance: vertexLoadProvenance,
            transformContext: transformContext,
            renderSetupContext: effectiveRenderSetupContext,
            textureSetups: textureSetups,
            staticData: staticData
        )
        return converted
    }

    /// Pure negative-test seam for malformed raw state.  It uses no source or
    /// host resource fallback and is intentionally not used by production
    /// rendering.
    static func validateStateForTesting(_ state: GEGBIStateV6) throws {
        _ = try lowerState(
            state,
            stateIndex: 0,
            imageToTexture: [:],
            textureByHandle: [:],
            logicalWidth: 440,
            logicalHeight: 330,
            matrixKinds: [:]
        )
    }

    /// Adds the source producer's outer Rareware setup to a private scene
    /// copy.  The guarded rarewarelogo.gesm remains the exact 389-command
    /// segment; these producer-owned setup commands are the value-only title.c state
    /// established before the segment's display lists are called.
    static func rarewareSceneWithOuterSetup(
        model: GoldenEyeSourceModelV6,
        scene: GESourceSceneV6
    ) -> GESourceSceneV6 {
        guard model.textures.count >= 6 else { return scene }
        let modelHandle: UInt32 = 0xF300_0001
        let projectionHandle: UInt32 = 0xF102_0200
        func setup(
            displayListID: UInt32,
            ordinal: UInt32,
            macro: String,
            arguments: [GoldenEyeSourceModelV6.TokenValue],
            word0: UInt32,
            word1: UInt32,
            handle: UInt32
        ) -> GESourceCompiledCommandV6 {
            GESourceCompiledCommandV6(
                displayListID: displayListID,
                // Keep producer-owned outer setup commands out of the
                // source `(display-list, ordinal)` namespace.  Rareware's
                // guarded segment legitimately starts at ordinal 0, so a
                // low ordinal here would collide in the builder's exact
                // source-command lookup even though the setup is distinct.
                ordinal: 0x8000_0000 | ordinal,
                macro: macro,
                macroHandle: handle,
                opcode: UInt8(word0 >> 24),
                arguments: arguments,
                word0: word0,
                word1: word1
            )
        }
        func bodySetup(
            displayListID: UInt32,
            textureHandle: UInt32,
            ordinalBase: UInt32,
            handleBase: UInt32
        ) -> [GESourceCompiledCommandV6] {
            let common: [GESourceCompiledCommandV6] = [
                setup(
                    displayListID: displayListID,
                    ordinal: ordinalBase,
                    macro: "gsDPSetTextureImage",
                    arguments: [.integer(0), .integer(2), .integer(1), .handle(kind: .texture, value: textureHandle)],
                    word0: 0xFD10_0000,
                    word1: textureHandle,
                    handle: handleBase
                ),
                setup(
                    displayListID: displayListID,
                    ordinal: ordinalBase + 1,
                    macro: "gsDPSetTile",
                    arguments: [.integer(0), .integer(2), .integer(0), .integer(0), .integer(7), .integer(0), .integer(0), .integer(5), .integer(0), .integer(0), .integer(5), .integer(0)],
                    word0: 0xF500_0E00,
                    word1: 0x0000_5040,
                    handle: handleBase + 1
                ),
                setup(
                    displayListID: displayListID,
                    ordinal: ordinalBase + 2,
                    macro: "gsDPLoadSync",
                    arguments: [],
                    word0: 0xE600_0000,
                    word1: 0,
                    handle: handleBase + 2
                ),
                setup(
                    displayListID: displayListID,
                    ordinal: ordinalBase + 3,
                    macro: "gsDPLoadBlock",
                    arguments: [.integer(7), .integer(0), .integer(0), .integer(255), .integer(255)],
                    word0: 0xF300_00FF,
                    word1: 0x070F_FFFF,
                    handle: handleBase + 3
                ),
                setup(
                    displayListID: displayListID,
                    ordinal: ordinalBase + 4,
                    macro: "gsDPSetTile",
                    arguments: [.integer(0), .integer(2), .integer(8), .integer(0), .integer(0), .integer(0), .integer(0), .integer(5), .integer(0), .integer(0), .integer(5), .integer(0)],
                    word0: 0xF500_1000,
                    word1: 0x0000_5040,
                    handle: handleBase + 4
                ),
                setup(
                    displayListID: displayListID,
                    ordinal: ordinalBase + 5,
                    macro: "gsDPSetTileSize",
                    arguments: [.integer(0), .integer(0), .integer(0), .integer(124), .integer(124)],
                    word0: 0xF200_0000,
                    word1: 0x0007_C07C,
                    handle: handleBase + 5
                ),
            ]
            return common
        }
        let matrixProjection = setup(
            displayListID: 4,
            ordinal: 0,
            macro: "gsSPMatrix",
            arguments: [.handle(kind: .resource, value: projectionHandle), .integer(1)],
            word0: 0x0101_0040,
            word1: projectionHandle,
            handle: 0x4E10_0001
        )
        let matrixModel = setup(
            displayListID: 4,
            ordinal: 1,
            macro: "gsSPMatrix",
            arguments: [.handle(kind: .resource, value: modelHandle), .integer(0)],
            word0: 0x0100_0040,
            word1: modelHandle,
            handle: 0x4E10_0002
        )
        let textureEnable = setup(
            displayListID: 4,
            ordinal: 2,
            macro: "gsSPTexture",
            arguments: [.integer(0x0800), .integer(0x0800), .integer(0), .integer(0), .boolean(true)],
            word0: 0xBB00_0001,
            word1: 0x0800_0800,
            handle: 0x4E10_0003
        )
        // title.c establishes these OtherMode-H values before calling the
        // Rareware segment.  The guarded GESM starts at the display-list
        // bodies, so omitting them silently selected point/no-perspective
        // sampling and made the letter mips look blurrier than the source.
        let texturePerspective = setup(
            displayListID: 4,
            ordinal: 3,
            macro: "gsSPSetOtherMode",
            arguments: [.integer(0xBA), .integer(19), .integer(1), .integer(1)],
            word0: 0xBA00_1301,
            word1: 1,
            handle: 0x4E10_0004
        )
        let textureFilter = setup(
            displayListID: 4,
            ordinal: 4,
            macro: "gsDPSetTextureFilter",
            arguments: [.integer(2)],
            word0: 0xBA00_0C02,
            word1: 2,
            handle: 0x4E10_0005
        )
        let textureConvert = setup(
            displayListID: 4,
            ordinal: 5,
            macro: "gsSPSetOtherMode",
            arguments: [.integer(0xBA), .integer(9), .integer(3), .integer(6)],
            word0: 0xBA00_0903,
            word1: 6,
            handle: 0x4E10_0006
        )
        let textureDetail = setup(
            displayListID: 4,
            ordinal: 6,
            macro: "gsDPSetTextureDetail",
            arguments: [.integer(0)],
            word0: 0xBA00_1102,
            word1: 0,
            handle: 0x4E10_0007
        )
        let textureLOD = setup(
            displayListID: 4,
            ordinal: 7,
            macro: "gsDPSetTextureLOD",
            arguments: [.integer(0)],
            word0: 0xBA00_1001,
            word1: 0,
            handle: 0x4E10_0008
        )
        let textureLUT = setup(
            displayListID: 4,
            ordinal: 8,
            macro: "gsSPSetOtherMode",
            arguments: [.integer(0xBA), .integer(14), .integer(2), .integer(0)],
            word0: 0xBA00_0E02,
            word1: 0,
            handle: 0x4E10_0009
        )
        let body0 = bodySetup(
            displayListID: 4,
            textureHandle: model.textures[4].resourceHandle,
            ordinalBase: 9,
            handleBase: 0x4E10_0010
        )
        var body1 = bodySetup(
            displayListID: 6,
            textureHandle: model.textures[5].resourceHandle,
            ordinalBase: 0,
            handleBase: 0x4E10_0020
        )
        // D_02004758 supplies its own exact SETTILESIZE after the
        // G_TX_NOLOD reset, so the outer upload only needs the five image/
        // tile/load commands here.  Keeping the command budget unchanged
        // preserves the packet's 414-command envelope.
        _ = body1.popLast()
        // title.c's second gDPLoadTextureBlock uses G_TX_NOLOD.  The
        // dedicated list repeats that gsSPTexture(…, 0, …) before its first
        // draw; retain the same reset before the outer image/tile upload so
        // the typed one-level setup cannot inherit the LOD-5 state from the
        // preceding Rareware text pass.
        let body1TextureReset = setup(
            displayListID: 6,
            // body1's outer upload already occupies synthetic ordinals
            // 0...4 in this list; keep the explicit G_TX_NOLOD reset
            // distinct while remaining outside the source ordinal space.
            ordinal: 0x100,
            macro: "gsSPTexture",
            arguments: [.integer(0x1C81), .integer(0x1426), .integer(0), .integer(0), .boolean(true)],
            word0: 0xBB00_0001,
            word1: 0x1C81_1426,
            handle: 0x4E10_002F
        )
        let originalByList = Dictionary(grouping: scene.commands, by: \ .displayListID)
        var commands: [GESourceCompiledCommandV6] = []
        commands.reserveCapacity(scene.commands.count + 3 + body0.count + body1.count)
        commands.append(matrixProjection)
        commands.append(matrixModel)
        commands.append(textureEnable)
        commands.append(texturePerspective)
        commands.append(textureFilter)
        commands.append(textureConvert)
        commands.append(textureDetail)
        commands.append(textureLOD)
        commands.append(textureLUT)
        commands.append(contentsOf: body0)
        commands.append(contentsOf: originalByList[4] ?? [])
        commands.append(contentsOf: originalByList[5] ?? [])
        commands.append(body1TextureReset)
        commands.append(contentsOf: body1)
        commands.append(contentsOf: originalByList[6] ?? [])
        for list in scene.displayLists where list.id != 4 && list.id != 5 && list.id != 6 {
            commands.append(contentsOf: originalByList[list.id] ?? [])
        }
        return GESourceSceneV6(
            modelHandle: scene.modelHandle,
            visibleNodeIDs: scene.visibleNodeIDs,
            displayLists: scene.displayLists,
            commands: commands,
            vertices: scene.vertices,
            textures: scene.textures,
            mips: scene.mips,
            tluts: scene.tluts,
            displayListHandles: scene.displayListHandles,
            vertexGroupHandles: scene.vertexGroupHandles,
            textureHandles: scene.textureHandles,
            unsupportedCount: scene.unsupportedCount,
            semanticHash: scene.semanticHash
        )
    }

    /// Restores the exact Type-4 setup emitted by `modelRenderNodeDl` for the
    /// Gunbarrel character/weapon path.  GESM packets keep only the guarded
    /// model display-list bodies; renderdata state is an owner-side value and
    /// therefore belongs in this additive scene adapter.  The title path uses
    /// `PropType = 7` and no depth buffer, which reaches the generic Type-4
    /// branch in the portable source: fog white, TRILERP/MODULATEIA2, and
    /// AA opaque/translucent modes.  Secondary lists retain their source
    /// translucent mode and are discovered from the node associations rather
    /// than from list order.
    static func gunbarrelSceneWithRenderSetup(
        model: GoldenEyeSourceModelV6,
        modelName: String,
        scene: GESourceSceneV6,
        context: GoldenEyeSourceDynamicRenderSetupContextV6
    ) -> GESourceSceneV6 {
        // Any guarded dynamic character/weapon listing uses the same
        // source modelRenderNodeDl Type-4 setup; the model name only
        // identifies which prepared GESM graph is being traversed.

        let visible = Set(scene.visibleNodeIDs)
        let secondaryIDs = Set(model.nodes.compactMap { node -> UInt32? in
            guard visible.contains(node.id),
                  node.secondaryDisplayListID != GoldenEyeSourceModelV6.nullHandle else {
                return nil
            }
            return node.secondaryDisplayListID
        })

        func setup(
            displayListID: UInt32,
            ordinal: UInt32,
            macro: String,
            arguments: [GoldenEyeSourceModelV6.TokenValue],
            word0: UInt32,
            word1: UInt32,
            handle: UInt32
        ) -> GESourceCompiledCommandV6 {
            GESourceCompiledCommandV6(
                displayListID: displayListID,
                ordinal: ordinal,
                macro: macro,
                macroHandle: handle,
                opcode: UInt8(word0 >> 24),
                arguments: arguments,
                word0: word0,
                word1: word1
            )
        }

        func setupForList(_ list: GoldenEyeSourceModelV6.DisplayList) -> [GESourceCompiledCommandV6] {
            let secondary = secondaryIDs.contains(list.id)
            let mode = secondary ? context.secondaryRawMode : context.primaryRawMode
            let base = 0x4B00_0000 | ((list.id & 0x3F) << 8)
            // Keep synthetic commands out of the source `(list, ordinal)`
            // namespace used by vertex-load validation and texture setup
            // lookup.  The high bit is outside the guarded source ordinals.
            let ordinalBase = 0x8000_0000 | ((list.id & 0x7F) << 8)
            let values: [(String, [GoldenEyeSourceModelV6.TokenValue], UInt32, UInt32)] = [
                ("gsDPPipeSync", [], 0xE700_0000, 0),
                ("gsDPSetCycleType", [.integer(1)], 0xBA00_1402, 0x0010_0000),
                ("gsDPSetFogColor", [.integer(0xFF), .integer(0xFF), .integer(0xFF), .integer(0)], 0xF800_0000, 0xFFFF_FF00),
                ("gsDPSetCombine", [.constant(name: "G_CC_TRILERP", value: 0), .constant(name: "G_CC_MODULATEIA2", value: 0)], 0xFC26_A004, 0x1F10_93FF),
                ("gsDPSetRenderMode", [.integer(Int64(secondary ? 1 : 0)), .integer(Int64(mode))], 0xB900_031D, mode),
            ]
            return values.enumerated().map { index, value in
                setup(
                    displayListID: list.id,
                    ordinal: ordinalBase + UInt32(index),
                    macro: value.0,
                    arguments: value.1,
                    word0: value.2,
                    word1: value.3,
                    handle: base + UInt32(index)
                )
            }
        }

        var commands: [GESourceCompiledCommandV6] = []
        commands.reserveCapacity(scene.commands.count + scene.displayLists.count * 5)
        let originalByList = Dictionary(grouping: scene.commands, by: \.displayListID)
        for list in scene.displayLists {
            commands.append(contentsOf: setupForList(list))
            commands.append(contentsOf: originalByList[list.id] ?? [])
        }
        return GESourceSceneV6(
            modelHandle: scene.modelHandle,
            visibleNodeIDs: scene.visibleNodeIDs,
            displayLists: scene.displayLists,
            commands: commands,
            vertices: scene.vertices,
            textures: scene.textures,
            mips: scene.mips,
            tluts: scene.tluts,
            displayListHandles: scene.displayListHandles,
            vertexGroupHandles: scene.vertexGroupHandles,
            textureHandles: scene.textureHandles,
            unsupportedCount: scene.unsupportedCount,
            semanticHash: scene.semanticHash
        )
    }

    private static func sceneByOmittingDisplayLists(
        _ scene: GESourceSceneV6,
        omitted: Set<UInt32>
    ) -> GESourceSceneV6 {
        let lists = scene.displayLists.filter { !omitted.contains($0.id) }
        let commands = scene.commands.filter { !omitted.contains($0.displayListID) }
        return GESourceSceneV6(
            modelHandle: scene.modelHandle,
            visibleNodeIDs: scene.visibleNodeIDs,
            displayLists: lists,
            commands: commands,
            vertices: scene.vertices,
            textures: scene.textures,
            mips: scene.mips,
            tluts: scene.tluts,
            displayListHandles: lists.map(\.handle),
            vertexGroupHandles: scene.vertexGroupHandles,
            textureHandles: scene.textureHandles,
            unsupportedCount: scene.unsupportedCount,
            semanticHash: scene.semanticHash
        )
    }

    static func vertexResourceOverrides(
        model: GoldenEyeSourceModelV6,
        scene: GESourceSceneV6
    ) throws -> [GEGBISourceVertexResourceV6] {
        var output: [GEGBISourceVertexResourceV6] = []
        var seen = Set<UInt32>()
        var groupRanges: [UInt32: (first: UInt32, count: UInt32)] = [:]
        var start = 0
        while start < model.vertices.count {
            let groupHandle = model.vertices[start].groupHandle
            var end = start + 1
            while end < model.vertices.count,
                  model.vertices[end].groupHandle == groupHandle {
                end += 1
            }
            groupRanges[groupHandle] = (UInt32(start), UInt32(end - start))
            start = end
        }
        for command in scene.commands where command.macro == "gsSPVertex" {
            guard let range = groupRanges[command.word1] else {
                throw GoldenEyeGBISceneBuilderV6Error.missingVertexGroup(command.word1)
            }
            let packetHandle = vertexLoadHandle(displayListID: command.displayListID, ordinal: command.ordinal)
            guard seen.insert(packetHandle).inserted else {
                throw GoldenEyeGBISceneBuilderV6Error.duplicateHandle("Rareware vertex load", packetHandle)
            }
            var value = GEGBISourceVertexResourceV6()
            value.handle = packetHandle
            value.first_vertex = range.first
            value.vertex_count = range.count
            value.flags = GE_SOURCE_GBI_V6_VERTEX_RESOURCE_FLAG_EXACT_ALIAS
            output.append(value)
        }
        return output
    }

    private static func validateInputResources(
        matrices: [GoldenEyeGBIMatrixResourceV6],
        viewports: [GoldenEyeGBIViewportResourceV6]
    ) throws {
        var handles = Set<UInt32>()
        for matrix in matrices {
            guard handles.insert(matrix.handle).inserted else {
                throw GoldenEyeGBISceneBuilderV6Error.duplicateHandle("matrix", matrix.handle)
            }
        }
        for viewport in viewports {
            guard handles.insert(viewport.handle).inserted else {
                throw GoldenEyeGBISceneBuilderV6Error.duplicateHandle("viewport", viewport.handle)
            }
        }
        guard matrices.count <= Int(GE_SOURCE_GBI_V6_MAX_MATRICES),
              viewports.count <= Int(GE_SOURCE_GBI_V6_MAX_VIEWPORTS) else {
            throw GoldenEyeGBISceneBuilderV6Error.packetCapacity("matrix/viewport resources")
        }
    }

    /// Validate an externally resolved vertex-resource manifest before it is
    /// copied into the bounded GBI packet.  Dynamic producers may preserve
    /// exact cache-window aliases, but they must still identify a non-empty
    /// range wholly inside the guarded source vertex array and use only the
    /// C contract's value flags.
    private static func validateVertexResourceOverrides(
        _ resources: [GEGBISourceVertexResourceV6],
        modelVertexCount: Int
    ) throws {
        guard resources.count <= Int(GE_SOURCE_GBI_V6_MAX_VERTEX_RESOURCE_TOTAL) else {
            throw GoldenEyeGBISceneBuilderV6Error.packetCapacity("vertex resource total")
        }
        var handles = Set<UInt32>()
        for resource in resources {
            guard resource.handle != 0,
                  resource.vertex_count > 0,
                  resource.flags & ~UInt32(GE_SOURCE_GBI_V6_VERTEX_RESOURCE_FLAG_MASK) == 0,
                  UInt64(resource.first_vertex) + UInt64(resource.vertex_count) <= UInt64(modelVertexCount),
                  handles.insert(resource.handle).inserted else {
                throw GoldenEyeGBISceneBuilderV6Error.invalidState(
                    0,
                    "invalid resolved vertex resource 0x\(String(resource.handle, radix: 16))"
                )
            }
        }
    }

    private static func validateTextureSetups(
        _ setups: [GoldenEyeSourceTextureSetupV6],
        modelName: String,
        model: GoldenEyeSourceModelV6
    ) throws {
        let textures = Dictionary(uniqueKeysWithValues: model.textures.map { ($0.resourceHandle, $0) })
        var keys = Set<String>()
        for setup in setups {
            guard setup.modelName == modelName,
                  setup.resourceHandle != 0,
                  setup.tile < 8,
                  setup.maxLOD < 8,
                  setup.setupHash != 0,
                  !setup.levels.isEmpty,
                  let texture = textures[setup.resourceHandle],
                  texture.payloadRecordID == setup.sourcePayloadRecordID,
                  texture.width == setup.levels[0].width,
                  texture.height == setup.levels[0].height else {
                throw GoldenEyeGBISceneBuilderV6Error.invalidSourceTexture(setup.resourceHandle)
            }
            let key = "\(setup.displayListID):\(setup.ordinal):\(setup.resourceHandle):\(setup.tile)"
            guard keys.insert(key).inserted else {
                throw GoldenEyeGBISceneBuilderV6Error.duplicateHandle(
                    "texture setup",
                    setup.resourceHandle
                )
            }
        }
    }

    private static func makePacket(
        model: GoldenEyeSourceModelV6,
        modelName: String,
        scene: GESourceSceneV6,
        matrices: [GoldenEyeGBIMatrixResourceV6],
        viewports: [GoldenEyeGBIViewportResourceV6],
        vertexResources: [GEGBISourceVertexResourceV6],
        additionalTextureHandles: [UInt32]
    ) throws -> UnsafeMutablePointer<GEGBISourcePacketV6> {
        let packetPointer = UnsafeMutablePointer<GEGBISourcePacketV6>.allocate(capacity: 1)
        // C structs are trivially initialized for this value-only contract;
        // zero the heap storage directly so no large temporary packet is
        // materialized on the calling owner's stack.
        _ = memset(packetPointer, 0, MemoryLayout<GEGBISourcePacketV6>.size)
        var transferred = false
        defer {
            if !transferred {
                packetPointer.deallocate()
            }
        }
        packetPointer.pointee.header.abi_version = UInt32(GE_NATIVE_ABI_VERSION)
        packetPointer.pointee.header.struct_size = UInt32(MemoryLayout<GEGBISourcePacketV6>.size)
        packetPointer.pointee.packet_version = UInt32(GE_SOURCE_GBI_V6_PACKET_VERSION)
        packetPointer.pointee.dialect = UInt32(GE_SOURCE_GBI_V6_DIALECT_CLASSIC_GE_F3D)
        packetPointer.pointee.list_count = UInt32(scene.displayLists.count + 1)
        packetPointer.pointee.vertex_count = UInt32(model.vertices.count)
        packetPointer.pointee.matrix_count = UInt32(matrices.count)
        packetPointer.pointee.viewport_count = UInt32(viewports.count)

        let textureAliases = try textureAliases(scene: scene, modelName: modelName, model: model)
        let flattened = flattenCommands(
            scene: scene,
            modelName: modelName,
            model: model,
            textureAliases: textureAliases
        )
        packetPointer.pointee.command_count = UInt32(flattened.commands.count)
        guard !flattened.commands.isEmpty, !scene.displayLists.isEmpty,
              flattened.commands.count <= Int(GE_SOURCE_GBI_V6_MAX_COMMANDS),
              flattened.lists.count <= Int(GE_SOURCE_GBI_V6_MAX_LISTS) else {
            throw GoldenEyeGBISceneBuilderV6Error.packetCapacity("empty root/list table")
        }
        packetPointer.pointee.root_list_handle = syntheticRootHandle

        try writeFixedArray(&packetPointer.pointee.commands, values: flattened.commands)
        try writeFixedArray(&packetPointer.pointee.lists, values: flattened.lists)

        let vertices = try model.vertices.map(sourceVertex)
        try writeFixedArray(&packetPointer.pointee.vertices, values: vertices)

        let baseResources = Array(vertexResources.prefix(Int(GE_SOURCE_GBI_V6_MAX_VERTEX_RESOURCES)))
        packetPointer.pointee.vertex_resource_count = UInt32(baseResources.count)
        try writeFixedArray(&packetPointer.pointee.vertex_resources, values: baseResources)

        let matrixValues = matrices.map { resource -> GEGBISourceMatrixResourceV6 in
            var value = GEGBISourceMatrixResourceV6()
            value.handle = resource.handle
            setInt32Tuple(&value.values, values: resource.values)
            return value
        }
        try writeFixedArray(&packetPointer.pointee.matrices, values: matrixValues)

        let viewportValues = viewports.map { resource -> GEGBISourceViewportResourceV6 in
            var value = GEGBISourceViewportResourceV6()
            value.handle = resource.handle
            setInt32Tuple(&value.values, values: resource.values)
            value.flags = 0
            return value
        }
        try writeFixedArray(&packetPointer.pointee.viewports, values: viewportValues)

        let imageValues = try makeImages(
            model: model,
            modelName: modelName,
            scene: scene,
            textureAliases: textureAliases,
            additionalTextureHandles: additionalTextureHandles
        )
        packetPointer.pointee.image_count = UInt32(imageValues.count)
        try writeFixedArray(&packetPointer.pointee.images, values: imageValues)
        transferred = true
        return packetPointer
    }

    private static func flattenCommands(
        scene: GESourceSceneV6,
        modelName: String,
        model: GoldenEyeSourceModelV6,
        textureAliases: [UInt32: UInt32]
    ) -> (commands: [GEGBISourceCommandV6], lists: [GEGBISourceListV6]) {
        var commands: [GEGBISourceCommandV6] = []
        var lists: [GEGBISourceListV6] = []
        commands.reserveCapacity(scene.commands.count + scene.displayLists.count + 1)
        let rootFirst = commands.count
        for list in scene.displayLists {
            var call = GEGBISourceCommandV6()
            call.w0 = UInt32(GE_SOURCE_GBI_V6_OP_DL) << 24
            call.w1 = list.handle
            commands.append(call)
        }
        var rootEnd = GEGBISourceCommandV6()
        rootEnd.w0 = UInt32(GE_SOURCE_GBI_V6_OP_ENDDL) << 24
        commands.append(rootEnd)
        var root = GEGBISourceListV6()
        root.handle = syntheticRootHandle
        root.first_command = UInt32(rootFirst)
        root.command_count = UInt32(commands.count - rootFirst)
        root.flags = 0
        lists.append(root)
        for list in scene.displayLists {
            let first = commands.count
            for command in scene.commands where command.displayListID == list.id {
                var value = GEGBISourceCommandV6()
                value.w0 = command.word0
                value.w1 = command.word1
                if command.macro == "gsSPVertex" {
                    // The C decoder resolves one resource per load.  Source
                    // GESM group handles may repeat across sequential cache
                    // windows, so give each load a deterministic packet-only
                    // handle while retaining the original command hash.
                    value.w1 = vertexLoadHandle(
                        displayListID: command.displayListID,
                        ordinal: command.ordinal
                    )
                } else if command.macro == "gsSPUseTexture", command.arguments.count >= 9 {
                    let rawHandle = compact(command.arguments[8])
                    let textureHandles = Set(textureAliases.keys)
                    let fullHandle = resolveTextureHandle(
                        rawHandle,
                        modelName: modelName,
                        model: model,
                        textures: textureHandles
                    ) ?? rawHandle
                    if let alias = textureAliases[fullHandle] {
                        value.w1 = (value.w1 & 0xffff_f000) | alias
                    }
                }
                commands.append(value)
            }
            var copied = GEGBISourceListV6()
            copied.handle = list.handle
            copied.first_command = UInt32(first)
            copied.command_count = UInt32(commands.count - first)
            copied.flags = 0
            lists.append(copied)
        }
        return (commands, lists)
    }

    private static func makeVertexResources(
        model: GoldenEyeSourceModelV6,
        modelName: String,
        scene: GESourceSceneV6,
        preferListMetadataForDynamicModel: Bool = false
    ) throws -> [GEGBISourceVertexResourceV6] {
        // The final GESM compiler keeps a typed vertex-group handle where the
        // source listing exposes one.  Address-marked loads are resolved
        // inside that display list's exact typed group span; never infer a
        // span from one global stream cursor.
        struct Run { let first: Int; let count: Int; let groupHandle: UInt32 }
        var runs: [Run] = []
        var runStart = 0
        while runStart < model.vertices.count {
            let groupHandle = model.vertices[runStart].groupHandle
            var end = runStart + 1
            while end < model.vertices.count, model.vertices[end].groupHandle == groupHandle { end += 1 }
            runs.append(Run(first: runStart, count: end - runStart, groupHandle: groupHandle))
            runStart = end
        }
        // A source model may legally reuse a typed group handle in separate
        // vertex runs (notably dynamic character attachments).  The old
        // `Dictionary(uniqueKeysWithValues:)` construction traps on that
        // input and takes down the 120 Hz owner thread.  Keep the lookup
        // deterministic, but turn the malformed/ambiguous source mapping
        // into the builder's typed fail-closed error instead.
        var groupRun: [UInt32: Run] = [:]
        groupRun.reserveCapacity(runs.count)
        for run in runs {
            guard groupRun[run.groupHandle] == nil else {
                throw GoldenEyeGBISceneBuilderV6Error.duplicateHandle(
                    "vertex group run",
                    run.groupHandle
                )
            }
            groupRun[run.groupHandle] = run
        }
        func resolveGroupHandle(_ raw: UInt32) throws -> UInt32? {
            guard raw != 0, raw != GoldenEyeSourceModelV6.nullHandle else { return nil }
            if groupRun[raw] != nil { return raw }
            let matches = groupRun.keys.filter { ($0 & 0x0000_0fff) == raw }
            if matches.count == 1 { return matches[0] }
            if matches.count > 1 {
                throw GoldenEyeGBISceneBuilderV6Error.duplicateHandle(
                    "vertex group alias", raw
                )
            }

            // Dynamic character packets may retain the source listing's
            // Vertex_0x value in node metadata while the GESM vertex table
            // stores the prepared FNV handle. Resolve that source row only
            // when it identifies one exact prepared run; never bind a
            // guessed/default vertex array.
            let rowCandidates = [
                "Vertex_0x\(String(raw, radix: 16))",
                "Vertex_0x\(raw)",
            ]
            let rowMatches = rowCandidates.flatMap { row in
                groupRun.keys.filter {
                    fnv32("\(modelName):vertex_group:\(row)") == $0
                }
            }
            let uniqueRows = Array(Set(rowMatches))
            if uniqueRows.count == 1 { return uniqueRows[0] }
            if uniqueRows.count > 1 {
                throw GoldenEyeGBISceneBuilderV6Error.duplicateHandle(
                    "vertex group source row alias", raw
                )
            }
            return nil
        }
        var listMetadata: [UInt32: (groupHandle: UInt32, vertexCount: Int)] = [:]
        for node in model.nodes {
            guard node.scalarStart < UInt32(model.scalars.count) else { continue }
            let metadata = model.scalars[Int(node.scalarStart)].metadata
            guard metadata.count > 4,
                  metadata[4] != 0,
                  metadata[4] != GoldenEyeSourceModelV6.nullHandle else { continue }
            let listIDs = [node.primaryDisplayListID, node.secondaryDisplayListID]
                .filter { $0 != GoldenEyeSourceModelV6.nullHandle }
            guard !listIDs.isEmpty else { continue }
            guard let groupHandle = try resolveGroupHandle(metadata[4]),
                  let group = groupRun[groupHandle] else {
                throw GoldenEyeGBISceneBuilderV6Error.missingVertexGroup(metadata[4])
            }
            for listID in listIDs {
                // Some generated display-list records retain the explicit
                // typed group handle while leaving the count field zero; the
                // validated GESM vertex run is the authoritative count in
                // that case.
                let value = (groupHandle: groupHandle, vertexCount: metadata[2] > 0 ? Int(metadata[2]) : group.count)
                if let prior = listMetadata[listID], prior.groupHandle != value.groupHandle || prior.vertexCount != value.vertexCount {
                    throw GoldenEyeGBISceneBuilderV6Error.duplicateHandle("display-list vertex metadata", listID)
                }
                listMetadata[listID] = value
            }
        }
        // Synthetic producer setup and source display-list commands share the
        // same copied scene container.  A malformed/incorrectly tagged setup
        // must never reach `Dictionary(uniqueKeysWithValues:)`: Swift traps
        // on a duplicate key and would take down the owner thread.  Keep the
        // source lookup deterministic and turn any collision into the
        // builder's typed fail-closed error instead.
        var selectedCommands: [String: GESourceCompiledCommandV6] = [:]
        selectedCommands.reserveCapacity(scene.commands.count)
        for command in scene.commands {
            let key = "\(command.displayListID):\(command.ordinal)"
            guard selectedCommands[key] == nil else {
                throw GoldenEyeGBISceneBuilderV6Error.duplicateHandle(
                    "source command ordinal", command.displayListID
                )
            }
            selectedCommands[key] = command
        }
        let addressRanges = try vertexAddressRanges(
            modelName: modelName,
            model: model,
            scene: scene
        )
        var ranges: [UInt32: (first: UInt32, count: UInt32)] = [:]
        // A source model may attach one vertex group to both a primary and a
        // secondary display list (the PP7 body uses a 46+4 split).  Consume
        // that guarded run across list boundaries in source display-list
        // order instead of requiring each list to repeat the full group.
        var consumedByGroup: [UInt32: Int] = [:]
        for list in model.displayLists {
            let start = Int(list.commandStart)
            let end = start + Int(list.commandCount)
            let loads = model.commands.indices.filter {
                $0 >= start && $0 < end && model.commands[$0].semantic.hasPrefix("gsSPVertex")
            }
            guard !loads.isEmpty else { continue }
            guard let metadata = listMetadata[list.id],
                  let explicitRun = groupRun[metadata.groupHandle],
                  (explicitRun.count == metadata.vertexCount || preferListMetadataForDynamicModel) else {
                throw GoldenEyeGBISceneBuilderV6Error.missingVertexGroup(list.id)
            }
            let requestedTotal = loads.reduce(0) { partial, index in
                partial + Int(vertexLoadCount(model.commands[index].semantic, word0: GESourceModelCompilerV6.encodedWords(model: model, commandIndex: index)?.word0 ?? 0))
            }
            let typedGroup = loads.compactMap { index -> UInt32? in
                let source = model.commands[index]
                guard let copied = selectedCommands["\(source.displayListID):\(source.ordinal)"],
                      let token = copied.arguments.first,
                      case .handle(let kind, let value) = token,
                      kind == .vertexGroup else {
                    return vertexGroupHandle(from: source.semantic)
                }
                return value
            }.first
            let run = explicitRun
            var groupOffset = consumedByGroup[run.groupHandle] ?? 0
            // A typed vertex-group command can be reused by another source
            // display list as a fresh cache window. If the accumulated
            // primary/secondary split cannot contain this list, restart that
            // window at the authored group base; raw-address loads retain
            // their exact source offset and never use this fallback.
            if requestedTotal > 0,
               groupOffset <= run.count,
               requestedTotal > run.count - groupOffset,
               typedGroup != nil {
                groupOffset = 0
            }
            guard requestedTotal > 0,
                  groupOffset <= run.count,
                  requestedTotal <= run.count - groupOffset else {
                throw GoldenEyeGBISceneBuilderV6Error.sceneValidation(
                    "vertex load total model=\(modelName) list=\(list.id) total=\(requestedTotal) run=\(run.first)..<\(run.first + run.count) offset=\(groupOffset)"
                )
            }
            if let typedGroup, typedGroup != run.groupHandle,
               !preferListMetadataForDynamicModel {
                throw GoldenEyeGBISceneBuilderV6Error.missingVertexGroup(typedGroup)
            }
            var offset = 0
            var maxConsumed = groupOffset
            for index in loads {
                guard let words = GESourceModelCompilerV6.encodedWords(model: model, commandIndex: index) else {
                    throw GoldenEyeGBISceneBuilderV6Error.missingVertexGroup(model.commands[index].macroHandle)
                }
                let requested = Int(vertexLoadCount(model.commands[index].semantic, word0: words.word0))
                guard requested > 0 else {
                    throw GoldenEyeGBISceneBuilderV6Error.sceneValidation(
                        "vertex load count model=\(modelName) list=\(model.commands[index].displayListID) ordinal=\(model.commands[index].ordinal) count=\(requested)"
                    )
                }
                if let copied = selectedCommands["\(model.commands[index].displayListID):\(model.commands[index].ordinal)"],
                   let token = copied.arguments.first,
                   case .handle(let kind, let value) = token,
                   kind == .vertexGroup {
                    guard value == run.groupHandle || preferListMetadataForDynamicModel else {
                        throw GoldenEyeGBISceneBuilderV6Error.missingVertexGroup(value)
                    }
                } else if let value = vertexGroupHandle(from: model.commands[index].semantic) {
                    guard value == run.groupHandle || preferListMetadataForDynamicModel else {
                        throw GoldenEyeGBISceneBuilderV6Error.missingVertexGroup(value)
                    }
                }
                let handle = vertexLoadHandle(
                    displayListID: model.commands[index].displayListID,
                    ordinal: model.commands[index].ordinal
                )
                let exactAddressHandle = selectedCommands["\(model.commands[index].displayListID):\(model.commands[index].ordinal)"]
                    .flatMap(vertexAddressHandle)
                let rangeFirst: Int
                if typedGroup == nil,
                   let exactAddressHandle, let exact = addressRanges[exactAddressHandle],
                   exact.groupHandle == run.groupHandle || exact.groupHandle == 0 {
                    rangeFirst = exact.groupHandle == 0
                        ? run.first + exact.first
                        : exact.first
                    offset = max(
                        offset,
                        rangeFirst + requested - run.first - groupOffset
                    )
                } else {
                    rangeFirst = run.first + groupOffset + offset
                    offset += requested
                }
                guard rangeFirst >= run.first,
                      rangeFirst + requested <= run.first + run.count else {
                    throw GoldenEyeGBISceneBuilderV6Error.sceneValidation(
                        "vertex load range model=\(modelName) list=\(model.commands[index].displayListID) ordinal=\(model.commands[index].ordinal) first=\(rangeFirst) count=\(requested) run=\(run.first)..<\(run.first + run.count)"
                    )
                }
                maxConsumed = max(maxConsumed, rangeFirst + requested - run.first)
                let range = (first: UInt32(rangeFirst), count: UInt32(requested))
                if let existing = ranges[handle], existing.first != range.first || existing.count != range.count {
                    throw GoldenEyeGBISceneBuilderV6Error.duplicateHandle("vertex load", handle)
                }
                ranges[handle] = range
            }
            consumedByGroup[run.groupHandle] = max(
                consumedByGroup[run.groupHandle] ?? 0,
                maxConsumed
            )
        }
        for command in scene.commands where command.macro == "gsSPVertex" {
            let loadHandle = vertexLoadHandle(
                displayListID: command.displayListID,
                ordinal: command.ordinal
            )
            guard ranges[loadHandle] != nil else {
                throw GoldenEyeGBISceneBuilderV6Error.missingVertexGroup(loadHandle)
            }
        }
        var values: [GEGBISourceVertexResourceV6] = []
        values.reserveCapacity(ranges.count)
        for handle in ranges.keys.sorted() {
            guard let range = ranges[handle] else { continue }
            var value = GEGBISourceVertexResourceV6()
            value.handle = handle
            value.first_vertex = range.first
            value.vertex_count = range.count
            value.flags = 0
            values.append(value)
        }
        return values
    }

    private struct VertexResourceRun {
        let first: Int
        let count: Int
        let groupHandle: UInt32
    }

    private static func vertexAddressHandle(
        _ command: GESourceCompiledCommandV6
    ) -> UInt32? {
        guard command.macro == "gsSPVertex",
              let argument = command.arguments.first,
              case .handle(let kind, let value) = argument,
              kind == .address else {
            return nil
        }
        return value
    }

    /// Recover the source Vertex-array subrange from the guarded address
    /// handle.  Preparation intentionally converts raw segmented addresses to
    /// deterministic hashes, but the hash input is the bounded low-24-bit
    /// source offset.  Brute-force only the aligned source-object range and
    /// retain no address or pointer; this restores exact 0xb0/0x120-style
    /// cache windows without opening source files at runtime.
    private static func vertexAddressRanges(
        modelName: String,
        model: GoldenEyeSourceModelV6,
        scene: GESourceSceneV6
    ) throws -> [UInt32: (groupHandle: UInt32, first: Int, count: Int)] {
        let neededAddressHandles = Set(
            scene.commands.compactMap(vertexAddressHandle)
        )
        guard !neededAddressHandles.isEmpty else { return [:] }
        let cacheKey = modelName + ":" + model.header.packetHash
            .map { String(format: "%02x", $0) }.joined()
            + ":" + neededAddressHandles.sorted()
                .map { String($0, radix: 16) }.joined(separator: ",")
        vertexAddressRangeCache.lock.lock()
        if let cached = vertexAddressRangeCache.values[cacheKey] {
            vertexAddressRangeCache.lock.unlock()
            return cached
        }
        vertexAddressRangeCache.lock.unlock()
        var runs: [VertexResourceRun] = []
        var runStart = 0
        while runStart < model.vertices.count {
            let groupHandle = model.vertices[runStart].groupHandle
            var end = runStart + 1
            while end < model.vertices.count,
                  model.vertices[end].groupHandle == groupHandle {
                end += 1
            }
            runs.append(VertexResourceRun(
                first: runStart, count: end - runStart, groupHandle: groupHandle
            ))
            runStart = end
        }
        let groupHandles = Set(runs.map(\.groupHandle))
        var groupBaseByHandle: [UInt32: Int] = [:]
        var addressBaseByHandle: [UInt32: Int] = [:]
        let searchLimit = 1 << 20
        for candidate in stride(from: 0, to: searchLimit, by: 16) {
            if groupBaseByHandle.count < groupHandles.count {
                let groupHandle = fnv32(
                    "\(modelName):vertex_group:Vertex_0x\(String(candidate, radix: 16))"
                )
                if groupHandles.contains(groupHandle) {
                    groupBaseByHandle[groupHandle] = candidate
                }
            }
            if addressBaseByHandle.count < neededAddressHandles.count {
                let addressHandle = fnv32(
                    "\(modelName):address:0x\(String(candidate, radix: 16))"
                )
                if neededAddressHandles.contains(addressHandle) {
                    addressBaseByHandle[addressHandle] = candidate
                }
            }
            if groupBaseByHandle.count == groupHandles.count,
               addressBaseByHandle.count == neededAddressHandles.count {
                break
            }
        }
        var output: [UInt32: (groupHandle: UInt32, first: Int, count: Int)] = [:]
        for (addressHandle, address) in addressBaseByHandle {
            guard let run = runs.first(where: { run in
                guard let groupBase = groupBaseByHandle[run.groupHandle] else { return false }
                return address >= groupBase && address < groupBase + run.count * 16
            }) else {
                // DLPRIMARY/dorottex dynamic vertex buffers use the guarded
                // model run as a zero-based vtx allocator; their 0x04 address
                // has no static Vertex_0x... base to match.  Preserve that
                // source offset and bind it to the display-list run later.
                output[addressHandle] = (
                    groupHandle: 0,
                    first: address / 16,
                    count: model.vertices.count
                )
                continue
            }
            guard let groupBase = groupBaseByHandle[run.groupHandle] else {
                throw GoldenEyeGBISceneBuilderV6Error.missingVertexGroup(addressHandle)
            }
            output[addressHandle] = (
                groupHandle: run.groupHandle,
                first: run.first + (address - groupBase) / 16,
                count: run.count - (address - groupBase) / 16
            )
        }
        guard output.count == neededAddressHandles.count else {
            let missing = neededAddressHandles.subtracting(output.keys)
            throw GoldenEyeGBISceneBuilderV6Error.missingVertexGroup(
                missing.sorted().first ?? 0
            )
        }
        vertexAddressRangeCache.lock.lock()
        vertexAddressRangeCache.values[cacheKey] = output
        vertexAddressRangeCache.lock.unlock()
        return output
    }

    private static func fnv32(_ value: String) -> UInt32 {
        var result: UInt32 = 2_166_136_261
        for byte in value.utf8 {
            result = (result ^ UInt32(byte)) &* 16_777_619
        }
        return result == 0 ? 1 : result
    }

    private static func makeVertexResourcePages(
        resources: [GEGBISourceVertexResourceV6],
        baseCount: Int
    ) throws -> [GEGBISourceVertexResourcePageV6] {
        guard baseCount >= 0, baseCount <= resources.count,
              baseCount <= Int(GE_SOURCE_GBI_V6_MAX_VERTEX_RESOURCES) else {
            throw GoldenEyeGBISceneBuilderV6Error.packetCapacity("vertex resource base page")
        }
        guard resources.count > baseCount else { return [] }
        let output = UnsafeMutablePointer<GEGBISourceVertexResourcePageV6>.allocate(
            capacity: Int(GE_SOURCE_GBI_V6_MAX_VERTEX_RESOURCE_PAGES)
        )
        defer { output.deallocate() }
        var pageCount: UInt32 = 0
        let status = resources.withUnsafeBufferPointer { buffer in
            ge_source_gbi_v6_build_vertex_resource_pages(
                buffer.baseAddress,
                UInt32(resources.count),
                output,
                UInt32(GE_SOURCE_GBI_V6_MAX_VERTEX_RESOURCE_PAGES),
                &pageCount
            )
        }
        guard status == GE_STATUS_OK else {
            throw GoldenEyeGBISceneBuilderV6Error.packetCapacity("vertex resource pages status \(status)")
        }
        var pages: [GEGBISourceVertexResourcePageV6] = []
        pages.reserveCapacity(Int(pageCount))
        for index in 0..<Int(pageCount) {
            var page = output[index]
            guard ge_source_gbi_v6_validate_vertex_resource_page(&page) == GE_STATUS_OK else {
                throw GoldenEyeGBISceneBuilderV6Error.packetCapacity("vertex resource page validation")
            }
            pages.append(page)
        }
        return pages
    }

    private static func vertexResourceManifestHash(
        baseResources: [GEGBISourceVertexResourceV6],
        pages: [GEGBISourceVertexResourcePageV6]
    ) -> UInt64 {
        let pagePointer = UnsafeMutablePointer<GEGBISourceVertexResourcePageV6>.allocate(capacity: max(1, pages.count))
        defer { pagePointer.deallocate() }
        if !pages.isEmpty {
            pages.withUnsafeBufferPointer { buffer in
                pagePointer.initialize(from: buffer.baseAddress!, count: pages.count)
            }
        }
        return baseResources.withUnsafeBufferPointer { buffer in
            ge_source_gbi_v6_hash_vertex_resource_manifest(
                buffer.baseAddress,
                UInt32(baseResources.count),
                pages.isEmpty ? nil : pagePointer,
                UInt32(pages.count)
            )
        }
    }

    private static func vertexLoadCount(_ semantic: String, word0: UInt32) -> UInt32 {
        let encoded = (word0 >> 16) & 0xff
        if encoded == 0, let open = semantic.firstIndex(of: "("), let close = semantic.lastIndex(of: ")") {
            let values = semantic[open..<close].split(separator: ",")
            if values.count >= 2, let count = UInt32(String(values[values.count - 2]).trimmingCharacters(in: .whitespaces)) {
                return count
            }
        }
        return (encoded >> 4) + 1
    }

    private static func vertexGroupHandle(from semantic: String) -> UInt32? {
        guard let marker = semantic.range(of: "handle(v,0x") else { return nil }
        let start = marker.upperBound
        guard let end = semantic[start...].firstIndex(of: ")") else { return nil }
        return UInt32(semantic[start..<end], radix: 16)
    }

    private struct ImageSpec {
        let handle: UInt32
        let texture: GoldenEyeSourceModelV6.Texture
        let format: UInt32
        let size: UInt32
        let width: UInt32
    }

    private static func textureAliases(
        scene: GESourceSceneV6,
        modelName: String,
        model: GoldenEyeSourceModelV6
    ) throws -> [UInt32: UInt32] {
        let textures = Set(model.textures.map(\.resourceHandle))
        var used: [UInt32] = []
        var rawToResolved: [UInt32: UInt32] = [:]
        for command in scene.commands {
            guard command.macro == "gsSPUseTexture", command.arguments.count >= 9 else { continue }
            let raw = compact(command.arguments[8])
            guard let resolved = resolveTextureHandle(
                raw,
                modelName: modelName,
                model: model,
                textures: textures
            ) else {
                throw GoldenEyeGBISceneBuilderV6Error.missingTexture(raw)
            }
            used.append(resolved)
            rawToResolved[raw] = resolved
        }
        var output: [UInt32: UInt32] = [:]
        for (index, handle) in Set(used).sorted().enumerated() {
            guard index < 0x0fff else { throw GoldenEyeGBISceneBuilderV6Error.packetCapacity("texture aliases") }
            output[handle] = UInt32(index + 1)
        }
        for (raw, resolved) in rawToResolved {
            guard let alias = output[resolved] else {
                throw GoldenEyeGBISceneBuilderV6Error.missingTexture(resolved)
            }
            if let existing = output[raw], existing != alias {
                throw GoldenEyeGBISceneBuilderV6Error.duplicateHandle("texture alias", raw)
            }
            output[raw] = alias
        }
        // A source G_SETTEX command without a typed full-handle argument is
        // not a consumable image record; preserve the exact failure boundary.
        for command in scene.commands where command.macro == "gsSPUseTexture" {
            guard command.arguments.count >= 9,
                  resolveTextureHandle(
                      compact(command.arguments[8]),
                      modelName: modelName,
                      model: model,
                      textures: textures
                  ) != nil else {
                throw GoldenEyeGBISceneBuilderV6Error.missingTexture(command.word1 & 0xfff)
            }
        }
        return output
    }

    private static func resolveTextureHandle(
        _ raw: UInt32,
        modelName: String,
        model: GoldenEyeSourceModelV6,
        textures: Set<UInt32>
    ) -> UInt32? {
        if textures.contains(raw) { return raw }
        let matches = textures.filter { ($0 & 0x0000_0fff) == raw }
        if matches.count == 1 { return Array(matches)[0] }
        let rowMatches = model.textures.filter {
            fnv32("\(modelName):texture_row:\(String(raw))") == $0.sourceRowHandle ||
            fnv32("\(modelName):texture_row:IMAGE_\(raw)") == $0.sourceRowHandle
        }
        return rowMatches.count == 1 ? rowMatches[0].resourceHandle : nil
    }

    private static func makeImages(
        model: GoldenEyeSourceModelV6,
        modelName: String,
        scene: GESourceSceneV6,
        textureAliases: [UInt32: UInt32],
        additionalTextureHandles: [UInt32] = []
    ) throws -> [GEGBISourceImageResourceV6] {
        let textures = Dictionary(uniqueKeysWithValues: model.textures.map { ($0.resourceHandle, $0) })
        var byHandle: [UInt32: ImageSpec] = [:]
        for command in scene.commands {
            let opcode = command.word0 >> 24
            if opcode == UInt32(GE_SOURCE_GBI_V6_OP_SETTIMG) {
                let handle = command.word1
                guard let texture = textures[handle] else {
                    throw GoldenEyeGBISceneBuilderV6Error.missingTexture(handle)
                }
                let spec = ImageSpec(
                    handle: handle,
                    texture: texture,
                    format: (command.word0 >> 21) & 7,
                    size: (command.word0 >> 19) & 3,
                    width: (command.word0 & 0xfff) + 1
                )
                try insertImage(spec, into: &byHandle)
            } else if opcode == UInt32(GE_SOURCE_GBI_V6_OP_SETTEX) {
                guard command.arguments.count >= 9 else {
                    throw GoldenEyeGBISceneBuilderV6Error.invalidSourceTexture(command.word1 & 0xfff)
                }
                let rawHandle = compact(command.arguments[8])
                let textureHandles = Set(textures.keys)
                let fullHandle = resolveTextureHandle(
                    rawHandle,
                    modelName: modelName,
                    model: model,
                    textures: textureHandles
                ) ?? rawHandle
                guard let handle = textureAliases[fullHandle] ?? textureAliases[rawHandle] else {
                    throw GoldenEyeGBISceneBuilderV6Error.missingTexture(rawHandle)
                }
                guard handle != 0 else { throw GoldenEyeGBISceneBuilderV6Error.invalidSourceTexture(handle) }
                guard let texture = textures[fullHandle] else {
                    throw GoldenEyeGBISceneBuilderV6Error.missingTexture(handle)
                }
                let inferred = try inferredWireFormat(texture)
                let spec = ImageSpec(
                    handle: handle,
                    texture: texture,
                    format: inferred.format,
                    size: inferred.size,
                    width: texture.width
                )
                try insertImage(spec, into: &byHandle)
            }
        }
        for handle in additionalTextureHandles {
            guard let texture = textures[handle] else {
                throw GoldenEyeGBISceneBuilderV6Error.missingTexture(handle)
            }
            let inferred = try inferredWireFormat(texture)
            try insertImage(
                ImageSpec(
                    handle: handle,
                    texture: texture,
                    format: inferred.format,
                    size: inferred.size,
                    width: texture.width
                ),
                into: &byHandle
            )
        }
        return byHandle.keys.sorted().compactMap { handle in
            guard let spec = byHandle[handle] else { return nil }
            var value = GEGBISourceImageResourceV6()
            value.handle = spec.handle
            value.byte_length = spec.texture.sourceSpan
            value.format = spec.format
            value.size = spec.size
            value.width = spec.width
            value.height = spec.texture.height
            value.flags = 0
            value.reserved = 0
            return value
        }
    }

    private static func insertImage(
        _ spec: ImageSpec,
        into images: inout [UInt32: ImageSpec]
    ) throws {
        guard spec.handle != 0, spec.texture.sourceSpan > 0 else {
            throw GoldenEyeGBISceneBuilderV6Error.invalidSourceTexture(spec.handle)
        }
        if let existing = images[spec.handle], existing.texture.resourceHandle != spec.texture.resourceHandle {
            throw GoldenEyeGBISceneBuilderV6Error.duplicateHandle("image alias", spec.handle)
        }
        images[spec.handle] = spec
        guard images.count <= Int(GE_SOURCE_GBI_V6_MAX_IMAGES) else {
            throw GoldenEyeGBISceneBuilderV6Error.packetCapacity("image resources")
        }
    }

    private static func inferredWireFormat(
        _ texture: GoldenEyeSourceModelV6.Texture
    ) throws -> (format: UInt32, size: UInt32) {
        // GESM preserves the source storage depth even for global IMAGE rows
        // whose SETTIMG command is outside the selected list.  This is a
        // source-format mapping, not a host pixel-format default.
        switch texture.depth {
        case 0: return (4, 0) // I4
        case 1: return (4, 1) // I8
        case 2: return (0, 2) // RGBA16
        case 3: return (0, 3) // RGBA32
        default: throw GoldenEyeGBISceneBuilderV6Error.unknownImageFormat(texture.resourceHandle)
        }
    }

    private static func makeDecodedPacketStaticData(
        model: GoldenEyeSourceModelV6,
        scene: GESourceSceneV6,
        packetPointer: UnsafeMutablePointer<GEGBISourcePacketV6>,
        decoderPointer: UnsafeMutablePointer<GEGBIResultV6>,
        textureAliases: [UInt32: UInt32],
        textureSetups: [GoldenEyeSourceTextureSetupV6],
        logicalWidth: UInt32,
        logicalHeight: UInt32,
        vertexLoadProvenance: [GEGBIVertexLoadProvenanceV6]
    ) throws -> DecodedPacketStaticData {
        let textureByHandle = Dictionary(uniqueKeysWithValues: model.textures.map {
            ($0.resourceHandle, $0)
        })
        let imageToTexture = try makeImageToTextureMap(
            model: model,
            packetPointer: packetPointer,
            textureAliases: textureAliases
        )
        let resources = try makeSceneResources(
            model: model,
            textureByHandle: textureByHandle,
            imageToTexture: imageToTexture
        )
        let sourceCommands = packetSourceCommandTable(scene)
        var sourceSequences: [String: UInt32] = [:]
        sourceSequences.reserveCapacity(scene.commands.count)
        var sourceSequence: UInt32 = 0
        for command in scene.commands where command.ordinal & 0x8000_0000 == 0 {
            let key = sourceCommandKey(command)
            sourceSequences[key] = sourceSequences[key] ?? sourceSequence
            sourceSequence &+= 1
        }

        // The C provenance records are source-ordered for the dynamic models.
        // Preserve original order for equal offsets so the last cache-slot
        // write has the same value as the previous per-draw reduction.
        let orderedProvenance = vertexLoadProvenance.enumerated().sorted {
            if $0.element.command_offset != $1.element.command_offset {
                return $0.element.command_offset < $1.element.command_offset
            }
            return $0.offset < $1.offset
        }.map(\.element)
        var provenanceIndex = 0
        var vertexLoadMatrixBySlot: [UInt32: UInt32] = [:]
        var loweredByState: [LoweredStateKey: LoweredState] = [:]
        let draws = readPointerArray(
            decoderPointer,
            fieldOffset: MemoryLayout<GEGBIResultV6>.offset(of: \.draws)!,
            count: Int(decoderPointer.pointee.draw_count),
            as: GEGBIDrawV6.self
        )
        let coordinateSourceCommandHash = sourceCommandWordHash(scene)
        var output: [DecodedDrawMetadata] = []
        output.reserveCapacity(draws.count)
        for draw in draws {
            while provenanceIndex < orderedProvenance.count,
                  orderedProvenance[provenanceIndex].command_offset <= draw.source_command_offset {
                let record = orderedProvenance[provenanceIndex]
                vertexLoadMatrixBySlot[record.cache_slot] = record.modelview_handle
                provenanceIndex += 1
            }
            let packetIndex = Int(draw.source_command_offset)
                / MemoryLayout<GEGBISourceCommandV6>.size
            let sourceCommand = packetIndex >= 0 && packetIndex < sourceCommands.count
                ? sourceCommands[packetIndex]
                : nil
            let state = readPointerElement(
                decoderPointer,
                fieldOffset: MemoryLayout<GEGBIResultV6>.offset(of: \.states)!,
                index: Int(draw.state_index),
                as: GEGBIStateV6.self
            )
            let textureTile = (state.texture_enabled_level_tile >> 8) & 7
            let resolvedTextureHandle = imageToTexture[state.texture_image_handle] ??
                state.texture_image_handle
            let commandTextureSetup = sourceCommand.flatMap { command in
                textureSetupForCommand(
                    command,
                    setups: textureSetups,
                    sourceSequence: sourceSequences[sourceCommandKey(command)],
                    textureHandle: resolvedTextureHandle
                )
            }
            let matchingCommandTextureSetup: GoldenEyeSourceTextureSetupV6?
            if model.header.modelHandle == rarewareModelHandle {
                matchingCommandTextureSetup = commandTextureSetup?.tile == textureTile
                    ? commandTextureSetup
                    : nil
            } else {
                matchingCommandTextureSetup = commandTextureSetup
            }
            let textureSetup = matchingCommandTextureSetup ?? (
                model.header.modelHandle == rarewareModelHandle
                    ? textureSetups.first(where: {
                        $0.modelName == "rarewarelogo" &&
                        $0.resourceHandle == resolvedTextureHandle &&
                        $0.tile == textureTile
                    })
                    : nil
            )
            let loweredStateKey = LoweredStateKey(
                stateIndex: draw.state_index,
                setupHash: textureSetup?.setupHash ?? 0,
                setupSequence: textureSetup?.sequence ?? 0,
                setupDisplayListID: textureSetup?.displayListID ?? 0,
                setupOrdinal: textureSetup?.ordinal ?? 0
            )
            let loweredState: LoweredState
            if let cached = loweredByState[loweredStateKey] {
                loweredState = cached
            } else {
                let lowered = try lowerState(
                    state,
                    stateIndex: draw.state_index,
                    imageToTexture: imageToTexture,
                    textureByHandle: textureByHandle,
                    logicalWidth: logicalWidth,
                    logicalHeight: logicalHeight,
                    matrixKinds: [:],
                    textureSetup: textureSetup
                )
                loweredByState[loweredStateKey] = lowered
                loweredState = lowered
            }
            var coordinateCommands: DecodedTextureCoordinateCommands?
            if loweredState.textureHandle != 0 {
                guard let texture = textureByHandle[loweredState.textureHandle] else {
                    throw GoldenEyeGBISceneBuilderV6Error.missingTexture(
                        loweredState.textureHandle
                    )
                }
                coordinateCommands = try makeTextureCoordinateCommands(
                    packetPointer: packetPointer,
                    draw: draw,
                    state: state,
                    texture: texture,
                    textureHandle: loweredState.textureHandle,
                    textureSetup: textureSetup
                )
            } else {
                coordinateCommands = nil
            }
            let textureCoordinates: [LoweredTextureCoordinate]?
            if loweredState.textureHandle != 0 {
                guard let texture = textureByHandle[loweredState.textureHandle],
                      let coordinateCommands else {
                    throw GoldenEyeGBISceneBuilderV6Error.missingTexture(
                        loweredState.textureHandle
                    )
                }
                let sourceIndices = [
                    draw.source_vertex_a,
                    draw.source_vertex_b,
                    draw.source_vertex_c,
                ]
                guard sourceIndices.allSatisfy({ $0 < UInt32(model.vertices.count) }) else {
                    throw GoldenEyeGBISceneBuilderV6Error.invalidSourceVertex(
                        sourceIndices.max() ?? 0
                    )
                }
                textureCoordinates = try sourceIndices.map { sourceIndex in
                    let coordinate = try lowerTextureCoordinate(
                        packetPointer: packetPointer,
                        draw: draw,
                        state: state,
                        sourceVertex: model.vertices[Int(sourceIndex)],
                        texture: texture,
                        textureHandle: loweredState.textureHandle,
                        textureSetup: textureSetup,
                        sourceStateHash: state.state_hash,
                        sourceCommandHash: coordinateSourceCommandHash,
                        coordinateCommands: coordinateCommands
                    )
                    return LoweredTextureCoordinate(
                        localS: coordinate.result.local_s_q16,
                        localT: coordinate.result.local_t_q16,
                        levelWidth: coordinate.result.level_width,
                        levelHeight: coordinate.result.level_height
                    )
                }
            } else {
                textureCoordinates = nil
            }
            output.append(DecodedDrawMetadata(
                draw: draw,
                state: state,
                sourceCommand: sourceCommand,
                textureSetup: textureSetup,
                loweredState: loweredState,
                coordinateCommands: coordinateCommands,
                textureCoordinates: textureCoordinates,
                vertexLoadMatrixBySlot: vertexLoadMatrixBySlot
            ))
        }
        return DecodedPacketStaticData(
            textureByHandle: textureByHandle,
            resources: resources,
            draws: output
        )
    }

    private static func makeImageToTextureMap(
        model: GoldenEyeSourceModelV6,
        packetPointer: UnsafeMutablePointer<GEGBISourcePacketV6>,
        textureAliases: [UInt32: UInt32]
    ) throws -> [UInt32: UInt32] {
        var imageToTexture: [UInt32: UInt32] = [:]
        for image in readPointerArray(
            packetPointer,
            fieldOffset: MemoryLayout<GEGBISourcePacketV6>.offset(of: \.images)!,
            count: Int(packetPointer.pointee.image_count),
            as: GEGBISourceImageResourceV6.self
        ) {
            let exact = model.textures.filter { $0.resourceHandle == image.handle }
            let aliasHandles = textureAliases.filter { $0.value == image.handle }.map(\.key)
            let aliases = model.textures.filter { aliasHandles.contains($0.resourceHandle) }
            let matches = exact.isEmpty ? aliases : exact
            guard matches.count == 1, let texture = matches.first else {
                throw GoldenEyeGBISceneBuilderV6Error.missingTexture(image.handle)
            }
            imageToTexture[image.handle] = texture.resourceHandle
        }
        return imageToTexture
    }

    private static func packetSourceCommandTable(
        _ scene: GESourceSceneV6
    ) -> [GESourceCompiledCommandV6?] {
        var output: [GESourceCompiledCommandV6?] = Array(
            repeating: nil,
            count: scene.displayLists.count + 1
        )
        output.reserveCapacity(scene.displayLists.count + scene.commands.count + 1)
        for list in scene.displayLists {
            output.append(contentsOf: scene.commands
                .filter { $0.displayListID == list.id }
                .map(Optional.some))
        }
        return output
    }

    private static func sourceCommandKey(
        _ command: GESourceCompiledCommandV6
    ) -> String {
        "\(command.displayListID):\(command.ordinal):\(command.macro)"
    }

    private static func convert(
        model: GoldenEyeSourceModelV6,
        modelName: String,
        scene: GESourceSceneV6,
        packetPointer: UnsafeMutablePointer<GEGBISourcePacketV6>,
        decoderPointer: UnsafeMutablePointer<GEGBIResultV6>,
        sourceCommandWordHash: UInt64,
        vertexResourceTotal: Int,
        vertexResourcePageCount: Int,
        vertexResourceManifestHash: UInt64,
        matrices: [GoldenEyeGBIMatrixResourceV6],
        viewports: [GoldenEyeGBIViewportResourceV6],
        matrixRoles: [GoldenEyeSourceMatrixRoleSidecarV6],
        frame: GoldenEyeGBISceneFrameContextV6,
        animationPoses: [GESourceAnimationPoseV6],
        vertexLoadProvenance: [GEGBIVertexLoadProvenanceV6],
        transformContext: GoldenEyeSourceNodeTransformContextV6?,
        renderSetupContext: GoldenEyeSourceDynamicRenderSetupContextV6?,
        textureSetups: [GoldenEyeSourceTextureSetupV6],
        staticData: DecodedPacketStaticData
    ) throws -> GoldenEyeGBISceneBuildResultV6 {
        let matrixKinds = try matrixRolesByHandle(
            scene: scene,
            supplied: matrixRoles,
            matrices: matrices
        )
        var transformBundle = try makeTransforms(
            matrices: matrices,
            viewports: viewports,
            matrixKinds: matrixKinds,
            viewportHandle: decoderPointer.pointee.state.viewport_handle
        )
        // Dynamic character packets carry the source skeleton pose separately
        // from the static GBI model-view resource. Lower those copied pose
        // records into actual value-only bone matrices before any draw is
        // emitted. Static title/menu models pass an empty pose array and keep
        // their historical transform/hash output byte-for-byte unchanged.
        let nodeTransformLowering: GoldenEyeSourceNodeTransformLoweringV6
        do {
            nodeTransformLowering = try GoldenEyeSourceNodeTransformLowererV6.lower(
                model: model,
                scene: scene,
                poses: animationPoses,
                modelName: modelName,
                transformContext: transformContext
            )
        } catch {
            throw GoldenEyeGBISceneBuilderV6Error.sceneValidation(
                "source node transform lowering: \(error)"
            )
        }
        for var boneTransform in nodeTransformLowering.transforms {
            try validateTransform(&boneTransform)
            transformBundle.append(boneTransform)
        }
        let boneTransformByHandle = nodeTransformLowering.transformByHandle
        // Any visible source pose packet is dynamic character work. It must
        // resolve every draw through exact source matrix/node provenance;
        // display-list order is never an animation authority.
        let requiresExactNodeTransforms = !animationPoses.isEmpty
        var clipTransformByHandle = Dictionary(uniqueKeysWithValues: transformBundle.map {
            ($0.handle, $0)
        })
        let resources = staticData.resources

        var vertices: [GESourceVertexV6] = []
        var indices: [GESourceIndexV6] = []
        var renderStates: [GESourceRenderStateV6] = []
        var drawCommands: [GESourceDrawCommandV6] = []
        var diagnostics: [GESourceDiagnosticV6] = []
        var unsupportedReasons: [String] = []
        var unsupportedVisible: UInt32 = 0
        var stateRecordByIndex: [UInt32: Int] = [:]
        var geometryModesByState: [UInt32: UInt32] = [:]
        var modelViewQ16ByState: [UInt32: [Int32]] = [:]
        var unsupportedStateIndices = Set<UInt32>()
        var groups: [DrawGroup] = []
        let matrixByHandle = Dictionary(uniqueKeysWithValues: matrices.map { ($0.handle, $0) })
        let viewportByHandle = Dictionary(uniqueKeysWithValues: viewports.map { ($0.handle, $0) })
        var compositeByKey: [ClipKey: (handle: UInt32, transformIndex: Int)] = [:]
        var nodeClipCompositeByKey: [NodeClipKey: UInt32] = [:]
        var combinedClipHandles: [UInt32] = []
        var consumedProjectionDrawCount: UInt32 = 0
        var consumedProjectionHandles = Set<UInt32>()
        var consumedViewportHandles = Set<UInt32>()
        var exactNodeTransformDrawCount: UInt32 = 0
        var fallbackNodeTransformDrawCount: UInt32 = 0
        var relativeMatrixByKey: [RelativeMatrixKey: [Int32]] = [:]

        let draws = staticData.draws
        // A source triangle can mix vertices captured by different
        // gsSPVertex loads.  The C decoder records that immutable provenance
        // at load time; do not reconstruct it from the post-setup Swift scene
        // order, because dynamic producers prepend source render setup words.
        if requiresExactNodeTransforms {
            let requiredFlags = UInt32(
                GE_SOURCE_GBI_V6_VERTEX_LOAD_PROVENANCE_FLAG_SOURCE_ORDERED
            ) | UInt32(GE_SOURCE_GBI_V6_VERTEX_LOAD_PROVENANCE_FLAG_MATRIX_LOAD_ONLY)
            guard vertexLoadProvenance.allSatisfy({ $0.flags & requiredFlags == requiredFlags }) else {
                throw GoldenEyeGBISceneBuilderV6Error.sceneValidation(
                    "dynamic vertex-load provenance uses unsupported modelview stack semantics"
                )
            }
        }
        let transformValuesByHandle = Dictionary(uniqueKeysWithValues: transformBundle.map {
            ($0.handle, Self.matrixValues($0.matrix_q16))
        })
        let matrixValuesByHandle = Dictionary(uniqueKeysWithValues: matrices.map { ($0.handle, $0.values) })
        for drawMetadata in draws {
            let draw = drawMetadata.draw
            let sourceCommand = drawMetadata.sourceCommand
            let state = drawMetadata.state
            let copiedStateHandle = stateHandle(draw.state_index)
            geometryModesByState[copiedStateHandle] = state.geometry_mode
            if let modelView = matrixValuesByHandle[state.modelview_handle] {
                modelViewQ16ByState[copiedStateHandle] = modelView
            }
            do {
                let clip = try makeClipTransform(
                    state: state,
                    matrixKinds: matrixKinds,
                    matrixByHandle: matrixByHandle,
                    viewportByHandle: viewportByHandle,
                    transformBundle: &transformBundle,
                    compositeByKey: &compositeByKey,
                    combinedClipHandles: &combinedClipHandles
                )
                if clipTransformByHandle[clip.handle] == nil,
                   let clipTransform = transformBundle.first(where: { $0.handle == clip.handle }) {
                    clipTransformByHandle[clip.handle] = clipTransform
                }
                consumedProjectionHandles.insert(clip.projectionHandle)
                consumedViewportHandles.insert(clip.viewportHandle)
                let lowered = drawMetadata.loweredState
                if let setupContext = renderSetupContext {
                    let rawMode = lowered.state.raw_othermode_l
                    guard rawMode == setupContext.primaryRawMode
                            || rawMode == setupContext.secondaryRawMode else {
                        throw GoldenEyeGBISceneBuilderV6Error.invalidState(
                            draw.state_index,
                            "dynamic render setup rawL=0x\(String(rawMode, radix: 16)) expected 0x\(String(setupContext.primaryRawMode, radix: 16))/0x\(String(setupContext.secondaryRawMode, radix: 16))"
                        )
                    }
                    let depthDisabled = lowered.state.depth_mode
                        == UInt32(GE_SOURCE_DEPTH_V6_DISABLED)
                    guard depthDisabled != setupContext.depthEnabled else {
                        throw GoldenEyeGBISceneBuilderV6Error.invalidState(
                            draw.state_index,
                            "dynamic render setup depth state mismatch rawL=0x\(String(rawMode, radix: 16)) depth=\(lowered.state.depth_mode)"
                        )
                    }
                }
                if let gap = lowered.gap, unsupportedStateIndices.insert(draw.state_index).inserted {
                    unsupportedVisible &+= 1
                    unsupportedReasons.append("state \(draw.state_index): \(gap)")
                    diagnostics.append(makeDiagnostic(error: GoldenEyeGBISceneBuilderV6Error.unsupportedState(draw.state_index, gap), sourceID: model.header.modelHandle, commandID: draw.source_command_offset))
                }
                let stateIndex: Int
                if let existing = stateRecordByIndex[draw.state_index] {
                    stateIndex = existing
                } else {
                    stateIndex = renderStates.count
                    stateRecordByIndex[draw.state_index] = stateIndex
                    var stateForFrame = lowered.state
                    if model.header.modelHandle == rarewareModelHandle {
                        stateForFrame.primitive_rgba = rarewarePrimitiveColor(
                            sourceTimer: frame.sourceTimer ?? 0,
                            pairPhase: frame.pairPhase,
                            textureHandle: lowered.textureHandle,
                            model: model
                        )
                    }
                    renderStates.append(stateForFrame)
                }
                let sourceIndices = [draw.source_vertex_a, draw.source_vertex_b, draw.source_vertex_c]
                guard sourceIndices.allSatisfy({ $0 < UInt32(model.vertices.count) }) else {
                    throw GoldenEyeGBISceneBuilderV6Error.invalidSourceVertex(sourceIndices.max() ?? 0)
                }
                let nodeAssociation = sourceCommand.flatMap {
                    nodeTransformLowering.association(
                        for: $0,
                        modelViewHandle: state.modelview_handle
                    )
                }
                let stateBoneTransformHandle =
                    nodeTransformLowering.matrixTransformHandles[state.modelview_handle]
                    ?? nodeAssociation?.transformHandle
                if requiresExactNodeTransforms {
                    guard sourceCommand != nil, let nodeAssociation,
                          stateBoneTransformHandle != nil else {
                        throw GoldenEyeGBISceneBuilderV6Error.missingSourceNodeTransform(
                            draw.source_command_offset,
                            modelName
                        )
                    }
                    guard nodeAssociation.provenance
                            == .exactGroupRecordMatrixSelector
                        || nodeAssociation.provenance
                            == .exactSourceMatrixNode else {
                        throw GoldenEyeGBISceneBuilderV6Error.fallbackSourceNodeTransform(
                            draw.source_command_offset,
                            nodeAssociation.displayListID,
                            state.modelview_handle
                        )
                    }
                }
                if let nodeAssociation, !animationPoses.isEmpty {
                    switch nodeAssociation.provenance {
                    case .exactGroupRecordMatrixSelector, .exactSourceMatrixNode:
                        exactNodeTransformDrawCount &+= 1
                    case .displayListFallback, .metadataOnly:
                        fallbackNodeTransformDrawCount &+= 1
                    }
                }
                let sourceSlots = [draw.vertex_slot_a, draw.vertex_slot_b, draw.vertex_slot_c]
                var emittedTransformHandle = clip.handle
                if let stateBoneTransformHandle,
                   let boneTransform = boneTransformByHandle[stateBoneTransformHandle],
                   let clipTransform = clipTransformByHandle[clip.handle] {
                    let key = NodeClipKey(
                        clipHandle: clip.handle,
                        boneHandle: stateBoneTransformHandle
                    )
                    if let existing = nodeClipCompositeByKey[key] {
                        emittedTransformHandle = existing
                    } else {
                        let handle = transformNodeClipPrefix | UInt32(nodeClipCompositeByKey.count + 1)
                        let composed: GESourceTransformV6
                        do {
                            composed = try GoldenEyeSourceNodeTransformLowererV6.composeClip(
                                clip: clipTransform,
                                bone: boneTransform,
                                handle: handle
                            )
                        } catch {
                            throw GoldenEyeGBISceneBuilderV6Error.sceneValidation(
                                "source node clip composition: \(error)"
                            )
                        }
                        transformBundle.append(composed)
                        clipTransformByHandle[handle] = composed
                        nodeClipCompositeByKey[key] = handle
                        emittedTransformHandle = handle
                    }
                }
                let key = DrawKey(
                    stateIndex: stateIndex,
                    textureHandle: lowered.textureHandle,
                    transformHandle: emittedTransformHandle
                )
                if groups.last?.key != key {
                    groups.append(DrawGroup(key: key, stateIndex: stateIndex, textureHandle: lowered.textureHandle, transformHandle: emittedTransformHandle, scissor: lowered.scissor, drawFlags: lowered.drawFlags, firstVertex: vertices.count, firstIndex: indices.count, sourceOffsets: []))
                }
                let groupIndex = groups.count - 1
                let baseVertex = vertices.count
                let drawBoneValues = stateBoneTransformHandle.flatMap {
                    transformValuesByHandle[$0]
                }
                for (vertexOffset, pair) in zip(sourceIndices, sourceSlots).enumerated() {
                    let sourceIndex = pair.0
                    let sourceSlot = pair.1
                    var value = makeSceneVertex(model.vertices[Int(sourceIndex)], handle: vertexHandle(vertices.count))
                    if requiresExactNodeTransforms {
                        guard let sourceMatrixHandle = drawMetadata.vertexLoadMatrixBySlot[sourceSlot],
                              let loadedTransformHandle = nodeTransformLowering.matrixTransformHandles[sourceMatrixHandle],
                              let loadedValues = transformValuesByHandle[loadedTransformHandle] else {
                            throw GoldenEyeGBISceneBuilderV6Error.sceneValidation(
                                "missing dynamic vertex-load matrix provenance draw=0x\(String(draw.source_command_offset, radix: 16)) slot=\(sourceSlot)"
                            )
                        }
                        guard let drawBoneValues,
                              let drawBoneHandle = stateBoneTransformHandle else {
                            throw GoldenEyeGBISceneBuilderV6Error.sceneValidation(
                                "missing dynamic draw matrix for vertex-load correction draw=0x\(String(draw.source_command_offset, radix: 16)) slot=\(sourceSlot)"
                            )
                        }
                        let correctionKey = RelativeMatrixKey(
                            drawBoneHandle: drawBoneHandle,
                            loadedBoneHandle: loadedTransformHandle
                        )
                        let correction: [Int32]
                        if let cachedCorrection = relativeMatrixByKey[correctionKey] {
                            correction = cachedCorrection
                        } else {
                            guard let computedCorrection = Self.relativeMatrix(
                                from: drawBoneValues,
                                to: loadedValues
                            ) else {
                                throw GoldenEyeGBISceneBuilderV6Error.sceneValidation(
                                    "missing dynamic draw matrix for vertex-load correction draw=0x\(String(draw.source_command_offset, radix: 16)) slot=\(sourceSlot)"
                                )
                            }
                            relativeMatrixByKey[correctionKey] = computedCorrection
                            correction = computedCorrection
                        }
                        Self.applyPositionCorrection(&value, matrix: correction)
                        guard Self.applyNormalCorrection(&value, matrix: correction) else {
                            throw GoldenEyeGBISceneBuilderV6Error.sceneValidation(
                                "dynamic vertex-load normal transform is non-finite draw=0x\(String(draw.source_command_offset, radix: 16)) slot=\(sourceSlot)"
                            )
                        }
                    }
                    if lowered.textureHandle != 0 {
                        guard let coordinate = drawMetadata.textureCoordinates?[vertexOffset] else {
                            throw GoldenEyeGBISceneBuilderV6Error.invalidState(
                                draw.state_index,
                                "missing cached texture coordinate texture=0x\(String(lowered.textureHandle, radix: 16)) draw=0x\(String(draw.source_command_offset, radix: 16)) vertex=\(sourceIndex)"
                            )
                        }
                        let samplerS = try unaddressedSamplerQ16(
                            coordinate.localS,
                            dimension: coordinate.levelWidth,
                            state: draw.state_index
                        )
                        let samplerT = try unaddressedSamplerQ16(
                            coordinate.localT,
                            dimension: coordinate.levelHeight,
                            state: draw.state_index
                        )
                        guard samplerS >= Int64(Int32.min),
                              samplerS <= Int64(Int32.max),
                              samplerT >= Int64(Int32.min),
                              samplerT <= Int64(Int32.max) else {
                            throw GoldenEyeGBISceneBuilderV6Error.invalidState(draw.state_index, "texture coordinate Q16 overflow")
                        }
                        // Keep unaddressed tile-local UVs. Address/mirror/
                        // clamp belongs to the Metal sampler per fragment;
                        // using C's addressed result collapses full-period
                        // corners to one edge before rasterization.
                        value.texcoord_q16.0 = Int32(samplerS)
                        value.texcoord_q16.1 = Int32(samplerT)
                    }
                    try validateVertex(&value)
                    vertices.append(value)
                }
                var index = makeSceneIndex(
                    handle: indexHandle(indices.count),
                    vertex0: UInt32(baseVertex),
                    vertex1: UInt32(baseVertex + 1),
                    vertex2: UInt32(baseVertex + 2),
                    sourceIndex: draw.source_command_offset
                )
                try validateIndex(&index)
                indices.append(index)
                groups[groupIndex].sourceOffsets.append(draw.source_command_offset)
                consumedProjectionDrawCount &+= 1
            } catch let error as GoldenEyeGBISceneBuilderV6Error {
                if requiresExactNodeTransforms {
                    throw error
                }
                unsupportedVisible &+= 1
                unsupportedReasons.append(error.description)
                diagnostics.append(makeDiagnostic(error: error, sourceID: model.header.modelHandle, commandID: draw.source_command_offset))
            }
        }

        for group in groups {
            guard group.sourceOffsets.count > 0 else { continue }
            let state = renderStates[group.stateIndex]
            let resourceHandle = group.textureHandle
            let firstVertex = UInt32(group.firstVertex)
            let vertexCount = UInt32(group.sourceOffsets.count * 3)
            let firstIndex = UInt32(group.firstIndex)
            let indexCount = UInt32(group.sourceOffsets.count)
            var draw = GESourceDrawCommandV6()
            setHeader(&draw.header, size: MemoryLayout<GESourceDrawCommandV6>.size)
            draw.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
            draw.command_kind = UInt32(GE_SOURCE_DRAW_V6_TRIANGLES)
            draw.flags = UInt32(GE_SOURCE_DRAW_V6_FLAG_SOURCE_ORDERED) | group.drawFlags
            draw.draw_handle = drawHandle(drawCommands.count)
            draw.transform_handle = group.transformHandle
            draw.resource_handle = resourceHandle
            draw.render_state_handle = state.state_handle
            draw.first_vertex = firstVertex
            draw.vertex_count = vertexCount
            draw.first_index = firstIndex
            draw.index_count = indexCount
            draw.instance_count = 1
            draw.sort_key = UInt32(drawCommands.count)
            draw.depth_q16 = 0
            draw.scissor_x = group.scissor.x
            draw.scissor_y = group.scissor.y
            draw.scissor_width = group.scissor.width
            draw.scissor_height = group.scissor.height
            draw.draw_hash = hashDraw(group: group, state: state)
            if draw.draw_hash == 0 { draw.draw_hash = 1 }
            try validateDraw(&draw)
            drawCommands.append(draw)
        }

        let sceneHash = hashRecords(model: model, eventHash: decoderPointer.pointee.event_hash, stateHash: decoderPointer.pointee.state_hash, transforms: transformBundle, vertices: vertices, indices: indices, states: renderStates, draws: drawCommands)
        let renderHash = hashDrawRecords(drawCommands)
        let textureSetupHash = hashTextureSetups(textureSetups)
        let stateHash = decoderPointer.pointee.state_hash == 0 ? 1 : decoderPointer.pointee.state_hash
        var frameHash = sceneHash ^ (renderHash &* 0x9e37_79b9_7f4a_7c15) ^ stateHash ^ textureSetupHash
        // The source scene records remain identical when only the paired
        // cadence phase changes, but the immutable frame identity must not:
        // odd native half-steps are distinct render observations between
        // equal even anchors.
        for value in [
            frame.nativeTick,
            frame.referenceTick,
            UInt64(frame.pairPhase),
            UInt64(frame.screen),
            UInt64(frame.subphase),
        ] {
            frameHash ^= value
            frameHash &*= 1_099_511_628_211
        }
        frameHash ^= UInt64(unsupportedVisible)
        if frameHash == 0 { frameHash = 1 }

        var summary = GESourceFrameSummaryV6()
        setHeader(&summary.header, size: MemoryLayout<GESourceFrameSummaryV6>.size)
        summary.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
        summary.flags = unsupportedVisible == 0
            ? UInt32(GE_SOURCE_FRAME_V6_FLAG_PRESENTABLE) | (frame.pairPhase == 0 ? UInt32(GE_SOURCE_FRAME_V6_FLAG_SOURCE_ANCHOR) : UInt32(GE_SOURCE_FRAME_V6_FLAG_INTERPOLATED))
            : (frame.pairPhase == 0 ? UInt32(GE_SOURCE_FRAME_V6_FLAG_SOURCE_ANCHOR) : UInt32(GE_SOURCE_FRAME_V6_FLAG_INTERPOLATED))
        summary.screen = frame.screen
        summary.subphase = frame.subphase
        summary.native_tick = frame.nativeTick
        summary.reference_tick = frame.referenceTick
        summary.pair_phase = frame.pairPhase
        summary.viewport_width = frame.viewportWidth
        summary.viewport_height = frame.viewportHeight
        summary.logical_width = frame.logicalWidth
        summary.logical_height = frame.logicalHeight
        summary.transform_count = UInt32(transformBundle.count)
        summary.resource_count = UInt32(resources.count)
        summary.vertex_count = UInt32(vertices.count)
        summary.index_count = UInt32(indices.count)
        summary.draw_count = UInt32(drawCommands.count)
        summary.render_state_count = UInt32(renderStates.count)
        summary.pose_count = UInt32(animationPoses.count)
        summary.diagnostic_count = UInt32(diagnostics.count)
        summary.unsupported_visible_count = unsupportedVisible
        summary.scene_hash = sceneHash
        summary.render_hash = renderHash
        summary.state_hash = stateHash
        summary.frame_hash = frameHash

        let sourceProjectionHandle = consumedProjectionHandles.count == 1
            ? consumedProjectionHandles.first!
            : 0
        let sourceViewportHandle = consumedViewportHandles.count == 1
            ? consumedViewportHandles.first!
            : 0
        let emittedProjectionTransformCount = UInt32(transformBundle.reduce(into: 0) { count, transform in
            if transform.transform_kind == UInt32(GE_SOURCE_TRANSFORM_V6_PROJECTION) {
                count += 1
            }
        })
        let emittedViewportTransformCount = UInt32(transformBundle.reduce(into: 0) { count, transform in
            if transform.transform_kind == UInt32(GE_SOURCE_TRANSFORM_V6_VIEWPORT) {
                count += 1
            }
        })
        let projectionConsumption = GoldenEyeGBIProjectionConsumptionEvidenceV6(
            sourceProjectionHandle: sourceProjectionHandle,
            sourceViewportHandle: sourceViewportHandle,
            emittedProjectionTransformCount: emittedProjectionTransformCount,
            emittedViewportTransformCount: emittedViewportTransformCount,
            combinedClipTransformHandle: combinedClipHandles.first ?? 0,
            combinedClipTransformHandles: combinedClipHandles,
            requiredDrawCount: UInt32(draws.count),
            consumedDrawCount: consumedProjectionDrawCount
        )

        let snapshot: GoldenEyeSourceSceneSnapshotV6
        do {
            let lightingFrameContext: GoldenEyeSourceSceneLightingFrameContextV6?
            if let sourceTimer = frame.sourceTimer {
                lightingFrameContext = try GoldenEyeSourceSceneLightingFrameContextV6(
                    screen: frame.screen,
                    nativeTick: frame.nativeTick,
                    referenceTick: frame.referenceTick,
                    sourceTimer: sourceTimer,
                    pairPhase: frame.pairPhase,
                    geometryModesByState: geometryModesByState,
                    modelViewQ16ByState: modelViewQ16ByState
                )
            } else {
                lightingFrameContext = nil
            }
            snapshot = try GoldenEyeSourceSceneSnapshotV6(
                summary: summary,
                resources: resources,
                transforms: transformBundle,
                animationPoses: animationPoses,
                vertices: vertices,
                indices: indices,
                renderStates: renderStates,
                drawCommands: drawCommands,
                textEvents: [],
                audioEvents: [],
                diagnostics: diagnostics,
                lightingFrameContext: lightingFrameContext
            )
        } catch {
            throw GoldenEyeGBISceneBuilderV6Error.sceneValidation(String(describing: error))
        }

        return GoldenEyeGBISceneBuildResultV6(
            snapshot: snapshot,
            packetDialect: packetPointer.pointee.dialect,
            packetCommandCount: packetPointer.pointee.command_count,
            packetListCount: packetPointer.pointee.list_count,
            packetVertexCount: packetPointer.pointee.vertex_count,
            packetImageCount: packetPointer.pointee.image_count,
            sourceCommandWordHash: sourceCommandWordHash,
            packetCommandWordHash: packetCommandWordHash(packetPointer),
            packetSourceCommandWordHash: packetSourceCommandWordHash(packetPointer),
            textureSetups: textureSetups,
            vertexResourceTotal: UInt32(vertexResourceTotal),
            vertexResourcePageCount: UInt32(vertexResourcePageCount),
            vertexResourceManifestHash: vertexResourceManifestHash,
            projectionConsumption: projectionConsumption,
            decoderStatus: decoderPointer.pointee.status,
            decoderDraws: readPointerArray(
                decoderPointer,
                fieldOffset: MemoryLayout<GEGBIResultV6>.offset(of: \.draws)!,
                count: Int(decoderPointer.pointee.draw_count),
                as: GEGBIDrawV6.self
            ),
            stateWordEvidence: (0..<Int(decoderPointer.pointee.state_count)).map { index in
                let state = readPointerElement(
                    decoderPointer,
                    fieldOffset: MemoryLayout<GEGBIResultV6>.offset(of: \.states)!,
                    index: index,
                    as: GEGBIStateV6.self
                )
                return GoldenEyeGBIStateWordEvidenceV6(
                    stateIndex: UInt32(index),
                    otherModeH: state.other_mode_h,
                    otherModeL: state.other_mode_l,
                    combineW0: state.combine_w0,
                    combineW1: state.combine_w1
                )
            },
            decoderUnsupportedCount: decoderPointer.pointee.unsupported_count,
            unsupportedVisibleCount: unsupportedVisible,
            unsupportedReasons: unsupportedReasons,
            presentable: snapshot.isPresentable,
            commandCount: decoderPointer.pointee.commands_processed,
            triangleCount: decoderPointer.pointee.draw_count,
            sourceTriangleSlotCount: sourceTriangleSlotCount(scene),
            decoderStateCount: decoderPointer.pointee.state_count,
            resourceCount: UInt32(resources.count),
            eventHash: decoderPointer.pointee.event_hash,
            stateHash: decoderPointer.pointee.state_hash,
            geometryModesByState: geometryModesByState,
            modelViewQ16ByState: modelViewQ16ByState,
            exactNodeTransformDrawCount: exactNodeTransformDrawCount,
            fallbackNodeTransformDrawCount: fallbackNodeTransformDrawCount,
            exactNodeTransformHandles: nodeTransformLowering.exactMatrixAssociations.keys.sorted()
        )
    }

    private static func sourceTriangleSlotCount(_ scene: GESourceSceneV6) -> UInt32 {
        scene.commands.reduce(into: UInt32(0)) { total, command in
            switch command.macro {
            case "gsSP1Triangle": total += 1
            case "gsSP2Triangles": total += 2
            case "gsSP4Triangles": total += 4
            default: break
            }
        }
    }

    /// Rareware's title producer writes the fade alpha into the primitive
    /// color immediately before the three display-list passes.  The GESM
    /// segment intentionally excludes that outer title.c command, so carry
    /// its copied scalar into each frame-local render-state record.  Texture
    /// 5 is the authored lilac body pass; the other five materials use the
    /// grayscale primitive value.
    private static func rarewarePrimitiveColor(
        sourceTimer: UInt32,
        pairPhase: UInt32,
        textureHandle: UInt32,
        model: GoldenEyeSourceModelV6
    ) -> UInt32 {
        let current = rarewareFadeInteger(sourceTimer)
        let fadeQ16: Int64
        if pairPhase == 1, sourceTimer != UInt32.max {
            fadeQ16 = (current + rarewareFadeInteger(sourceTimer &+ 1)) * 32_768
        } else {
            fadeQ16 = current * 65_536
        }
        let fade = Int(min(max((fadeQ16 + 32_768) / 65_536, 0), 255))
        let bodyTexture = model.textures.last?.resourceHandle
        if textureHandle == bodyTexture {
            let redBlue = (fade * 0xF0) / 0xFF
            let green = (fade * 0xD0) / 0xFF
            return UInt32(redBlue) << 24 | UInt32(green) << 16 |
                UInt32(redBlue) << 8 | 0xFF
        }
        return UInt32(fade) << 24 | UInt32(fade) << 16 | UInt32(fade) << 8 | 0xFF
    }

    private static func rarewareFadeInteger(_ sourceTimer: UInt32) -> Int64 {
        let counter = Int64(sourceTimer)
        let fadeIn = min(max((counter * 255) / 70, 0), 255)
        let fadeOut = min(max(255 - ((counter * 255 - 40_800) / 70), 0), 255)
        return (fadeIn * fadeOut) / 255
    }

    private struct DrawKey: Equatable {
        let stateIndex: Int
        let textureHandle: UInt32
        let transformHandle: UInt32
    }

    private struct DrawGroup {
        let key: DrawKey
        let stateIndex: Int
        let textureHandle: UInt32
        let transformHandle: UInt32
        let scissor: (x: Int32, y: Int32, width: UInt32, height: UInt32)
        let drawFlags: UInt32
        let firstVertex: Int
        let firstIndex: Int
        var sourceOffsets: [UInt32]
    }

    private struct LoweredState {
        let state: GESourceRenderStateV6
        let textureHandle: UInt32
        let scissor: (x: Int32, y: Int32, width: UInt32, height: UInt32)
        let drawFlags: UInt32
        let gap: String?
    }

    private struct ClipKey: Hashable {
        let modelViewHandle: UInt32
        let projectionHandle: UInt32
        let viewportHandle: UInt32
    }

    private struct NodeClipKey: Hashable {
        let clipHandle: UInt32
        let boneHandle: UInt32
    }

    /// The vertex-load correction depends only on the pair of immutable
    /// source matrices for a converted frame.  Keep it value-only and local
    /// to `convert`: poses can change on every tick, while each pair is reused
    /// by all vertices that share the same source load/model node.
    private struct RelativeMatrixKey: Hashable {
        let drawBoneHandle: UInt32
        let loadedBoneHandle: UInt32
    }

    private static func lowerState(
        _ source: GEGBIStateV6,
        stateIndex: UInt32,
        imageToTexture: [UInt32: UInt32],
        textureByHandle: [UInt32: GoldenEyeSourceModelV6.Texture],
        logicalWidth: UInt32,
        logicalHeight: UInt32,
        matrixKinds: [UInt32: Set<UInt32>],
        textureSetup: GoldenEyeSourceTextureSetupV6? = nil
    ) throws -> LoweredState {
        let cycleType = (source.other_mode_h >> 20) & 3
        let cycleGap: String? = cycleType >= 2
            ? "source RDP cycle mode \(cycleType) is not representable by triangle combiner V6"
            : nil
        let cycleCount: UInt32 = cycleType == 1 ? 2 : 1
        let textureHandle: UInt32
        if source.texture_image_handle == 0 {
            textureHandle = 0
        } else if let mapped = imageToTexture[source.texture_image_handle] {
            textureHandle = mapped
        } else {
            throw GoldenEyeGBISceneBuilderV6Error.invalidState(stateIndex, "missing image alias 0x\(String(source.texture_image_handle, radix: 16))")
        }
        if let textureSetup, textureHandle != 0,
           textureSetup.resourceHandle != textureHandle {
            throw GoldenEyeGBISceneBuilderV6Error.invalidState(
                stateIndex,
                "texture setup resource 0x\(String(textureSetup.resourceHandle, radix: 16)) does not match 0x\(String(textureHandle, radix: 16))"
            )
        }

        let combiner = decodeCombiner(source.combine_w0, source.combine_w1, cycleCount: cycleCount)
        guard let combiner else {
            throw GoldenEyeGBISceneBuilderV6Error.unsupportedState(stateIndex, "combiner selector w0=0x\(String(source.combine_w0, radix: 16)) w1=0x\(String(source.combine_w1, radix: 16)) cycle=\(cycleCount)")
        }
        var rawH = source.other_mode_h
        let rawL = source.other_mode_l
        var filterRaw = (rawH >> 12) & 3
        // The Rareware segment is invoked after title.c establishes the
        // producer-owned perspective/BILERP/FILT state.  Some guarded source
        // lists retain the decoder's initial point/LOD word in their copied
        // state snapshots, so apply the typed outer state at the lowering
        // boundary as well as retaining the synthetic provenance commands.
        if textureSetup?.modelName == "rarewarelogo",
           rawL == 0x0f0a_4000 {
            rawH = 0x0019_2c00
            filterRaw = 2
        }
        let filter: UInt32
        switch filterRaw {
        case 0: filter = UInt32(GE_SOURCE_FILTER_V6_POINT)
        case 2, 3: filter = UInt32(GE_SOURCE_FILTER_V6_BILINEAR)
        default: throw GoldenEyeGBISceneBuilderV6Error.unsupportedState(stateIndex, "texture filter")
        }
        let alphaRaw = rawL & 3
        guard alphaRaw <= UInt32(GE_SOURCE_ALPHA_V6_MAX) else {
            throw GoldenEyeGBISceneBuilderV6Error.unsupportedState(stateIndex, "alpha compare")
        }
        let coverageRaw = (rawL >> 8) & 3
        // Coverage-save (destination selector 3) is retained as an additive
        // V6 typed value; the raw OtherMode words remain authoritative too.
        let coverageMode: UInt32 = coverageRaw

        let geometry = source.geometry_mode
        let front = geometry & 0x0000_1000 != 0
        let back = geometry & 0x0000_2000 != 0
        let cull: UInt32
        switch (front, back) {
        case (false, false): cull = UInt32(GE_SOURCE_CULL_V6_NONE)
        case (true, false): cull = UInt32(GE_SOURCE_CULL_V6_FRONT)
        case (false, true): cull = UInt32(GE_SOURCE_CULL_V6_BACK)
        case (true, true): cull = UInt32(GE_SOURCE_CULL_V6_BOTH)
        }
        let zCompare = ((rawL >> 4) & 1) != 0
        let zUpdate = ((rawL >> 5) & 1) != 0
        let depth: UInt32
        if zCompare { depth = UInt32(GE_SOURCE_DEPTH_V6_LEQUAL) }
        else if zUpdate { depth = UInt32(GE_SOURCE_DEPTH_V6_ALWAYS) }
        else { depth = UInt32(GE_SOURCE_DEPTH_V6_DISABLED) }
        var flags: UInt32 = 0
        if depth != UInt32(GE_SOURCE_DEPTH_V6_DISABLED) { flags |= UInt32(GE_SOURCE_RENDER_STATE_V6_FLAG_DEPTH_TEST) }
        if zUpdate { flags |= UInt32(GE_SOURCE_RENDER_STATE_V6_FLAG_DEPTH_WRITE) }
        if alphaRaw != 0 { flags |= UInt32(GE_SOURCE_RENDER_STATE_V6_FLAG_ALPHA_COMPARE) }
        if coverageRaw != UInt32(GE_SOURCE_COVERAGE_V6_CLAMP) { flags |= UInt32(GE_SOURCE_RENDER_STATE_V6_FLAG_COVERAGE) }
        if coverageRaw == UInt32(GE_SOURCE_COVERAGE_V6_SAVE) { flags |= UInt32(GE_SOURCE_RENDER_STATE_V6_FLAG_COVERAGE_SAVE) }
        if geometry & 0x0001_0000 != 0 { flags |= UInt32(GE_SOURCE_RENDER_STATE_V6_FLAG_FOG) }
        if ((rawL >> 3) & 1) != 0 { flags |= UInt32(GE_SOURCE_RENDER_STATE_V6_FLAG_ANTIALIAS) }

        let texture = textureByHandle[textureHandle]
        if textureHandle != 0, texture == nil {
            throw GoldenEyeGBISceneBuilderV6Error.missingTexture(textureHandle)
        }
        var wrapS = UInt32(GE_SOURCE_WRAP_V6_CLAMP)
        var wrapT = UInt32(GE_SOURCE_WRAP_V6_CLAMP)
        let tile = Int((source.texture_enabled_level_tile >> 8) & 7)
        var sourceCopy = source
        let tileState = withUnsafeMutablePointer(to: &sourceCopy) { pointer in
            readPointerElement(
                pointer,
                fieldOffset: MemoryLayout<GEGBIStateV6>.offset(of: \.tiles)!,
                index: tile,
                as: GEGBITileStateV6.self
            )
        }
        let cmt = (tileState.tile_palette_cmt_maskt_shiftt >> 18) & 3
        let cms = (tileState.cms_masks_shifts >> 8) & 3
        guard cmt <= 2, cms <= 2 else {
            throw GoldenEyeGBISceneBuilderV6Error.unsupportedState(stateIndex, "tile wrap/clamp")
        }
        if let texture {
            let tileHasAddressModes = tileState.tile_palette_cmt_maskt_shiftt != 0 || tileState.cms_masks_shifts != 0
            wrapS = try wrapSelector(tileHasAddressModes ? cms : texture.sFlags)
            wrapT = try wrapSelector(tileHasAddressModes ? cmt : texture.tFlags)
        }
        let mipCount = texture?.mipMapTiles ?? 1
        let lodEnabled = ((rawH >> 16) & 1) != 0
        let lodMax: UInt32
        if texture?.mipMapTiles == 1 {
            // The source Type-4 character auxiliary tile is a true 1x1
            // material.  Its surrounding display-list state may retain the
            // LOD-enable bit while the selected image has no mip chain; the
            // source max LOD for that tile is therefore level zero.
            lodMax = 0
        } else if let textureSetup {
            guard textureSetup.maxLOD < 32_768 else {
                throw GoldenEyeGBISceneBuilderV6Error.invalidState(stateIndex, "texture setup max LOD overflow")
            }
            lodMax = textureSetup.maxLOD << 16
        } else {
            lodMax = lodEnabled ? max(0, mipCount - 1) << 16 : 0
        }
        if let textureSetup, textureHandle != 0 {
            wrapS = wrapSelector(textureSetup.tileState.addressS)
            wrapT = wrapSelector(textureSetup.tileState.addressT)
        }
        let scissor = decodeScissor(source, logicalWidth: logicalWidth, logicalHeight: logicalHeight)

        var value = GESourceRenderStateV6()
        setHeader(&value.header, size: MemoryLayout<GESourceRenderStateV6>.size)
        value.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
        value.state_handle = stateHandle(stateIndex)
        value.flags = flags
        value.material_handle = textureHandle == 0 ? stateHandle(stateIndex) : textureHandle
        value.combiner_cycle_count = cycleCount
        value.cycle0_color_a = combiner.c0.0
        value.cycle0_color_b = combiner.c0.1
        value.cycle0_color_c = combiner.c0.2
        value.cycle0_color_d = combiner.c0.3
        value.cycle0_alpha_a = combiner.c0.4
        value.cycle0_alpha_b = combiner.c0.5
        value.cycle0_alpha_c = combiner.c0.6
        value.cycle0_alpha_d = combiner.c0.7
        value.cycle1_color_a = combiner.c1.0
        value.cycle1_color_b = combiner.c1.1
        value.cycle1_color_c = combiner.c1.2
        value.cycle1_color_d = combiner.c1.3
        value.cycle1_alpha_a = combiner.c1.4
        value.cycle1_alpha_b = combiner.c1.5
        value.cycle1_alpha_c = combiner.c1.6
        value.cycle1_alpha_d = combiner.c1.7
        value.primitive_rgba = source.prim_color
        value.environment_rgba = source.env_color
        value.fog_rgba = source.fog_color
        value.blend_rgba = source.blend_color
        value.depth_mode = depth
        value.alpha_mode = alphaRaw
        value.coverage_mode = coverageMode
        value.cull_mode = cull
        value.filter_mode = filter
        value.wrap_s = wrapS
        value.wrap_t = wrapT
        value.lod_min_q16 = 0
        value.lod_max_q16 = lodMax
        value.raw_othermode_h = rawH
        value.raw_othermode_l = rawL
        value.raw_render_mode = rawL & 0xffff_fff8
        value.raw_blender_a = packBlender(rawL, shift0: 30, shift1: 28)
        value.raw_blender_b = packBlender(rawL, shift0: 26, shift1: 24)
        value.raw_blender_c = packBlender(rawL, shift0: 22, shift1: 20)
        value.raw_blender_d = packBlender(rawL, shift0: 18, shift1: 16)
        try validateRenderState(&value)
        let renderMode = loweredDrawFlags(
            for: value.raw_render_mode,
            coverageSave: coverageRaw == 3
        )
        let gap = cycleGap ?? renderMode.gap
        return LoweredState(state: value, textureHandle: textureHandle, scissor: scissor, drawFlags: renderMode.flags, gap: gap)
    }

    private static func decodeCombiner(
        _ w0: UInt32,
        _ w1: UInt32,
        cycleCount: UInt32
    ) -> ((c0: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32), c1: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32)))? {
        guard w0 >> 24 == UInt32(GE_SOURCE_GBI_V6_OP_SETCOMBINE) else { return nil }
        // A/B selectors are four bits, C selectors are five bits, and the
        // D selector occupies only three bits.  The same numeric value has
        // different source meanings in those fields: G_CCMUX_0 (31)
        // truncates to 15 in A/B and to 7 in D, while raw 15 remains K5 only
        // in the five-bit C field.  Decode each slot by its actual width.
        func colorA(_ raw: UInt32) -> UInt32? {
            switch raw {
            case 0: return UInt32(GE_SOURCE_COMBINER_V6_KEY_COMBINED)
            case 1: return UInt32(GE_SOURCE_COMBINER_V6_KEY_TEXEL0)
            case 2: return UInt32(GE_SOURCE_COMBINER_V6_KEY_TEXEL1)
            case 3: return UInt32(GE_SOURCE_COMBINER_V6_KEY_PRIMITIVE)
            case 4: return UInt32(GE_SOURCE_COMBINER_V6_KEY_SHADE)
            case 5: return UInt32(GE_SOURCE_COMBINER_V6_KEY_ENVIRONMENT)
            case 6: return UInt32(GE_SOURCE_COMBINER_V6_KEY_ONE)
            case 7: return UInt32(GE_SOURCE_COMBINER_V6_KEY_K4)
            case 8: return UInt32(GE_SOURCE_COMBINER_V6_KEY_TEXEL0)
            case 9: return UInt32(GE_SOURCE_COMBINER_V6_KEY_TEXEL1)
            case 10: return UInt32(GE_SOURCE_COMBINER_V6_KEY_PRIMITIVE)
            case 11: return UInt32(GE_SOURCE_COMBINER_V6_KEY_SHADE)
            case 12: return UInt32(GE_SOURCE_COMBINER_V6_KEY_ENVIRONMENT)
            case 13: return UInt32(GE_SOURCE_COMBINER_V6_KEY_LOD_FRACTION)
            case 14: return UInt32(GE_SOURCE_COMBINER_V6_KEY_PRIMITIVE_LOD_FRACTION)
            case 15: return UInt32(GE_SOURCE_COMBINER_V6_KEY_ZERO)
            default: return nil
            }
        }
        func colorB(_ raw: UInt32) -> UInt32? {
            // The four-bit B selector encodes the source literal 0 as ZERO;
            // it is not the COMBINED value used by the A field.
            if raw == 0 || raw == 15 { return UInt32(GE_SOURCE_COMBINER_V6_KEY_ZERO) }
            return colorA(raw)
        }
        func colorC(_ raw: UInt32) -> UInt32? {
            switch raw {
            case 0: return UInt32(GE_SOURCE_COMBINER_V6_KEY_COMBINED)
            case 1: return UInt32(GE_SOURCE_COMBINER_V6_KEY_TEXEL0)
            case 2: return UInt32(GE_SOURCE_COMBINER_V6_KEY_TEXEL1)
            case 3: return UInt32(GE_SOURCE_COMBINER_V6_KEY_PRIMITIVE)
            case 4: return UInt32(GE_SOURCE_COMBINER_V6_KEY_SHADE)
            case 5: return UInt32(GE_SOURCE_COMBINER_V6_KEY_ENVIRONMENT)
            case 6: return UInt32(GE_SOURCE_COMBINER_V6_KEY_CENTER)
            case 7: return UInt32(GE_SOURCE_COMBINER_V6_KEY_COMBINED_ALPHA)
            case 8: return UInt32(GE_SOURCE_COMBINER_V6_KEY_TEXEL0)
            case 9: return UInt32(GE_SOURCE_COMBINER_V6_KEY_TEXEL1)
            case 10: return UInt32(GE_SOURCE_COMBINER_V6_KEY_PRIMITIVE)
            case 11: return UInt32(GE_SOURCE_COMBINER_V6_KEY_SHADE)
            case 12: return UInt32(GE_SOURCE_COMBINER_V6_KEY_ENVIRONMENT)
            case 13: return UInt32(GE_SOURCE_COMBINER_V6_KEY_LOD_FRACTION)
            case 14: return UInt32(GE_SOURCE_COMBINER_V6_KEY_PRIMITIVE_LOD_FRACTION)
            case 15: return UInt32(GE_SOURCE_COMBINER_V6_KEY_K5)
            case 31: return UInt32(GE_SOURCE_COMBINER_V6_KEY_ZERO)
            default: return nil
            }
        }
        func colorD(_ raw: UInt32) -> UInt32? {
            switch raw {
            case 0: return UInt32(GE_SOURCE_COMBINER_V6_KEY_ZERO)
            case 1: return UInt32(GE_SOURCE_COMBINER_V6_KEY_TEXEL0)
            case 2: return UInt32(GE_SOURCE_COMBINER_V6_KEY_TEXEL1)
            case 3: return UInt32(GE_SOURCE_COMBINER_V6_KEY_PRIMITIVE)
            case 4: return UInt32(GE_SOURCE_COMBINER_V6_KEY_SHADE)
            case 5: return UInt32(GE_SOURCE_COMBINER_V6_KEY_ENVIRONMENT)
            case 6: return UInt32(GE_SOURCE_COMBINER_V6_KEY_ONE)
            case 7: return UInt32(GE_SOURCE_COMBINER_V6_KEY_ZERO)
            default: return nil
            }
        }
        func alphaA(_ raw: UInt32) -> UInt32? {
            switch raw {
            case 0: return UInt32(GE_SOURCE_COMBINER_V6_KEY_COMBINED)
            case 1: return UInt32(GE_SOURCE_COMBINER_V6_KEY_TEXEL0)
            case 2: return UInt32(GE_SOURCE_COMBINER_V6_KEY_TEXEL1)
            case 3: return UInt32(GE_SOURCE_COMBINER_V6_KEY_PRIMITIVE)
            case 4: return UInt32(GE_SOURCE_COMBINER_V6_KEY_SHADE)
            case 5: return UInt32(GE_SOURCE_COMBINER_V6_KEY_ENVIRONMENT)
            case 6: return UInt32(GE_SOURCE_COMBINER_V6_KEY_ONE)
            case 7: return UInt32(GE_SOURCE_COMBINER_V6_KEY_ZERO)
            default: return nil
            }
        }
        func alphaB(_ raw: UInt32) -> UInt32? {
            if raw == 0 || raw == 7 { return UInt32(GE_SOURCE_COMBINER_V6_KEY_ZERO) }
            return alphaA(raw)
        }
        func alphaD(_ raw: UInt32) -> UInt32? {
            if raw == 0 || raw == 7 { return UInt32(GE_SOURCE_COMBINER_V6_KEY_ZERO) }
            return alphaA(raw)
        }
        func alphaC(_ raw: UInt32) -> UInt32? {
            // G_ACMUX_LOD_FRACTION shares raw zero in the C slot only;
            // alpha A/B/D raw zero remains COMBINED.
            switch raw {
            case 0: return UInt32(GE_SOURCE_COMBINER_V6_KEY_LOD_FRACTION)
            case 1: return UInt32(GE_SOURCE_COMBINER_V6_KEY_TEXEL0)
            case 2: return UInt32(GE_SOURCE_COMBINER_V6_KEY_TEXEL1)
            case 3: return UInt32(GE_SOURCE_COMBINER_V6_KEY_PRIMITIVE)
            case 4: return UInt32(GE_SOURCE_COMBINER_V6_KEY_SHADE)
            case 5: return UInt32(GE_SOURCE_COMBINER_V6_KEY_ENVIRONMENT)
            case 6: return UInt32(GE_SOURCE_COMBINER_V6_KEY_ONE)
            case 7: return UInt32(GE_SOURCE_COMBINER_V6_KEY_ZERO)
            default: return nil
            }
        }
        let rawC0: [UInt32] = [(w0 >> 20) & 0xf, (w1 >> 28) & 0xf, (w0 >> 15) & 0x1f, (w1 >> 15) & 7]
        let rawA0: [UInt32] = [(w0 >> 12) & 7, (w1 >> 12) & 7, (w0 >> 9) & 7, (w1 >> 9) & 7]
        let rawC1: [UInt32] = [(w0 >> 5) & 0xf, (w1 >> 24) & 0xf, w0 & 0x1f, (w1 >> 6) & 7]
        let rawA1: [UInt32] = [(w1 >> 21) & 7, (w1 >> 3) & 7, (w1 >> 18) & 7, w1 & 7]
        guard let c0a = colorA(rawC0[0]), let c0b = colorB(rawC0[1]), let c0c = colorC(rawC0[2]), let c0d = colorD(rawC0[3]),
              let c0aa = alphaA(rawA0[0]), let c0ab = alphaB(rawA0[1]), let c0ac = alphaC(rawA0[2]), let c0ad = alphaD(rawA0[3]),
              let c1a = colorA(rawC1[0]), let c1b = colorB(rawC1[1]), let c1c = colorC(rawC1[2]), let c1d = colorD(rawC1[3]),
              let c1aa = alphaA(rawA1[0]), let c1ab = alphaB(rawA1[1]), let c1ac = alphaC(rawA1[2]), let c1ad = alphaD(rawA1[3]) else { return nil }
        // The raw source word retains second-cycle bits even for one-cycle
        // modes. Keep those bits in stateWordEvidence, but normalize the
        // typed inactive cycle to ZERO so the Metal contract cannot consume
        // phantom second-cycle work.
        let inactive: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32) = (
            UInt32(GE_SOURCE_COMBINER_V6_KEY_ZERO), UInt32(GE_SOURCE_COMBINER_V6_KEY_ZERO),
            UInt32(GE_SOURCE_COMBINER_V6_KEY_ZERO), UInt32(GE_SOURCE_COMBINER_V6_KEY_ZERO),
            UInt32(GE_SOURCE_COMBINER_V6_KEY_ZERO), UInt32(GE_SOURCE_COMBINER_V6_KEY_ZERO),
            UInt32(GE_SOURCE_COMBINER_V6_KEY_ZERO), UInt32(GE_SOURCE_COMBINER_V6_KEY_ZERO)
        )
        return (
            (c0a, c0b, c0c, c0d, c0aa, c0ab, c0ac, c0ad),
            cycleCount == 1 ? inactive : (c1a, c1b, c1c, c1d, c1aa, c1ab, c1ac, c1ad)
        )
    }

    private static func wrapSelector(_ raw: UInt32) throws -> UInt32 {
        switch raw {
        case 0: return UInt32(GE_SOURCE_WRAP_V6_REPEAT)
        case 1: return UInt32(GE_SOURCE_WRAP_V6_MIRROR)
        case 2: return UInt32(GE_SOURCE_WRAP_V6_CLAMP)
        default: throw GoldenEyeGBISceneBuilderV6Error.unsupportedWrap(raw)
        }
    }

    private static func wrapSelector(
        _ mode: GoldenEyeSourceTextureAddressModeV6
    ) -> UInt32 {
        switch mode {
        case .wrap: return UInt32(GE_SOURCE_WRAP_V6_REPEAT)
        case .mirror: return UInt32(GE_SOURCE_WRAP_V6_MIRROR)
        case .clamp: return UInt32(GE_SOURCE_WRAP_V6_CLAMP)
        }
    }

    private static func decodeScissor(
        _ state: GEGBIStateV6,
        logicalWidth: UInt32,
        logicalHeight: UInt32
    ) -> (x: Int32, y: Int32, width: UInt32, height: UInt32) {
        let ul = state.scissor_ulx_uly
        let lr = state.scissor_lrx_lry
        guard ul != 0 || lr != 0 else { return (0, 0, logicalWidth, logicalHeight) }
        let x = Int32(((ul >> 12) & 0xfff) / 4)
        let y = Int32((ul & 0xfff) / 4)
        let right = Int32(((lr >> 12) & 0xfff) / 4)
        let bottom = Int32((lr & 0xfff) / 4)
        guard right > x, bottom > y else { return (0, 0, logicalWidth, logicalHeight) }
        return (x, y, UInt32(right - x), UInt32(bottom - y))
    }

    private static func matrixValues<T>(_ tuple: T) -> [Int32] {
        withUnsafeBytes(of: tuple) { rawBytes in
            Array(rawBytes.bindMemory(to: Int32.self).prefix(16))
        }
    }

    /// Returns inverse(from) * to for source affine Q16 transforms.  The
    /// lowerer emits affine matrices with a final [0,0,0,1] row; rejecting a
    /// singular 3x3 basis keeps malformed source transforms fail-closed.
    private static func relativeMatrix(from: [Int32], to: [Int32]) -> [Int32]? {
        guard from.count == 16, to.count == 16,
              let inverse = inverseAffine(from) else { return nil }
        return multiplyQ16(inverse, to)
    }

    private static func inverseAffine(_ matrix: [Int32]) -> [Int32]? {
        let scale = 65_536.0
        let m00 = Double(matrix[0]) / scale
        let m01 = Double(matrix[4]) / scale
        let m02 = Double(matrix[8]) / scale
        let m10 = Double(matrix[1]) / scale
        let m11 = Double(matrix[5]) / scale
        let m12 = Double(matrix[9]) / scale
        let m20 = Double(matrix[2]) / scale
        let m21 = Double(matrix[6]) / scale
        let m22 = Double(matrix[10]) / scale
        let determinant = m00 * (m11 * m22 - m12 * m21)
            - m01 * (m10 * m22 - m12 * m20)
            + m02 * (m10 * m21 - m11 * m20)
        guard determinant.isFinite, abs(determinant) > 0.0000001 else { return nil }
        let inv00 = (m11 * m22 - m12 * m21) / determinant
        let inv01 = (m02 * m21 - m01 * m22) / determinant
        let inv02 = (m01 * m12 - m02 * m11) / determinant
        let inv10 = (m12 * m20 - m10 * m22) / determinant
        let inv11 = (m00 * m22 - m02 * m20) / determinant
        let inv12 = (m02 * m10 - m00 * m12) / determinant
        let inv20 = (m10 * m21 - m11 * m20) / determinant
        let inv21 = (m01 * m20 - m00 * m21) / determinant
        let inv22 = (m00 * m11 - m01 * m10) / determinant
        let tx = Double(matrix[12]) / scale
        let ty = Double(matrix[13]) / scale
        let tz = Double(matrix[14]) / scale
        func q16(_ value: Double) -> Int32 { Int32(clamping: Int64((value * scale).rounded())) }
        return [
            q16(inv00), q16(inv10), q16(inv20), 0,
            q16(inv01), q16(inv11), q16(inv21), 0,
            q16(inv02), q16(inv12), q16(inv22), 0,
            q16(-(inv00 * tx + inv01 * ty + inv02 * tz)),
            q16(-(inv10 * tx + inv11 * ty + inv12 * tz)),
            q16(-(inv20 * tx + inv21 * ty + inv22 * tz)),
            65_536,
        ]
    }

    private static func multiplyQ16(_ lhs: [Int32], _ rhs: [Int32]) -> [Int32] {
        guard lhs.count == 16, rhs.count == 16 else { return Array(repeating: 0, count: 16) }
        var result = Array(repeating: Int32(0), count: 16)
        for column in 0..<4 {
            for row in 0..<4 {
                var value: Int64 = 0
                for index in 0..<4 {
                    value += Int64(lhs[index * 4 + row]) * Int64(rhs[column * 4 + index])
                }
                result[column * 4 + row] = Int32(clamping: value >> 16)
            }
        }
        return result
    }

    private static func applyPositionCorrection(
        _ vertex: inout GESourceVertexV6,
        matrix: [Int32]
    ) {
        guard matrix.count == 16 else { return }
        // The homogeneous row is intentionally not materialized: the source
        // vertex ABI carries xyz only, and the prior loop's row-3 result was
        // discarded. Keep the exact column-major Q16 accumulation for the
        // three consumed rows without allocating temporary arrays per vertex.
        let x = Int64(vertex.position_q16.0)
        let y = Int64(vertex.position_q16.1)
        let z = Int64(vertex.position_q16.2)
        let one = Int64(65_536)
        vertex.position_q16.0 = Int32(clamping:
            (Int64(matrix[0]) * x + Int64(matrix[4]) * y
                + Int64(matrix[8]) * z + Int64(matrix[12]) * one) >> 16
        )
        vertex.position_q16.1 = Int32(clamping:
            (Int64(matrix[1]) * x + Int64(matrix[5]) * y
                + Int64(matrix[9]) * z + Int64(matrix[13]) * one) >> 16
        )
        vertex.position_q16.2 = Int32(clamping:
            (Int64(matrix[2]) * x + Int64(matrix[6]) * y
                + Int64(matrix[10]) * z + Int64(matrix[14]) * one) >> 16
        )
    }

    private static func applyNormalCorrection(
        _ vertex: inout GESourceVertexV6,
        matrix: [Int32]
    ) -> Bool {
        guard matrix.count == 16 else { return false }
        let x = Int64(vertex.normal_q16.0)
        let y = Int64(vertex.normal_q16.1)
        let z = Int64(vertex.normal_q16.2)
        if x == 0, y == 0, z == 0 { return true }
        let shifted0 = (Int64(matrix[0]) * x + Int64(matrix[4]) * y
            + Int64(matrix[8]) * z) >> 16
        let shifted1 = (Int64(matrix[1]) * x + Int64(matrix[5]) * y
            + Int64(matrix[9]) * z) >> 16
        let shifted2 = (Int64(matrix[2]) * x + Int64(matrix[6]) * y
            + Int64(matrix[10]) * z) >> 16
        guard shifted0 >= Int64(Int32.min), shifted0 <= Int64(Int32.max),
              shifted1 >= Int64(Int32.min), shifted1 <= Int64(Int32.max),
              shifted2 >= Int64(Int32.min), shifted2 <= Int64(Int32.max) else {
            return false
        }
        guard shifted0 != 0 || shifted1 != 0 || shifted2 != 0 else { return false }
        vertex.normal_q16.0 = Int32(shifted0)
        vertex.normal_q16.1 = Int32(shifted1)
        vertex.normal_q16.2 = Int32(shifted2)
        return true
    }

    private static func textureSetupForCommand(
        _ command: GESourceCompiledCommandV6,
        setups: [GoldenEyeSourceTextureSetupV6],
        sourceSequence: UInt32? = nil,
        textureHandle: UInt32? = nil
    ) -> GoldenEyeSourceTextureSetupV6? {
        let local = setups
            .filter {
                $0.displayListID == command.displayListID &&
                $0.ordinal <= command.ordinal
            }
            .max {
                if $0.ordinal != $1.ordinal { return $0.ordinal < $1.ordinal }
                return $0.sequence < $1.sequence
            }
        if let local { return local }
        guard let sourceSequence, let textureHandle else { return nil }
        return setups
            .filter {
                $0.resourceHandle == textureHandle &&
                $0.sequence <= sourceSequence
            }
            .max {
                if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
                return $0.ordinal < $1.ordinal
            }
    }

    private static func makeTextureCoordinateCommands(
        packetPointer: UnsafeMutablePointer<GEGBISourcePacketV6>,
        draw: GEGBIDrawV6,
        state: GEGBIStateV6,
        texture: GoldenEyeSourceModelV6.Texture,
        textureHandle: UInt32,
        textureSetup: GoldenEyeSourceTextureSetupV6?
    ) throws -> DecodedTextureCoordinateCommands {
        let commandCount = Int(packetPointer.pointee.command_count)
        let drawIndex = Int(draw.source_command_offset)
            / MemoryLayout<GEGBISourceCommandV6>.size
        let end = min(max(drawIndex, 0), commandCount)
        var textureCommand: GEGBISourceCommandV6?
        var tileCommand: GEGBISourceCommandV6?
        var tileSizeCommand: GEGBISourceCommandV6?
        let tile = (state.texture_enabled_level_tile >> 8) & 7
        // G_SETTEX is a compact source material switch.  Rareware's outer
        // title setup and four mip-chain material switches likewise carry
        // the authoritative per-pass scale/tile words; the flattened packet
        // can still expose the preceding pass's gsSPTexture state. Prefer
        // typed expansion for those guarded Rareware records (and all custom
        // G_SETTEX records) instead of applying stale packet coordinates.
        let useTypedTextureSetup = textureSetup?.kind == .customGSetTex ||
            textureSetup?.modelName == "rarewarelogo"
        if !useTypedTextureSetup {
            for index in 0..<end {
                let command = readPointerElement(
                    packetPointer,
                    fieldOffset: MemoryLayout<GEGBISourcePacketV6>.offset(of: \.commands)!,
                    index: index,
                    as: GEGBISourceCommandV6.self
                )
                switch command.w0 >> 24 {
                case GE_SOURCE_TEXTURE_COORDINATES_V6_OP_TEXTURE:
                    textureCommand = command
                case GE_SOURCE_TEXTURE_COORDINATES_V6_OP_SETTILE:
                    if ((command.w1 >> 24) & 7) == tile { tileCommand = command }
                case GE_SOURCE_TEXTURE_COORDINATES_V6_OP_SETTILESIZE:
                    if ((command.w1 >> 24) & 7) == tile { tileSizeCommand = command }
                default:
                    break
                }
            }
        }
        if let textureSetup {
            guard textureSetup.resourceHandle == textureHandle else {
                throw GoldenEyeGBISceneBuilderV6Error.invalidState(
                    0,
                    "texture setup resource does not match draw texture 0x\(String(textureHandle, radix: 16))"
                )
            }
            let expanded = try expandedTextureCommands(
                setup: textureSetup,
                texture: texture
            )
            textureCommand = expanded.texture
            tileCommand = expanded.tile
            tileSizeCommand = expanded.tileSize
        } else if textureCommand == nil || tileCommand == nil || tileSizeCommand == nil {
            throw GoldenEyeGBISceneBuilderV6Error.invalidState(
                0,
                "missing exact G_TEXTURE/SETTILE/SETTILESIZE words for draw offset 0x\(String(draw.source_command_offset, radix: 16))"
            )
        }
        guard let textureCommand, let tileCommand, let tileSizeCommand else {
            throw GoldenEyeGBISceneBuilderV6Error.invalidState(
                0,
                "texture setup expansion did not produce complete coordinate state"
            )
        }
        return DecodedTextureCoordinateCommands(
            texture: textureCommand,
            tile: tileCommand,
            tileSize: tileSizeCommand
        )
    }

    private static func lowerTextureCoordinate(
        packetPointer: UnsafeMutablePointer<GEGBISourcePacketV6>,
        draw: GEGBIDrawV6,
        state: GEGBIStateV6,
        sourceVertex: GoldenEyeSourceModelV6.Vertex,
        texture: GoldenEyeSourceModelV6.Texture,
        textureHandle: UInt32,
        textureSetup: GoldenEyeSourceTextureSetupV6?,
        sourceStateHash: UInt64,
        sourceCommandHash: UInt64,
        coordinateCommands: DecodedTextureCoordinateCommands?
    ) throws -> GoldenEyeSourceTextureCoordinateV6 {
        let commands = try coordinateCommands ?? makeTextureCoordinateCommands(
            packetPointer: packetPointer,
            draw: draw,
            state: state,
            texture: texture,
            textureHandle: textureHandle,
            textureSetup: textureSetup
        )
        let textureCommand = commands.texture
        let tileCommand = commands.tile
        let tileSizeCommand = commands.tileSize
        let flags = UInt32(GE_SOURCE_TEXTURE_COORDINATES_V6_FLAG_TEXTURE_ENABLED)
            | UInt32(GE_SOURCE_TEXTURE_COORDINATES_V6_FLAG_TILE_CONFIGURED)
            | UInt32(GE_SOURCE_TEXTURE_COORDINATES_V6_FLAG_TILE_BOUNDS)
        let input = GoldenEyeSourceTextureCoordinateV6.input(
            sourceCommandOffset: draw.source_command_offset,
            sourceVertexIndex: sourceVertex.id,
            textureHandle: textureHandle,
            sourceS10_5: signedSource16(sourceVertex.s),
            sourceT10_5: signedSource16(sourceVertex.t),
            textureCommandW0: textureCommand.w0,
            textureCommandW1: textureCommand.w1,
            tileCommandW0: tileCommand.w0,
            tileCommandW1: tileCommand.w1,
            tileSizeCommandW0: tileSizeCommand.w0,
            tileSizeCommandW1: tileSizeCommand.w1,
            // The source can request a higher LOD than the guarded payload
            // exposes for tiny attachment materials (the PP7 1x1 row is the
            // observed case).  Preserve the raw request in the setup record,
            // but lower the sampler's effective level to the highest copied
            // level so native coordinate validation remains bounded.
            maxLevel: textureSetup.map {
                min($0.maxLOD, UInt32(max(0, $0.levels.count - 1)))
            } ?? ((state.texture_enabled_level_tile >> 4) & 7),
            levelCount: UInt32(max(1, textureSetup?.levels.count ?? Int(texture.mipMapTiles))),
            levelWidth: textureSetup?.levels.first?.width ?? texture.width,
            levelHeight: textureSetup?.levels.first?.height ?? texture.height,
            flags: flags,
            sourceStateHash: sourceStateHash,
            sourceCommandHash: sourceCommandHash
        )
        return try GoldenEyeSourceTextureCoordinateV6.lower(input)
    }

    private static func unaddressedSamplerQ16(
        _ localQ16: Int64,
        dimension: UInt32,
        state: UInt32
    ) throws -> Int64 {
        guard dimension > 0 else {
            throw GoldenEyeGBISceneBuilderV6Error.invalidState(
                state,
                "texture coordinate dimension is zero"
            )
        }
        return localQ16 / Int64(dimension)
    }

    private static func expandedTextureCommands(
        setup: GoldenEyeSourceTextureSetupV6,
        texture: GoldenEyeSourceModelV6.Texture
    ) throws -> (
        texture: GEGBISourceCommandV6,
        tile: GEGBISourceCommandV6,
        tileSize: GEGBISourceCommandV6
    ) {
        guard setup.tile < 8, setup.maxLOD < 8,
              setup.textureScaleS <= 0xffff,
              setup.textureScaleT <= 0xffff else {
            throw GoldenEyeGBISceneBuilderV6Error.invalidSourceTexture(setup.resourceHandle)
        }
        let bounds = setup.tileState.bounds
        guard bounds.ulsQ2 <= 0xfff, bounds.ultQ2 <= 0xfff,
              bounds.lrsQ2 <= 0xfff, bounds.lrtQ2 <= 0xfff,
              bounds.lrsQ2 >= bounds.ulsQ2,
              bounds.lrtQ2 >= bounds.ultQ2 else {
            throw GoldenEyeGBISceneBuilderV6Error.invalidState(
                setup.tile,
                "texture setup tile bounds exceed classic encoding"
            )
        }

        // Standard tiles carry all RDP tile words.  A custom G_SETTEX has no
        // literal SETTILE command in Model.c; its typed expansion still
        // supplies exact dimensions/addressing from the guarded payload and
        // macro arguments.  Format/size are source texture depth mappings;
        // line/TMEM/palette are metadata-only for coordinate normalization
        // and remain zero when the custom source command does not define them.
        let inferred = try inferredWireFormat(texture)
        let effectiveMaxLOD = min(setup.maxLOD, UInt32(max(0, setup.levels.count - 1)))
        let format = setup.tileState.format ?? inferred.format
        let size = setup.tileState.size ?? inferred.size
        let line = setup.tileState.line ?? 0
        let tmem = setup.tileState.tmem ?? 0
        let palette = setup.tileState.palette ?? 0
        guard format < 8, size < 4, line < 512, tmem < 512, palette < 16 else {
            throw GoldenEyeGBISceneBuilderV6Error.invalidState(
                setup.tile,
                "texture setup tile fields exceed classic encoding"
            )
        }
        var textureCommand = GEGBISourceCommandV6()
        textureCommand.w0 = (UInt32(GE_SOURCE_TEXTURE_COORDINATES_V6_OP_TEXTURE) << 24)
            | (setup.tile << 8)
            | (effectiveMaxLOD << 11)
            | 1
        textureCommand.w1 = (setup.textureScaleS << 16) | setup.textureScaleT

        var tileCommand = GEGBISourceCommandV6()
        tileCommand.w0 = (UInt32(GE_SOURCE_TEXTURE_COORDINATES_V6_OP_SETTILE) << 24)
            | (format << 21)
            | (size << 19)
            | (line << 9)
            | tmem
        tileCommand.w1 = (setup.tile << 24)
            | (palette << 20)
            | (setup.tileState.addressT.rawValue << 18)
            | (setup.tileState.maskT << 14)
            | (setup.tileState.shiftT << 10)
            | (setup.tileState.addressS.rawValue << 8)
            | (setup.tileState.maskS << 4)
            | setup.tileState.shiftS

        var tileSizeCommand = GEGBISourceCommandV6()
        tileSizeCommand.w0 = (UInt32(GE_SOURCE_TEXTURE_COORDINATES_V6_OP_SETTILESIZE) << 24)
            | (bounds.ulsQ2 << 12)
            | bounds.ultQ2
        tileSizeCommand.w1 = (setup.tile << 24)
            | (bounds.lrsQ2 << 12)
            | bounds.lrtQ2
        return (textureCommand, tileCommand, tileSizeCommand)
    }

    private static func loweredDrawFlags(
        for rawMode: UInt32,
        coverageSave: Bool = false
    ) -> (flags: UInt32, gap: String?) {
        if rawMode == 0 { return (UInt32(GE_SOURCE_DRAW_V6_FLAG_OPAQUE), nil) }
        // Rareware's G_RM_PASS/G_RM_OPA_SURF2 pair carries FORCE_BLEND in
        // the raw RDP word, but its source PASS blender writes the fragment
        // directly.  Preserve that authored opaque equation at the draw
        // boundary so Metal's disabled blend state agrees with every LOD
        // material state.
        if rawMode == 0x0f0a_4000 {
            return (UInt32(GE_SOURCE_DRAW_V6_FLAG_OPAQUE), nil)
        }
        let zMode = (rawMode >> 10) & 3
        let forceBlend = (rawMode >> 14) & 1
        switch (zMode, forceBlend) {
        case (0, 0): return (UInt32(GE_SOURCE_DRAW_V6_FLAG_OPAQUE), nil)
        // AA_OPA_StanFOG_2 (the Gunbarrel secondary mode) uses the
        // force-blend path with coverage WRAP rather than COVERAGE_SAVE.  It
        // is still a source translucent pass; requiring SAVE here rejected
        // the exact 0xc41041c8 mode even though no unsupported blend feature
        // was present.
        case (0, 1):
            return (UInt32(GE_SOURCE_DRAW_V6_FLAG_TRANSLUCENT), nil)
        // Source Type-4 translucent secondary passes may use ZMODE_XLU with
        // force-blend (the guarded cast/stage mode 0xc41049d8). The Metal
        // draw contract already carries depth test/write independently from
        // blend classification, so this is the same translucent lowering as
        // the AA opaque-fog secondary variant above.
        case (2, 1):
            return (UInt32(GE_SOURCE_DRAW_V6_FLAG_TRANSLUCENT), nil)
        case (3, 0): return (UInt32(GE_SOURCE_DRAW_V6_FLAG_DECAL), nil)
        case (3, 1): return (UInt32(GE_SOURCE_DRAW_V6_FLAG_TRANSLUCENT), nil)
        default: return (0, "source render mode 0x\(String(rawMode, radix: 16)) is not representable by V6 blend flags")
        }
    }

    private static func makeTransforms(
        matrices: [GoldenEyeGBIMatrixResourceV6],
        viewports: [GoldenEyeGBIViewportResourceV6],
        matrixKinds: [UInt32: Set<UInt32>],
        viewportHandle: UInt32
    ) throws -> [GESourceTransformV6] {
        var output: [GESourceTransformV6] = []
        for matrix in matrices {
            guard let kinds = matrixKinds[matrix.handle] else {
                // An unreferenced provider matrix has no source role at this
                // bridge.  Do not guess modelview/projection from its handle;
                // the production matrix lane owns explicit role assignment.
                continue
            }
            if kinds.contains(UInt32(GE_SOURCE_TRANSFORM_V6_MODELVIEW)) {
                var value = makeMatrixTransform(matrix, kind: UInt32(GE_SOURCE_TRANSFORM_V6_MODELVIEW), handle: transformModelPrefix | (matrix.handle & 0x00ff_ffff), viewportID: viewportHandle)
                try validateTransform(&value)
                output.append(value)
            }
            if kinds.contains(UInt32(GE_SOURCE_TRANSFORM_V6_PROJECTION)) {
                var value = makeMatrixTransform(matrix, kind: UInt32(GE_SOURCE_TRANSFORM_V6_PROJECTION), handle: transformProjectionPrefix | (matrix.handle & 0x00ff_ffff), viewportID: viewportHandle)
                try validateTransform(&value)
                output.append(value)
            }
        }
        for viewport in viewports {
            var value = GESourceTransformV6()
            setHeader(&value.header, size: MemoryLayout<GESourceTransformV6>.size)
            value.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
            value.transform_kind = UInt32(GE_SOURCE_TRANSFORM_V6_VIEWPORT)
            value.flags = UInt32(GE_SOURCE_TRANSFORM_V6_FLAG_SOURCE_QUANTIZED)
            value.handle = transformViewportPrefix | (viewport.handle & 0x00ff_ffff)
            value.viewport_id = viewport.handle
            var matrix = Array(repeating: Int32(0), count: 16)
            matrix[0] = viewport.values[0]; matrix[5] = viewport.values[1]; matrix[10] = viewport.values[2]; matrix[15] = viewport.values[3]
            matrix[12] = viewport.values[4]; matrix[13] = viewport.values[5]; matrix[14] = viewport.values[6]
            setInt32Tuple(&value.matrix_q16, values: matrix)
            try validateTransform(&value)
            output.append(value)
        }
        return output
    }

    private static func makeMatrixTransform(
        _ matrix: GoldenEyeGBIMatrixResourceV6,
        kind: UInt32,
        handle: UInt32,
        viewportID: UInt32
    ) -> GESourceTransformV6 {
        var value = GESourceTransformV6()
        setHeader(&value.header, size: MemoryLayout<GESourceTransformV6>.size)
        value.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
        value.transform_kind = kind
        value.flags = UInt32(GE_SOURCE_TRANSFORM_V6_FLAG_SOURCE_QUANTIZED)
        value.handle = handle
        value.viewport_id = viewportID
        setInt32Tuple(&value.matrix_q16, values: matrix.values)
        return value
    }

    private static func makeClipTransform(
        state: GEGBIStateV6,
        matrixKinds: [UInt32: Set<UInt32>],
        matrixByHandle: [UInt32: GoldenEyeGBIMatrixResourceV6],
        viewportByHandle: [UInt32: GoldenEyeGBIViewportResourceV6],
        transformBundle: inout [GESourceTransformV6],
        compositeByKey: inout [ClipKey: (handle: UInt32, transformIndex: Int)],
        combinedClipHandles: inout [UInt32]
    ) throws -> (handle: UInt32, projectionHandle: UInt32, viewportHandle: UInt32) {
        let modelViewHandle = state.modelview_handle
        guard modelViewHandle != 0,
              matrixKinds[modelViewHandle]?.contains(UInt32(GE_SOURCE_TRANSFORM_V6_MODELVIEW)) == true,
              let modelView = matrixByHandle[modelViewHandle] else {
            throw GoldenEyeGBISceneBuilderV6Error.projectionComposition(
                "draw modelview role/resource missing 0x\(String(modelViewHandle, radix: 16))"
            )
        }

        let projectionHandle: UInt32
        if state.projection_handle != 0 {
            guard matrixKinds[state.projection_handle]?.contains(UInt32(GE_SOURCE_TRANSFORM_V6_PROJECTION)) == true else {
                throw GoldenEyeGBISceneBuilderV6Error.matrixRoleMismatch(state.projection_handle)
            }
            projectionHandle = state.projection_handle
        } else {
            let candidates = matrixKinds.keys.filter {
                matrixKinds[$0]?.contains(UInt32(GE_SOURCE_TRANSFORM_V6_PROJECTION)) == true
            }.sorted()
            guard candidates.count == 1, let candidate = candidates.first else {
                throw GoldenEyeGBISceneBuilderV6Error.missingProjectionRole
            }
            projectionHandle = candidate
        }
        guard let projection = matrixByHandle[projectionHandle] else {
            throw GoldenEyeGBISceneBuilderV6Error.missingMatrix(projectionHandle)
        }

        let viewportHandle: UInt32
        if state.viewport_handle != 0 {
            viewportHandle = state.viewport_handle
        } else {
            // Some static frontend display lists rely on the source VI
            // viewport established outside the list.  Accept that only when
            // the provider supplied exactly one explicit viewport resource;
            // never derive one from a handle prefix or guessed dimensions.
            guard viewportByHandle.count == 1, let only = viewportByHandle.keys.first else {
                throw GoldenEyeGBISceneBuilderV6Error.missingViewportRole(state.viewport_handle)
            }
            viewportHandle = only
        }
        guard let viewport = viewportByHandle[viewportHandle] else {
            throw GoldenEyeGBISceneBuilderV6Error.missingViewportRole(viewportHandle)
        }
        let key = ClipKey(
            modelViewHandle: modelViewHandle,
            projectionHandle: projectionHandle,
            viewportHandle: viewportHandle
        )
        if let existing = compositeByKey[key] {
            return (existing.handle, projectionHandle, viewportHandle)
        }

        let inputs: GoldenEyeSourceProjectionClipInputsV6
        do {
            inputs = try GoldenEyeSourceProjectionClipInputsV6(
                modelViewHandle: modelViewHandle,
                projectionHandle: projectionHandle,
                viewportHandle: viewportHandle,
                modelViewQ16: modelView.values,
                projectionQ16: projection.values,
                viewportQ16: viewport.values
            )
        } catch {
            throw GoldenEyeGBISceneBuilderV6Error.projectionComposition(String(describing: error))
        }
        let handle = transformClipPrefix | UInt32(compositeByKey.count + 1)
        let composite: GESourceTransformV6
        do {
            composite = try GoldenEyeSourceProjectionBindingV6.makeTransform(
                handle: handle,
                inputs: inputs
            )
        } catch {
            throw GoldenEyeGBISceneBuilderV6Error.projectionComposition(String(describing: error))
        }
        let index = transformBundle.count
        transformBundle.append(composite)
        compositeByKey[key] = (handle: handle, transformIndex: index)
        combinedClipHandles.append(handle)
        return (handle, projectionHandle, viewportHandle)
    }

    private static func matrixRolesByHandle(
        scene: GESourceSceneV6,
        supplied: [GoldenEyeSourceMatrixRoleSidecarV6],
        matrices: [GoldenEyeGBIMatrixResourceV6]
    ) throws -> [UInt32: Set<UInt32>] {
        let matrixHandles = Set(matrices.map(\.handle))
        var result: [UInt32: Set<UInt32>] = [:]
        if supplied.isEmpty {
            // This is only an explicit role encoded in the source GBI
            // command itself.  No handle-prefix convention is consulted.
            for command in scene.commands where command.macro == "gsSPMatrix" {
                guard command.arguments.count >= 2 else { continue }
                let handle = compact(command.arguments[0])
                let flags = compact(command.arguments[1])
                let kind: UInt32 = flags & 1 != 0
                    ? UInt32(GE_SOURCE_TRANSFORM_V6_PROJECTION)
                    : UInt32(GE_SOURCE_TRANSFORM_V6_MODELVIEW)
                result[handle, default: []].insert(kind)
            }
            return result
        }

        let suppliedMap = try GoldenEyeSourceProjectionBindingV6.roleMap(supplied)
        for role in supplied {
            guard matrixHandles.contains(role.handle) else {
                throw GoldenEyeGBISceneBuilderV6Error.missingMatrix(role.handle)
            }
            if role.roleFlags & GoldenEyeSourceMatrixRoleSidecarV6.modelView != 0 {
                result[role.handle, default: []].insert(UInt32(GE_SOURCE_TRANSFORM_V6_MODELVIEW))
            }
            if role.roleFlags & GoldenEyeSourceMatrixRoleSidecarV6.projection != 0 {
                result[role.handle, default: []].insert(UInt32(GE_SOURCE_TRANSFORM_V6_PROJECTION))
            }
        }
        for command in scene.commands where command.macro == "gsSPMatrix" {
            guard command.arguments.count >= 2 else { continue }
            let handle = compact(command.arguments[0])
            let flags = compact(command.arguments[1])
            let expected: UInt32 = flags & 1 != 0
                ? UInt32(GE_SOURCE_TRANSFORM_V6_PROJECTION)
                : UInt32(GE_SOURCE_TRANSFORM_V6_MODELVIEW)
            guard let suppliedFlags = suppliedMap[handle],
                  (expected == UInt32(GE_SOURCE_TRANSFORM_V6_PROJECTION)
                      ? suppliedFlags & GoldenEyeSourceMatrixRoleSidecarV6.projection != 0
                      : suppliedFlags & GoldenEyeSourceMatrixRoleSidecarV6.modelView != 0) else {
                throw GoldenEyeGBISceneBuilderV6Error.matrixRoleMismatch(handle)
            }
        }
        return result
    }

    private static func matrixRoleSidecars(
        from matrices: [GoldenEyeGBIMatrixResourceV6]
    ) throws -> [GoldenEyeSourceMatrixRoleSidecarV6] {
        var output: [GoldenEyeSourceMatrixRoleSidecarV6] = []
        output.reserveCapacity(matrices.count)
        for matrix in matrices where matrix.roleFlags != 0 {
            output.append(try GoldenEyeSourceMatrixRoleSidecarV6(
                handle: matrix.handle,
                roleFlags: matrix.roleFlags
            ))
        }
        return output
    }

    private static func makeSceneResources(
        model: GoldenEyeSourceModelV6,
        textureByHandle: [UInt32: GoldenEyeSourceModelV6.Texture],
        imageToTexture: [UInt32: UInt32]
    ) throws -> [GESourceResourceV6] {
        var output: [GESourceResourceV6] = []
        var handles = Set<UInt32>()
        var paletteEvidence: [UInt32: (sourceID: UInt32, byteSize: UInt32, contentHash: UInt64, provenanceHash: UInt64)] = [:]
        var paletteHandleByIdentity: [String: UInt32] = [:]
        var modelResource = GESourceResourceV6()
        setHeader(&modelResource.header, size: MemoryLayout<GESourceResourceV6>.size)
        modelResource.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
        modelResource.resource_kind = UInt32(GE_SOURCE_RESOURCE_V6_MODEL)
        modelResource.flags = UInt32(GE_SOURCE_RESOURCE_V6_FLAG_RESIDENT) | UInt32(GE_SOURCE_RESOURCE_V6_FLAG_SOURCE_ORDERED)
        modelResource.handle = modelResourcePrefix | (model.header.modelHandle & 0x00ff_ffff)
        modelResource.source_id = model.header.modelHandle
        modelResource.format = UInt32(GE_SOURCE_RESOURCE_V6_FORMAT_NONE)
        modelResource.width = 1; modelResource.height = 1; modelResource.depth = 1
        modelResource.mip_count = 1; modelResource.level_count = 1
        modelResource.byte_size = UInt32(model.header.totalBytes)
        modelResource.content_hash = digestPrefix(model.header.packetHash)
        modelResource.provenance_hash = digestPrefix(model.header.sourceHash)
        try validateResource(&modelResource)
        output.append(modelResource); handles.insert(modelResource.handle)

        let usedTextures = Set(imageToTexture.values)
        for handle in usedTextures.sorted() {
            guard let texture = textureByHandle[handle] else { throw GoldenEyeGBISceneBuilderV6Error.missingTexture(handle) }
            let format = try semanticFormat(texture)
            guard format != UInt32(GE_SOURCE_RESOURCE_V6_FORMAT_NONE) else {
                throw GoldenEyeGBISceneBuilderV6Error.invalidSourceTexture(handle)
            }
            var value = GESourceResourceV6()
            setHeader(&value.header, size: MemoryLayout<GESourceResourceV6>.size)
            value.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
            value.resource_kind = UInt32(GE_SOURCE_RESOURCE_V6_TEXTURE)
            value.flags = UInt32(GE_SOURCE_RESOURCE_V6_FLAG_RESIDENT) | UInt32(GE_SOURCE_RESOURCE_V6_FLAG_SOURCE_ORDERED)
            if texture.mipCount > 1 { value.flags |= UInt32(GE_SOURCE_RESOURCE_V6_FLAG_MIP_CHAIN) }
            value.handle = texture.resourceHandle
            value.source_id = texture.sourceRowHandle
            value.format = format
            value.width = texture.width; value.height = texture.height; value.depth = 1
            value.mip_count = max(1, texture.mipCount); value.level_count = max(1, texture.mipCount)
            value.byte_size = texture.sourceSpan
            value.content_hash = hashTexture(texture)
            value.provenance_hash = UInt64(texture.sourceRowHandle) << 32 | UInt64(texture.sourceSpan)
            guard handles.insert(value.handle).inserted else { throw GoldenEyeGBISceneBuilderV6Error.duplicateHandle("resource", value.handle) }
            try validateResource(&value)
            output.append(value)
            if texture.tlutIndex != GoldenEyeSourceModelV6.nullHandle,
               Int(texture.tlutIndex) < model.tluts.count {
                let tlut = model.tluts[Int(texture.tlutIndex)]
                var palette = GESourceResourceV6()
                setHeader(&palette.header, size: MemoryLayout<GESourceResourceV6>.size)
                palette.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
                palette.resource_kind = UInt32(GE_SOURCE_RESOURCE_V6_PALETTE)
                palette.flags = UInt32(GE_SOURCE_RESOURCE_V6_FLAG_RESIDENT) | UInt32(GE_SOURCE_RESOURCE_V6_FLAG_PALETTE) | UInt32(GE_SOURCE_RESOURCE_V6_FLAG_SOURCE_ORDERED)
                palette.source_id = tlut.sourceRowHandle
                palette.format = UInt32(GE_SOURCE_RESOURCE_V6_FORMAT_RGBA16)
                palette.width = max(1, tlut.rawByteCount / 2); palette.height = 1; palette.depth = 1
                palette.mip_count = 1; palette.level_count = 1; palette.byte_size = tlut.rawByteCount
                palette.content_hash = UInt64(tlut.payloadRecordID) << 32 | UInt64(tlut.rawByteCount)
                palette.provenance_hash = UInt64(tlut.sourceRowHandle) << 32 | UInt64(tlut.sourceRecordID)
                let paletteIdentity = "\(palette.source_id):\(tlut.sourceRecordID)"
                if let existingHandle = paletteHandleByIdentity[paletteIdentity] {
                    palette.handle = existingHandle
                } else {
                    // The strict scene adapter derives the palette resource
                    // from the sampled texture handle, not the TLUT source
                    // row.  Keep this namespace deterministic across every
                    // repeated Wallet instance and preserve the low 24-bit
                    // texture identity required at each draw boundary.
                    let suffix = texture.resourceHandle & 0x00ff_ffff
                    var prefix = palettePrefix & 0xff00_0000
                    var candidate = prefix | suffix
                    while handles.contains(candidate) || paletteEvidence[candidate] != nil {
                        prefix &+= 0x0100_0000
                        guard prefix != 0 else {
                            throw GoldenEyeGBISceneBuilderV6Error.packetCapacity("palette handle namespace")
                        }
                        candidate = prefix | suffix
                    }
                    palette.handle = candidate
                    paletteHandleByIdentity[paletteIdentity] = candidate
                }
                if let existing = paletteEvidence[palette.handle] {
                    // Several PP7 materials can reference the same source TLUT
                    // while their texture handles alias to one palette handle.
                    // Reuse only when the copied provenance is identical; a
                    // real collision remains a fail-closed resource error.
                    guard existing.sourceID == palette.source_id,
                          existing.byteSize == palette.byte_size,
                          existing.contentHash == palette.content_hash,
                          existing.provenanceHash == palette.provenance_hash else {
                        throw GoldenEyeGBISceneBuilderV6Error.duplicateHandle(
                            "palette collision source=0x\(String(existing.sourceID, radix: 16))/\(existing.byteSize)/0x\(String(existing.contentHash, radix: 16))/0x\(String(existing.provenanceHash, radix: 16)) new=0x\(String(palette.source_id, radix: 16))/\(palette.byte_size)/0x\(String(palette.content_hash, radix: 16))/0x\(String(palette.provenance_hash, radix: 16))",
                            palette.handle
                        )
                    }
                } else {
                    guard handles.insert(palette.handle).inserted else {
                        throw GoldenEyeGBISceneBuilderV6Error.duplicateHandle("palette", palette.handle)
                    }
                    try validateResource(&palette)
                    output.append(palette)
                    paletteEvidence[palette.handle] = (
                        sourceID: palette.source_id,
                        byteSize: palette.byte_size,
                        contentHash: palette.content_hash,
                        provenanceHash: palette.provenance_hash
                    )
                }
            }
        }
        return output
    }

    private static func semanticFormat(_ texture: GoldenEyeSourceModelV6.Texture) throws -> UInt32 {
        switch texture.depth {
        case 0: return UInt32(GE_SOURCE_RESOURCE_V6_FORMAT_I4)
        case 1: return UInt32(GE_SOURCE_RESOURCE_V6_FORMAT_I8)
        case 2: return UInt32(GE_SOURCE_RESOURCE_V6_FORMAT_RGBA16)
        case 3: return UInt32(GE_SOURCE_RESOURCE_V6_FORMAT_RGBA32)
        default: throw GoldenEyeGBISceneBuilderV6Error.unknownImageFormat(texture.resourceHandle)
        }
    }

    private static func sourceVertex(_ source: GoldenEyeSourceModelV6.Vertex) throws -> GEVertexV1 {
        let x = signedSource16(source.x)
        let y = signedSource16(source.y)
        let z = signedSource16(source.z)
        let s = signedSource16(source.s)
        let t = signedSource16(source.t)
        guard x >= Int32(Int16.min), x <= Int32(Int16.max),
              y >= Int32(Int16.min), y <= Int32(Int16.max),
              z >= Int32(Int16.min), z <= Int32(Int16.max),
              s >= Int32(Int16.min), s <= Int32(Int16.max),
              t >= Int32(Int16.min), t <= Int32(Int16.max) else {
            throw GoldenEyeGBISceneBuilderV6Error.invalidSourceVertex(source.id)
        }
        var value = GEVertexV1()
        value.x = Int16(x)
        value.y = Int16(y)
        value.z = Int16(z)
        value.s = Int16(s)
        value.t = Int16(t)
        value.r = source.r; value.g = source.g; value.b = source.b; value.a = source.a
        value.reserved0 = 0; value.reserved1 = 0
        return value
    }

    private static func makeSceneVertex(_ source: GoldenEyeSourceModelV6.Vertex, handle: UInt32) -> GESourceVertexV6 {
        let x = signedSource16(source.x)
        let y = signedSource16(source.y)
        let z = signedSource16(source.z)
        let s = signedSource16(source.s)
        let t = signedSource16(source.t)
        var value = GESourceVertexV6()
        setHeader(&value.header, size: MemoryLayout<GESourceVertexV6>.size)
        value.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
        value.handle = handle
        value.flags = UInt32(GE_SOURCE_VERTEX_V6_FLAG_SOURCE_QUANTIZED) | UInt32(GE_SOURCE_VERTEX_V6_FLAG_INTERPOLATABLE)
        value.position_q16.0 = x << 16; value.position_q16.1 = y << 16; value.position_q16.2 = z << 16
        value.texcoord_q16.0 = s << 8; value.texcoord_q16.1 = t << 8
        value.normal_q16.0 = Int32(Int8(bitPattern: source.nx)) << 9
        value.normal_q16.1 = Int32(Int8(bitPattern: source.ny)) << 9
        value.normal_q16.2 = Int32(Int8(bitPattern: source.nz)) << 9
        value.color_rgba = UInt32(source.r) << 24 | UInt32(source.g) << 16 | UInt32(source.b) << 8 | UInt32(source.a)
        value.source_index = source.id
        return value
    }

    private static func signedSource16(_ value: Int32) -> Int32 {
        if value >= 0, value <= Int32(UInt16.max), value > Int32(Int16.max) {
            return value - 65_536
        }
        return value
    }

    private static func makeSceneIndex(handle: UInt32, vertex0: UInt32, vertex1: UInt32, vertex2: UInt32, sourceIndex: UInt32) -> GESourceIndexV6 {
        var value = GESourceIndexV6()
        setHeader(&value.header, size: MemoryLayout<GESourceIndexV6>.size)
        value.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
        value.handle = handle
        value.flags = UInt32(GE_SOURCE_INDEX_V6_FLAG_SOURCE_ORDERED)
        value.vertex0 = vertex0; value.vertex1 = vertex1; value.vertex2 = vertex2; value.source_index = sourceIndex
        return value
    }

    private static func makeDiagnostic(error: Error, sourceID: UInt32, commandID: UInt32) -> GESourceDiagnosticV6 {
        var value = GESourceDiagnosticV6()
        setHeader(&value.header, size: MemoryLayout<GESourceDiagnosticV6>.size)
        value.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
        value.diagnostic_kind = UInt32(GE_SOURCE_DIAGNOSTIC_V6_UNSUPPORTED_COMMAND)
        value.severity = UInt32(GE_SOURCE_DIAGNOSTIC_V6_SEVERITY_ERROR)
        value.code = UInt32(GE_SOURCE_DIAGNOSTIC_V6_UNSUPPORTED_COMMAND)
        value.source_id = sourceID
        value.command_id = commandID
        value.detail_hash = hashString(String(describing: error))
        return value
    }

    private static func hashRecords(model: GoldenEyeSourceModelV6, eventHash: UInt64, stateHash: UInt64, transforms: [GESourceTransformV6], vertices: [GESourceVertexV6], indices: [GESourceIndexV6], states: [GESourceRenderStateV6], draws: [GESourceDrawCommandV6]) -> UInt64 {
        var hash = UInt64(1_469_598_103_934_665_603)
        hash ^= digestPrefix(model.header.packetHash); hash &*= 1_099_511_628_211
        hash ^= eventHash; hash &*= 1_099_511_628_211
        hash ^= stateHash; hash &*= 1_099_511_628_211
        for value in transforms { hash = hashRecordBytes(hash, value) }
        for value in vertices { hash = hashRecordBytes(hash, value) }
        for value in indices { hash = hashRecordBytes(hash, value) }
        for value in states { hash = hashRecordBytes(hash, value) }
        for value in draws { hash = hashRecordBytes(hash, value) }
        return hash == 0 ? 1 : hash
    }

    private static func hashDrawRecords(_ draws: [GESourceDrawCommandV6]) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for draw in draws { hash = hashRecordBytes(hash, draw) }
        return hash == 0 ? 1 : hash
    }

    private static func hashDraw(group: DrawGroup, state: GESourceRenderStateV6) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for value in [UInt32(group.stateIndex), group.textureHandle, UInt32(group.firstVertex), UInt32(group.firstIndex), state.state_handle, state.raw_othermode_h, state.raw_othermode_l] {
            hash ^= UInt64(value); hash &*= 1_099_511_628_211
        }
        for value in group.sourceOffsets { hash ^= UInt64(value); hash &*= 1_099_511_628_211 }
        return hash
    }

    private static func hashTexture(_ texture: GoldenEyeSourceModelV6.Texture) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for value in [texture.resourceHandle, texture.width, texture.height, texture.mipMapTiles, texture.type, texture.depth, texture.sFlags, texture.tFlags, texture.payloadRecordID, texture.sourceRowHandle, texture.sourceSpan] {
            hash ^= UInt64(value); hash &*= 1_099_511_628_211
        }
        return hash == 0 ? 1 : hash
    }

    private static func hashTextureSetups(
        _ setups: [GoldenEyeSourceTextureSetupV6]
    ) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for setup in setups.sorted(by: {
            if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
            if $0.resourceHandle != $1.resourceHandle { return $0.resourceHandle < $1.resourceHandle }
            return $0.tile < $1.tile
        }) {
            hash ^= setup.setupHash
            hash &*= 1_099_511_628_211
        }
        return setups.isEmpty ? 0 : (hash == 0 ? 1 : hash)
    }

    private static func hashString(_ value: String) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in value.utf8 { hash ^= UInt64(byte); hash &*= 1_099_511_628_211 }
        return hash == 0 ? 1 : hash
    }

    private static func hashRecordBytes<T>(_ seed: UInt64, _ value: T) -> UInt64 {
        var hash = seed
        withUnsafeBytes(of: value) { bytes in
            for byte in bytes { hash ^= UInt64(byte); hash &*= 1_099_511_628_211 }
        }
        return hash
    }

    private static func digestPrefix(_ digest: [UInt8]) -> UInt64 {
        digest.prefix(8).enumerated().reduce(UInt64(0)) { partial, pair in partial | UInt64(pair.element) << UInt64(pair.offset * 8) }
    }

    private static func compact(_ value: GoldenEyeSourceModelV6.TokenValue) -> UInt32 {
        switch value {
        case .integer(let value): return UInt32(truncatingIfNeeded: value)
        case .constant(_, let value): return value
        case .handle(_, let value): return value
        case .null: return GoldenEyeSourceModelV6.nullHandle
        case .boolean(let value): return value ? 1 : 0
        }
    }

    private static func drawHandle(_ index: Int) -> UInt32 { drawPrefix | UInt32(index + 1) }
    private static func stateHandle(_ index: UInt32) -> UInt32 { statePrefix | (index + 1) }
    private static func vertexHandle(_ index: Int) -> UInt32 { vertexPrefix | UInt32(index + 1) }
    private static func indexHandle(_ index: Int) -> UInt32 { indexPrefix | UInt32(index + 1) }

    private static func vertexLoadHandle(displayListID: UInt32, ordinal: UInt32) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        hash ^= displayListID; hash &*= 16_777_619
        hash ^= ordinal; hash &*= 16_777_619
        let value = hash & 0x00ff_ffff
        return vertexLoadPrefix | (value == 0 ? 1 : value)
    }

    private static func transformHandle(for sourceHandle: UInt32) -> UInt32 {
        guard sourceHandle != 0 else { return 0 }
        return transformModelPrefix | (sourceHandle & 0x00ff_ffff)
    }

    private static func setHeader(_ header: inout GEAbiHeaderV1, size: Int) {
        header.abi_version = UInt32(GE_NATIVE_ABI_VERSION)
        header.struct_size = UInt32(size)
    }

    private static func setInt32Tuple<T>(_ tuple: inout T, values: [Int32]) {
        withUnsafeMutableBytes(of: &tuple) { raw in
            let typed = raw.bindMemory(to: Int32.self)
            for index in values.indices where index < typed.count { typed[index] = values[index] }
        }
    }

    private static func writeFixedArray<Container, Element>(_ destination: inout Container, values: [Element]) throws {
        var capacity = 0
        withUnsafeMutableBytes(of: &destination) { raw in
            capacity = raw.count / MemoryLayout<Element>.stride
            let typed = raw.bindMemory(to: Element.self)
            for index in values.indices where index < capacity { typed[index] = values[index] }
        }
        guard values.count <= capacity else {
            throw GoldenEyeGBISceneBuilderV6Error.packetCapacity("fixed array count=\(values.count) capacity=\(capacity)")
        }
    }

    private static func readPointerArray<Container, Element>(
        _ pointer: UnsafeMutablePointer<Container>,
        fieldOffset: Int,
        count: Int,
        as: Element.Type
    ) -> [Element] {
        guard count > 0 else { return [] }
        let base = UnsafeRawPointer(pointer).advanced(by: fieldOffset)
        let typed = base.bindMemory(to: Element.self, capacity: count)
        return Array(UnsafeBufferPointer(start: typed, count: count))
    }

    private static func readPointerElement<Container, Element>(
        _ pointer: UnsafeMutablePointer<Container>,
        fieldOffset: Int,
        index: Int,
        as: Element.Type
    ) -> Element {
        precondition(index >= 0)
        let offset = fieldOffset + index * MemoryLayout<Element>.stride
        return UnsafeRawPointer(pointer).load(fromByteOffset: offset, as: Element.self)
    }

    private static func sourceCommandWordHash(_ scene: GESourceSceneV6) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for command in scene.commands {
            hash ^= UInt64(command.word0); hash &*= 1_099_511_628_211
            hash ^= UInt64(command.word1); hash &*= 1_099_511_628_211
        }
        return hash == 0 ? 1 : hash
    }

    private static func packetCommandWordHash(
        _ pointer: UnsafeMutablePointer<GEGBISourcePacketV6>
    ) -> UInt64 {
        let commands = readPointerArray(
            pointer,
            fieldOffset: MemoryLayout<GEGBISourcePacketV6>.offset(of: \.commands)!,
            count: Int(pointer.pointee.command_count),
            as: GEGBISourceCommandV6.self
        )
        var hash: UInt64 = 1_469_598_103_934_665_603
        for command in commands {
            hash ^= UInt64(command.w0); hash &*= 1_099_511_628_211
            hash ^= UInt64(command.w1); hash &*= 1_099_511_628_211
        }
        return hash == 0 ? 1 : hash
    }

    private static func packetSourceCommandWordHash(
        _ pointer: UnsafeMutablePointer<GEGBISourcePacketV6>
    ) -> UInt64 {
        let lists = readPointerArray(
            pointer,
            fieldOffset: MemoryLayout<GEGBISourcePacketV6>.offset(of: \.lists)!,
            count: Int(pointer.pointee.list_count),
            as: GEGBISourceListV6.self
        )
        let commands = readPointerArray(
            pointer,
            fieldOffset: MemoryLayout<GEGBISourcePacketV6>.offset(of: \.commands)!,
            count: Int(pointer.pointee.command_count),
            as: GEGBISourceCommandV6.self
        )
        var hash: UInt64 = 1_469_598_103_934_665_603
        for list in lists.dropFirst() {
            let first = Int(list.first_command)
            let end = first + Int(list.command_count)
            guard first >= 0, end <= commands.count else { return 0 }
            for command in commands[first..<end] {
                hash ^= UInt64(command.w0); hash &*= 1_099_511_628_211
                hash ^= UInt64(command.w1); hash &*= 1_099_511_628_211
            }
        }
        return hash == 0 ? 1 : hash
    }

    private static func validateResource(_ value: inout GESourceResourceV6) throws {
        guard ge_source_scene_v6_validate_resource(&value) == GE_STATUS_OK else { throw GoldenEyeGBISceneBuilderV6Error.sceneValidation("resource \(value.handle)") }
    }
    private static func validateTransform(_ value: inout GESourceTransformV6) throws {
        guard ge_source_scene_v6_validate_transform(&value) == GE_STATUS_OK else { throw GoldenEyeGBISceneBuilderV6Error.sceneValidation("transform \(value.handle)") }
    }
    private static func validateVertex(_ value: inout GESourceVertexV6) throws {
        guard ge_source_scene_v6_validate_vertex(&value) == GE_STATUS_OK else { throw GoldenEyeGBISceneBuilderV6Error.sceneValidation("vertex \(value.handle)") }
    }
    private static func validateIndex(_ value: inout GESourceIndexV6) throws {
        guard ge_source_scene_v6_validate_index(&value) == GE_STATUS_OK else { throw GoldenEyeGBISceneBuilderV6Error.sceneValidation("index \(value.handle)") }
    }
    private static func validateRenderState(_ value: inout GESourceRenderStateV6) throws {
        guard ge_source_scene_v6_validate_render_state(&value) == GE_STATUS_OK else { throw GoldenEyeGBISceneBuilderV6Error.sceneValidation("state \(value.state_handle)") }
    }
    private static func validateDraw(_ value: inout GESourceDrawCommandV6) throws {
        guard ge_source_scene_v6_validate_draw_command(&value) == GE_STATUS_OK else { throw GoldenEyeGBISceneBuilderV6Error.sceneValidation("draw \(value.draw_handle)") }
    }

    private static func packBlender(_ raw: UInt32, shift0: UInt32, shift1: UInt32) -> UInt32 {
        ((raw >> shift0) & 3) | (((raw >> shift1) & 3) << 2)
    }
}
