import Foundation
import Metal
import QuartzCore
#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

enum GoldenEyeSourceProductRendererV6Error: Error, Sendable, Equatable, CustomStringConvertible {
    case missingPreparedRoot
    case missingAudioAssetRoot
    case missingPipelineLibrary
    case missing2DPipelineLibrary
    case metal4Unavailable
    case missingFrameResources
    case unsupportedScreen(UInt32)
    case unsupportedSourceFrame(UInt32)
    case staleSourceFrame(UInt32, expected: UInt32)
    case projectionNotConsumed(GoldenEyeGBIProjectionConsumptionEvidenceV6)
    case noSubmittedFrame
    case sourceBuild(String)
    case renderFailure(String)
    case shutdownFailure(String)

    var description: String {
        switch self {
        case .missingPreparedRoot: return "source product prepared root is missing"
        case .missingAudioAssetRoot: return "source product audio asset root is missing"
        case .missingPipelineLibrary: return "source product source-scene metallib is missing"
        case .missing2DPipelineLibrary: return "source product source-2d metallib is missing"
        case .metal4Unavailable: return "Metal 4 source product renderer is unavailable"
        case .missingFrameResources: return "source product frame matrices/viewports are missing"
        case .unsupportedScreen(let screen): return "source product screen is not statically lowerable: \(screen)"
        case .unsupportedSourceFrame(let count): return "source product frame has \(count) unsupported source event(s)"
        case .staleSourceFrame(let actual, let expected):
            return "source product frame screen \(actual) does not match submitted screen \(expected)"
        case .projectionNotConsumed(let evidence):
            return "source product projection/clip transform was not consumed: "
                + "projection=0x\(String(evidence.sourceProjectionHandle, radix: 16)) "
                + "viewport=0x\(String(evidence.sourceViewportHandle, radix: 16)) "
                + "emittedProjection=\(evidence.emittedProjectionTransformCount) "
                + "emittedViewport=\(evidence.emittedViewportTransformCount) "
                + "combined=0x\(String(evidence.combinedClipTransformHandle, radix: 16)) "
                + "draws=\(evidence.consumedDrawCount)/\(evidence.requiredDrawCount)"
        case .noSubmittedFrame: return "source product renderer has no submitted source frame"
        case .sourceBuild(let detail): return "source product scene build failed: \(detail)"
        case .renderFailure(let detail): return "source product scene render failed: \(detail)"
        case .shutdownFailure(let detail): return "source product renderer shutdown failed: \(detail)"
        }
    }
}

private func makeGunbarrelAttachmentPoseV6(modelHandle: UInt32) -> GESourceAnimationPoseV6 {
    var value = GESourceAnimationPoseV6()
    value.header.abi_version = GE_NATIVE_ABI_VERSION
    value.header.struct_size = UInt32(MemoryLayout<GESourceAnimationPoseV6>.size)
    value.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
    value.pose_handle = 0xDA00_0000 | (modelHandle & 0xff)
    value.skeleton_handle = 0xDA01_0000 | (modelHandle & 0xff)
    value.node_handle = 0xD700_0001
    value.parent_handle = 0
    value.flags = UInt32(GE_SOURCE_POSE_V6_FLAG_INTERPOLATABLE)
    value.animation_tick = 0
    value.translation_q16 = (0, 0, 0)
    value.rotation_q16 = (0, 0, 0, 65_536)
    value.scale_q16 = (65_536, 65_536, 65_536)
    value.pose_hash = UInt64(value.pose_handle)
    return value
}

private func gunbarrelMatrixQ16V6(_ transform: GESourceTransformV6) -> [Int32] {
    withUnsafeBytes(of: transform.matrix_q16) {
        Array($0.bindMemory(to: Int32.self).prefix(16))
    }
}

/// Renderer-owned handoff for a copied gameplay-camera frame.  The owner may
/// submit only value records; the renderer resolves the guarded scene and
/// publishes a presentable scoped composition after the adapter's full-scene
/// and category checks succeed.
@available(macOS 26.0, *)
protocol GoldenEyeStageGameplayCameraFrameRendererV7: AnyObject {
    func submit(
        stageGameplayCameraSnapshot snapshot: GoldenEyeStageGameplayCameraSnapshotV7
    ) throws
}

/// Product-level adapter for the source-derived V6 path.
///
/// The adapter has one deliberately narrow responsibility: load the guarded
/// GEFV/GESM root, upload the validated RGBA8 texture plan and source 2D
/// payloads, build a source scene from the classic GE/F3D packet, and submit
/// the immutable 3D+2D frame to the supplied CAMetalDisplayLink drawable. It
/// never acquires a drawable, reads a ROM, manufactures geometry/text, or
/// selects a procedural fallback.
@available(macOS 26.0, *)
final class GoldenEyeSourceProductRendererV6: GoldenEyeFrameRenderer,
    GoldenEyeTitleSnapshotRenderer,
    GoldenEyeSourceFrontendFrameRendererV6,
    GoldenEyeSourceFrontendModelResultProviderV6,
    GoldenEyeSourceFrontendModelLifecycleV6,
    GoldenEyeStageSourceEnvironmentFrameRendererV6,
    GoldenEyeStageSourceMaterialFrameRendererV6,
    GoldenEyeStageGameplayCameraFrameRendererV7,
    GoldenEyeCastSourceSceneFrameRendererV6,
    GoldenEyeDrawableFrameRenderer,
    @unchecked Sendable
{
    private static let modelForScreen: [UInt32: String] = [
        UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_LEGAL): "legalpage",
        UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_NINTENDO): "nintendologo",
        UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_RAREWARE): "rarewarelogo",
        UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL): "gunbarrel",
        UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GOLDENEYE): "goldeneyelogo",
        UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_FILE_SELECT): "walletbond",
        UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_MODE_SELECT): "walletbond",
    ]

    private static let modelNameForID: [UInt32: String] = [
        UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_LEGALPAGE): "legalpage",
        UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_NINTENDOLOGO): "nintendologo",
        UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RAREWARELOGO): "rarewarelogo",
        UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GUNBARREL): "gunbarrel",
        UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GOLDENEYELOGO): "goldeneyelogo",
        UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_WALLETBOND): "walletbond",
    ]

    private static func loadGunbarrelSidecar(root: URL) throws -> GoldenEyeGunbarrelDynamicSidecarV6? {
        let candidates: [URL]
        if let value = ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_GUNBARREL_SIDECAR"], !value.isEmpty {
            candidates = [URL(fileURLWithPath: value, isDirectory: false)]
        } else {
            candidates = [
                root.appendingPathComponent("gunbarrel.gbar", isDirectory: false),
                root.appendingPathComponent("title/gunbarrel.gbar", isDirectory: false),
            ]
        }
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            return try GoldenEyeGunbarrelDynamicSidecarV6(loading: candidate)
        }
        return nil
    }

    private static func castAnimationClipName(_ animationID: UInt32) throws -> String {
        let names: [UInt32: String] = [
            63: "spotting_bond",
            66: "fire_standing_draw_one_handed_weapon_fast",
            67: "fire_standing_draw_one_handed_weapon_slow",
            72: "fire_step_right_one_handed_weapon",
            76: "fire_kneel_forward_one_handed_weapon_fast",
            89: "running_one_handed_weapon",
            98: "draw_one_handed_weapon_and_stand_up",
            99: "aim_one_handed_weapon_left_right",
            100: "cock_one_handed_weapon_and_turn_around",
            102: "cock_one_handed_weapon_turn_around_and_stand_up",
            103: "draw_one_handed_weapon_and_turn_around",
            153: "drop_weapon_and_show_fight_stance",
            163: "laughing_in_disbelief",
            70: "fire_hip_forward_one_handed_weapon",
            74: "fire_standing_left_one_handed_weapon_fast",
            80: "fire_kneel_left_one_handed_weapon_fast",
            97: "draw_one_handed_weapon_and_look_around",
            150: "aim_one_handed_weapon_left",
            151: "aim_one_handed_weapon_right",
            152: "conversation",
            161: "conversation_listener",
            160: "conversation_cleaned",
        ]
        guard let value = names[animationID] else {
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                "Cast animation (animationID) has no prepared source clip"
            )
        }
        return value
    }

    private let preparation: GoldenEyeSourceProductPreparationV6
    /// Optional extended Cast root.  Title assets stay sourced from the
    /// canonical eight-model root; Cast models/textures are merged only when
    /// the caller explicitly supplies the guarded extended root.
    private let castPreparation: GoldenEyeCastPreparedAssetCatalogV6?
    private let stageTextureCatalog: GoldenEyeStageTextureCatalogV6?
    private let stageSetupDependencyCatalog: GoldenEyeStageSetupDependencyCatalogV6?
    private let stageModelSidecarCatalog: GoldenEyeStageModelSidecarCatalogV6?
    private let visibleDependencyCatalog: GoldenEyeRamRomVisibleDependencyCatalogV6?
    private let gunbarrelSidecar: GoldenEyeGunbarrelDynamicSidecarV6?
    private let textureStore: GoldenEyeSourceTextureStoreV6
    private let textureBindingAdapter: GoldenEyeSourceSceneTextureBindingAdapterV6
    private let renderer: GoldenEyeSourceSceneRendererV6
    private let gunbarrelPassRenderer: GoldenEyeGunbarrelPassRendererV6?
    private let source2DRenderer: GoldenEyeSource2DMetalRendererV6
    private let source2DLowerer: GoldenEyeSource2DLowererV6
    private let frameResourceProvider: GoldenEyeSourceProductFrameResourceProviderV6?
    private let outputMode: GoldenEyeFidelityOutputMode
    private let presentationTreatment: GoldenEyeSourceScenePresentationTreatmentV6
    private let state: GoldenEyeMetalDeviceState
    private let stageAssetRootURL: URL?
    /// Owner submissions and the display-link callback share the immutable
    /// scene slots below. Keep publication/read atomic so a renderer cannot
    /// observe the intentional pre-build invalidation window as a missing
    /// frame while a complete replacement is being lowered.
    private let frameStateLock = NSLock()
    /// Serializes Metal encoding/presentation while allowing the owner to
    /// publish the next immutable scene without waiting for a drawable's GPU
    /// work. The publication lock is held only while copying this state.
    private let renderLock = NSLock()
    /// Stage packet loading can happen on the bounded V7 submission queue
    /// while the display-link callback renders the last published frame.
    private let stageScenePacketCacheLock = NSLock()
    private var latestTitleSnapshot: GoldenEyeTitleSnapshot?
    private var latestSourceFrame: GoldenEyeSourceFrontendFrameV6?
    private var latestSource2DFrame: GoldenEyeSource2DFrameV6?
    private var latestSource2DBackgroundFrame: GoldenEyeSource2DFrameV6?
    private var latestScene: GoldenEyeSourceSceneSnapshotV6?
    private var latestStageScene: GoldenEyeSourceSceneSnapshotV6?
    private var latestStagePacketHash: UInt64 = 0
    private var latestStageUnsupportedMask: UInt32 = 0
    private var latestStageMaterialHash: UInt64 = 0
    private var latestStageMaterialStateCount: UInt32 = 0
    private var latestStageTexturePending: UInt32 = 0
    private var latestStageComposition: GoldenEyeStageModelSceneCompositionV6.Result?
    private var latestStageGameplayCameraPacketHash: UInt64 = 0
    private var latestStageGameplayCameraSubsetHash: UInt64 = 0
    private var latestStageFullSceneUnsupportedMask: UInt32 = 0
    private var latestStageFrameResources: GoldenEyeSourceProductFrameResourcesV6?
    private var stageScenePacketCache: [UInt32: GoldenEyeStageScenePacket] = [:]
    /// A stage packet/material hash identifies the immutable room+prop
    /// topology. RAMROM emits the same prepared packet across many native
    /// ticks, so retain the validated composition and reframe only its tick /
    /// lighting metadata instead of rebuilding every prop on the owner.
    private struct StageCompositionCacheKey: Hashable {
        let stageID: UInt32
        let environmentHash: UInt64
        let materialHash: UInt64
    }
    private var stageCompositionCache:
        [StageCompositionCacheKey: GoldenEyeStageModelSceneCompositionV6.Result] = [:]
    /// Monotonic publication generation for asynchronous V7 builds. Every
    /// route replacement or shutdown advances it while holding
    /// `frameStateLock`; an older composition may never overwrite a newer
    /// title/stage frame after its build finishes.
    private var publicationGeneration: UInt64 = 0
    private var latestGunbarrelPass: GoldenEyeGunbarrelRenderPassV6?
    private var lastRenderableSceneScreen: UInt32 = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_LEGAL)
    private var pendingModelExecutionResult: GoldenEyeSourceProductModelExecutionResultV6?
    private var lastRenderEvidence: GoldenEyeSourceSceneRenderEvidenceV6?
    private var didShutdown = false
    private var renderIndex: UInt64 = 0

    private struct PublishedRenderState {
        let didShutdown: Bool
        let stageScene: GoldenEyeSourceSceneSnapshotV6?
        let scene: GoldenEyeSourceSceneSnapshotV6?
        let titleSnapshot: GoldenEyeTitleSnapshot?
        let source2DFrame: GoldenEyeSource2DFrameV6?
        let source2DBackgroundFrame: GoldenEyeSource2DFrameV6?
        let gunbarrelPass: GoldenEyeGunbarrelRenderPassV6?
        let stagePacketHash: UInt64
        let stageUnsupportedMask: UInt32
        let stageMaterialHash: UInt64
        let stageMaterialStateCount: UInt32
        let stageTexturePending: UInt32
    }
    /// Model command traversal, texture setup resolution, and immutable
    /// source records are cached per model/switch route. A cache hit reframes
    /// only copied transforms, lighting/fade values, and frame hashes; it
    /// never shares mutable frame or Metal state across the owner boundary.
    private var compiledModelCache: [GoldenEyeSourceTitleRenderCacheKeyV6: GoldenEyeSourceTitleRenderCacheEntryV6] = [:]
    private var compiledModelCacheHits: UInt64 = 0
    private var compiledModelCacheMisses: UInt64 = 0
    /// Gunbarrel model graphs and texture setup rows are immutable across the
    /// intro.  Keep that source topology on the owner and rebuild only the
    /// frame-local pose/matrix projection at each native tick.
    private struct GunbarrelTopologyCacheEntry {
        let scene: GESourceSceneV6
        let textureSetups: [GoldenEyeSourceTextureSetupV6]
    }
    private var gunbarrelTopologyCache: [String: GunbarrelTopologyCacheEntry] = [:]
    /// Incremental source root-motion state for the live Gunbarrel owner. The
    /// immutable sidecar remains the pure oracle; this state only advances
    /// already-validated substeps and is reset at each source entry.
    private var gunbarrelRootMotionStepper:
        GoldenEyeGunbarrelDynamicSidecarV6.RootMotionStepperV6?
    /// Cast GESM traversal and texture setup are immutable for a prepared
    /// model.  Keep those copied source values warm before the owner starts its
    /// 120 Hz loop; the dynamic builder still receives the live C pose and
    /// camera matrices for every frame.
    private struct CastTopologyCacheEntry {
        let packetHash: UInt64
        let scene: GESourceSceneV6
        let textureSetups: [GoldenEyeSourceTextureSetupV6]
    }
    private var castTopologyCache: [String: CastTopologyCacheEntry] = [:]
    private var castTopologyCacheHits: UInt64 = 0
    private var castTopologyCacheMisses: UInt64 = 0
    private var castTopologyPrewarmModelCount: UInt32 = 0
    private var gunbarrelPreviousAnchorScene: GoldenEyeSourceSceneSnapshotV6?
    private var gunbarrelCurrentAnchorScene: GoldenEyeSourceSceneSnapshotV6?
    private var gunbarrelCurrentAnchorPass: GoldenEyeGunbarrelRenderPassV6?
    /// The source ABI exposes titleTransitionX on the odd continuous-state
    /// event only. Retain that copied value so the even mode-2 dot frames do
    /// not fall back to the initial -100 position after the trailing ring is
    /// retargeted by title.c.
    private var gunbarrelTransitionXQ16: Int32 = -100 * 65_536
    /// Source primes blood frame 0 at the mode-4 -> mode-5 boundary, then
    /// advances to frames 1...41 on the 41 BLOOD_TICK callbacks.  Keep this
    /// owner-thread playback state separate from the source result mailbox so
    /// the same frame can submit BLOOD_TICK and DRAW without racing a second
    /// decode.
    private var gunbarrelBloodFrameIndex: UInt32 = 0
    private var gunbarrelBloodTickCount: UInt32 = 0
    /// The source callback that decodes continuation 41 is observed after
    /// the authority step has already consumed the previous mailbox value.
    /// Latch completion after continuation 40 and carry it across the
    /// intervening native draw-only frames so continuation 41 consumes it at
    /// the exact source transition tick.
    private var gunbarrelBloodCompletionPending = false


    var stageTextureDependenciesReady: Bool {
        guard let stageTextureCatalog,
              let visibleDependencyCatalog,
              visibleDependencyCatalog.count(category: "textures") == stageTextureCatalog.textures.count,
              stageTextureCatalog.allBindingsPrepared else {
            return false
        }
        return stageTextureCatalog.isGPURepresentable
    }

    init(
        state: GoldenEyeMetalDeviceState,
        sourceRoot: URL? = nil,
        libraryURL: URL? = nil,
        source2DLibraryURL: URL? = nil,
        outputMode: GoldenEyeFidelityOutputMode = .faithfulHD,
        presentationTreatment: GoldenEyeSourceScenePresentationTreatmentV6 = .enhancedHD,
        frameResourceProvider: GoldenEyeSourceProductFrameResourceProviderV6? = nil
    ) throws {
        guard state.device.supportsFamily(.metal4) else {
            throw GoldenEyeSourceProductRendererV6Error.metal4Unavailable
        }
        // A scene cannot be built until the source projection/matrix lane has
        // supplied exact copied values.  Do not let the product initialize
        // with an identity matrix, guessed viewport, or title fallback.
        guard frameResourceProvider != nil else {
            throw GoldenEyeSourceProductRendererV6Error.missingFrameResources
        }
        let root: URL
        if let sourceRoot {
            root = sourceRoot
        } else if let rawRoot = ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_SOURCE_FRONTEND_ROOT"],
                  !rawRoot.isEmpty {
            root = URL(fileURLWithPath: rawRoot, isDirectory: true)
        } else {
            throw GoldenEyeSourceProductRendererV6Error.missingPreparedRoot
        }
        let preparation: GoldenEyeSourceProductPreparationV6
        do {
            preparation = try GoldenEyeSourceProductPreparationV6.load(rootURL: root)
        } catch {
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(String(describing: error))
        }
        let castPreparation: GoldenEyeCastPreparedAssetCatalogV6?
        if let rawCastRoot = ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_CAST_ASSET_ROOT"],
           !rawCastRoot.isEmpty {
            do {
                castPreparation = try GoldenEyeCastPreparedAssetCatalogV6.load(
                    rootURL: URL(fileURLWithPath: rawCastRoot, isDirectory: true)
                )
            } catch {
                throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                    "cast prepared root: \(error)"
                )
            }
        } else {
            castPreparation = nil
        }
        let gunbarrelSidecar: GoldenEyeGunbarrelDynamicSidecarV6?
        do {
            gunbarrelSidecar = try Self.loadGunbarrelSidecar(root: root)
        } catch {
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                "gunbarrel dynamic sidecar: \(error)"
            )
        }

        let stageTextureCatalog: GoldenEyeStageTextureCatalogV6?
        if let rawStageRoot = ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_STAGE_ASSET_ROOT"],
           !rawStageRoot.isEmpty {
            do {
                stageTextureCatalog = try GoldenEyeStageTextureCatalogV6.load(
                    stageAssetRoot: URL(fileURLWithPath: rawStageRoot, isDirectory: true)
                )
            } catch {
                throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                    "stage texture catalog: \(error)"
                )
            }
        } else {
            stageTextureCatalog = nil
        }
        let stageSetupDependencyCatalog: GoldenEyeStageSetupDependencyCatalogV6?
        if let rawStageRoot = ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_STAGE_ASSET_ROOT"],
           !rawStageRoot.isEmpty {
            do {
                stageSetupDependencyCatalog = try GoldenEyeStageSetupDependencyCatalogV6.load(
                    stageAssetRoot: URL(fileURLWithPath: rawStageRoot, isDirectory: true)
                )
            } catch {
                throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                    "stage setup dependency catalog: \(error)"
                )
            }
        } else {
            stageSetupDependencyCatalog = nil
        }
        let stageModelSidecarCatalog: GoldenEyeStageModelSidecarCatalogV6?
        if let rawStageRoot = ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_STAGE_ASSET_ROOT"],
           !rawStageRoot.isEmpty {
            do {
                stageModelSidecarCatalog = try GoldenEyeStageModelSidecarCatalogV6.load(
                    stageAssetRoot: URL(fileURLWithPath: rawStageRoot, isDirectory: true)
                )
            } catch {
                throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                    "stage model sidecar catalog: \(error)"
                )
            }
        } else {
            stageModelSidecarCatalog = nil
        }
        let visibleDependencyCatalog: GoldenEyeRamRomVisibleDependencyCatalogV6?
        if let rawVisibleRoot = ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_VISIBLE_DEPENDENCY_ROOT"],
           !rawVisibleRoot.isEmpty {
            do {
                visibleDependencyCatalog = try GoldenEyeRamRomVisibleDependencyCatalogV6.load(
                    rootURL: URL(fileURLWithPath: rawVisibleRoot, isDirectory: true)
                )
            } catch {
                throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                    "visible dependency catalog: \(error)"
                )
            }
        } else {
            visibleDependencyCatalog = nil
        }

        let sceneLibraryURL: URL
        if let libraryURL {
            sceneLibraryURL = libraryURL
        } else if let bundled = Bundle.main.url(
            forResource: "GoldenEyeSourceSceneV6",
            withExtension: "metallib"
        ) {
            sceneLibraryURL = bundled
        } else {
            throw GoldenEyeSourceProductRendererV6Error.missingPipelineLibrary
        }

        let resolved2DLibraryURL: URL
        if let source2DLibraryURL = source2DLibraryURL {
            resolved2DLibraryURL = source2DLibraryURL
        } else if let bundled = Bundle.main.url(
            forResource: "GoldenEyeSource2DV6",
            withExtension: "metallib"
        ) {
            resolved2DLibraryURL = bundled
        } else {
            throw GoldenEyeSourceProductRendererV6Error.missing2DPipelineLibrary
        }

        guard let uploadEvent = state.device.makeSharedEvent() else {
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                "texture upload completion event unavailable"
            )
        }
        uploadEvent.label = "GoldenEye.V6.SourceProduct.TextureUpload"
        let textureContext = GoldenEyeSourceTextureStoreV6MetalContext(
            device: state.device,
            queue: state.queue,
            residency: state.sceneResidency,
            completionEvent: uploadEvent
        )
        let textureStore: GoldenEyeSourceTextureStoreV6
        let texturePlan: GoldenEyeSourceTextureUploadPlanV6
        do {
            textureStore = try GoldenEyeSourceTextureStoreV6(context: textureContext)
            // Cast assets can replace a title-sidecar name (for example
            // chrwppk) with the corrected extended packet. Keep one
            // deterministic descriptor per handle while retaining all title
            // models that are absent from the Cast root.
            let titlePairs = preparation.models.keys
                .filter { castPreparation?.models[$0] == nil }
                .sorted()
                .compactMap { name in
                    preparation.models[name].map { (name: name, model: $0) }
                }
            let castPairs = castPreparation?.models.keys.sorted().compactMap { name in
                castPreparation?.models[name].map { (name: name, model: $0) }
            } ?? []
            let pairs = titlePairs + castPairs
            if pairs.count != GoldenEyeSourceProductPreparationV6.requiredModelNames.count,
               castPreparation == nil {
                throw GoldenEyeSourceProductPreparationV6Error.modelSetMismatch(
                    expected: GoldenEyeSourceProductPreparationV6.requiredModelNames.sorted(),
                    actual: pairs.map(\.name).sorted()
                )
            }
            let frontendTexturePlan: GoldenEyeSourceTextureUploadPlanV6
            if let castPreparation {
                let titlePlan = try GoldenEyeSourceTextureUploadPlanV6.make(
                    catalog: preparation.catalog,
                    models: titlePairs
                )
                let castPlan = try GoldenEyeSourceTextureUploadPlanV6.make(
                    catalog: castPreparation.catalog,
                    models: castPairs
                )
                frontendTexturePlan = try GoldenEyeSourceTextureUploadPlanV6.make(
                    descriptors: titlePlan.descriptors + castPlan.descriptors
                )
            } else {
                frontendTexturePlan = try GoldenEyeSourceTextureUploadPlanV6.make(
                    catalog: preparation.catalog,
                    models: pairs
                )
            }
            let stageDescriptors = stageTextureCatalog?.uploadDescriptors() ?? []
            let stageModelDescriptors: [GoldenEyeSourceTextureDescriptorV6]
            if let stageTextureCatalog, stageTextureCatalog.isGPURepresentable,
               let stageModelSidecarCatalog {
                let existingHandles = Set(frontendTexturePlan.descriptors.map(\.resourceHandle)
                    + stageDescriptors.map(\.resourceHandle))
                stageModelDescriptors = GoldenEyeStageModelSceneCompositionV6
                    .textureDescriptors(
                        models: stageModelSidecarCatalog.models,
                        sidecars: stageModelSidecarCatalog,
                        stageTextures: stageTextureCatalog
                    )
                    .filter { !existingHandles.contains($0.resourceHandle) }
            } else {
                stageModelDescriptors = []
            }
            texturePlan = try GoldenEyeSourceTextureUploadPlanV6.make(
                descriptors: frontendTexturePlan.descriptors + stageDescriptors + stageModelDescriptors
            )
            _ = try textureStore.upload(plan: texturePlan)
            try textureStore.drain()
        } catch {
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                "texture store: \(error)"
            )
        }

        let textureBindingAdapter: GoldenEyeSourceSceneTextureBindingAdapterV6
        do {
            textureBindingAdapter = try GoldenEyeSourceSceneTextureBindingAdapterV6(
                store: textureStore,
                plan: texturePlan
            )
        } catch {
            try? textureStore.shutdown()
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                "texture binding adapter: \(error)"
            )
        }

        let pipeline: GoldenEyeSourceScenePipelineV6
        do {
            pipeline = try GoldenEyeSourceScenePipelineV6(
                device: state.device,
                libraryURL: sceneLibraryURL,
                pixelFormat: .bgra8Unorm
            )
        } catch {
            try? textureStore.shutdown()
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                "source-scene pipeline: \(error)"
            )
        }

        let sourceRenderer: GoldenEyeSourceSceneRendererV6
        do {
            sourceRenderer = try GoldenEyeSourceSceneRendererV6(
                state: state,
                pipeline: pipeline,
                textureResolver: { [textureStore] handle in
                    textureStore.texture(handle: handle)
                },
                textureBindingAdapter: textureBindingAdapter,
                outputMode: outputMode,
                presentationTreatment: presentationTreatment
            )
        } catch {
            try? textureStore.shutdown()
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                "source-scene renderer: \(error)"
            )
        }

        let gunbarrelPassRenderer: GoldenEyeGunbarrelPassRendererV6?
        if let gunbarrelSidecar {
            do {
                let backgroundRecord = try preparation.catalog.record(
                    kind: .background,
                    name: "gunbarrel-background",
                    family: "gunbarrel"
                )
                let backgroundData = try preparation.catalog.copyOut(.decoded, for: backgroundRecord)
                gunbarrelPassRenderer = try GoldenEyeGunbarrelPassRendererV6(
                    state: state,
                    sourcePipeline: pipeline,
                    backgroundData: backgroundData,
                    bloodData: gunbarrelSidecar.bloodEncoded
                )
            } catch {
                try? textureStore.shutdown()
                sourceRenderer.shutdown()
                throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                    "gunbarrel non-model pass: \(error)"
                )
            }
        } else {
            gunbarrelPassRenderer = nil
        }

        let source2DAssets: GoldenEyeSource2DAssetsV6
        do {
            source2DAssets = try GoldenEyeSource2DAssetsV6(catalog: preparation.catalog)
        } catch {
            try? textureStore.shutdown()
            sourceRenderer.shutdown()
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                "source-2d assets: \(error)"
            )
        }
        let source2DRenderer: GoldenEyeSource2DMetalRendererV6
        do {
            source2DRenderer = try GoldenEyeSource2DMetalRendererV6(
                state: state,
                assets: source2DAssets,
                libraryURL: resolved2DLibraryURL,
                outputMode: outputMode
            )
        } catch {
            try? textureStore.shutdown()
            sourceRenderer.shutdown()
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                "source-2d renderer: \(error)"
            )
        }

        self.state = state
        self.preparation = preparation
        self.castPreparation = castPreparation
        self.stageTextureCatalog = stageTextureCatalog
        self.stageSetupDependencyCatalog = stageSetupDependencyCatalog
        self.stageModelSidecarCatalog = stageModelSidecarCatalog
        self.visibleDependencyCatalog = visibleDependencyCatalog
        self.gunbarrelSidecar = gunbarrelSidecar
        self.textureStore = textureStore
        self.textureBindingAdapter = textureBindingAdapter
        self.renderer = sourceRenderer
        self.gunbarrelPassRenderer = gunbarrelPassRenderer
        self.source2DRenderer = source2DRenderer
        self.source2DLowerer = GoldenEyeSource2DLowererV6(assets: source2DAssets)
        self.frameResourceProvider = frameResourceProvider
        self.outputMode = outputMode
        self.presentationTreatment = presentationTreatment
        self.stageAssetRootURL = ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_STAGE_ASSET_ROOT"].flatMap {
            $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL
        }
    }

    /// Build the first static topology for the title models before the 120 Hz
    /// owner starts.  GESM traversal, texture setup resolution, and vertex
    /// expansion are bounded but intentionally not realtime work; doing the
    /// first Rareware/Nintendo build inside a source tick creates seconds of
    /// scheduler debt and leaves the display link with no submitted scene.
    func prewarmSourceTitleScenes() throws {
        try prewarmSourceTitleModel(
            model: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_NINTENDOLOGO),
            screen: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_NINTENDO),
            sourceTimer: 0,
            subphase: 0
        )
        try prewarmSourceTitleModel(
            model: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RAREWARELOGO),
            screen: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_RAREWARE),
            sourceTimer: 4,
            subphase: 0
        )
        try prewarmGunbarrelTopologies()
        try prewarmCastTopologies()
        try prewarmSourceTitleModel(
            model: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GOLDENEYELOGO),
            screen: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GOLDENEYE),
            sourceTimer: 0,
            subphase: 0
        )
        // Do not present the synthetic prewarm frame; the first owner tick
        // will publish the real source-authoritative frame.
        latestScene = nil
        latestSourceFrame = nil
        latestGunbarrelPass = nil
        gunbarrelPreviousAnchorScene = nil
        gunbarrelCurrentAnchorScene = nil
        gunbarrelCurrentAnchorPass = nil
        gunbarrelTransitionXQ16 = -100 * 65_536
        gunbarrelBloodCompletionPending = false
        pendingModelExecutionResult = nil
    }

    /// Copy the immutable Cast graph/setup seam before the source owner starts
    /// its cadence loop.  This deliberately does not call the dynamic GBI
    /// builder: pose records, attachment matrices, camera matrices, and frame
    /// hashes remain lowered on every live Cast tick by the source path.
    private func prewarmCastTopologies() throws {
        guard let castPreparation else {
            // The extended Cast catalog is optional for title-only/debug
            // launches.  Keep the existing fail-closed behavior when it is
            // absent instead of manufacturing a partial Cast cache.
            return
        }
        let models = castModels
        let resolver = GESourceModelDynamicResolverV6(
            resolvedModels: Set(models.keys)
        )
        let catalog = castPreparation.catalog
        let names = GoldenEyeCastSceneComposerV6.requiredPreparedModelNames.sorted()
        let start = DispatchTime.now().uptimeNanoseconds
        for modelName in names {
            guard let model = models[modelName] else {
                throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                    "Cast prewarm model is missing: \(modelName)"
                )
            }
            _ = try castTopology(
                modelName: modelName,
                model: model,
                resolver: resolver,
                catalog: catalog
            )
        }
        try prewarmFirstCastBuilderPackets(
            sourceIndex: 1,
            models: models,
            resolver: resolver
        )
        // The source-ordered route for the canonical title seed advances to
        // row 2 on its first live Cast anchor. Warm that distinct model/packet
        // set before the owner starts so the first dynamic Cast frame does not
        // pay a multi-period decode/convert stall.
        do {
            try prewarmFirstCastBuilderPackets(
                sourceIndex: 2,
                models: models,
                resolver: resolver
            )
        } catch {
            // A source row may select a distinct weapon prop that is not in
            // the guarded Cast catalog. Keep the exact skip diagnostic and
            // let the live submission apply its existing source-validated
            // missing-weapon resolution; never abort owner startup because
            // an optional prewarm row is unavailable.
            try? "castBuilderPacketPrewarm=0 sourceIndex=2 error=\(error)\n".write(
                toFile: "/tmp/goldeneye-source-product-renderer-v6-cast-builder-prewarm.log",
                atomically: false,
                encoding: .utf8
            )
        }
        castTopologyPrewarmModelCount = UInt32(castTopologyCache.count)
        let elapsedMicros = (DispatchTime.now().uptimeNanoseconds - start) / 1_000
        try? (
            "castTopologyPrewarm=1 models=\(castTopologyPrewarmModelCount) "
                + "cacheEntries=\(castTopologyCache.count) elapsedUs=\(elapsedMicros) "
                + "sourceGESM=1 textureSetup=1 immutablePacket=firstRoute "
                + "dynamicPose=perTick\n"
        ).write(
                toFile: "/tmp/goldeneye-source-product-renderer-v6-cast-prewarm.log",
                atomically: false,
                encoding: .utf8
            )
    }

    /// Populate the GBI builder's immutable packet/decoder cache for the
    /// deterministic first normal-attract Cast row.  The resulting no-pose
    /// packet is discarded; this call only moves source packet allocation,
    /// decoder traversal, and static resource expansion out of the live
    /// transition.  The first owner Cast frame still supplies C-authoritative
    /// poses, attachments, matrices, and frame hashes to `build`.
    private func prewarmFirstCastBuilderPackets(
        sourceIndex: UInt16,
        models: [String: GoldenEyeSourceModelV6],
        resolver: GESourceModelDynamicResolverV6
    ) throws {
        let seed = Self.castPrewarmSeed()
        let nativeTick = Self.castPrewarmNativeTick()
        let identity = try GoldenEyeCastSourceTableV6.identity(sourceIndex: sourceIndex)
        let randomWord = Self.castPrewarmWord(
            seed: seed,
            sourceIndex: sourceIndex,
            nativeTick: nativeTick
        )
        let animation = try GoldenEyeCastSceneComposerV6.animation(randomWord: randomWord)
        let requestedWeaponPropID: UInt16?
        if animation.usesWeaponCamera {
            let pool = animation.cameraPreset == 2
                ? GoldenEyeCastSourceTableV6.rifleWeapons
                : GoldenEyeCastSourceTableV6.pistolWeapons
            requestedWeaponPropID = pool[Int(randomWord % UInt32(pool.count))].propID
        } else {
            requestedWeaponPropID = nil
        }
        let availableNames = Set(models.keys)
        let availableHandles = models.reduce(into: [String: UInt32]()) {
            $0[$1.key] = $1.value.header.modelHandle
        }
        // Match the live Cast handoff exactly: an authored prop ID that has no
        // guarded packet falls back to the source-selected prepared weapon
        // pool. Prewarm the fallback topology as well, otherwise row 2 pays
        // the full decoder/vertex expansion on its first visible frame.
        let binding: GoldenEyeCastPreparedModelBindingV6
        do {
            binding = try GoldenEyeCastSceneComposerV6.resolveModels(
                identity: identity,
                animation: animation,
                availableModelNames: availableNames,
                availableHandles: availableHandles,
                randomWord: randomWord,
                requestedWeaponPropID: requestedWeaponPropID
            )
        } catch GoldenEyeCastSceneComposerV6Error.missingWeapon {
            binding = try GoldenEyeCastSceneComposerV6.resolveModels(
                identity: identity,
                animation: animation,
                availableModelNames: availableNames,
                availableHandles: availableHandles,
                randomWord: randomWord,
                requestedWeaponPropID: nil
            )
        }
        let modelNames = [binding.bodyName, binding.headName, binding.weaponName]
            .filter { !$0.isEmpty }
        let frameResources = try GoldenEyeCastCameraResourcesV6.make(
            modelMatrixHandles: modelMatrixHandles(for: modelNames, models: models),
            distanceQ16: 70 * 65_536,
            angleQ16: 0,
            heightQ16: 0
        )
        let frame = try GoldenEyeGBISceneFrameContextV6(
            nativeTick: max(nativeTick, 2),
            referenceTick: max(nativeTick, 2) >> 1,
            sourceTimer: 0,
            pairPhase: max(nativeTick, 2) & 1 == 0 ? 0 : 1,
            screen: UInt32(GE_SOURCE_FRAME_V6_SCREEN_CAST),
            subphase: UInt32(sourceIndex),
            viewportWidth: frameResources.viewportWidth,
            viewportHeight: frameResources.viewportHeight
        )
        let matrixRoles = try frameResources.matrices.compactMap {
            matrix -> GoldenEyeSourceMatrixRoleSidecarV6? in
            guard matrix.roleFlags != 0 else { return nil }
            return try GoldenEyeSourceMatrixRoleSidecarV6(
                handle: matrix.handle,
                roleFlags: matrix.roleFlags
            )
        }
        let start = DispatchTime.now().uptimeNanoseconds
        var packetCount = 0
        for modelName in modelNames {
            guard let model = models[modelName],
                  let topology = castTopologyCache[modelName] else {
                throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                    "Cast first-route prewarm topology is missing: \(modelName)"
                )
            }
            let result = try GoldenEyeGBISceneBuilderV6.build(
                model: model,
                modelName: modelName,
                matrices: frameResources.matrices,
                viewports: frameResources.viewports,
                matrixRoles: matrixRoles,
                frame: frame,
                dynamicResolver: resolver,
                transformContext: .cast,
                renderSetupContext: .cast(forModel: model, scene: topology.scene),
                textureSetups: topology.textureSetups,
                resolvedScene: GoldenEyeGBIResolvedSceneInputV6(scene: topology.scene)
            )
            guard result.presentable,
                  result.unsupportedVisibleCount == 0,
                  !result.snapshot.drawCommands.isEmpty else {
                throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                    "Cast first-route packet prewarm is not presentable: \(modelName)"
                )
            }
            packetCount += 1
        }
        let elapsedMicros = (DispatchTime.now().uptimeNanoseconds - start) / 1_000
        try? (
            "castBuilderPacketPrewarm=1 sourceIndex=\(sourceIndex) "
                + "nativeTick=\(nativeTick) randomWord=0x\(String(randomWord, radix: 16)) "
                + "body=\(binding.bodyName) head=\(binding.headName) weapon=\(binding.weaponName) "
                + "packets=\(packetCount) elapsedUs=\(elapsedMicros) "
                + "poses=perTick attachments=perTick hashes=perTick\n"
        ).write(
            toFile: "/tmp/goldeneye-source-product-renderer-v6-cast-builder-prewarm.log",
            atomically: false,
            encoding: .utf8
        )
    }

    private static func castPrewarmSeed() -> UInt64 {
        guard let raw = ProcessInfo.processInfo.environment["GOLDENEYE_TITLE_RANDOM_SEED"] else {
            return 1
        }
        let isHex = raw.hasPrefix("0x") || raw.hasPrefix("0X")
        return UInt64(
            isHex ? String(raw.dropFirst(2)) : raw,
            radix: isHex ? 16 : 10
        ) ?? 1
    }

    private static func castPrewarmNativeTick() -> UInt64 {
        guard let raw = ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_CAST_PREWARM_TICK"],
              let value = UInt64(raw), value > 0 else {
            // The canonical source route first submits Cast at native tick
            // 3952/3953. This keeps the deterministic prewarm word aligned
            // with the first row-2 transition while remaining overrideable for
            // alternate seeds/harnesses.
            return 3_953
        }
        return value
    }

    private static func castPrewarmWord(
        seed: UInt64,
        sourceIndex: UInt16,
        nativeTick: UInt64
    ) -> UInt32 {
        var value = seed &+
            UInt64(sourceIndex) &* 0x9E37_79B9 &+
            nativeTick &* 0xD1B5_4A32_D192_ED03
        value ^= value >> 30
        value &*= 0xBF58_476D_1CE4_E5B9
        value ^= value >> 27
        value &*= 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return UInt32(truncatingIfNeeded: value)
    }

    /// Resolve one guarded Cast model's immutable source topology.  The
    /// packet hash is part of the cache entry so a stale model/catalog cannot
    /// be silently reused if a prepared root changes between launches.
    private func castTopology(
        modelName: String,
        model: GoldenEyeSourceModelV6,
        resolver: GESourceModelDynamicResolverV6,
        catalog: GoldenEyeSourceFrontendCatalog
    ) throws -> CastTopologyCacheEntry {
        let packetHash = Self.castDigestPrefix(model.header.packetHash)
        if let cached = castTopologyCache[modelName], cached.packetHash == packetHash {
            castTopologyCacheHits &+= 1
            return cached
        }
        castTopologyCacheMisses &+= 1
        let compilation = GESourceModelCompilerV6.compile(
            model,
            modelName: modelName,
            dynamicResolver: resolver
        )
        guard compilation.status == .complete,
              let scene = compilation.scene,
              compilation.diagnostics.isEmpty,
              scene.unsupportedCount == 0 else {
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                "Cast dynamic source traversal is incomplete for \(modelName)"
            )
        }
        let setup = try GoldenEyeSourceTextureSetupResolverV6.resolve(
            modelName: modelName,
            model: model,
            catalog: catalog,
            compiledCommands: scene.commands
        )
        let entry = CastTopologyCacheEntry(
            packetHash: packetHash,
            scene: scene,
            textureSetups: setup.setups
        )
        castTopologyCache[modelName] = entry
        return entry
    }

    private static func castDigestPrefix(_ digest: [UInt8]) -> UInt64 {
        digest.prefix(8).enumerated().reduce(UInt64(0)) { partial, pair in
            partial | UInt64(pair.element) << UInt64(pair.offset * 8)
        }
    }

    private func prewarmGunbarrelTopologies() throws {
        guard let sidecar = gunbarrelSidecar, sidecar.resolvesGunbarrelModels else {
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                "validated Gunbarrel animation/attachment sidecar is missing"
            )
        }
        let resolver = sidecar.dynamicResolver
        for modelName in ["suitbond", "headbrosnansuit", "chrwppk"] {
            guard gunbarrelTopologyCache[modelName] == nil else { continue }
            let model = try preparation.model(named: modelName)
            let compilation = GESourceModelCompilerV6.compile(
                model,
                modelName: modelName,
                dynamicResolver: resolver
            )
            guard compilation.status == .complete,
                  let scene = compilation.scene,
                  compilation.diagnostics.isEmpty,
                  scene.unsupportedCount == 0 else {
                throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                    "Gunbarrel dynamic source traversal is incomplete for \(modelName)"
                )
            }
            let setup = try GoldenEyeSourceTextureSetupResolverV6.resolve(
                modelName: modelName,
                model: model,
                catalog: preparation.catalog,
                compiledCommands: scene.commands
            )
            gunbarrelTopologyCache[modelName] = GunbarrelTopologyCacheEntry(
                scene: scene,
                textureSetups: setup.setups
            )
        }
    }

    private func prewarmSourceTitleModel(
        model modelID: UInt32,
        screen: UInt32,
        sourceTimer: UInt32,
        subphase: UInt32
    ) throws {
        guard let modelName = Self.modelNameForID[modelID],
              Self.modelForScreen[screen] == modelName else {
            throw GoldenEyeSourceProductRendererV6Error.unsupportedScreen(screen)
        }
        let modelPacket = try preparation.model(named: modelName)
        var matrixHandles: [UInt32] = []
        for (index, command) in modelPacket.commands.enumerated()
            where command.semantic.hasPrefix("gsSPMatrix") {
            guard let token = modelPacket.tokens(for: index).first,
                  token.encodedValue != 0,
                  !matrixHandles.contains(token.encodedValue) else { continue }
            matrixHandles.append(token.encodedValue)
        }
        let modelMatrixHandle: UInt32
        if screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_RAREWARE),
           matrixHandles.isEmpty {
            modelMatrixHandle = 0xF300_0001
        } else {
            guard let first = matrixHandles.first else {
                throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                    "prewarm model \(modelName) has no source matrix handle"
                )
            }
            modelMatrixHandle = first
        }
        let matrixInput = try GoldenEyeSourceFrontendMatrixInputV6(
            screen: screen,
            nativeTick: 2,
            referenceTick: 1,
            sourceTimer: sourceTimer,
            pairPhase: 0
        )
        let matrixFrame = try GoldenEyeSourceFrontendMatricesV6.make(
            input: matrixInput,
            modelMatrixHandle: modelMatrixHandle,
            viewportWidth: 440,
            viewportHeight: 330
        )
        let request = try GoldenEyeSourceProductModelRequestV6(
            screen: screen,
            model: modelID,
            operation: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_DRAW),
            nativeTick: 2,
            referenceTick: 1,
            sourceTimer: sourceTimer,
            subphase: subphase,
            flags: 0
        )
        _ = try buildModelScene(
            request: request,
            sourceFrame: nil,
            frameResources: matrixFrame.resources
        )
    }

    /// Source-owner handoff used by the 120 Hz engine owner.  The provider is
    /// the sole authority for matrices and viewports; a missing or rejected
    /// resource set is propagated as a typed failure before any drawable is
    /// touched.
    func submit(sourceFrontendFrame: GoldenEyeSourceFrontendFrameV6) throws {
        frameStateLock.lock()
        defer { frameStateLock.unlock() }
        publicationGeneration &+= 1
        let wasGunbarrel = latestSourceFrame?.screen ==
            UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL)
        let isGunbarrel = sourceFrontendFrame.screen ==
            UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL)
        if !wasGunbarrel && isGunbarrel {
            // The source model-load ledger is intentionally one-shot, but the
            // attract loop may re-enter Gunbarrel after a completed Cast/demo.
            // Reset the copied blood stream at each screen entry so a prior
            // 41-frame completion cannot authorize the next cycle early.
            gunbarrelBloodFrameIndex = 0
            gunbarrelBloodTickCount = 0
            gunbarrelBloodCompletionPending = false
            gunbarrelRootMotionStepper = nil
        }
        if !isGunbarrel {
            gunbarrelPreviousAnchorScene = nil
            gunbarrelCurrentAnchorScene = nil
            gunbarrelCurrentAnchorPass = nil
            gunbarrelTransitionXQ16 = -100 * 65_536
            gunbarrelRootMotionStepper = nil
        } else if let transitionEvent = sourceFrontendFrame.renderEvents.first(where: {
            $0.operation == GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_CONTINUOUS_STATE
                && $0.subphase == GE_SOURCE_FRONTEND_RUNTIME_V6_CONTINUOUS_GUNBARREL_TRANSLATION
        }) {
            gunbarrelTransitionXQ16 = transitionEvent.value1
        }
        // Build the replacement scene off to the side and publish it only
        // from `buildModelScene` after all validation has succeeded.
        latestStageScene = nil
        latestStagePacketHash = 0
        latestStageUnsupportedMask = 0
        latestStageMaterialHash = 0
        latestStageMaterialStateCount = 0
        latestStageTexturePending = 0
        latestGunbarrelPass = nil
        latestTitleSnapshot = nil
        latestSource2DFrame = nil
        latestSource2DBackgroundFrame = nil
        latestSourceFrame = sourceFrontendFrame
        pendingModelExecutionResult = nil
        let renderOperations = sourceFrontendFrame.renderEvents.map(\.operation)
        let clearBlackOnly = GoldenEyeSourceProductFrameClassifierV6.isClearBlackOnly(
            renderOperations: renderOperations,
            modelEventCount: sourceFrontendFrame.modelEvents.count,
            textEventCount: sourceFrontendFrame.textEvents.count
        )
        // MENU_SWITCH_SCREENS is an internal source state, not a renderable
        // title screen.  Its source constructor emits the transition's
        // CLEAR_BLACK packet, but the matrix provider intentionally accepts
        // only renderable screens.  Consume that exact transition packet
        // before asking for matrices; otherwise the Release route dies at
        // the first Legal -> Nintendo handoff with an unsupported-screen
        // matrix error.
        if sourceFrontendFrame.screen ==
                UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_SWITCH) {
            try submit(sourceFrame: sourceFrontendFrame, frameResources: nil)
            return
        }
        if clearBlackOnly {
            try submit(sourceFrame: sourceFrontendFrame, frameResources: nil)
            return
        }
        guard let frameResourceProvider else {
            throw GoldenEyeSourceProductRendererV6Error.missingFrameResources
        }
        let resources = try frameResourceProvider.frameResources(for: sourceFrontendFrame)
        try submit(sourceFrame: sourceFrontendFrame, frameResources: resources)
    }

    /// Release-capable gameplay-camera handoff. The owner supplies only a
    /// copied demo/stage/camera subset; this method resolves the existing
    /// guarded catalogs, runs the V7 adapter's full-scene `0x38` guard, and
    /// publishes its room+static-prop composition only after every
    /// presentability check succeeds. There is intentionally no environment
    /// or diagnostic fallback on this path.
    func submit(
        stageGameplayCameraSnapshot snapshot: GoldenEyeStageGameplayCameraSnapshotV7
    ) throws {
        frameStateLock.lock()
        guard !didShutdown else {
            frameStateLock.unlock()
            throw GoldenEyeSourceProductRendererV6Error.shutdownFailure(
                "gameplay-camera submission arrived after renderer shutdown"
            )
        }
        publicationGeneration &+= 1
        let submissionGeneration = publicationGeneration
        // Release the publication lock before the expensive
        // source/material/composition lowering. The display-link callback
        // must never wait on this work.
        frameStateLock.unlock()

        do {
            guard let stageTextures = stageTextureCatalog,
                  stageTextures.isGPURepresentable,
                  stageTextures.allBindingsPrepared else {
                throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                    "gameplay-camera stage texture catalog is not GPU-representable"
                )
            }
            guard let sidecars = stageModelSidecarCatalog,
                  sidecars.isComplete,
                  let setupDependencies = stageSetupDependencyCatalog,
                  setupDependencies.isReady,
                  let visibleDependencies = visibleDependencyCatalog,
                  visibleDependencies.isComplete,
                  let scene = loadStageScenePacket(stageID: snapshot.stageID) else {
                throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                    "gameplay-camera guarded stage catalogs or scene packet are missing"
                )
            }

            // Lower the room material packet at the same guarded source seam
            // used by the default stage submission. The V7 adapter may then
            // validate material state and source texture provenance together
            // with the camera-scoped scene.
            let materialPacket = try GoldenEyeStageSourceMaterialLowererV6.make(scene: scene)
            guard materialPacket.stageID == snapshot.stageID,
                  materialPacket.hasSourceState,
                  materialPacket.unsupportedCommandCount == 0 else {
                throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                    "gameplay-camera stage material packet is incomplete"
                )
            }
            let gameplayPacket = try GoldenEyeStageGameplayCameraPacketAdapterV7.make(
                scene: scene,
                snapshot: snapshot,
                materialPacket: materialPacket,
                stageTextures: stageTextures,
                sidecars: sidecars,
                setupDependencies: setupDependencies,
                visibleDependencies: visibleDependencies
            )
            guard gameplayPacket.stageID == snapshot.stageID,
                  gameplayPacket.nativeTick == snapshot.nativeTick,
                  gameplayPacket.subset.fullSceneUnsupportedMask ==
                    GoldenEyeStageGameplayCameraPacketV7.expectedFullSceneUnsupportedMask,
                  gameplayPacket.subset.unsupportedMask == 0,
                  gameplayPacket.composition.unsupportedMask == 0,
                  gameplayPacket.composition.snapshot.summary.unsupported_visible_count == 0,
                  gameplayPacket.composition.isPresentable,
                  gameplayPacket.isPresentable,
                  !gameplayPacket.composition.snapshot.drawCommands.isEmpty else {
                throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                    "gameplay-camera scoped stage composition is not presentable"
                )
            }

            // Publish only after all source/category guards pass. The lock is
            // held for value swaps and telemetry only; it never covers the
            // composition build. A prior valid frame may remain visible while
            // the replacement is lowered, avoiding a drawable starvation
            // gap without accepting an invalid replacement.
            frameStateLock.lock()
            guard !didShutdown, publicationGeneration == submissionGeneration else {
                frameStateLock.unlock()
                throw GoldenEyeSourceProductRendererV6Error.shutdownFailure(
                    "gameplay-camera composition completed after route replacement or shutdown"
                )
            }
            invalidatePublishedFrameLocked()
            latestStageScene = gameplayPacket.composition.snapshot
            latestStageComposition = gameplayPacket.composition
            latestStagePacketHash = gameplayPacket.environmentPacket.packetHash
            latestStageUnsupportedMask = gameplayPacket.subset.unsupportedMask
            latestStageMaterialHash = materialPacket.packetHash
            latestStageMaterialStateCount = UInt32(materialPacket.states.count)
            latestStageTexturePending = 0
            latestStageGameplayCameraPacketHash = gameplayPacket.packetHash
            latestStageGameplayCameraSubsetHash = gameplayPacket.subset.metadataHash
            latestStageFullSceneUnsupportedMask = gameplayPacket.subset.fullSceneUnsupportedMask
            lastRenderableSceneScreen = UInt32(GE_SOURCE_FRAME_V6_SCREEN_RAMROM)
            frameStateLock.unlock()

            appendEvidenceLine(
                "stageGameplayCameraSubmit=1 releaseStageSubmission=1 "
                + "demo=\(gameplayPacket.demoID) nativeTick=\(gameplayPacket.nativeTick) "
                + "stage=\(gameplayPacket.stageID) cameraPacketHash=\(gameplayPacket.packetHash) "
                + "environmentHash=\(gameplayPacket.environmentPacket.packetHash) "
                + "materialHash=\(materialPacket.packetHash) materialStates=\(materialPacket.states.count) "
                + "roomCommands=\(gameplayPacket.subset.roomGeometryCommandCount) "
                + "props=\(gameplayPacket.subset.drawableStaticPropPlacementCount)/\(gameplayPacket.subset.staticPropPlacementCount) "
                + "compositionHash=\(gameplayPacket.composition.compositionHash) "
                + "subsetHash=\(gameplayPacket.subset.metadataHash) "
                + "unsupportedMask=0x\(String(gameplayPacket.subset.unsupportedMask, radix: 16)) "
                + "fullSceneUnsupportedMask=0x\(String(gameplayPacket.subset.fullSceneUnsupportedMask, radix: 16)) "
                + "draws=\(gameplayPacket.composition.snapshot.drawCommands.count) presentable=1\n",
                path: "/tmp/goldeneye-source-product-renderer-v6-stage-gameplay-camera.log"
            )
        } catch {
            // A rejected replacement must leave the product fail-closed; do
            // not keep a stale title/stage frame after a failed submission.
            frameStateLock.lock()
            if publicationGeneration == submissionGeneration {
                invalidatePublishedFrameLocked()
                publicationGeneration &+= 1
            }
            frameStateLock.unlock()
            throw error
        }
    }

    /// Release-capable source-environment handoff. The packet is lowered into
    /// the same immutable source-scene contract and rendered by the existing
    /// direct Metal 4 source-scene renderer. Unsupported stage categories stay
    /// in the packet evidence mask and are not replaced by fallback art.
    func submit(
        sourceEnvironmentPacket packet: GoldenEyeStageBackgroundDrawPacket,
        nativeTick: UInt64
    ) throws {
        frameStateLock.lock()
        defer { frameStateLock.unlock() }
        publicationGeneration &+= 1
        // RAMROM stage packets are immutable environment/topology data. Clear
        // the previous dynamic model frame resources before composing so the
        // bounded stage-composition cache can reuse the source packet across
        // ticks; Cast/title resources must never disable that cache forever.
        latestStageFrameResources = nil
        latestStageComposition = nil
        latestStageScene = try composedStageSnapshot(
            packet: packet,
            materialPacket: nil,
            nativeTick: nativeTick
        ) ?? GoldenEyeStageSourceSceneSnapshotAdapterV6.make(
            packet: packet,
            nativeTick: nativeTick,
            stageTextureCatalog: stageTextureCatalog
        )
        latestStagePacketHash = packet.packetHash
        latestStageUnsupportedMask = packet.unsupportedMask
        latestStageMaterialHash = 0
        latestStageMaterialStateCount = 0
        latestStageTexturePending = 0
        latestScene = nil
        latestTitleSnapshot = nil
        latestSource2DFrame = nil
        latestSource2DBackgroundFrame = nil
        latestSourceFrame = nil
        pendingModelExecutionResult = nil
        try? "stageEnvironmentSubmit=1 releaseStageSubmission=1 nativeTick=\(nativeTick) stage=\(packet.stageID) packetHash=\(packet.packetHash) draws=\(packet.commands.count) vertices=\(packet.vertices.count) unsupportedMask=\(packet.unsupportedMask) frameResources=\(latestStageFrameResources == nil ? 0 : 1)\n".write(
            toFile: "/tmp/goldeneye-source-product-renderer-v6-stage.log",
            atomically: false,
            encoding: .utf8
        )
    }

    /// Material-aware stage handoff. The source state packet is consumed into
    /// immutable per-draw render states; texture payloads remain explicitly
    /// pending in the coverage mask until guarded stage texels/TLUTs exist.
    func submit(
        sourceEnvironmentPacket packet: GoldenEyeStageBackgroundDrawPacket,
        materialPacket: GoldenEyeStageSourceMaterialPacketV6,
        nativeTick: UInt64
    ) throws {
        frameStateLock.lock()
        defer { frameStateLock.unlock() }
        publicationGeneration &+= 1
        // A stage handoff supersedes any Cast/title matrix resources. Keeping
        // them here would force every otherwise-identical environment packet
        // through a full model composition and starve the owner cadence.
        latestStageFrameResources = nil
        latestStageComposition = nil
        latestStageScene = try composedStageSnapshot(
            packet: packet,
            materialPacket: materialPacket,
            nativeTick: nativeTick
        ) ?? GoldenEyeStageSourceSceneSnapshotAdapterV6.make(
            packet: packet,
            nativeTick: nativeTick,
            materialPacket: materialPacket,
            stageTextureCatalog: stageTextureCatalog
        )
        latestStagePacketHash = packet.packetHash
        latestStageUnsupportedMask = packet.unsupportedMask
        latestStageMaterialHash = materialPacket.packetHash
        latestStageMaterialStateCount = UInt32(materialPacket.states.count)
        latestStageTexturePending = stageTexturePending(materialPacket)
        latestScene = nil
        latestTitleSnapshot = nil
        latestSource2DFrame = nil
        latestSource2DBackgroundFrame = nil
        latestSourceFrame = nil
        pendingModelExecutionResult = nil
        try? "stageMaterialSubmit=1 releaseStageSubmission=1 nativeTick=\(nativeTick) stage=\(packet.stageID) environmentHash=\(packet.packetHash) materialHash=\(materialPacket.packetHash) states=\(materialPacket.states.count) draws=\(packet.commands.count) textureCommands=\(materialPacket.textureStateCommandCount) texturePending=\(latestStageTexturePending) frameResources=\(latestStageFrameResources == nil ? 0 : 1) unsupportedCommands=\(materialPacket.unsupportedCommandCount)\n".write(
            toFile: "/tmp/goldeneye-source-product-renderer-v6-stage-material.log",
            atomically: false,
            encoding: .utf8
        )
    }

    /// Loads one guarded stage packet and asks the generic GBI builder to
    /// lower only placements whose exact source transform and texture alias
    /// are available. A failed/partial composition remains non-presentable.
    private func composedStageSnapshot(
        packet: GoldenEyeStageBackgroundDrawPacket,
        materialPacket: GoldenEyeStageSourceMaterialPacketV6?,
        nativeTick: UInt64
    ) throws -> GoldenEyeSourceSceneSnapshotV6? {
        guard let stageTextures = stageTextureCatalog,
              let sidecars = stageModelSidecarCatalog,
              let setupDependencies = stageSetupDependencyCatalog,
              let stageScene = loadStageScenePacket(stageID: packet.stageID) else {
            return nil
        }
        do {
            let canCache = latestStageFrameResources == nil
            let cacheKey = StageCompositionCacheKey(
                stageID: packet.stageID,
                environmentHash: packet.packetHash,
                materialHash: materialPacket?.packetHash ?? 0
            )
            if canCache, let cached = stageCompositionCache[cacheKey] {
                let reframed = try reframeStageComposition(
                    cached,
                    nativeTick: nativeTick
                )
                latestStageComposition = reframed
                return reframed.snapshot
            }
            let result = try GoldenEyeStageModelSceneCompositionV6.make(
                stageScene: stageScene,
                environmentPacket: packet,
                materialPacket: materialPacket,
                sidecars: sidecars,
                setupDependencies: setupDependencies,
                stageTextures: stageTextures,
                frameResources: latestStageFrameResources,
                nativeTick: nativeTick,
                visibleDependencies: visibleDependencyCatalog
            )
            if canCache {
                stageCompositionCache[cacheKey] = result
                if stageCompositionCache.count > 32,
                   let oldest = stageCompositionCache.keys.first {
                    stageCompositionCache.removeValue(forKey: oldest)
                }
            }
            latestStageComposition = result
            try? "stageComposition=1 releaseStageSubmission=1 stage=\(packet.stageID) placements=\(result.placementCount) drawable=\(result.drawablePlacementCount) unsupportedPlacements=\(result.unsupportedPlacementCount) unsupportedMask=0x\(String(result.unsupportedMask, radix: 16)) aliases=\(result.aliasDescriptorCount) compositionHash=\(result.compositionHash) presentable=\(result.isPresentable ? 1 : 0)\n".write(
                toFile: "/tmp/goldeneye-source-product-renderer-v6-stage-composition.log",
                atomically: false,
                encoding: .utf8
            )
            return result.snapshot
        } catch {
            try? "stageCompositionFailure=1 stage=\(packet.stageID) error=\(error)\n".write(
                toFile: "/tmp/goldeneye-source-product-renderer-v6-stage-composition.log",
                atomically: false,
                encoding: .utf8
            )
            return nil
        }
    }

    private func reframeStageComposition(
        _ result: GoldenEyeStageModelSceneCompositionV6.Result,
        nativeTick: UInt64
    ) throws -> GoldenEyeStageModelSceneCompositionV6.Result {
        let source = result.snapshot
        var summary = source.summary
        summary.native_tick = nativeTick
        summary.reference_tick = nativeTick >> 1
        summary.pair_phase = UInt32(nativeTick & 1)
        summary.flags = (summary.flags | UInt32(GE_SOURCE_FRAME_V6_FLAG_PRESENTABLE))
            & ~UInt32(GE_SOURCE_FRAME_V6_FLAG_SOURCE_ANCHOR)
            & ~UInt32(GE_SOURCE_FRAME_V6_FLAG_INTERPOLATED)
        summary.flags |= nativeTick & 1 == 0
            ? UInt32(GE_SOURCE_FRAME_V6_FLAG_SOURCE_ANCHOR)
            : UInt32(GE_SOURCE_FRAME_V6_FLAG_INTERPOLATED)
        summary.frame_hash = summary.scene_hash ^ nativeTick
        let lighting = try source.lightingFrameContext.map {
            try GoldenEyeSourceSceneLightingFrameContextV6(
                screen: $0.screen,
                nativeTick: nativeTick,
                referenceTick: nativeTick >> 1,
                sourceTimer: $0.sourceTimer,
                pairPhase: UInt32(nativeTick & 1),
                geometryModesByState: $0.geometryModesByState,
                modelViewQ16ByState: $0.modelViewQ16ByState
            )
        }
        let snapshot = try GoldenEyeSourceSceneSnapshotV6(
            reframing: source,
            summary: summary,
            transforms: source.transforms,
            renderStates: source.renderStates,
            lightingFrameContext: lighting
        )
        return GoldenEyeStageModelSceneCompositionV6.Result(
            snapshot: snapshot,
            stageID: result.stageID,
            placementCount: result.placementCount,
            drawablePlacementCount: result.drawablePlacementCount,
            unsupportedPlacementCount: result.unsupportedPlacementCount,
            propPlacementCount: result.propPlacementCount,
            characterPlacementCount: result.characterPlacementCount,
            aliasDescriptorCount: result.aliasDescriptorCount,
            unsupportedMask: result.unsupportedMask,
            failureReasons: result.failureReasons,
            categoryPackets: result.categoryPackets,
            compositionHash: result.compositionHash,
            contiguousBatchCount: result.contiguousBatchCount,
            largestContiguousBatch: result.largestContiguousBatch
        )
    }

    private func loadStageScenePacket(stageID: UInt32) -> GoldenEyeStageScenePacket? {
        stageScenePacketCacheLock.lock()
        if let cached = stageScenePacketCache[stageID] {
            stageScenePacketCacheLock.unlock()
            return cached
        }
        stageScenePacketCacheLock.unlock()
        guard let root = stageAssetRootURL else { return nil }
        do {
            let catalog = try GoldenEyeStageAssetCatalog.load(stageAssetRoot: root)
            let packet = try GoldenEyeStageScenePacket.load(stageID: stageID, catalog: catalog)
            stageScenePacketCacheLock.lock()
            if let cached = stageScenePacketCache[stageID] {
                stageScenePacketCacheLock.unlock()
                return cached
            }
            stageScenePacketCache[stageID] = packet
            stageScenePacketCacheLock.unlock()
            return packet
        } catch {
            try? "stageSceneLoadFailure=1 stage=\(stageID) error=\(error)\n".write(
                toFile: "/tmp/goldeneye-source-product-renderer-v6-stage-composition.log",
                atomically: false,
                encoding: .utf8
            )
            return nil
        }
    }

    /// Clear every published route field. Callers must hold `frameStateLock`.
    /// Keeping this operation centralized prevents a rejected asynchronous
    /// V7 build from accidentally leaving a title, environment, or stage
    /// snapshot available to the supplied-drawable callback.
    private func invalidatePublishedFrameLocked() {
        latestScene = nil
        latestStageScene = nil
        latestStageComposition = nil
        latestStagePacketHash = 0
        latestStageUnsupportedMask = 0
        latestStageMaterialHash = 0
        latestStageMaterialStateCount = 0
        latestStageTexturePending = 0
        latestStageGameplayCameraPacketHash = 0
        latestStageGameplayCameraSubsetHash = 0
        latestStageFullSceneUnsupportedMask = 0
        latestStageFrameResources = nil
        stageCompositionCache.removeAll(keepingCapacity: true)
        latestTitleSnapshot = nil
        latestSource2DFrame = nil
        latestSource2DBackgroundFrame = nil
        latestSourceFrame = nil
        latestGunbarrelPass = nil
        pendingModelExecutionResult = nil
    }

    private func stageTexturePending(
        _ materialPacket: GoldenEyeStageSourceMaterialPacketV6
    ) -> UInt32 {
        guard materialPacket.textureStateCommandCount > 0 else { return 0 }
        guard let stageTextureCatalog else {
            return materialPacket.unsupportedTextureBindingCount
        }
        guard stageTextureCatalog.isGPURepresentable,
              stageTextureCatalog.allBindingsPrepared else {
            return materialPacket.unsupportedTextureBindingCount
        }
        let ids = Set(materialPacket.states.compactMap { $0.resolvedTextureID })
        guard !ids.isEmpty,
              ids.allSatisfy({ stageTextureCatalog.texture(textureID: $0) != nil }) else {
            return materialPacket.unsupportedTextureBindingCount
        }
        return 0
    }

    /// Lower one explicitly selected, fully prepared Cast row through the
    /// same source GBI/texture/Metal scene path as Gunbarrel. Body/head/
    /// weapon names, source camera values, attachments, text and fade remain
    /// copied source values; no source-index or diagnostic-character gate is
    /// used here.
    func submit(castSceneRequest request: GoldenEyeCastSourceSceneRequestV6) throws {
        frameStateLock.lock()
        defer { frameStateLock.unlock() }
        publicationGeneration &+= 1
        guard let sidecar = gunbarrelSidecar, sidecar.resolvesGunbarrelModels else {
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                "Cast animation/attachment sidecar is missing"
            )
        }

        let availableModels = castModels
        let availableNames = Set(availableModels.keys)
        let availableHandles = availableModels.reduce(into: [String: UInt32]()) {
            $0[$1.key] = $1.value.header.modelHandle
        }
        let binding: GoldenEyeCastPreparedModelBindingV6
        do {
            binding = try GoldenEyeCastSceneComposerV6.resolveModels(
                identity: request.identity,
                animation: request.animation,
                availableModelNames: availableNames,
                availableHandles: availableHandles,
                randomWord: request.randomWord,
                requestedWeaponPropID: request.weapon?.propID
            )
        } catch GoldenEyeCastSceneComposerV6Error.missingWeapon {
            // The source roster can select a prop ID whose distinct packet is
            // not present in the guarded Cast catalog. Resolve the same
            // animation against the prepared pool instead of terminating the
            // attract route at its first Cast frame.
            binding = try GoldenEyeCastSceneComposerV6.resolveModels(
                identity: request.identity,
                animation: request.animation,
                availableModelNames: availableNames,
                availableHandles: availableHandles,
                randomWord: request.randomWord,
                requestedWeaponPropID: nil
            )
        }
        let castCatalog = castPreparation?.catalog ?? preparation.catalog
        let resolver = GESourceModelDynamicResolverV6(resolvedModels: availableNames)

        let sceneFrame = try GoldenEyeGBISceneFrameContextV6(
            nativeTick: request.nativeTick,
            referenceTick: request.nativeTick >> 1,
            sourceTimer: request.sourceTimer,
            pairPhase: request.nativeTick & 1 == 0 ? 0 : 1,
            screen: UInt32(GE_SOURCE_FRAME_V6_SCREEN_CAST),
            subphase: UInt32(request.identity.sourceIndex),
            viewportWidth: 440,
            viewportHeight: 330
        )
        let castClipName = try Self.castAnimationClipName(request.animation.animationID)
        let castClip = try sidecar.clip(named: castClipName)
        let castFrameQ16 = Int64(request.animation.startFrameQ16)
            + Int64(request.sourceFrameQ16)
        let castFrame = UInt32(max(0, castFrameQ16) >> 16) % castClip.frameCount
        let modelNames = [binding.bodyName, binding.headName, binding.weaponName]
            .filter { !$0.isEmpty }
        var built: [GoldenEyeGBISceneBuildResultV6] = []
        built.reserveCapacity(modelNames.count)
        guard let bodyModelForAttachment = availableModels[binding.bodyName] else {
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                "Cast body packet is missing: \(binding.bodyName)"
            )
        }
        let bodyPosesForAttachment = try sidecar.sourcePoseRecords(
            modelHandle: sidecar.attachment.bodyModelHandle,
            clipName: castClipName,
            frame: castFrame,
            flip: request.flip,
            translationScaleQ16: GoldenEyeSourceNodeTransformContextV6.cast.rootTranslationScaleQ16
        )
        let bodyFrameResources = try GoldenEyeCastCameraResourcesV6.make(
            modelMatrixHandles: modelMatrixHandles(for: modelNames, models: availableModels),
            distanceQ16: request.cameraDistanceQ16,
            angleQ16: request.cameraAngleQ16,
            heightQ16: request.cameraHeightQ16,
            rootOffsetQ16: request.rootOffsetQ16,
            targetOffsetQ16: request.targetOffsetQ16
        )
        latestStageFrameResources = bodyFrameResources
        let bodyTopology = try castTopology(
            modelName: binding.bodyName,
            model: bodyModelForAttachment,
            resolver: resolver,
            catalog: castCatalog
        )
        let bodyScene = bodyTopology.scene
        let bodyLowering = try GoldenEyeSourceNodeTransformLowererV6.lower(
            model: bodyModelForAttachment,
            scene: bodyScene,
            poses: bodyPosesForAttachment,
            modelName: binding.bodyName,
            transformContext: .cast
        )
        func attachmentValues(_ switchIndex: UInt32) -> [Int32]? {
            guard let handle = bodyLowering.attachmentBoneHandle(
                model: bodyModelForAttachment,
                modelName: binding.bodyName,
                switchIndex: switchIndex
            ), let transform = bodyLowering.transformByHandle[handle] else {
                return nil
            }
            return gunbarrelMatrixQ16V6(transform)
        }
        let weaponSwitchForCast: UInt32 = request.flip ? 5 : 3
        let headAttachmentValuesForCast: [Int32]?
        if binding.headName.isEmpty {
            // Source Model.c marks bodies such as Natalya as embedded-head
            // models. Their SwitchNodes[4] entry is intentionally NULL, so
            // requiring a separate neck matrix would reject an otherwise
            // complete source body before the weapon hand is resolved.
            headAttachmentValuesForCast = nil
        } else {
            guard let values = attachmentValues(4) else {
                throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                    "Cast body neck attachment matrix is missing "
                        + "body=\(binding.bodyName) poses=\(bodyPosesForAttachment.count) "
                        + "bindings=\(bodyLowering.bindings.count) "
                        + "exactMatrices=\(bodyLowering.exactMatrixAssociations.count) "
                        + "matrixTransforms=\(bodyLowering.matrixTransformHandles.count)"
                )
            }
            headAttachmentValuesForCast = values
        }
        guard let weaponAttachmentValuesForCast = attachmentValues(weaponSwitchForCast) else {
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                "Cast body hand attachment matrix is missing "
                    + "body=\(binding.bodyName) poses=\(bodyPosesForAttachment.count) "
                    + "bindings=\(bodyLowering.bindings.count) "
                    + "exactMatrices=\(bodyLowering.exactMatrixAssociations.count) "
                    + "matrixTransforms=\(bodyLowering.matrixTransformHandles.count) "
                    + "weaponSwitch=\(weaponSwitchForCast)"
            )
        }

        for modelName in modelNames {
            guard let model = availableModels[modelName] else {
                throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                    "Cast prepared model is missing: \(modelName)"
                )
            }
            let matrixRoles = try bodyFrameResources.matrices.compactMap {
                matrix -> GoldenEyeSourceMatrixRoleSidecarV6? in
                guard matrix.roleFlags != 0 else { return nil }
                return try GoldenEyeSourceMatrixRoleSidecarV6(
                    handle: matrix.handle, roleFlags: matrix.roleFlags
                )
            }
            let topology = try castTopology(
                modelName: modelName,
                model: model,
                resolver: resolver,
                catalog: castCatalog
            )
            let compiledScene = topology.scene
            let resolvedScene = GoldenEyeGBIResolvedSceneInputV6(
                scene: compiledScene
            )
            let poses = modelName == binding.bodyName ? bodyPosesForAttachment : []
            let attachmentValues: [Int32]?
            switch modelName {
            case binding.headName: attachmentValues = headAttachmentValuesForCast
            case binding.weaponName:
                attachmentValues = request.flip
                    ? Self.castFlippedWeaponAttachment(weaponAttachmentValuesForCast)
                    : weaponAttachmentValuesForCast
            default: attachmentValues = nil
            }
            var modelMatrices = bodyFrameResources.matrices
            if let attachmentValues {
                for (index, command) in model.commands.enumerated()
                    where command.semantic.hasPrefix("gsSPMatrix") {
                    guard let token = model.tokens(for: index).first,
                          token.encodedValue != 0,
                          let matrixIndex = modelMatrices.firstIndex(where: {
                              $0.handle == token.encodedValue
                          }) else { continue }
                    let existing = modelMatrices[matrixIndex]
                    modelMatrices[matrixIndex] = try GoldenEyeGBIMatrixResourceV6(
                        handle: existing.handle,
                        values: attachmentValues,
                        roleFlags: existing.roleFlags
                    )
                }
            }
            let result: GoldenEyeGBISceneBuildResultV6
            do {
                result = try GoldenEyeGBISceneBuilderV6.build(
                    model: model,
                    modelName: modelName,
                    matrices: modelMatrices,
                    viewports: bodyFrameResources.viewports,
                    matrixRoles: matrixRoles,
                    frame: sceneFrame,
                    dynamicResolver: resolver,
                animationPoses: poses,
                transformContext: .cast,
                renderSetupContext: .cast(forModel: model, scene: compiledScene),
                textureSetups: topology.textureSetups,
                resolvedScene: resolvedScene
                )
            } catch {
                throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                    "Cast request model \(modelName) GBI build failed: \(error)"
                )
            }
            guard result.presentable,
                  result.unsupportedVisibleCount == 0,
                  !result.snapshot.drawCommands.isEmpty,
                  (modelName == binding.bodyName || result.snapshot.animationPoses.isEmpty) else {
                throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                    "Cast model \(modelName) is not presentable "
                        + "(unsupported=\(result.unsupportedVisibleCount) "
                        + "reasons=\(result.unsupportedReasons))"
                )
            }
            built.append(result)
        }

        let snapshot = try GoldenEyeCastSceneComposerV6.compose(
            built,
            frame: sceneFrame
        )
        guard snapshot.isPresentable,
              snapshot.summary.screen == UInt32(GE_SOURCE_FRAME_V6_SCREEN_CAST),
              snapshot.summary.unsupported_visible_count == 0,
              snapshot.summary.draw_count > 0,
              snapshot.summary.pose_count > 0 else {
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                "Cast composed scene is not presentable"
            )
        }
        latestStageScene = nil
        latestStagePacketHash = 0
        latestStageUnsupportedMask = 0
        latestStageMaterialHash = 0
        latestStageMaterialStateCount = 0
        latestStageTexturePending = 0
        latestScene = snapshot
        latestSource2DFrame = try source2DLowerer.makeCastFrame(
            nativeTick: request.nativeTick,
            sourceTimer: request.sourceTimer,
            textSourceHashes: [request.identity.text1SourceID, request.identity.text2SourceID, request.identity.text3SourceID],
            fadeAlpha: presentationVisibilityAlpha(request.fadeQ16),
            fullActorIntro: request.fullActorIntro
        )
        latestTitleSnapshot = nil
        latestSource2DBackgroundFrame = nil
        latestSourceFrame = nil
        latestGunbarrelPass = nil
        lastRenderableSceneScreen = UInt32(GE_SOURCE_FRAME_V6_SCREEN_CAST)
        pendingModelExecutionResult = nil
        try? "castSubmit=1 nativeTick=\(request.nativeTick) sourceIndex=\(request.identity.sourceIndex) body=\(request.identity.bodyID) head=\(request.identity.headID) weapon=\(request.weapon?.propID ?? UInt16.max) animation=\(request.animation.animationID) draws=\(snapshot.summary.draw_count) vertices=\(snapshot.summary.vertex_count) poses=\(snapshot.summary.pose_count) sceneHash=\(snapshot.summary.scene_hash) renderHash=\(snapshot.summary.render_hash)\n".write(
            toFile: "/tmp/goldeneye-source-product-renderer-v6-cast.log",
            atomically: false,
            encoding: .utf8
        )
    }

    /// Submit one source cast frame after the owner has supplied its copied
    /// camera/matrix resources.  The frontend authority owns identity,
    /// animation timing, fade and randomized route selection; this renderer
    /// only resolves the guarded body/head/weapon GESM packets and composes
    /// their complete dynamic pose scenes.  No cast identity is substituted
    /// when its distinct prepared assets are unavailable.
    func submit(
        castFrame: GoldenEyeCastSceneFrameV6,
        frameResources: GoldenEyeSourceProductFrameResourcesV6
    ) throws {
        frameStateLock.lock()
        defer { frameStateLock.unlock() }
        publicationGeneration &+= 1
        latestStageFrameResources = frameResources
        latestScene = nil
        latestStageScene = nil
        latestStagePacketHash = 0
        latestStageUnsupportedMask = 0
        latestStageMaterialHash = 0
        latestStageMaterialStateCount = 0
        latestStageTexturePending = 0
        latestGunbarrelPass = nil
        latestTitleSnapshot = nil
        latestSource2DFrame = nil
        latestSource2DBackgroundFrame = nil
        latestSourceFrame = nil
        pendingModelExecutionResult = nil

        guard castFrame.isRenderable,
              castFrame.unsupportedVisibleCommandCount == 0 else {
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                "cast frame is not renderable (unsupported=\(castFrame.unsupportedVisibleCommandCount))"
            )
        }
        let identity = try GoldenEyeCastSourceTableV6.identity(sourceIndex: castFrame.sourceIndex)
        let animation = try GoldenEyeCastSceneComposerV6.animation(for: identity)
        let availableModels = castModels
        let availableNames = Set(availableModels.keys)
        let availableHandles = availableModels.reduce(into: [String: UInt32]()) {
            $0[$1.key] = $1.value.header.modelHandle
        }
        let binding = try GoldenEyeCastSceneComposerV6.resolveModels(
            identity: identity,
            animation: animation,
            availableModelNames: availableNames,
            availableHandles: availableHandles
        )
        guard let sidecar = gunbarrelSidecar, sidecar.resolvesGunbarrelModels else {
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                "cast dynamic animation/attachment sidecar is missing"
            )
        }
        let sourceTimer = UInt32(max(0, Int64(castFrame.sourceFrameQ16) >> 16))
        let sceneFrame = try GoldenEyeGBISceneFrameContextV6(
            nativeTick: castFrame.nativeTick,
            referenceTick: castFrame.referenceTick,
            sourceTimer: sourceTimer,
            pairPhase: castFrame.pairPhase,
            screen: 7,
            subphase: UInt32(castFrame.sourceIndex),
            viewportWidth: frameResources.viewportWidth,
            viewportHeight: frameResources.viewportHeight
        )
        let matrixRoles = try frameResources.matrices.compactMap {
            matrix -> GoldenEyeSourceMatrixRoleSidecarV6? in
            guard matrix.roleFlags != 0 else { return nil }
            return try GoldenEyeSourceMatrixRoleSidecarV6(
                handle: matrix.handle, roleFlags: matrix.roleFlags
            )
        }
        let castClipName = try Self.castAnimationClipName(animation.animationID)
        let castClip = try sidecar.clip(named: castClipName)
        let animationFrameQ16 = Int64(animation.startFrameQ16)
            + Int64(castFrame.sourceFrameQ16)
        let animationFrame = UInt32(max(0, animationFrameQ16) >> 16)
            % castClip.frameCount
        let resolver = GESourceModelDynamicResolverV6(resolvedModels: availableNames)
        let castCatalog = castPreparation?.catalog ?? preparation.catalog
        guard let bodyModelForCast = availableModels[binding.bodyName] else {
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                "Cast body packet is missing: \(binding.bodyName)"
            )
        }
        let bodyPosesForCast = try sidecar.sourcePoseRecords(
            modelHandle: bodyModelForCast.header.modelHandle,
            clipName: castClipName,
            frame: animationFrame,
            translationScaleQ16: GoldenEyeSourceNodeTransformContextV6.cast.rootTranslationScaleQ16
        )
        let bodyTopology = try castTopology(
            modelName: binding.bodyName,
            model: bodyModelForCast,
            resolver: resolver,
            catalog: castCatalog
        )
        let bodyScene = bodyTopology.scene
        let bodyLowering = try GoldenEyeSourceNodeTransformLowererV6.lower(
            model: bodyModelForCast,
            scene: bodyScene,
            poses: bodyPosesForCast,
            modelName: binding.bodyName,
            transformContext: .cast
        )
        func attachmentValues(_ switchIndex: UInt32) -> [Int32]? {
            guard let handle = bodyLowering.attachmentBoneHandle(
                model: bodyModelForCast,
                modelName: binding.bodyName,
                switchIndex: switchIndex
            ), let transform = bodyLowering.transformByHandle[handle] else {
                return nil
            }
            return gunbarrelMatrixQ16V6(transform)
        }
        // The older RAMROM frame contract does not carry the mirrored-hand
        // bit; its source camera path always uses the primary gun hand.
        let weaponSwitchForCastFrame: UInt32 = 3
        let headAttachmentValuesForCastFrame: [Int32]?
        if binding.headName.isEmpty {
            headAttachmentValuesForCastFrame = nil
        } else {
            guard let values = attachmentValues(4) else {
                throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                    "Cast body neck attachment matrix is missing "
                        + "body=\(binding.bodyName) poses=\(bodyPosesForCast.count) "
                        + "bindings=\(bodyLowering.bindings.count) "
                        + "exactMatrices=\(bodyLowering.exactMatrixAssociations.count) "
                        + "matrixTransforms=\(bodyLowering.matrixTransformHandles.count)"
                )
            }
            headAttachmentValuesForCastFrame = values
        }
        guard let weaponAttachmentValuesForCastFrame = attachmentValues(weaponSwitchForCastFrame) else {
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                "Cast body hand attachment matrix is missing "
                    + "body=\(binding.bodyName) poses=\(bodyPosesForCast.count) "
                    + "bindings=\(bodyLowering.bindings.count) "
                    + "exactMatrices=\(bodyLowering.exactMatrixAssociations.count) "
                    + "matrixTransforms=\(bodyLowering.matrixTransformHandles.count) "
                    + "weaponSwitch=\(weaponSwitchForCastFrame)"
            )
        }
        var results: [GoldenEyeGBISceneBuildResultV6] = []
        let modelNames = [binding.bodyName, binding.headName, binding.weaponName]
            .filter { !$0.isEmpty }
        results.reserveCapacity(modelNames.count)
        for modelName in modelNames {
            guard let model = availableModels[modelName] else {
                throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                    "Cast model packet is missing: \(modelName)"
                )
            }
            let topology = try castTopology(
                modelName: modelName,
                model: model,
                resolver: resolver,
                catalog: castCatalog
            )
            let compiledScene = topology.scene
            let poses = modelName == binding.bodyName ? bodyPosesForCast : []
            let attachmentValues: [Int32]?
            switch modelName {
            case binding.headName: attachmentValues = headAttachmentValuesForCastFrame
            case binding.weaponName: attachmentValues = weaponAttachmentValuesForCastFrame
            default: attachmentValues = nil
            }
            var modelMatrices = frameResources.matrices
            if let attachmentValues {
                for (index, command) in model.commands.enumerated()
                    where command.semantic.hasPrefix("gsSPMatrix") {
                    guard let token = model.tokens(for: index).first,
                          token.encodedValue != 0,
                          let matrixIndex = modelMatrices.firstIndex(where: {
                              $0.handle == token.encodedValue
                          }) else { continue }
                    let existing = modelMatrices[matrixIndex]
                    modelMatrices[matrixIndex] = try GoldenEyeGBIMatrixResourceV6(
                        handle: existing.handle,
                        values: attachmentValues,
                        roleFlags: existing.roleFlags
                    )
                }
            }
            let result: GoldenEyeGBISceneBuildResultV6
            do {
                result = try GoldenEyeGBISceneBuilderV6.build(
                    model: model,
                    modelName: modelName,
                    matrices: modelMatrices,
                    viewports: frameResources.viewports,
                    matrixRoles: matrixRoles,
                    frame: sceneFrame,
                    dynamicResolver: resolver,
                animationPoses: poses,
                transformContext: .cast,
                renderSetupContext: .cast(forModel: model, scene: compiledScene),
                textureSetups: topology.textureSetups,
                resolvedScene: GoldenEyeGBIResolvedSceneInputV6(scene: compiledScene)
                )
            } catch {
                throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                    "Cast frame model \(modelName) GBI build failed: \(error)"
                )
            }
            guard result.presentable,
                  result.unsupportedVisibleCount == 0,
                  !result.snapshot.drawCommands.isEmpty,
                  (modelName != binding.bodyName || !result.snapshot.animationPoses.isEmpty) else {
                throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                    "cast model \(modelName) has no complete pose/draw packet "
                        + "(unsupported=\(result.unsupportedVisibleCount) "
                        + "reasons=\(result.unsupportedReasons))"
                )
            }
            results.append(result)
        }
        let snapshot = try GoldenEyeCastSceneComposerV6.compose(results, frame: sceneFrame)
        guard snapshot.animationPoses.count == bodyPosesForCast.count,
              snapshot.summary.unsupported_visible_count == 0 else {
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                "cast composed pose packet is incomplete"
            )
        }
        latestScene = snapshot
        latestSource2DFrame = try source2DLowerer.makeCastFrame(
            nativeTick: castFrame.nativeTick,
            sourceTimer: sourceTimer,
            textSourceHashes: [identity.text1SourceID, identity.text2SourceID, identity.text3SourceID],
            fadeAlpha: presentationVisibilityAlpha(castFrame.fadeQ16),
            fullActorIntro: identity.sourceIndex == 0
        )
        lastRenderableSceneScreen = 7
    }

    private func presentationVisibilityAlpha(_ visibilityQ16: Int32) -> UInt8 {
        let source = Double(max(0, min(65_536, visibilityQ16))) / 65_536.0
        let visible = presentationTreatment.isEnhanced ? sqrt(source) : source
        return UInt8(max(0, min(255, (visible * 255.0).rounded())))
    }

    func acknowledgeSourceModelLoad(model: UInt32) throws {
        if model == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GUNBARREL) {
            guard gunbarrelSidecar?.resolvesGunbarrelModels == true else {
                throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                    "validated Gunbarrel animation/attachment sidecar is missing"
                )
            }
            resetGunbarrelBloodStream()
            return
        }
        guard let modelName = Self.modelNameForID[model],
              preparation.models[modelName] != nil else {
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                "prepared model load is missing for source model \(model)"
            )
        }
    }

    func resetGunbarrelBloodStream() {
        frameStateLock.lock()
        defer { frameStateLock.unlock() }
        gunbarrelBloodFrameIndex = 0
        gunbarrelBloodTickCount = 0
        gunbarrelBloodCompletionPending = false
        gunbarrelRootMotionStepper = nil
    }

    /// The source owner submits a complete copied event frame.  A frame whose
    /// only visible operation is CLEAR_BLACK is lowered directly to a
    /// presentable zero-draw scene; it does not need a matrix or texture.
    /// Model frames require explicit source matrices/viewports and are built
    /// before an executed result is exposed to the next authority step.
    func submit(
        sourceFrame: GoldenEyeSourceFrontendFrameV6,
        frameResources: GoldenEyeSourceProductFrameResourcesV6? = nil
    ) throws {
        // Preserve the last complete scene until the replacement model build
        // reaches its publication point.
        latestGunbarrelPass = nil
        latestTitleSnapshot = nil
        latestSource2DFrame = nil
        latestSource2DBackgroundFrame = nil
        latestSourceFrame = sourceFrame
        pendingModelExecutionResult = nil
        guard sourceFrame.nativeTick > 0 else {
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild("zero native tick")
        }
        let renderOperations = sourceFrame.renderEvents.map(\.operation)
        if sourceFrame.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_SWITCH) {
            // Keep the transition fail-closed: only the source's own
            // frame-begin/CLEAR_BLACK sequence may become this zero-draw
            // scene.  Model RELEASE/LOAD records are lifecycle bookkeeping
            // emitted around the transition and are not visible work; a
            // DRAW record would still fail instead of silently acquiring a
            // guessed matrix.
            let visibleModelEventCount = sourceFrame.modelEvents.reduce(into: 0) {
                if $1.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_DRAW) {
                    $0 += 1
                }
            }
            guard GoldenEyeSourceProductFrameClassifierV6.isClearBlackOnly(
                renderOperations: renderOperations,
                modelEventCount: visibleModelEventCount,
                textEventCount: sourceFrame.textEvents.count
            ), sourceRenderEventsMatch(sourceFrame) else {
                throw GoldenEyeSourceProductRendererV6Error.unsupportedSourceFrame(
                    max(sourceFrame.summary.unsupportedCount, 1)
                )
            }
            guard sourceFrame.summary.stateHash != 0,
                  sourceFrame.summary.renderHash != 0,
                  sourceFrame.summary.renderEventHash != 0 else {
                throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                    "switch clear-black source hashes are zero"
                )
            }
            latestScene = try makeClearBlackScene(sourceFrame: sourceFrame)
            latestTitleSnapshot = nil
            pendingModelExecutionResult = nil
            return
        }
        if GoldenEyeSourceProductFrameClassifierV6.isClearBlackOnly(
            renderOperations: renderOperations,
            modelEventCount: sourceFrame.modelEvents.count,
            textEventCount: sourceFrame.textEvents.count
        ) {
            guard sourceRenderEventsMatch(sourceFrame) else {
                throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                    "clear-black source render events do not match frame"
                )
            }
            guard sourceFrame.summary.stateHash != 0,
                  sourceFrame.summary.renderHash != 0,
                  sourceFrame.summary.renderEventHash != 0 else {
                throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                    "clear-black source hashes are zero"
                )
            }
            latestSourceFrame = sourceFrame
            latestScene = try makeClearBlackScene(sourceFrame: sourceFrame)
            latestTitleSnapshot = nil
            pendingModelExecutionResult = nil
            return
        }

        // Cast is owner-submitted through the complete source roster path.
        // A Cast frame reaching this generic source-frame entry point means
        // the roster/camera/pose handoff failed; keep Release fail-closed
        // instead of manufacturing a black or diagnostic character frame.
        if sourceFrame.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_CAST) {
            throw GoldenEyeSourceProductRendererV6Error.unsupportedSourceFrame(
                max(sourceFrame.summary.unsupportedCount, 1)
            )
        }

        let renderedScreen = GoldenEyeSourceFrontendScreenSelectionV6.renderableScreen(
            for: sourceFrame
        )
        let modelRequest: GoldenEyeSourceProductModelRequestV6
        if let modelEvent = sourceFrame.modelEvents.first(where: {
            $0.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_DRAW)
        }) {
            let modelSourceTimer: UInt32
            if modelEvent.model == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RAREWARELOGO) {
                // Rareware's animation uses the source counter, not the
                // inherited switch/menu timer carried on the model event.
                modelSourceTimer = sourceFrame.rarewareCounter
            } else if modelEvent.model ==
                        UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GUNBARREL) {
                modelSourceTimer = modelEvent.gunbarrelSourceSubstep ?? modelEvent.sourceTimer
            } else {
                modelSourceTimer = modelEvent.sourceTimer
            }
            modelRequest = try GoldenEyeSourceProductModelRequestV6(
                screen: renderedScreen,
                model: modelEvent.model,
                operation: modelEvent.operation,
                nativeTick: modelEvent.nativeTick,
                referenceTick: modelEvent.referenceTick,
                sourceTimer: modelSourceTimer,
                subphase: modelEvent.subphase,
                flags: modelEvent.flags
            )
        } else if renderedScreen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL),
                  let pipeline = sourceFrame.renderEvents.first(where: {
                      $0.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_GUNBARREL_PIPELINE)
                  }) {
            // Gunbarrel's initial source subphase has a valid model LOAD and
            // pipeline but no visible DRAW yet.  Use the typed pipeline event
            // to submit the guarded dynamic scene; do not invent a matrix or
            // fallback model.
            modelRequest = try GoldenEyeSourceProductModelRequestV6(
                screen: renderedScreen,
                model: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GUNBARREL),
                operation: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_DRAW),
                nativeTick: sourceFrame.nativeTick,
                referenceTick: sourceFrame.referenceTick,
                sourceTimer: 0,
                subphase: pipeline.subphase,
                flags: pipeline.flags
            )
        } else {
            if sourceFrame.summary.unsupportedCount != 0 {
                throw GoldenEyeSourceProductRendererV6Error.unsupportedSourceFrame(
                    sourceFrame.summary.unsupportedCount
                )
            }
            throw GoldenEyeSourceProductRendererV6Error.unsupportedScreen(sourceFrame.screen)
        }
        guard let frameResources else {
            throw GoldenEyeSourceProductRendererV6Error.missingFrameResources
        }
        latestStageFrameResources = frameResources
        try buildModelScene(
            request: modelRequest,
            sourceFrame: sourceFrame,
            frameResources: frameResources
        )
        latestSource2DFrame = try makeSource2DFrame(
            sourceFrame,
            screenOverride: renderedScreen
        )
        if renderedScreen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_FILE_SELECT)
                || renderedScreen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_MODE_SELECT) {
            latestSource2DBackgroundFrame = source2DLowerer.makeFileModeBackgroundFrame(
                nativeTick: sourceFrame.nativeTick,
                sourceTimer: sourceFrame.sourceTimer
            )
        }
    }

    /// Accepts a copied model request before the authority's next step.  This
    /// is the non-deadlocking handoff used when the prior authority frame
    /// contains a zero-result model event: scene construction is attempted
    /// from the request itself, and only a successful build yields EXECUTED.
    @discardableResult
    func submit(
        modelRequest request: GoldenEyeSourceProductModelRequestV6,
        frameResources: GoldenEyeSourceProductFrameResourcesV6
    ) throws -> GoldenEyeSourceProductModelExecutionResultV6 {
        frameStateLock.lock()
        defer { frameStateLock.unlock() }
        publicationGeneration &+= 1
        // Preserve the last complete scene until the replacement model build
        // reaches its publication point.
        latestGunbarrelPass = nil
        latestTitleSnapshot = nil
        latestSource2DFrame = nil
        latestSource2DBackgroundFrame = nil
        latestSourceFrame = nil
        pendingModelExecutionResult = nil
        try buildModelScene(
            request: request,
            sourceFrame: nil,
            frameResources: frameResources
        )
        guard let result = pendingModelExecutionResult else {
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                "model scene completed without an execution result"
            )
        }
        return result
    }

    /// The owner consumes this value and passes its five fixed-width fields
    /// to ``GoldenEyeSourceFrontendAuthorityV6.step`` on the next tick.
    func takeModelExecutionResult() -> GoldenEyeSourceProductModelExecutionResultV6? {
        frameStateLock.lock()
        defer { frameStateLock.unlock() }
        defer { pendingModelExecutionResult = nil }
        return pendingModelExecutionResult
    }

    @discardableResult
    private func buildModelScene(
        request: GoldenEyeSourceProductModelRequestV6,
        sourceFrame: GoldenEyeSourceFrontendFrameV6?,
        frameResources: GoldenEyeSourceProductFrameResourcesV6
    ) throws -> GoldenEyeSourceProductModelExecutionResultV6 {
        guard request.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_DRAW) else {
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                "only source model draw requests are renderable"
            )
        }
        if request.model == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GUNBARREL) {
            return try buildGunbarrelScene(
                request: request,
                sourceFrame: sourceFrame,
                frameResources: frameResources
            )
        }
        guard let modelName = Self.modelNameForID[request.model],
              Self.modelForScreen[request.screen] == modelName else {
            throw GoldenEyeSourceProductRendererV6Error.unsupportedScreen(request.screen)
        }
        let model: GoldenEyeSourceModelV6
        do {
            model = try preparation.model(named: modelName)
        } catch {
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(String(describing: error))
        }
        let frame: GoldenEyeGBISceneFrameContextV6
        do {
            frame = try GoldenEyeGBISceneFrameContextV6(
                nativeTick: request.nativeTick,
                referenceTick: request.referenceTick,
                sourceTimer: request.sourceTimer,
                pairPhase: request.nativeTick & 1 == 0 ? 0 : 1,
                screen: request.screen,
                subphase: request.subphase,
                viewportWidth: frameResources.viewportWidth,
                viewportHeight: frameResources.viewportHeight
            )
        } catch {
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(String(describing: error))
        }
        var result: GoldenEyeGBISceneBuildResultV6?
        var composedSnapshot: GoldenEyeSourceSceneSnapshotV6?
        var composedProjection: GoldenEyeGBIProjectionConsumptionEvidenceV6?
        var composedUnsupported: UInt32 = 0
        do {
            let matrixRoles = try frameResources.matrices.compactMap { matrix -> GoldenEyeSourceMatrixRoleSidecarV6? in
                guard matrix.roleFlags != 0 else { return nil }
                return try GoldenEyeSourceMatrixRoleSidecarV6(
                    handle: matrix.handle,
                    roleFlags: matrix.roleFlags
                )
            }
            let dynamicResolver: GESourceModelDynamicResolverV6? =
                modelName == "rarewarelogo"
                    ? GESourceModelDynamicResolverV6(resolvedModels: [modelName])
                    : nil
            let walletVisual: GoldenEyeWalletVisualInputPacketV6?
            if modelName == "walletbond" {
                try GoldenEyeWalletSwitchTextResolverV6.validate(model: model)
                let route: GoldenEyeWalletRouteV6 = request.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_FILE_SELECT)
                    ? .fileSelect
                    : .modeSelect
                let progress: [GoldenEyeWalletFolderProgressV6]
                if let sourceFrame, let saveState = sourceFrame.fileModeSaveState {
                    let view = try GoldenEyeSource2DFileModeViewV6(
                        frame: sourceFrame.fileModeFrame ?? (try GoldenEyeFileModeAuthorityV6(saveState: saveState)).lastFrame,
                        saveState: saveState
                    )
                    progress = view.folders.map {
                        GoldenEyeWalletFolderProgressV6(
                            number: $0.number,
                            isReset: $0.isReset,
                            hasCompletion: $0.hasCompletion,
                            highestStage: $0.highestStage,
                            highestDifficulty: $0.highestDifficulty
                        )
                    }
                } else {
                    progress = []
                }
                walletVisual = try GoldenEyeWalletSwitchTextResolverV6.resolve(
                    route: route,
                    folders: progress,
                    selectedFolder: sourceFrame?.fileModeFrame?.state.selectedFolder ?? 0,
                    selectedBond: UInt32(sourceFrame?.fileModeSaveState?.selectedBond ?? 0),
                    modeSelection: sourceFrame?.fileModeFrame?.state.modeSelection ?? 0,
                    controllerCount: sourceFrame?.fileModeFrame?.state.controllerCount ?? 1,
                    eraseConfirmation: sourceFrame?.fileModeFrame.map { $0.state.flags & GE_FILE_MODE_V6_STATE_FLAG_ERASE_CONFIRM != 0 } ?? false,
                    eraseChoice: sourceFrame?.fileModeFrame?.state.eraseChoice ?? 1
                )
            } else {
                walletVisual = nil
            }
            let walletSwitchInputs = walletVisual?.switchInputs ?? [:]
            let cacheKey = GoldenEyeSourceTitleRenderCacheV6.makeKey(
                model: model,
                modelName: modelName,
                screen: request.screen,
                switchInputs: walletSwitchInputs,
                routeIdentity: walletVisual?.semanticHash ?? 0
            )
            // A changed model packet, screen route, or wallet switch/save
            // state must not reuse an older topology. Keep other model routes
            // warm while removing stale entries for this source model.
            compiledModelCache = compiledModelCache.filter {
                $0.key.modelName != modelName || $0.key == cacheKey
            }
            var cached = compiledModelCache[cacheKey]
            let resolvedSceneInput: GoldenEyeGBIResolvedSceneInputV6
            let textureSetups: [GoldenEyeSourceTextureSetupV6]
            if let cached {
                resolvedSceneInput = GoldenEyeGBIResolvedSceneInputV6(scene: cached.scene)
                textureSetups = cached.textureSetups
            } else {
                let compilation = GESourceModelCompilerV6.compile(
                    model,
                    modelName: modelName,
                    switchInputs: walletSwitchInputs,
                    dynamicResolver: dynamicResolver,
                    switchInputsAreVisibility: walletVisual != nil
                )
                guard compilation.status == .complete,
                      let scene = compilation.scene,
                      compilation.diagnostics.isEmpty else {
                    throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                        "texture setup source traversal is incomplete for \(modelName)"
                    )
                }
                let setupScene = modelName == "rarewarelogo"
                    ? GoldenEyeGBISceneBuilderV6.rarewareSceneWithOuterSetup(
                        model: model,
                        scene: scene
                    )
                    : scene
                let setupResult = try GoldenEyeSourceTextureSetupResolverV6.resolve(
                    modelName: modelName,
                    model: model,
                    catalog: preparation.catalog,
                    compiledCommands: setupScene.commands
                )
                if modelName == "rarewarelogo" {
                    // Rareware is a linked source segment rather than a
                    // normal node graph.  Its validated capture path carries
                    // the typed per-list vertex resources and all six source
                    // texture handles; use that same bounded override here
                    // so production does not attempt to infer a graph group
                    // that the segment intentionally does not expose.
                    resolvedSceneInput = GoldenEyeGBIResolvedSceneInputV6(
                        scene: setupScene,
                        vertexResources: try GoldenEyeGBISceneBuilderV6.vertexResourceOverrides(
                            model: model,
                            scene: setupScene
                        ),
                        additionalTextureHandles: model.textures.map(\.resourceHandle)
                    )
                } else {
                    resolvedSceneInput = GoldenEyeGBIResolvedSceneInputV6(scene: setupScene)
                }
                textureSetups = setupResult.setups
            }
            if modelName == "walletbond",
               request.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_FILE_SELECT) {
                let modelMatrices = frameResources.matrices.filter {
                    $0.roleFlags & GoldenEyeSourceMatrixRoleSidecarV6.modelView != 0
                }
                guard modelMatrices.count == 4 else {
                    throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                        "File Select requires four source wallet matrices, got \(modelMatrices.count)"
                    )
                }
                let sourceModelHandle = modelMatrices[0].handle
                var walletResults: [GoldenEyeGBISceneBuildResultV6] = []
                walletResults.reserveCapacity(modelMatrices.count)
                for walletMatrix in modelMatrices {
                    let scopedMatrices = frameResources.matrices.filter {
                        $0.roleFlags & GoldenEyeSourceMatrixRoleSidecarV6.modelView == 0
                    } + [try GoldenEyeGBIMatrixResourceV6(
                        handle: sourceModelHandle,
                        values: walletMatrix.values,
                        roleFlags: GoldenEyeSourceMatrixRoleSidecarV6.modelView
                    )]
                    let scopedHandles = Set(scopedMatrices.map(\.handle))
                    let scopedRoles = matrixRoles.filter { scopedHandles.contains($0.handle) }
                    let walletResult: GoldenEyeGBISceneBuildResultV6
                    if let cached {
                        compiledModelCacheHits &+= 1
                        walletResult = try GoldenEyeSourceTitleRenderCacheV6.reframe(
                            cached,
                            model: model,
                            modelName: modelName,
                            frame: frame,
                            matrices: scopedMatrices,
                            viewports: frameResources.viewports
                        )
                    } else {
                        compiledModelCacheMisses &+= 1
                        walletResult = try GoldenEyeGBISceneBuilderV6.build(
                            model: model,
                            modelName: modelName,
                            switchInputs: walletSwitchInputs,
                            matrices: scopedMatrices,
                            viewports: frameResources.viewports,
                            matrixRoles: scopedRoles,
                            frame: frame,
                            textureSetups: textureSetups,
                            resolvedScene: resolvedSceneInput,
                            switchInputsAreVisibility: walletVisual != nil
                        )
                        if cached == nil {
                            let entry = GoldenEyeSourceTitleRenderCacheV6.makeEntry(
                                key: cacheKey,
                                scene: resolvedSceneInput.scene,
                                textureSetups: textureSetups,
                                result: walletResult
                            )
                            compiledModelCache[cacheKey] = entry
                            cached = entry
                        }
                    }
                    guard walletResult.presentable,
                          walletResult.unsupportedVisibleCount == 0,
                          walletResult.snapshot.drawCommands.count == 8 else {
                        throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                            "File Select wallet instance is incomplete (draws=\(walletResult.snapshot.drawCommands.count), unsupported=\(walletResult.unsupportedVisibleCount))"
                        )
                    }
                    walletResults.append(walletResult)
                }
                composedSnapshot = try GoldenEyeSourceSceneComposerV6.combine(walletResults, frame: frame)
                composedProjection = walletResults.first?.projectionConsumption
                composedUnsupported = walletResults.reduce(UInt32(0)) {
                    $0 &+ $1.unsupportedVisibleCount
                }
            } else {
                if let cached {
                    compiledModelCacheHits &+= 1
                    result = try GoldenEyeSourceTitleRenderCacheV6.reframe(
                        cached,
                        model: model,
                        modelName: modelName,
                        frame: frame,
                        matrices: frameResources.matrices,
                        viewports: frameResources.viewports
                    )
                } else {
                    compiledModelCacheMisses &+= 1
                    let built = try GoldenEyeGBISceneBuilderV6.build(
                        model: model,
                        modelName: modelName,
                        switchInputs: walletSwitchInputs,
                        matrices: frameResources.matrices,
                        viewports: frameResources.viewports,
                        matrixRoles: matrixRoles,
                        frame: frame,
                        dynamicResolver: dynamicResolver,
                        textureSetups: textureSetups,
                        resolvedScene: resolvedSceneInput,
                        switchInputsAreVisibility: walletVisual != nil
                    )
                    result = built
                    let entry = GoldenEyeSourceTitleRenderCacheV6.makeEntry(
                        key: cacheKey,
                        scene: resolvedSceneInput.scene,
                        textureSetups: textureSetups,
                        result: built
                    )
                    compiledModelCache[cacheKey] = entry
                }
            }
        } catch {
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(String(describing: error))
        }
        let snapshot: GoldenEyeSourceSceneSnapshotV6
        let projectionConsumption: GoldenEyeGBIProjectionConsumptionEvidenceV6
        let unsupportedVisibleCount: UInt32
        let presentable: Bool
        if let result {
            snapshot = result.snapshot
            projectionConsumption = result.projectionConsumption
            unsupportedVisibleCount = result.unsupportedVisibleCount
            presentable = result.presentable
        } else if let composedSnapshot, let composedProjection {
            snapshot = composedSnapshot
            projectionConsumption = composedProjection
            unsupportedVisibleCount = composedUnsupported
            presentable = composedSnapshot.isPresentable
        } else {
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                "source scene build produced no snapshot"
            )
        }
        guard presentable, unsupportedVisibleCount == 0 else {
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                "scene is not presentable (unsupported=\(unsupportedVisibleCount))"
            )
        }
        guard projectionConsumption.isComplete else {
            throw GoldenEyeSourceProductRendererV6Error.projectionNotConsumed(
                projectionConsumption
            )
        }

        if let sourceFrame = sourceFrame {
            recordSourceDiagnostics(sourceFrame.diagnosticEvents)
            guard GoldenEyeSourceFrontendScreenSelectionV6.containsModelDraw(
                sourceFrame,
                model: request.model,
                operation: request.operation,
                renderedScreen: request.screen
            ) else {
                throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                    "model request does not belong to source frame"
                )
            }
            latestSourceFrame = sourceFrame
        } else {
            latestSourceFrame = nil
        }
        latestScene = snapshot
        latestGunbarrelPass = nil
        lastRenderableSceneScreen = request.screen
        latestTitleSnapshot = nil
        pendingModelExecutionResult = .executed(model: request.model, operation: request.operation)
        return pendingModelExecutionResult!
    }

    /// Lower only the source-owned frontend 2D stream for screens that emit
    /// text, fills, or texture rectangles.  The source 3D scene and this
    /// packet remain separate immutable products until the renderer opens
    /// their one shared Metal render pass.
    private func buildGunbarrelScene(
        request: GoldenEyeSourceProductModelRequestV6,
        sourceFrame: GoldenEyeSourceFrontendFrameV6?,
        frameResources: GoldenEyeSourceProductFrameResourcesV6
    ) throws -> GoldenEyeSourceProductModelExecutionResultV6 {
        guard let sidecar = gunbarrelSidecar, sidecar.resolvesGunbarrelModels else {
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                "validated Gunbarrel animation/attachment sidecar is missing"
            )
        }
        let gunbarrelMode = request.subphase &+ 2
        if gunbarrelMode != 5 {
            gunbarrelBloodCompletionPending = false
        }
        let pipelineEvent = sourceFrame?.renderEvents.first {
            $0.operation == GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_GUNBARREL_PIPELINE
        }
        let titleXQ16 = pipelineEvent?.value0 ?? (-30 * 65_536)
        let transitionXQ16 = sourceFrame?.renderEvents.first {
            $0.operation == GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_CONTINUOUS_STATE
                && $0.subphase == GE_SOURCE_FRONTEND_RUNTIME_V6_CONTINUOUS_GUNBARREL_TRANSLATION
        }?.value1 ?? gunbarrelTransitionXQ16
        // title.c does not submit Bond during the first dot-sweep mode, and
        // keeps the character off-screen during the first part of mode 3
        // until the moving sight reaches the authored reveal threshold.
        let bondVisible = gunbarrelMode >= 4
            || (gunbarrelMode == 3 && titleXQ16 < 600 * 65_536)

        if let sourceFrame {
            recordSourceDiagnostics(sourceFrame.diagnosticEvents)
            let modelBelongs = sourceFrame.modelEvents.contains {
                $0.model == request.model
                    && ($0.operation == request.operation
                        || (request.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_DRAW)
                            && $0.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_BLOOD_TICK)))
            }
            let pipelineBelongs = sourceFrame.renderEvents.contains {
                $0.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_GUNBARREL_PIPELINE)
            }
            guard sourceFrame.screen == request.screen,
                  modelBelongs || pipelineBelongs else {
                throw GoldenEyeSourceProductRendererV6Error.sourceBuild("Gunbarrel request does not belong to source frame")
            }
            latestSourceFrame = sourceFrame
        } else {
            latestSourceFrame = nil
        }
        if request.nativeTick & 1 == 1,
           let previous = gunbarrelPreviousAnchorScene,
           let current = gunbarrelCurrentAnchorScene {
            let interpolated = try interpolateGunbarrelScene(
                previous: previous,
                current: current,
                nativeTick: request.nativeTick
            )
            latestScene = interpolated
            if let anchorPass = gunbarrelCurrentAnchorPass {
                latestGunbarrelPass = reframeGunbarrelPass(
                    anchorPass,
                    sourceFrame: sourceFrame,
                    titleXQ16: titleXQ16,
                    transitionXQ16: transitionXQ16
                )
            } else {
                latestGunbarrelPass = nil
            }
            lastRenderableSceneScreen = request.screen
            pendingModelExecutionResult = gunbarrelModelExecutionResult(
                request: request,
                sourceFrame: sourceFrame,
                snapshot: interpolated,
                sidecar: sidecar
            )
            return pendingModelExecutionResult!
        }
        let sceneFrame = try GoldenEyeGBISceneFrameContextV6(
            nativeTick: request.nativeTick,
            referenceTick: request.referenceTick,
            sourceTimer: request.sourceTimer,
            pairPhase: request.nativeTick & 1 == 0 ? 0 : 1,
            screen: request.screen,
            subphase: request.subphase,
            viewportWidth: frameResources.viewportWidth,
            viewportHeight: frameResources.viewportHeight
        )

        // The source mode-2 dot sweep is a 2D/non-model phase.  Keep the
        // dynamic Bond scene absent until title.c's explicit reveal gate; the
        // compositor still renders the generated dot/hole pass below.
        if !bondVisible {
            let snapshot = try makeEmptyGunbarrelScene(frame: sceneFrame)
            let gunbarrelPass = GoldenEyeGunbarrelRenderPassV6.make(
                nativeTick: request.nativeTick,
                mode: gunbarrelMode,
                poseCount: 0,
                bloodPayloadAvailable: !sidecar.bloodEncoded.isEmpty,
                bloodVisible: false,
                muzzleFlashVisible: false,
                fade: .none,
                fadeAlphaQ8: 0,
                titleXQ16: titleXQ16,
                bloodFrameIndex: 0,
                transitionXQ16: transitionXQ16,
                backgroundVisible: gunbarrelMode >= 3 && gunbarrelMode <= 7,
                holeVisible: gunbarrelMode >= 2 && gunbarrelMode <= 7
            )
            if request.nativeTick & 1 == 0 {
                gunbarrelPreviousAnchorScene = gunbarrelCurrentAnchorScene
                gunbarrelCurrentAnchorScene = snapshot
                gunbarrelCurrentAnchorPass = gunbarrelPass
            }
            latestScene = snapshot
            latestGunbarrelPass = gunbarrelPass
            lastRenderableSceneScreen = request.screen
            latestTitleSnapshot = nil
            pendingModelExecutionResult = gunbarrelModelExecutionResult(
                request: request,
                sourceFrame: sourceFrame,
                snapshot: snapshot,
                sidecar: sidecar
            )
            return pendingModelExecutionResult!
        }

        let sourceSubstep = request.sourceTimer
        var rootMotionStepper = try gunbarrelRootMotionStepper
            ?? GoldenEyeGunbarrelDynamicSidecarV6.RootMotionStepperV6(sidecar: sidecar)
        let integratedRootMotion = try rootMotionStepper.advance(to: sourceSubstep)
        gunbarrelRootMotionStepper = rootMotionStepper
        let resolver = sidecar.dynamicResolver
        let roles = try frameResources.matrices.compactMap {
            matrix -> GoldenEyeSourceMatrixRoleSidecarV6? in
            guard matrix.roleFlags != 0 else { return nil }
            return try GoldenEyeSourceMatrixRoleSidecarV6(
                handle: matrix.handle, roleFlags: matrix.roleFlags
            )
        }
        let names = ["suitbond", "headbrosnansuit", "chrwppk"]
        let clipName = integratedRootMotion.clipName
        let animationFrame = UInt32(
            max(0, integratedRootMotion.frameQ16 / 65_536)
        ) % (try sidecar.clip(named: clipName)).frameCount
        let muzzleVisible = bondVisible && sourceSubstep == 230 && (request.nativeTick & 1) == 0
        let bloodTickRequested = sourceFrame?.modelEvents.contains {
            $0.model == request.model
                && $0.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_BLOOD_TICK)
        } == true
        if bloodTickRequested {
            // The source BLOOD_TICK callback decodes before the paired DRAW;
            // frame zero was primed at mode entry, so the first continuation
            // displays frame one and the 41st continuation displays frame 41.
            gunbarrelBloodTickCount = min(gunbarrelBloodTickCount &+ 1, 41)
            gunbarrelBloodFrameIndex = gunbarrelBloodTickCount
            // The result mailbox is consumed one native tick before the
            // source callback that can advance the state. Once continuation
            // 40 is visible, retain completion through draw-only substeps so
            // continuation 41 can consume it without changing the source
            // frame count.
            if gunbarrelBloodTickCount >= 40 {
                gunbarrelBloodCompletionPending = true
            }
        }
        let bloodFrameIndex = gunbarrelBloodFrameIndex
        let bodyModel = try preparation.model(named: "suitbond")
        let bodyPoses = try sidecar.sourcePoseRecords(
            modelHandle: bodyModel.header.modelHandle,
            clipName: clipName,
            frame: animationFrame,
            integratedRootMotion: integratedRootMotion
        )
        let bodyTopology: GunbarrelTopologyCacheEntry
        if let cached = gunbarrelTopologyCache["suitbond"] {
            bodyTopology = cached
        } else {
            let compilation = GESourceModelCompilerV6.compile(
                bodyModel,
                modelName: "suitbond",
                dynamicResolver: resolver
            )
            guard compilation.status == .complete,
                  let scene = compilation.scene,
                  compilation.diagnostics.isEmpty,
                  scene.unsupportedCount == 0 else {
                throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                    "Gunbarrel body attachment traversal is incomplete"
                )
            }
            let setup = try GoldenEyeSourceTextureSetupResolverV6.resolve(
                modelName: "suitbond",
                model: bodyModel,
                catalog: preparation.catalog,
                compiledCommands: scene.commands
            )
            let value = GunbarrelTopologyCacheEntry(scene: scene, textureSetups: setup.setups)
            gunbarrelTopologyCache["suitbond"] = value
            bodyTopology = value
        }
        let bodyScene = bodyTopology.scene
        let bodyLowering = try GoldenEyeSourceNodeTransformLowererV6.lower(
            model: bodyModel,
            scene: bodyScene,
            poses: bodyPoses,
            modelName: "suitbond"
        )
        let bodyBaseHandle = try firstModelMatrixHandle(bodyModel)
        guard let bodyBase = frameResources.matrices.first(where: {
            $0.handle == bodyBaseHandle
        }) else {
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                "Gunbarrel body base matrix is missing"
            )
        }
        let boneMatrices = Dictionary(uniqueKeysWithValues: bodyLowering.transforms.map {
            ($0.handle, gunbarrelMatrixQ16V6($0))
        })
        func attachmentValues(matrixID: UInt32) -> [Int32]? {
            let sourceHandle = GoldenEyeCastSkeletonTransformV6.matrixHandle(
                modelName: "suitbond", matrixID: matrixID
            )
            guard let association = bodyLowering.exactMatrixAssociations[sourceHandle],
                  let bone = boneMatrices[association.transformHandle] else {
                return nil
            }
            return GoldenEyeSourceProjectionBindingV6.multiply(bodyBase.values, bone)
        }
        let headAttachmentValues = attachmentValues(matrixID: 0)
        let weaponAttachmentValues = attachmentValues(matrixID: 15)
        guard headAttachmentValues != nil, weaponAttachmentValues != nil else {
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                "Gunbarrel attachment matrices are missing (head joint3 / weapon joint9)"
            )
        }
        var built: [GoldenEyeGBISceneBuildResultV6] = []
        for name in names {
            let model = try preparation.model(named: name)
            let topology: GunbarrelTopologyCacheEntry
            if let cached = gunbarrelTopologyCache[name] {
                topology = cached
            } else {
                let compilation = GESourceModelCompilerV6.compile(
                    model,
                    modelName: name,
                    dynamicResolver: resolver
                )
                guard compilation.status == .complete,
                      let compiledScene = compilation.scene,
                      compilation.diagnostics.isEmpty,
                      compiledScene.unsupportedCount == 0 else {
                    throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                        "Gunbarrel dynamic source traversal is incomplete for \(name): \(compilation.diagnostics)"
                    )
                }
                let setup = try GoldenEyeSourceTextureSetupResolverV6.resolve(
                    modelName: name,
                    model: model,
                    catalog: preparation.catalog,
                    compiledCommands: compiledScene.commands
                )
                let value = GunbarrelTopologyCacheEntry(
                    scene: compiledScene,
                    textureSetups: setup.setups
                )
                gunbarrelTopologyCache[name] = value
                topology = value
            }
            let compiledScene = topology.scene
            let textureSetups = topology.textureSetups
            let resolvedScene = GoldenEyeGBIResolvedSceneInputV6(
                scene: compiledScene
            )
            let poses: [GESourceAnimationPoseV6]
            switch name {
            case "suitbond":
                poses = bodyPoses
            case "headbrosnansuit":
                // The head is an attached source model with one identity
                // root for exact node provenance; its placement still comes
                // from the body neck matrix below.
                poses = [makeGunbarrelAttachmentPoseV6(modelHandle: model.header.modelHandle)]
            default:
                // PP7 is attached to body matrix15/joint9. It has no
                // independent animation pose or synthetic weapon skeleton.
                poses = []
            }
            let attachmentValues: [Int32]?
            switch name {
            case "headbrosnansuit": attachmentValues = headAttachmentValues
            case "chrwppk": attachmentValues = weaponAttachmentValues
            default: attachmentValues = nil
            }
            var modelMatrices = frameResources.matrices
            if let attachmentValues {
                for (index, command) in model.commands.enumerated()
                    where command.semantic.hasPrefix("gsSPMatrix") {
                    guard let token = model.tokens(for: index).first,
                          token.encodedValue != 0,
                          let matrixIndex = modelMatrices.firstIndex(where: {
                              $0.handle == token.encodedValue
                          }) else { continue }
                    let existing = modelMatrices[matrixIndex]
                    modelMatrices[matrixIndex] = try GoldenEyeGBIMatrixResourceV6(
                        handle: existing.handle,
                        values: attachmentValues,
                        roleFlags: existing.roleFlags
                    )
                }
            }
            let result = try GoldenEyeGBISceneBuilderV6.build(
                model: model,
                modelName: name,
                // The generic V6 builder lowers the immutable animation poses
                // into exact node/clip transforms. The parent-world body
                // lowering above is used only to obtain head/weapon
                // attachment matrices; feeding those matrices back for the
                // body would apply every joint a second time.
                matrices: modelMatrices,
                viewports: frameResources.viewports,
                matrixRoles: roles,
                frame: sceneFrame,
                dynamicResolver: resolver,
                animationPoses: poses,
                renderSetupContext: .gunbarrel,
                textureSetups: textureSetups,
                resolvedScene: resolvedScene,
                omittedDisplayListIDs: name == "chrwppk" && !muzzleVisible
                    ? Set<UInt32>([1])
                    : []
            )
            guard result.presentable, result.unsupportedVisibleCount == 0,
                  !result.snapshot.drawCommands.isEmpty else {
                throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                    "Gunbarrel scene \(name) has no presentable draws (unsupported=\(result.unsupportedVisibleCount))"
                )
            }
            built.append(result)
        }
        let gunbarrelFade: GoldenEyeGunbarrelFrameV6.Fade = switch gunbarrelMode {
        case 6, 7: .red
        case 8: .clearBlack
        default: .none
        }
        let gunbarrelOverlayAlphaQ8: UInt32
        if gunbarrelMode == 7 {
            let counter = sourceFrame?.modelEvents.compactMap {
                $0.gunbarrelSourceSubstep
            }.first ?? 0
            gunbarrelOverlayAlphaQ8 = min(counter, 248)
        } else if gunbarrelMode == 8 {
            gunbarrelOverlayAlphaQ8 = 255
        } else if gunbarrelMode == 6 {
            gunbarrelOverlayAlphaQ8 = 180
        } else {
            gunbarrelOverlayAlphaQ8 = 0
        }
        let combinedSnapshot = try combineGunbarrelScenes(built, frame: sceneFrame)
        // The source animation's root-motion packet is retained for pose and
        // attachment provenance, but its world-space travel continues after
        // Bond has reached the authored sight. Keep the final presentation
        // centered as one composed character (body, head, and PP7) instead of
        // letting the root packet carry the visible model off the barrel.
        let snapshot = try centerGunbarrelPresentation(
            combinedSnapshot,
            mode: gunbarrelMode
        )
        let gunbarrelPass = GoldenEyeGunbarrelRenderPassV6.make(
            nativeTick: request.nativeTick,
            mode: gunbarrelMode,
            poseCount: snapshot.summary.pose_count,
            bloodPayloadAvailable: !sidecar.bloodEncoded.isEmpty,
            bloodVisible: gunbarrelMode == 5,
            muzzleFlashVisible: muzzleVisible,
            fade: gunbarrelFade,
            fadeAlphaQ8: gunbarrelOverlayAlphaQ8,
            titleXQ16: titleXQ16,
            bloodFrameIndex: bloodFrameIndex,
            transitionXQ16: transitionXQ16,
            backgroundVisible: gunbarrelMode >= 3 && gunbarrelMode <= 7,
            holeVisible: gunbarrelMode >= 3 && gunbarrelMode <= 7
        )
        if request.nativeTick & 1 == 0 {
            gunbarrelPreviousAnchorScene = gunbarrelCurrentAnchorScene
            gunbarrelCurrentAnchorScene = snapshot
            gunbarrelCurrentAnchorPass = gunbarrelPass
        }
        latestScene = snapshot
        latestGunbarrelPass = gunbarrelPass
        lastRenderableSceneScreen = request.screen
        latestTitleSnapshot = nil
        pendingModelExecutionResult = gunbarrelModelExecutionResult(
            request: request,
            sourceFrame: sourceFrame,
            snapshot: snapshot,
            sidecar: sidecar
        )
        return pendingModelExecutionResult!
    }

    private func gunbarrelModelExecutionResult(
        request: GoldenEyeSourceProductModelRequestV6,
        sourceFrame: GoldenEyeSourceFrontendFrameV6?,
        snapshot: GoldenEyeSourceSceneSnapshotV6,
        sidecar: GoldenEyeGunbarrelDynamicSidecarV6
    ) -> GoldenEyeSourceProductModelExecutionResultV6 {
        let bloodTickRequested = sourceFrame?.modelEvents.contains {
            $0.model == request.model
                && $0.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_BLOOD_TICK)
        } == true || (
            sourceFrame?.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL)
                && sourceFrame?.modelEvents.contains {
                    $0.model == request.model
                        && $0.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_DRAW)
                        && $0.subphase == 3
                } == true
                && (sourceFrame?.nativeTick ?? 0) & 1 == 1
        )
        let bloodPlaybackFrame = request.subphase == 3
            && sourceFrame?.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL)
        guard (bloodTickRequested || (bloodPlaybackFrame && gunbarrelBloodCompletionPending)),
              !sidecar.bloodEncoded.isEmpty else {
            return .executed(
                model: request.model,
                operation: request.operation,
                value0: snapshot.summary.pose_count,
                value1: snapshot.summary.draw_count
            )
        }
        let complete = gunbarrelBloodCompletionPending || gunbarrelBloodFrameIndex >= 41
        return .sourceResult(
            model: request.model,
            operation: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_BLOOD_TICK),
            flags: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_EXECUTED)
                | (complete
                    ? UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_BLOOD_COMPLETE)
                    : 0),
            value0: gunbarrelBloodFrameIndex,
            value1: snapshot.summary.draw_count
        )
    }

    private func interpolateGunbarrelScene(
        previous: GoldenEyeSourceSceneSnapshotV6,
        current: GoldenEyeSourceSceneSnapshotV6,
        nativeTick: UInt64
    ) throws -> GoldenEyeSourceSceneSnapshotV6 {
        let sameIndices = previous.indices.count == current.indices.count && zip(
            previous.indices, current.indices
        ).allSatisfy {
            $0.0.vertex0 == $0.1.vertex0 && $0.0.vertex1 == $0.1.vertex1
                && $0.0.vertex2 == $0.1.vertex2
        }
        let sameDraws = previous.drawCommands.count == current.drawCommands.count && zip(
            previous.drawCommands, current.drawCommands
        ).allSatisfy {
            $0.0.draw_handle == $0.1.draw_handle
                && $0.0.first_vertex == $0.1.first_vertex
                && $0.0.vertex_count == $0.1.vertex_count
                && $0.0.first_index == $0.1.first_index
                && $0.0.index_count == $0.1.index_count
        }
        let sameStates = previous.renderStates.count == current.renderStates.count && zip(
            previous.renderStates, current.renderStates
        ).allSatisfy { $0.0.state_handle == $0.1.state_handle }
        let sameResources = previous.resources.count == current.resources.count && zip(
            previous.resources, current.resources
        ).allSatisfy { $0.0.handle == $0.1.handle && $0.0.content_hash == $0.1.content_hash }
        guard previous.vertices.count == current.vertices.count,
              previous.summary.screen == current.summary.screen,
              previous.summary.subphase == current.summary.subphase,
              sameIndices, sameDraws, sameStates, sameResources,
              previous.transforms.count == current.transforms.count else {
            return current
        }
        // Dynamic scene vertices are still in their source model space.  The
        // per-draw clip transform carries the animated bone/attachment
        // matrix, so interpolating vertices alone leaves the odd half-step
        // rendered through the *current* pose and produces a visible snap
        // (most obviously at Bond's walk -> fire transition). Interpolate
        // the value-only transform records alongside the vertices and keep
        // the handle/role envelope unchanged.
        var transforms = current.transforms
        for index in transforms.indices {
            guard previous.transforms[index].handle == current.transforms[index].handle,
                  previous.transforms[index].transform_kind == current.transforms[index].transform_kind else {
                return current
            }
            var value = current.transforms[index]
            withUnsafeBytes(of: previous.transforms[index].matrix_q16) { previousBytes in
                withUnsafeMutableBytes(of: &value.matrix_q16) { currentBytes in
                    let previousValues = previousBytes.bindMemory(to: Int32.self)
                    let currentValues = currentBytes.bindMemory(to: Int32.self)
                    guard previousValues.count == currentValues.count else { return }
                    for matrixIndex in currentValues.indices {
                        currentValues[matrixIndex] = midpoint(
                            previousValues[matrixIndex],
                            currentValues[matrixIndex]
                        )
                    }
                }
            }
            transforms[index] = value
        }
        var vertices = current.vertices
        for index in vertices.indices {
            guard previous.vertices[index].handle == current.vertices[index].handle,
                  previous.vertices[index].source_index == current.vertices[index].source_index else {
                return current
            }
            var value = current.vertices[index]
            value.position_q16.0 = midpoint(previous.vertices[index].position_q16.0, value.position_q16.0)
            value.position_q16.1 = midpoint(previous.vertices[index].position_q16.1, value.position_q16.1)
            value.position_q16.2 = midpoint(previous.vertices[index].position_q16.2, value.position_q16.2)
            value.normal_q16.0 = midpoint(previous.vertices[index].normal_q16.0, value.normal_q16.0)
            value.normal_q16.1 = midpoint(previous.vertices[index].normal_q16.1, value.normal_q16.1)
            value.normal_q16.2 = midpoint(previous.vertices[index].normal_q16.2, value.normal_q16.2)
            vertices[index] = value
        }
        var summary = current.summary
        summary.native_tick = nativeTick
        summary.reference_tick = nativeTick >> 1
        summary.pair_phase = 1
        summary.flags = (summary.flags | UInt32(GE_SOURCE_FRAME_V6_FLAG_PRESENTABLE)
            | UInt32(GE_SOURCE_FRAME_V6_FLAG_INTERPOLATED))
            & ~UInt32(GE_SOURCE_FRAME_V6_FLAG_SOURCE_ANCHOR)
        var hash: UInt64 = 1_469_598_103_934_665_603
        hash ^= previous.copiedRecordAggregateHash
        hash &*= 1_099_511_628_211
        hash ^= current.copiedRecordAggregateHash
        hash &*= 1_099_511_628_211
        hash ^= nativeTick
        hash &*= 1_099_511_628_211
        if hash == 0 { hash = 1 }
        summary.scene_hash = hash
        summary.render_hash = hash ^ 0x9E37_79B9_7F4A_7C15
        summary.frame_hash = hash ^ 0xD1B5_4A32_D192_ED03
        // The interpolated vertices are published under the odd native tick,
        // so the lighting sidecar must carry that same frame identity.  The
        // previous snapshot reused the even anchor's context, which made the
        // renderer reject the otherwise valid frame as stale and left the
        // title/intro route visibly frozen at the first dynamic scene.
        var interpolatedModelViews = current.lightingFrameContext?.modelViewQ16ByState ?? [:]
        if let previousLighting = previous.lightingFrameContext,
           let currentLighting = current.lightingFrameContext {
            for (stateHandle, currentValues) in currentLighting.modelViewQ16ByState {
                guard let previousValues = previousLighting.modelViewQ16ByState[stateHandle],
                      previousValues.count == currentValues.count else { continue }
                interpolatedModelViews[stateHandle] = zip(previousValues, currentValues).map {
                    midpoint($0, $1)
                }
            }
        }
        let interpolatedLighting = try current.lightingFrameContext.map {
            try GoldenEyeSourceSceneLightingFrameContextV6(
                screen: $0.screen,
                nativeTick: nativeTick,
                referenceTick: nativeTick >> 1,
                sourceTimer: $0.sourceTimer,
                pairPhase: 1,
                geometryModesByState: $0.geometryModesByState,
                modelViewQ16ByState: interpolatedModelViews
            )
        }
        return try GoldenEyeSourceSceneSnapshotV6(
            summary: summary,
            resources: current.resources,
            transforms: transforms,
            animationPoses: current.animationPoses,
            vertices: vertices,
            indices: current.indices,
            renderStates: current.renderStates,
            drawCommands: current.drawCommands,
            textEvents: current.textEvents,
            audioEvents: current.audioEvents,
            diagnostics: current.diagnostics,
            lightingFrameContext: interpolatedLighting
        )
    }

    private func midpoint(_ a: Int32, _ b: Int32) -> Int32 {
        Int32((Int64(a) + Int64(b)) / 2)
    }

    private func reframeGunbarrelPass(
        _ pass: GoldenEyeGunbarrelRenderPassV6,
        sourceFrame: GoldenEyeSourceFrontendFrameV6?,
        titleXQ16: Int32,
        transitionXQ16: Int32
    ) -> GoldenEyeGunbarrelRenderPassV6 {
        // The odd source frame already carries the midpoint translations in
        // its render events. Keep the anchor's mode/payload policy while
        // rebasing only those two compositor positions. A mode transition can
        // occur between the even anchor and this odd frame, so prefer the
        // source pipeline subphase when it is available.
        let mode = sourceFrame?.renderEvents.first(where: {
            $0.operation == GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_GUNBARREL_PIPELINE
        }).map { $0.subphase &+ 2 } ?? pass.mode
        return GoldenEyeGunbarrelRenderPassV6.make(
            nativeTick: pass.nativeTick,
            mode: mode,
            poseCount: pass.poseCount,
            bloodPayloadAvailable: pass.bloodPayloadAvailable,
            bloodVisible: pass.bloodVisible,
            muzzleFlashVisible: pass.muzzleFlashVisible,
            fade: pass.fade,
            fadeAlphaQ8: pass.fadeAlphaQ8,
            titleXQ16: titleXQ16,
            bloodFrameIndex: pass.bloodFrameIndex,
            transitionXQ16: transitionXQ16,
            backgroundVisible: mode >= 3 && mode <= 7,
            holeVisible: mode >= 2 && mode <= 7
        )
    }

    private func combineGunbarrelScenes(
        _ results: [GoldenEyeGBISceneBuildResultV6],
        frame: GoldenEyeGBISceneFrameContextV6
    ) throws -> GoldenEyeSourceSceneSnapshotV6 {
        var resources: [GESourceResourceV6] = []
        var transforms: [GESourceTransformV6] = []
        var poses: [GESourceAnimationPoseV6] = []
        var vertices: [GESourceVertexV6] = []
        var indices: [GESourceIndexV6] = []
        var states: [GESourceRenderStateV6] = []
        var draws: [GESourceDrawCommandV6] = []
        var diagnostics: [GESourceDiagnosticV6] = []
        var resourceHandles = Set<UInt32>()
        var resourceHashes: [UInt32: UInt64] = [:]
        var transformHandles = Set<UInt32>()
        var poseHandles = Set<UInt32>()
        var stateHandles = Set<UInt32>()
        var drawHandles = Set<UInt32>()
        var geometryModesByState: [UInt32: UInt32] = [:]
        var modelViewQ16ByState: [UInt32: [Int32]] = [:]
        for (sceneIndex, result) in results.enumerated() {
            let scene = result.snapshot
            let vertexOffset = UInt32(vertices.count)
            let indexOffset = UInt32(indices.count)
            let resourcePrefix = UInt32(0xE000_0000) | UInt32(sceneIndex + 1) << 20
            let transformPrefix = UInt32(0xE100_0000) | UInt32(sceneIndex + 1) << 20
            let statePrefix = UInt32(0xE200_0000) | UInt32(sceneIndex + 1) << 20
            let drawPrefix = UInt32(0xE300_0000) | UInt32(sceneIndex + 1) << 20
            let posePrefix = UInt32(0xE400_0000) | UInt32(sceneIndex + 1) << 20
            let vertexPrefix = UInt32(0xE500_0000) | UInt32(sceneIndex + 1) << 20
            let indexPrefix = UInt32(0xE600_0000) | UInt32(sceneIndex + 1) << 20
            var resourceMap: [UInt32: UInt32] = [:]
            var transformMap: [UInt32: UInt32] = [:]
            var stateMap: [UInt32: UInt32] = [:]
            for source in scene.resources {
                var value = source
                let texture = source.resource_kind == UInt32(GE_SOURCE_RESOURCE_V6_TEXTURE)
                    || source.resource_kind == UInt32(GE_SOURCE_RESOURCE_V6_PALETTE)
                if texture, let priorHash = resourceHashes[source.handle] {
                    guard priorHash == source.content_hash else {
                        throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                            "Gunbarrel texture handle collision 0x\(String(source.handle, radix: 16))"
                        )
                    }
                    resourceMap[source.handle] = source.handle
                    continue
                }
                if !texture || resourceHandles.contains(source.handle) {
                    value.handle = resourcePrefix | (source.handle & 0x000F_FFFF)
                }
                resourceMap[source.handle] = value.handle
                resourceHandles.insert(value.handle)
                resourceHashes[value.handle] = value.content_hash
                resources.append(value)
            }
            for source in scene.transforms {
                var value = source
                // Source matrix/clip handles may share low bits across the
                // body and attachment graphs.  Allocate the composed handle
                // from the destination transform ordinal instead of
                // truncating the source handle and creating a duplicate V6
                // transform record.
                value.handle = transformPrefix | UInt32(transforms.count & 0x000F_FFFF)
                transformMap[source.handle] = value.handle
                transformHandles.insert(value.handle)
                transforms.append(value)
            }
            for source in scene.renderStates {
                var value = source
                value.state_handle = statePrefix | (source.state_handle & 0x000F_FFFF)
                stateMap[source.state_handle] = value.state_handle
                stateHandles.insert(value.state_handle)
                states.append(value)
            }
            if let lighting = scene.lightingFrameContext {
                for (sourceHandle, mode) in lighting.geometryModesByState {
                    if let mapped = stateMap[sourceHandle] { geometryModesByState[mapped] = mode }
                }
                for (sourceHandle, matrix) in lighting.modelViewQ16ByState {
                    if let mapped = stateMap[sourceHandle] { modelViewQ16ByState[mapped] = matrix }
                }
            }
            for source in scene.vertices {
                var value = source
                value.handle = vertexPrefix | (source.handle & 0x000F_FFFF)
                vertices.append(value)
            }
            for source in scene.indices {
                var value = source
                value.handle = indexPrefix | (source.handle & 0x000F_FFFF)
                // Each dynamic model owns a local vertex/index window.  The
                // product composer concatenates those windows, so preserve
                // the source triangle topology while rebasing all three
                // vertex references into the combined snapshot.
                value.vertex0 &+= vertexOffset
                value.vertex1 &+= vertexOffset
                value.vertex2 &+= vertexOffset
                indices.append(value)
            }
            for source in scene.animationPoses {
                var value = source
                value.pose_handle = posePrefix | (source.pose_handle & 0x000F_FFFF)
                poseHandles.insert(value.pose_handle)
                poses.append(value)
            }
            for source in scene.drawCommands {
                var value = source
                value.draw_handle = drawPrefix | (source.draw_handle & 0x000F_FFFF)
                value.transform_handle = transformMap[source.transform_handle] ?? source.transform_handle
                value.render_state_handle = stateMap[source.render_state_handle] ?? source.render_state_handle
                value.resource_handle = resourceMap[source.resource_handle] ?? source.resource_handle
                value.first_vertex &+= vertexOffset
                value.first_index &+= indexOffset
                drawHandles.insert(value.draw_handle)
                draws.append(value)
            }
            diagnostics.append(contentsOf: scene.diagnostics)
        }
        var summary = GESourceFrameSummaryV6()
        summary.header.abi_version = UInt32(GE_NATIVE_ABI_VERSION)
        summary.header.struct_size = UInt32(MemoryLayout<GESourceFrameSummaryV6>.size)
        summary.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
        summary.flags = UInt32(GE_SOURCE_FRAME_V6_FLAG_PRESENTABLE)
            | (frame.pairPhase == 0 ? UInt32(GE_SOURCE_FRAME_V6_FLAG_SOURCE_ANCHOR) : UInt32(GE_SOURCE_FRAME_V6_FLAG_INTERPOLATED))
        summary.screen = frame.screen; summary.subphase = frame.subphase
        summary.native_tick = frame.nativeTick; summary.reference_tick = frame.referenceTick
        summary.pair_phase = frame.pairPhase; summary.viewport_width = frame.viewportWidth
        summary.viewport_height = frame.viewportHeight; summary.logical_width = frame.logicalWidth
        summary.logical_height = frame.logicalHeight; summary.transform_count = UInt32(transforms.count)
        summary.resource_count = UInt32(resources.count); summary.pose_count = UInt32(poses.count)
        summary.vertex_count = UInt32(vertices.count); summary.index_count = UInt32(indices.count)
        summary.draw_count = UInt32(draws.count); summary.render_state_count = UInt32(states.count)
        summary.text_count = 0; summary.audio_count = 0; summary.diagnostic_count = UInt32(diagnostics.count)
        summary.unsupported_visible_count = 0
        var hash: UInt64 = 1_469_598_103_934_665_603
        for result in results { hash ^= result.snapshot.copiedRecordAggregateHash; hash &*= 1_099_511_628_211; hash ^= result.eventHash; hash &*= 1_099_511_628_211 }
        hash ^= UInt64(summary.pose_count) << 32 | UInt64(summary.draw_count)
        if hash == 0 { hash = 1 }
        summary.scene_hash = hash; summary.render_hash = hash ^ 0x9E37_79B9_7F4A_7C15
        summary.state_hash = hash ^ 0xD1B5_4A32_D192_ED03; summary.audio_hash = 1
        summary.frame_hash = hash ^ UInt64(frame.nativeTick); summary.reserved0 = 0; summary.reserved1 = 0
        let lighting = try GoldenEyeSourceSceneLightingFrameContextV6(
            screen: frame.screen,
            nativeTick: frame.nativeTick,
            referenceTick: frame.referenceTick,
            sourceTimer: frame.sourceTimer ?? 0,
            pairPhase: frame.pairPhase,
            geometryModesByState: geometryModesByState,
            modelViewQ16ByState: modelViewQ16ByState
        )
        return try GoldenEyeSourceSceneSnapshotV6(
            summary: summary,
            resources: resources,
            transforms: transforms,
            animationPoses: poses,
            vertices: vertices,
            indices: indices,
            renderStates: states,
            drawCommands: draws,
            textEvents: [],
            audioEvents: [],
            diagnostics: diagnostics,
            lightingFrameContext: lighting
        )
    }

    /// Align the settled Gunbarrel presentation without rewriting the source
    /// animation records.  The source root packet is an accumulated world
    /// translation; after the reveal it continues to walk Bond left even
    /// though the title's sight/backdrop has reached its authored center. A
    /// clip-space translation is applied to every composed body/attachment
    /// draw, preserving perspective, pose, normals, and the original copied
    /// root-motion values while making the visible character a single centered
    /// unit.
    private func centerGunbarrelPresentation(
        _ snapshot: GoldenEyeSourceSceneSnapshotV6,
        mode: UInt32
    ) throws -> GoldenEyeSourceSceneSnapshotV6 {
        guard mode >= 4, mode <= 7 else { return snapshot }

        let bodyDrawPrefix: UInt32 = 0xE310_0000
        let bodyDraws = snapshot.drawCommands.filter {
            $0.draw_handle & 0xFFF0_0000 == bodyDrawPrefix
        }
        guard !bodyDraws.isEmpty else { return snapshot }

        let transformsByHandle = snapshot.transformByHandle
        var minX = Double.infinity
        var minY = Double.infinity
        var maxX = -Double.infinity
        var maxY = -Double.infinity
        var projectedPoints = 0

        for draw in bodyDraws {
            guard let transform = transformsByHandle[draw.transform_handle],
                  transform.transform_kind == UInt32(GE_SOURCE_TRANSFORM_V6_CLIP_COMPOSITE) else {
                return snapshot
            }
            let matrix = gunbarrelMatrixQ16V6(transform)
            let firstIndex = Int(draw.first_index)
            let endIndex = firstIndex + Int(draw.index_count)
            guard firstIndex >= 0, endIndex <= snapshot.indices.count else {
                return snapshot
            }
            for index in snapshot.indices[firstIndex..<endIndex] {
                for vertexHandle in [index.vertex0, index.vertex1, index.vertex2] {
                    let vertexIndex = Int(vertexHandle)
                    guard vertexIndex >= 0, vertexIndex < snapshot.vertices.count else {
                        return snapshot
                    }
                    let vertex = snapshot.vertices[vertexIndex]
                    let projected = try GoldenEyeSourceProjectionBindingV6.apply(
                        matrixQ16: matrix,
                        pointQ16: (
                            x: vertex.position_q16.0,
                            y: vertex.position_q16.1,
                            z: vertex.position_q16.2
                        )
                    )
                    guard projected.w > 0 else { continue }
                    let reciprocalW = 1.0 / Double(projected.w)
                    let x = Double(projected.x) * reciprocalW
                    let y = Double(projected.y) * reciprocalW
                    guard x.isFinite, y.isFinite else { continue }
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                    projectedPoints += 1
                }
            }
        }

        guard projectedPoints > 0,
              minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite else {
            return snapshot
        }
        let deltaXQ16 = Int32(clamping: Int64((-(minX + maxX) * 0.5 * 65_536.0).rounded()))
        let deltaYQ16 = Int32(clamping: Int64((-(minY + maxY) * 0.5 * 65_536.0).rounded()))
        guard deltaXQ16 != 0 || deltaYQ16 != 0 else { return snapshot }

        let drawTransformHandles = Set(snapshot.drawCommands.map(\.transform_handle))
        var transforms = snapshot.transforms
        for index in transforms.indices {
            let transform = transforms[index]
            guard drawTransformHandles.contains(transform.handle),
                  transform.transform_kind == UInt32(GE_SOURCE_TRANSFORM_V6_CLIP_COMPOSITE) else {
                continue
            }
            transforms[index] = shiftedGunbarrelClipTransform(
                transform,
                deltaXQ16: deltaXQ16,
                deltaYQ16: deltaYQ16
            )
        }

        return try GoldenEyeSourceSceneSnapshotV6(
            reframing: snapshot,
            summary: snapshot.summary,
            transforms: transforms,
            renderStates: snapshot.renderStates,
            lightingFrameContext: snapshot.lightingFrameContext
        )
    }

    private func shiftedGunbarrelClipTransform(
        _ transform: GESourceTransformV6,
        deltaXQ16: Int32,
        deltaYQ16: Int32
    ) -> GESourceTransformV6 {
        var result = transform
        var values = gunbarrelMatrixQ16V6(transform)
        for column in 0..<4 {
            let base = column * 4
            values[base] = Int32(clamping:
                Int64(values[base])
                    + ((Int64(deltaXQ16) * Int64(values[base + 3])) >> 16)
            )
            values[base + 1] = Int32(clamping:
                Int64(values[base + 1])
                    + ((Int64(deltaYQ16) * Int64(values[base + 3])) >> 16)
            )
        }
        withUnsafeMutableBytes(of: &result.matrix_q16) { rawBytes in
            let typed = rawBytes.bindMemory(to: Int32.self)
            for index in values.indices {
                typed[index] = values[index]
            }
        }
        return result
    }

    /// Capture-only seam for the source menu harness.  It reuses the same
    /// bounded scene composition used by the Release owner; no production
    /// renderer state or Metal object crosses this value-only boundary.
    func composeSourceScenesForCapture(
        _ results: [GoldenEyeGBISceneBuildResultV6],
        frame: GoldenEyeGBISceneFrameContextV6
    ) throws -> GoldenEyeSourceSceneSnapshotV6 {
        try GoldenEyeSourceSceneComposerV6.combine(results, frame: frame)
    }

    private func makeSource2DFrame(
        _ sourceFrame: GoldenEyeSourceFrontendFrameV6,
        screenOverride: UInt32? = nil
    ) throws -> GoldenEyeSource2DFrameV6? {
        let screen = screenOverride ?? GoldenEyeSourceFrontendScreenSelectionV6.renderableScreen(
            for: sourceFrame
        )
        guard screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_LEGAL)
                || screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_FILE_SELECT)
                || screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_MODE_SELECT) else {
            return nil
        }
        let renderEvents = sourceFrame.renderEvents.map { event in
            GoldenEyeSource2DRenderEventV6(
                screen: event.screen,
                operation: event.operation,
                subphase: event.subphase,
                nativeTick: event.nativeTick,
                referenceTick: event.referenceTick,
                sourceTimer: event.sourceTimer,
                value0: event.value0,
                value1: event.value1,
                flags: event.flags,
                sequence: event.sequence
            )
        }
        let textEvents = sourceFrame.textEvents.map { event in
            GoldenEyeSource2DTextEventV6(
                screen: event.screen,
                textID: event.textID,
                x: event.x,
                y: event.y,
                nativeTick: event.nativeTick,
                sourceTimer: event.sourceTimer,
                flags: event.flags,
                sequence: event.sequence
            )
        }
        if let menuFrame = sourceFrame.fileModeFrame,
           let saveState = sourceFrame.fileModeSaveState {
            let menu = try GoldenEyeSource2DFileModeViewV6(
                frame: menuFrame,
                saveState: saveState
            )
            switch screen {
            case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_FILE_SELECT):
                return try source2DLowerer.makeFileSelectFrame(
                    nativeTick: sourceFrame.nativeTick,
                    sourceTimer: sourceFrame.sourceTimer,
                    menu: menu
                )
            case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_MODE_SELECT):
                return try source2DLowerer.makeModeSelectFrame(
                    nativeTick: sourceFrame.nativeTick,
                    sourceTimer: sourceFrame.sourceTimer,
                    menu: menu
                )
            default:
                break
            }
        }
        return try source2DLowerer.lower(
            screen: screen,
            nativeTick: sourceFrame.nativeTick,
            sourceTimer: sourceFrame.sourceTimer,
            renderEvents: renderEvents,
            textEvents: textEvents
        )
    }

    /// Presentable zero-draw scene used while title.c is still running the
    /// mode-2 dot sweep (and while mode 3 is waiting for the sight reveal).
    /// The non-model compositor owns the visible work for those frames; an
    /// empty source scene keeps the renderer's clear/depth/present contract
    /// intact without leaking Bond into the earlier phase.
    private func makeEmptyGunbarrelScene(
        frame: GoldenEyeGBISceneFrameContextV6
    ) throws -> GoldenEyeSourceSceneSnapshotV6 {
        var summary = GESourceFrameSummaryV6()
        summary.header.abi_version = UInt32(GE_NATIVE_ABI_VERSION)
        summary.header.struct_size = UInt32(MemoryLayout<GESourceFrameSummaryV6>.size)
        summary.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
        summary.flags = UInt32(GE_SOURCE_FRAME_V6_FLAG_PRESENTABLE)
            | (frame.pairPhase == 0
                ? UInt32(GE_SOURCE_FRAME_V6_FLAG_SOURCE_ANCHOR)
                : UInt32(GE_SOURCE_FRAME_V6_FLAG_INTERPOLATED))
        summary.screen = frame.screen
        summary.subphase = frame.subphase
        summary.native_tick = frame.nativeTick
        summary.reference_tick = frame.referenceTick
        summary.pair_phase = frame.pairPhase
        summary.viewport_width = frame.viewportWidth
        summary.viewport_height = frame.viewportHeight
        summary.logical_width = frame.logicalWidth
        summary.logical_height = frame.logicalHeight
        summary.transform_count = 0
        summary.resource_count = 0
        summary.pose_count = 0
        summary.vertex_count = 0
        summary.index_count = 0
        summary.draw_count = 0
        summary.render_state_count = 0
        summary.text_count = 0
        summary.audio_count = 0
        summary.diagnostic_count = 0
        summary.unsupported_visible_count = 0
        var hash: UInt64 = 1_469_598_103_934_665_603
        for value in [
            frame.nativeTick,
            frame.referenceTick,
            UInt64(frame.screen),
            UInt64(frame.subphase),
            UInt64(frame.pairPhase)
        ] {
            hash ^= value
            hash &*= 1_099_511_628_211
        }
        if hash == 0 { hash = 1 }
        summary.scene_hash = hash
        summary.render_hash = hash ^ 0x9E37_79B9_7F4A_7C15
        summary.state_hash = hash ^ 0xD1B5_4A32_D192_ED03
        summary.audio_hash = 1
        summary.frame_hash = hash ^ frame.nativeTick
        summary.reserved0 = 0
        summary.reserved1 = 0
        let lighting = try GoldenEyeSourceSceneLightingFrameContextV6(
            screen: frame.screen,
            nativeTick: frame.nativeTick,
            referenceTick: frame.referenceTick,
            sourceTimer: frame.sourceTimer ?? 0,
            pairPhase: frame.pairPhase,
            geometryModesByState: [:],
            modelViewQ16ByState: [:]
        )
        return try GoldenEyeSourceSceneSnapshotV6(
            summary: summary,
            resources: [],
            transforms: [],
            animationPoses: [],
            vertices: [],
            indices: [],
            renderStates: [],
            drawCommands: [],
            textEvents: [],
            audioEvents: [],
            diagnostics: [],
            lightingFrameContext: lighting
        )
    }

    private func makeClearBlackScene(
        sourceFrame: GoldenEyeSourceFrontendFrameV6,
        screenOverride: UInt32? = nil
    ) throws -> GoldenEyeSourceSceneSnapshotV6 {
        let screen = screenOverride ?? lastRenderableSceneScreen
        let pairPhase: UInt32 = sourceFrame.nativeTick & 1 == 0 ? 0 : 1
        let diagnostics = makeDiagnostics(sourceFrame.diagnosticEvents)
        var summary = GESourceFrameSummaryV6()
        summary.header.abi_version = UInt32(GE_NATIVE_ABI_VERSION)
        summary.header.struct_size = UInt32(MemoryLayout<GESourceFrameSummaryV6>.size)
        summary.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
        summary.flags = UInt32(GE_SOURCE_FRAME_V6_FLAG_PRESENTABLE)
            | (pairPhase == 0
                ? UInt32(GE_SOURCE_FRAME_V6_FLAG_SOURCE_ANCHOR)
                : UInt32(GE_SOURCE_FRAME_V6_FLAG_INTERPOLATED))
        summary.screen = screen
        summary.subphase = sourceFrame.subphase
        summary.native_tick = sourceFrame.nativeTick
        summary.reference_tick = sourceFrame.referenceTick
        summary.pair_phase = pairPhase
        summary.viewport_width = 440
        summary.viewport_height = 330
        summary.logical_width = 440
        summary.logical_height = 330
        summary.transform_count = 0
        summary.resource_count = 0
        summary.pose_count = 0
        summary.vertex_count = 0
        summary.index_count = 0
        summary.draw_count = 0
        summary.render_state_count = 0
        summary.text_count = 0
        summary.audio_count = 0
        summary.diagnostic_count = UInt32(diagnostics.count)
        summary.unsupported_visible_count = 0
        summary.scene_hash = sourceFrame.modelHash == 0 ? sourceFrame.renderHash : sourceFrame.modelHash
        summary.render_hash = sourceFrame.renderEventHash
        summary.state_hash = sourceFrame.stateHash
        summary.audio_hash = sourceFrame.audioEventHash == 0 ? 1 : sourceFrame.audioEventHash
        summary.frame_hash = sourceFrame.renderHash
        summary.reserved0 = 0
        summary.reserved1 = 0
        guard summary.scene_hash != 0, summary.render_hash != 0,
              summary.state_hash != 0, summary.frame_hash != 0 else {
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                "clear-black scene evidence hash is zero"
            )
        }
        return try GoldenEyeSourceSceneSnapshotV6(
            summary: summary,
            resources: [],
            transforms: [],
            animationPoses: [],
            vertices: [],
            indices: [],
            renderStates: [],
            drawCommands: [],
            textEvents: [],
            audioEvents: [],
            diagnostics: diagnostics
        )
    }

    private func makeDiagnostics(
        _ events: [GoldenEyeSourceFrontendDiagnosticEventV6]
    ) -> [GESourceDiagnosticV6] {
        events.map { event in
            var value = GESourceDiagnosticV6()
            value.header.abi_version = UInt32(GE_NATIVE_ABI_VERSION)
            value.header.struct_size = UInt32(MemoryLayout<GESourceDiagnosticV6>.size)
            value.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
            value.diagnostic_kind = UInt32(GE_SOURCE_DIAGNOSTIC_V6_UNSUPPORTED_COMMAND)
            value.flags = 0
            value.severity = min(event.severity, UInt32(GE_SOURCE_DIAGNOSTIC_V6_SEVERITY_MAX))
            value.code = event.code
            value.source_id = event.detail0
            value.command_id = event.detail1
            value.first_bad_index = 0
            value.item_count = 1
            value.detail_hash = diagnosticHash(event)
            value.reserved0 = 0
            value.reserved1 = 0
            return value
        }
    }

    private func recordSourceDiagnostics(
        _ events: [GoldenEyeSourceFrontendDiagnosticEventV6]
    ) {
        guard !events.isEmpty else { return }
        let line = events.map {
            "sourceDiagnostic=\($0.code) severity=\($0.severity) detail0=\($0.detail0) detail1=\($0.detail1)"
        }.joined(separator: " ") + "\n"
        try? line.write(
            to: URL(fileURLWithPath: "/tmp/goldeneye-source-product-renderer-v6-diagnostics.log"),
            atomically: false,
            encoding: .utf8
        )
    }

    private func diagnosticHash(
        _ event: GoldenEyeSourceFrontendDiagnosticEventV6
    ) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for value in [event.screen, event.code, event.severity, event.sourceTimer,
                      UInt32(truncatingIfNeeded: event.nativeTick),
                      UInt32(truncatingIfNeeded: event.nativeTick >> 32),
                      UInt32(truncatingIfNeeded: event.sequence),
                      UInt32(truncatingIfNeeded: event.sequence >> 32),
                      event.detail0, event.detail1] {
            hash ^= UInt64(value)
            hash &*= 1_099_511_628_211
        }
        return hash == 0 ? 1 : hash
    }

    private func sourceRenderEventsMatch(
        _ sourceFrame: GoldenEyeSourceFrontendFrameV6
    ) -> Bool {
        guard !sourceFrame.renderEvents.isEmpty else { return false }
        return sourceFrame.renderEvents.allSatisfy { event in
            // The source transition callback emits FRAME_BEGIN/CLEAR_BLACK
            // while the outgoing screen is still current; the copied frame
            // summary has already advanced to SWITCH. Preserve that source
            // ordering instead of rejecting the valid transition at the
            // Legal -> Nintendo boundary (native tick 482).
            let transitionScreenEvent = sourceFrame.screen ==
                UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_SWITCH)
                && (event.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_FRAME_BEGIN)
                    || event.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_CLEAR_BLACK))
            let screenMatches = event.screen == sourceFrame.screen || transitionScreenEvent
            return screenMatches &&
                event.nativeTick == sourceFrame.nativeTick &&
                event.referenceTick == sourceFrame.referenceTick
        }
    }

    private var castModels: [String: GoldenEyeSourceModelV6] {
        var models = preparation.models
        if let castPreparation {
            for (name, model) in castPreparation.models {
                models[name] = model
            }
        }
        return models
    }

    private func modelMatrixHandles(
        for names: [String],
        models: [String: GoldenEyeSourceModelV6]
    ) throws -> [UInt32] {
        var handles: [UInt32] = []
        for name in names {
            guard let model = models[name] else {
                throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                    "Cast model matrix source is missing: \(name)"
                )
            }
            for (index, command) in model.commands.enumerated()
                where command.semantic.hasPrefix("gsSPMatrix") {
                guard let token = model.tokens(for: index).first,
                      token.encodedValue != 0,
                      !handles.contains(token.encodedValue) else { continue }
                handles.append(token.encodedValue)
            }
        }
        guard !handles.isEmpty else {
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                "Cast scene has no source model matrix handles"
            )
        }
        return handles
    }

    /// The source Cast constructor rotates the attached weapon half a turn
    /// when the mirrored hand is selected. Keep that value-only post-multiply
    /// beside the attachment handoff so the weapon is not silently rendered
    /// from the unmirrored switch matrix.
    private static func castFlippedWeaponAttachment(_ values: [Int32]) -> [Int32] {
        let halfTurn: [Int32] = [
            -65_536, 0, 0, 0,
            0, -65_536, 0, 0,
            0, 0, 65_536, 0,
            0, 0, 0, 65_536,
        ]
        return GoldenEyeSourceProjectionBindingV6.multiply(values, halfTurn)
    }

    private func firstModelMatrixHandle(
        _ model: GoldenEyeSourceModelV6
    ) throws -> UInt32 {
        var handles: [UInt32] = []
        for (index, command) in model.commands.enumerated()
            where command.semantic.hasPrefix("gsSPMatrix") {
            guard let first = model.tokens(for: index).first else { continue }
            let handle = first.encodedValue
            if handle != 0, !handles.contains(handle) {
                handles.append(handle)
            }
        }
        // Gunbarrel character packets contain a matrix load per authored
        // body part.  The first source handle seeds the shared body frame;
        // exact per-load handles are retained by the GBI provenance sidecar
        // and resolved during scene lowering.
        guard let handle = handles.first else {
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                "Gunbarrel model has no source matrix handle"
            )
        }
        return handle
    }

    /// Compatibility telemetry from the existing title owner.  It is not a
    /// rendering authority: without a complete source frame and explicit
    /// transforms, the next render remains fail-closed.
    func submit(titleSnapshot: GoldenEyeTitleSnapshot) {
        frameStateLock.lock()
        defer { frameStateLock.unlock() }
        publicationGeneration &+= 1
        latestTitleSnapshot = titleSnapshot
        latestStageScene = nil
        latestStagePacketHash = 0
        latestStageUnsupportedMask = 0
        latestStageMaterialHash = 0
        latestStageMaterialStateCount = 0
        latestStageTexturePending = 0
        if titleSnapshot.screen != .gunbarrel {
            latestGunbarrelPass = nil
        }
        if let scene = latestScene, scene.summary.screen != titleSnapshot.screen.rawValue {
            latestScene = nil
            latestSourceFrame = nil
        }
    }

    func render(drawable: any CAMetalDrawable, timing: GE120DisplayTiming) -> Bool {
        let renderStart = DispatchTime.now().uptimeNanoseconds
        var renderRoute = "unresolved"
        frameStateLock.lock()
        let published = PublishedRenderState(
            didShutdown: didShutdown,
            stageScene: latestStageScene,
            scene: latestScene,
            titleSnapshot: latestTitleSnapshot,
            source2DFrame: latestSource2DFrame,
            source2DBackgroundFrame: latestSource2DBackgroundFrame,
            gunbarrelPass: latestGunbarrelPass,
            stagePacketHash: latestStagePacketHash,
            stageUnsupportedMask: latestStageUnsupportedMask,
            stageMaterialHash: latestStageMaterialHash,
            stageMaterialStateCount: latestStageMaterialStateCount,
            stageTexturePending: latestStageTexturePending
        )
        frameStateLock.unlock()
        // Do not hold publication state across Metal encode/commit/present.
        // Source-owner publication may be expensive during Gunbarrel/Cast;
        // the display path renders this immutable copied state independently.
        renderLock.lock()
        defer {
            let elapsed = DispatchTime.now().uptimeNanoseconds &- renderStart
            if elapsed >= 100_000_000 {
                appendEvidenceLine(
                    "slowProductRender=1 route=\(renderRoute) elapsedNs=\(elapsed)\n",
                    path: "/tmp/goldeneye-source-product-renderer-v6-slow-render.log"
                )
            }
            renderLock.unlock()
        }
        _ = timing
        guard !published.didShutdown else { return false }
        let stageScene = published.stageScene
        renderRoute = stageScene == nil ? "title" : "stage"
        guard let scene = stageScene ?? published.scene else {
            recordFailure(GoldenEyeSourceProductRendererV6Error.noSubmittedFrame)
            return false
        }
        guard scene.isPresentable else {
            recordFailure(GoldenEyeSourceProductRendererV6Error.renderFailure(
                "source scene is fail-closed (unsupportedVisible=\(scene.summary.unsupported_visible_count))"
            ))
            return false
        }
        if stageScene == nil, let title = published.titleSnapshot,
           title.screen.rawValue != scene.summary.screen {
            recordFailure(
                GoldenEyeSourceProductRendererV6Error.staleSourceFrame(
                    scene.summary.screen,
                    expected: title.screen.rawValue
                )
            )
            return false
        }
        do {
            var source2DBatch: GoldenEyeSource2DMetalBatchV6?
            let currentGunbarrelPass = published.gunbarrelPass
            let evidence = try renderer.render(
                snapshot: scene,
                suppliedDrawable: drawable,
                underlay: { [source2DRenderer, source2DBackgroundFrame = published.source2DBackgroundFrame, gunbarrelPassRenderer, currentGunbarrelPass] encoder, slotIndex in
                    guard stageScene == nil else { return }
                    if (scene.summary.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_FILE_SELECT)
                            || scene.summary.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_MODE_SELECT)),
                       let source2DBackgroundFrame {
                        _ = try source2DRenderer.encode(
                            frame: source2DBackgroundFrame,
                            into: encoder,
                            drawableWidth: drawable.texture.width,
                            drawableHeight: drawable.texture.height,
                            slotIndex: slotIndex,
                            includeFills: true,
                            skipInitialSourceClear: false
                        )
                    }
                    if scene.summary.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL),
                       let currentGunbarrelPass,
                       let gunbarrelPassRenderer {
                        try gunbarrelPassRenderer.encodeUnderlay(
                            pass: currentGunbarrelPass,
                            encoder: encoder,
                            slotIndex: slotIndex
                        )
                    }
                },
                overlay: { [source2DRenderer, source2DFrame = published.source2DFrame, gunbarrelPassRenderer, currentGunbarrelPass] encoder, slotIndex in
                    if stageScene == nil,
                       scene.summary.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL),
                       let currentGunbarrelPass,
                       let gunbarrelPassRenderer {
                        try gunbarrelPassRenderer.encodeOverlay(
                            pass: currentGunbarrelPass,
                            encoder: encoder,
                            slotIndex: slotIndex
                        )
                    }
                    guard stageScene == nil else { return }
                    guard let source2DFrame else { return }
                    guard source2DFrame.screen == scene.summary.screen else {
                        throw GoldenEyeSourceProductRendererV6Error.staleSourceFrame(
                            source2DFrame.screen,
                            expected: scene.summary.screen
                        )
                    }
                    source2DBatch = try source2DRenderer.encodeOverlay(
                        frame: source2DFrame,
                        into: encoder,
                        drawableWidth: drawable.texture.width,
                        drawableHeight: drawable.texture.height,
                        slotIndex: slotIndex
                    )
                }
            )
            lastRenderEvidence = evidence
            renderIndex &+= 1
            recordRender(
                evidence,
                source2DBatch: source2DBatch,
                isStageEnvironment: stageScene != nil,
                published: published
            )
            return true
        } catch {
            recordFailure(GoldenEyeSourceProductRendererV6Error.renderFailure(String(describing: error)))
            return false
        }
    }

    func render(
        suppliedDrawable drawable: any CAMetalDrawable,
        timing: GE120DisplayTiming?
    ) -> Bool {
        let resolvedTiming = timing ?? GE120DisplayTiming(
            targetTimestamp: CACurrentMediaTime(),
            targetPresentationTimestamp: CACurrentMediaTime(),
            drawableWidth: drawable.texture.width,
            drawableHeight: drawable.texture.height,
            callbackSequence: renderIndex
        )
        return render(drawable: drawable, timing: resolvedTiming)
    }

    /// The compatibility owner path cannot acquire a drawable here.  A false
    /// result is intentional and keeps all product presentation on the
    /// callback-supplied CAMetalDisplayLink path.
    func renderFrame() -> Bool {
        recordFailure(GoldenEyeSourceProductRendererV6Error.renderFailure(
            "compatibility drawable acquisition is disabled"
        ))
        return false
    }

    func shutdown() {
        frameStateLock.lock()
        guard !didShutdown else {
            frameStateLock.unlock()
            return
        }
        didShutdown = true
        publicationGeneration &+= 1
        frameStateLock.unlock()
        renderLock.lock()
        defer { renderLock.unlock() }
        renderer.shutdown()
        source2DRenderer.shutdown()
        do {
            try textureStore.shutdown()
            let evidence = "frames=\(renderIndex) textureCount=\(textureStore.textureCount) "
                + "textureResources=\(textureBindingAdapter.resourceCount) "
                + "validatedPalettes=\(textureBindingAdapter.validatedPaletteCount) "
                + "titleCacheHits=\(compiledModelCacheHits) titleCacheMisses=\(compiledModelCacheMisses) "
                + "mode=\(outputMode.rawValue) root=\(preparation.rootURL.path) "
                + "lastSignal=\(lastRenderEvidence?.signalValue ?? 0)\n"
            try evidence.write(
                to: URL(fileURLWithPath: "/tmp/goldeneye-source-product-renderer-v6.log"),
                atomically: true,
                encoding: .utf8
            )
        } catch {
            recordFailure(GoldenEyeSourceProductRendererV6Error.shutdownFailure(String(describing: error)))
        }
    }

    var lastEvidence: GoldenEyeSourceSceneRenderEvidenceV6? { lastRenderEvidence }
    var lastGunbarrelPass: GoldenEyeGunbarrelRenderPassV6? { latestGunbarrelPass }

    private func recordRender(
        _ evidence: GoldenEyeSourceSceneRenderEvidenceV6,
        source2DBatch: GoldenEyeSource2DMetalBatchV6?,
        isStageEnvironment: Bool = false,
        published: PublishedRenderState
    ) {
        let visibleProps = visibleDependencyCatalog?.count(category: "props") ?? 0
        let visibleGuards = visibleDependencyCatalog?.count(category: "guards") ?? 0
        let visibleEffects = visibleDependencyCatalog?.count(category: "effects") ?? 0
        let visibleHUD = visibleDependencyCatalog?.count(category: "hud") ?? 0
        let line = "frame=\(evidence.frameIndex) tick=\(evidence.nativeTick) draws=\(evidence.drawCount) "
            + "triangles=\(evidence.triangleCount) copiedHash=\(evidence.copiedRecordAggregateHash) "
            + "source2DDraws=\(source2DBatch?.draws.count ?? 0) "
            + "source2DVertices=\(source2DBatch?.vertices.count ?? 0) "
            + "source2DHash=\(source2DBatch?.geometryHash ?? 0) "
            + "gunbarrelPass=\(published.gunbarrelPass?.passHash ?? 0) "
            + "gunbarrelMode=\(published.gunbarrelPass?.mode ?? 0) "
            + "gunbarrelBackground=\(published.gunbarrelPass.map { "\($0.backgroundWidth)x\($0.backgroundHeight)" } ?? "none") "
            + "gunbarrelBackgroundVisible=\(published.gunbarrelPass?.backgroundVisible == true ? 1 : 0) "
            + "gunbarrelHole=\(published.gunbarrelPass?.holeTriangleCount ?? 0) "
            + "gunbarrelHoleVisible=\(published.gunbarrelPass?.holeVisible == true ? 1 : 0) "
            + "gunbarrelHolePasses=\(published.gunbarrelPass?.holePassCount ?? 0) "
            + "gunbarrelTitleXQ16=\(published.gunbarrelPass?.titleXQ16 ?? 0) "
            + "gunbarrelTransitionXQ16=\(published.gunbarrelPass?.transitionXQ16 ?? 0) "
            + "gunbarrelPoses=\(published.gunbarrelPass?.poseCount ?? 0) "
            + "gunbarrelMuzzle=\(published.gunbarrelPass?.muzzleFlashVisible == true ? 1 : 0) "
            + "gunbarrelBlood=\(published.gunbarrelPass?.bloodVisible == true ? 1 : 0) "
            + "stageEnvironment=\(isStageEnvironment ? 1 : 0) stagePacketHash=\(published.stagePacketHash) "
            + "stageUnsupportedMask=\(published.stageUnsupportedMask) "
            + "stageMaterialHash=\(published.stageMaterialHash) stageMaterialStates=\(published.stageMaterialStateCount) "
            + "stageTexturePending=\(published.stageTexturePending) "
            + "stageTextureBindings=\(stageTextureCatalog?.bindingCount ?? 0) "
            + "stageTextureBindingHash=\(stageTextureCatalog?.bindingValidationHash ?? 0) "
            + "stageSetupDeps=\(stageSetupDependencyCatalog?.dependencies.count ?? 0) "
            + "stageSetupProps=\(stageSetupDependencyCatalog?.propCount ?? 0) "
            + "stageSetupCharacters=\(stageSetupDependencyCatalog?.characterCount ?? 0) "
            + "stageModelSidecars=\(stageModelSidecarCatalog?.models.count ?? 0) "
            + "stageModelSidecarsComplete=\(stageModelSidecarCatalog?.isComplete == true ? 1 : 0) "
            + "visibleDependencies=\(visibleDependencyCatalog?.dependencies.count ?? 0) "
            + "visibleDependenciesComplete=\(visibleDependencyCatalog?.isComplete == true ? 1 : 0) "
            + "visibleProps=\(visibleProps) visibleGuards=\(visibleGuards) "
            + "visibleEffects=\(visibleEffects) visibleHUD=\(visibleHUD) "
            + "slot=\(evidence.slotIndex) signal=\(evidence.signalValue)\n"
        appendEvidenceLine(line, path: "/tmp/goldeneye-source-product-renderer-v6-frames.log")
    }

    private func recordFailure(_ error: Error) {
        let line = "failure=\(error)\n"
        appendEvidenceLine(line, path: "/tmp/goldeneye-source-product-renderer-v6-failures.log")
    }

    private func appendEvidenceLine(_ line: String, path: String) {
        let url = URL(fileURLWithPath: path)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            try? handle.write(contentsOf: Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url, options: .atomic)
        }
    }
}
