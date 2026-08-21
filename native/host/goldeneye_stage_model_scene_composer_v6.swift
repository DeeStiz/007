import CryptoKit
import Foundation

#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

/// The stage model lowerer is deliberately stricter than the setup catalog.
/// A setup row becomes a draw only when its GESM graph, setup transform, every
/// texture/mip/TLUT payload, and the source frame projection are all present.
/// This keeps partial preparation useful as evidence without making it a
/// Release fallback.
struct GoldenEyeStageModelSceneCompositionV6: @unchecked Sendable {
    struct Result: @unchecked Sendable {
        let snapshot: GoldenEyeSourceSceneSnapshotV6
        let stageID: UInt32
        let placementCount: UInt32
        let drawablePlacementCount: UInt32
        let unsupportedPlacementCount: UInt32
        let propPlacementCount: UInt32
        let characterPlacementCount: UInt32
        let aliasDescriptorCount: UInt32
        let unsupportedMask: UInt32
        let failureReasons: [String]
        let categoryPackets: [GoldenEyeRamRomVisibleCategoryPacketV6]
        let compositionHash: UInt64
        let contiguousBatchCount: UInt32
        let largestContiguousBatch: UInt32

        var isPresentable: Bool { snapshot.isPresentable && snapshot.summary.unsupported_visible_count == 0 }
    }

    enum Error: Swift.Error, CustomStringConvertible, Sendable, Equatable {
        case missingStageProjection
        case missingStageViewport
        case invalidPlacement(UInt32, String)
        case textureMismatch(String)
        case setupMismatch(String)
        case composition(String)

        var description: String {
            switch self {
            case .missingStageProjection: return "stage model lowering has no explicit projection resource"
            case .missingStageViewport: return "stage model lowering has no explicit viewport resource"
            case let .invalidPlacement(index, detail): return "stage placement \(index) is not lowerable: \(detail)"
            case let .textureMismatch(detail): return "stage model texture provenance mismatch: \(detail)"
            case let .setupMismatch(detail): return "stage model texture setup mismatch: \(detail)"
            case let .composition(detail): return "stage model scene composition failed: \(detail)"
            }
        }
    }

    /// Lowers the source-visible static-prop slice into the same GBI/scene
    /// contract used by the frontend.  Character skeletons, effects, HUD,
    /// and every placement that lacks a complete source payload remain in the
    /// returned unsupported evidence; no placeholder geometry is emitted.
    static func make(
        stageScene: GoldenEyeStageScenePacket,
        environmentPacket: GoldenEyeStageBackgroundDrawPacket,
        materialPacket: GoldenEyeStageSourceMaterialPacketV6?,
        sidecars: GoldenEyeStageModelSidecarCatalogV6,
        setupDependencies: GoldenEyeStageSetupDependencyCatalogV6,
        stageTextures: GoldenEyeStageTextureCatalogV6,
        frameResources: GoldenEyeSourceProductFrameResourcesV6?,
        nativeTick: UInt64,
        demoID: UInt8? = nil,
        visibleDependencies: GoldenEyeRamRomVisibleDependencyCatalogV6? = nil,
        requireExactFogCoordinates: Bool = true
    ) throws -> Result {
        let base = try GoldenEyeStageSourceSceneSnapshotAdapterV6.make(
            packet: environmentPacket,
            nativeTick: nativeTick,
            materialPacket: materialPacket,
            stageTextureCatalog: stageTextures
        )

        let placements = GoldenEyeStageModelPlacementCatalogV6.make(
            stageID: stageScene.stageID,
            setup: stageScene.setup,
            dependencies: setupDependencies,
            sidecars: sidecars,
            visibleDependencies: visibleDependencies
        ).placements

        let categoryPackets = GoldenEyeRamRomVisibleCategoryLowererV6.make(
            catalog: visibleDependencies,
            stageID: stageScene.stageID,
            stageName: stageScene.stageName,
            demoID: demoID
        )

        guard let frameResources else {
            let stageMask = unsupportedMask(
                environment: environmentPacket,
                propPlacementCount: placements.reduce(into: 0) { if $1.kind == "prop" { $0 += 1 } },
                drawablePropPlacementCount: 0,
                characterPlacementCount: placements.reduce(into: 0) { if $1.kind == "character" { $0 += 1 } },
                categoryPackets: categoryPackets
            )
            let snapshot = try compose(
                base: base,
                modelResults: [],
                unsupportedMask: stageMask,
                nativeTick: nativeTick,
                stageID: stageScene.stageID,
                requireExactFogCoordinates: requireExactFogCoordinates
            )
            return Result(
                snapshot: snapshot,
                stageID: stageScene.stageID,
                placementCount: UInt32(placements.count),
                drawablePlacementCount: 0,
                unsupportedPlacementCount: UInt32(placements.count),
                propPlacementCount: UInt32(placements.reduce(into: 0) { if $1.kind == "prop" { $0 += 1 } }),
                characterPlacementCount: UInt32(placements.reduce(into: 0) { if $1.kind == "character" { $0 += 1 } }),
                aliasDescriptorCount: 0,
                unsupportedMask: stageMask,
                failureReasons: ["missing explicit stage frame resources"],
                categoryPackets: categoryPackets,
                compositionHash: compositionHash(snapshot: snapshot, categoryPackets: categoryPackets),
                contiguousBatchCount: UInt32(contiguousBatches(snapshot: snapshot).count),
                largestContiguousBatch: UInt32(contiguousBatches(snapshot: snapshot).max() ?? 0)
            )
        }

        guard frameResources.matrices.contains(where: { $0.roleFlags & GoldenEyeSourceMatrixRoleSidecarV6.projection != 0 }) else {
            throw Error.missingStageProjection
        }
        guard !frameResources.viewports.isEmpty else { throw Error.missingStageViewport }

        let sidecarModels = sidecars.models
        let aliasDescriptors = stageTextures.isGPURepresentable
            ? textureDescriptors(models: sidecarModels, sidecars: sidecars, stageTextures: stageTextures)
            : []
        let aliasHandles = Set(aliasDescriptors.map(\.resourceHandle))
        let aliasDescriptorByHandle = Dictionary(uniqueKeysWithValues: aliasDescriptors.map { ($0.resourceHandle, $0) })
        var modelResults: [GoldenEyeGBISceneBuildResultV6] = []
        modelResults.reserveCapacity(placements.count)
        var drawableCount = 0
        var failureReasons: [String] = []

        for placement in placements {
            guard placement.kind == "prop" else { continue }
            guard placement.isRenderable else {
                if failureReasons.count < 512 {
                    failureReasons.append("\(placement.modelName)#\(placement.objectIndex): placement transform/sidecar incomplete sidecar=\(placement.sidecarReady ? 1 : 0) matrixWords=\(placement.matrixWords.count) matrixQ16=\(placement.matrixQ16.count)")
                }
                continue
            }
            guard let model = sidecarModels[placement.modelName] else {
                if failureReasons.count < 512 { failureReasons.append("\(placement.modelName)#\(placement.objectIndex): sidecar missing") }
                continue
            }
            do {
                let compilation = GESourceModelCompilerV6.compile(
                    model,
                    modelName: placement.modelName
                )
                guard compilation.status == .complete,
                      let scene = compilation.scene,
                      compilation.diagnostics.isEmpty else {
                    if failureReasons.count < 512 {
                        let detail = compilation.diagnostics.map(\.description).joined(separator: ",")
                        failureReasons.append("\(placement.modelName)#\(placement.objectIndex): source graph compilation incomplete \(detail)")
                    }
                    continue
                }
                let normalizedScene = normalizeTextureAliases(
                    scene: scene,
                    modelName: placement.modelName,
                    model: model
                )
                let matrixHandles = matrixHandles(in: normalizedScene.commands)
                guard !matrixHandles.modelView.isEmpty,
                      matrixHandles.projection.isEmpty else {
                    if failureReasons.count < 512 { failureReasons.append("\(placement.modelName)#\(placement.objectIndex): matrix handles model=\(matrixHandles.modelView.count) projection=\(matrixHandles.projection.count)") }
                    continue
                }
                guard model.textures.allSatisfy({ aliasHandles.contains($0.resourceHandle) }) else {
                    if failureReasons.count < 512 { failureReasons.append("\(placement.modelName)#\(placement.objectIndex): texture alias incomplete") }
                    continue
                }
                guard let setups = textureSetups(
                    modelName: placement.modelName,
                    model: model,
                    commands: normalizedScene.commands,
                    descriptors: aliasDescriptorByHandle
                ) else {
                    if failureReasons.count < 512 { failureReasons.append("\(placement.modelName)#\(placement.objectIndex): texture setup incomplete") }
                    continue
                }
                // Seed the bounded decoder with the same value-only Type-4
                // combiner/texture setup used by the source model producer.
                // Stage props may then replace render modes in their own
                // display-list bodies, so no dynamic setup validation context
                // is passed to the builder below.
                let renderScene = GoldenEyeGBISceneBuilderV6.gunbarrelSceneWithRenderSetup(
                    model: model,
                    modelName: placement.modelName,
                    scene: normalizedScene,
                    context: .cast
                )
                var matrices = frameResources.matrices.filter {
                    !matrixHandles.modelView.contains($0.handle)
                }
                for modelMatrixHandle in matrixHandles.modelView {
                    matrices.append(try GoldenEyeGBIMatrixResourceV6(
                        handle: modelMatrixHandle,
                        values: placement.matrixQ16,
                        roleFlags: GoldenEyeSourceMatrixRoleSidecarV6.modelView
                    ))
                }
                let roles = try matrices.compactMap { matrix -> GoldenEyeSourceMatrixRoleSidecarV6? in
                    guard matrix.roleFlags != 0 else { return nil }
                    return try GoldenEyeSourceMatrixRoleSidecarV6(
                        handle: matrix.handle,
                        roleFlags: matrix.roleFlags
                    )
                }
                let frame = try GoldenEyeGBISceneFrameContextV6(
                    nativeTick: nativeTick,
                    referenceTick: nativeTick >> 1,
                    sourceTimer: 0,
                    pairPhase: UInt32(nativeTick & 1),
                    screen: UInt32(GE_SOURCE_FRAME_V6_SCREEN_RAMROM),
                    subphase: stageScene.stageID,
                    viewportWidth: frameResources.viewportWidth,
                    viewportHeight: frameResources.viewportHeight
                )
                let result = try GoldenEyeGBISceneBuilderV6.build(
                    model: model,
                    modelName: placement.modelName,
                    matrices: matrices,
                    viewports: frameResources.viewports,
                    matrixRoles: roles,
                    frame: frame,
                    animationPoses: staticGroupPoses(model: model, modelName: placement.modelName),
                    transformContext: .standard,
                    textureSetups: setups,
                    resolvedScene: GoldenEyeGBIResolvedSceneInputV6(
                        scene: renderScene,
                        vertexResources: try vertexResourceOverrides(model: model, scene: renderScene)
                    )
                )
                guard result.presentable,
                      result.unsupportedVisibleCount == 0,
                      result.decoderUnsupportedCount == 0,
                      !result.snapshot.drawCommands.isEmpty else {
                    if failureReasons.count < 512 {
                        let reason = result.unsupportedReasons.first ?? "none"
                        failureReasons.append("\(placement.modelName)#\(placement.objectIndex): builder presentable=\(result.presentable ? 1 : 0) unsupported=\(result.unsupportedVisibleCount) decoder=\(result.decoderUnsupportedCount) draws=\(result.snapshot.drawCommands.count) reason=\(reason)")
                    }
                    continue
                }
                modelResults.append(result)
                drawableCount += 1
            } catch {
                // A placement-level failure is evidence, not a reason to
                // invent a draw. The aggregate mask below keeps Release
                // closed until the complete allowlist is lowerable.
                if failureReasons.count < 512 {
                    failureReasons.append("\(placement.modelName)#\(placement.objectIndex): \(error)")
                }
                continue
            }
        }

        let unsupportedMask = unsupportedMask(
            environment: environmentPacket,
            propPlacementCount: placements.reduce(into: 0) { if $1.kind == "prop" { $0 += 1 } },
            drawablePropPlacementCount: drawableCount,
            characterPlacementCount: placements.reduce(into: 0) { if $1.kind == "character" { $0 += 1 } },
            categoryPackets: categoryPackets
        )
        let snapshot = try compose(
            base: base,
            modelResults: modelResults,
            unsupportedMask: unsupportedMask,
            nativeTick: nativeTick,
            stageID: stageScene.stageID,
            requireExactFogCoordinates: requireExactFogCoordinates
        )
        return Result(
            snapshot: snapshot,
            stageID: stageScene.stageID,
            placementCount: UInt32(placements.count),
            drawablePlacementCount: UInt32(drawableCount),
            unsupportedPlacementCount: UInt32(max(0, placements.count - drawableCount)),
            propPlacementCount: UInt32(placements.reduce(into: 0) { if $1.kind == "prop" { $0 += 1 } }),
            characterPlacementCount: UInt32(placements.reduce(into: 0) { if $1.kind == "character" { $0 += 1 } }),
            aliasDescriptorCount: UInt32(aliasDescriptors.count),
            unsupportedMask: unsupportedMask,
            failureReasons: failureReasons,
            categoryPackets: categoryPackets,
            compositionHash: compositionHash(snapshot: snapshot, categoryPackets: categoryPackets),
            contiguousBatchCount: UInt32(contiguousBatches(snapshot: snapshot).count),
            largestContiguousBatch: UInt32(contiguousBatches(snapshot: snapshot).max() ?? 0)
        )
    }

    /// Builds alias descriptors under each sidecar's deterministic resource
    /// handle. The payload bytes still come from the corrected stage catalog;
    /// no private model payload is guessed or reconstructed here.
    static func textureDescriptors(
        models: [String: GoldenEyeSourceModelV6],
        stageTextures: GoldenEyeStageTextureCatalogV6
    ) -> [GoldenEyeSourceTextureDescriptorV6] {
        var descriptors: [GoldenEyeSourceTextureDescriptorV6] = []
        var handles = Set<UInt32>()
        for modelName in models.keys.sorted() {
            guard let model = models[modelName] else { continue }
            for texture in model.textures {
                guard let stageTexture = stageTexture(
                    modelName: modelName,
                    texture: texture,
                    stageTextures: stageTextures
                ),
                texture.mipCount <= UInt32(stageTexture.levels.count),
                Int(texture.mipStart) + Int(texture.mipCount) <= model.mips.count,
                handles.insert(texture.resourceHandle).inserted else { continue }
                let levelCount = Int(texture.mipCount)
                let levels = Array(stageTexture.levels.prefix(levelCount)).enumerated().map { offset, level in
                    let mip = model.mips[Int(texture.mipStart) + offset]
                    return GoldenEyeSourceTextureLevelUploadV6(
                        level: UInt32(offset), width: level.width, height: level.height,
                        payloadRecordID: mip.payloadRecordID,
                        sourceOffset: mip.sourceOffset,
                        sourceRowHandle: mip.sourceRowHandle,
                        rawByteCount: mip.rawByteCount,
                        decodedByteCount: UInt32(level.decoded.count),
                        decodedSHA256: sha256(level.decoded), decoded: level.decoded
                    )
                }
                guard levels.count == levelCount,
                      levels.first?.width == texture.width,
                      levels.first?.height == texture.height else { continue }
                let palette: GoldenEyeSourceTexturePaletteUploadV6?
                if texture.tlutIndex != GoldenEyeSourceModelV6.nullHandle,
                   texture.tlutIndex < UInt32(model.tluts.count),
                   let sourcePalette = stageTexture.palette {
                    let tlut = model.tluts[Int(texture.tlutIndex)]
                    palette = GoldenEyeSourceTexturePaletteUploadV6(
                        resourceHandle: texture.resourceHandle,
                        entries: sourcePalette.entries,
                        payloadRecordID: tlut.payloadRecordID,
                        sourceOffset: tlut.sourceOffset,
                        sourceRowHandle: tlut.sourceRowHandle,
                        rawByteCount: tlut.rawByteCount,
                        decodedByteCount: UInt32(sourcePalette.decoded.count),
                        decodedSHA256: sha256(sourcePalette.decoded),
                        decoded: sourcePalette.decoded
                    )
                } else {
                    palette = nil
                }
                descriptors.append(GoldenEyeSourceTextureDescriptorV6(
                    modelName: modelName,
                    family: "ramrom-stage-model",
                    resourceHandle: texture.resourceHandle,
                    width: texture.width,
                    height: texture.height,
                    mipLevels: texture.mipCount,
                    payloadRecordID: texture.payloadRecordID,
                    payloadDecodedSHA256: sha256(levels[0].decoded),
                    sourceOffset: texture.sourceOffset,
                    sourceRowHandle: texture.sourceRowHandle,
                    sourceSpan: texture.sourceSpan,
                    levels: levels,
                    palette: palette
                ))
            }
        }
        return descriptors
    }

    /// Uses the sidecar payload manifest first. This is required for model
    /// textures whose source IMAGE row has only an implicit level in the
    /// room-image catalog while the model authoring declares generated,
    /// source-derived mip levels. The stage catalog remains the guarded
    /// fallback for shared rows.
    static func textureDescriptors(
        models: [String: GoldenEyeSourceModelV6],
        sidecars: GoldenEyeStageModelSidecarCatalogV6,
        stageTextures: GoldenEyeStageTextureCatalogV6
    ) -> [GoldenEyeSourceTextureDescriptorV6] {
        var descriptors: [GoldenEyeSourceTextureDescriptorV6] = []
        var handles = Set<UInt32>()
        for modelName in models.keys.sorted() {
            guard let model = models[modelName] else { continue }
            for texture in model.textures {
                let descriptor = sidecarTextureDescriptor(
                    modelName: modelName,
                    model: model,
                    texture: texture,
                    sidecars: sidecars
                ) ?? stageTextureDescriptor(
                    modelName: modelName,
                    model: model,
                    texture: texture,
                    stageTextures: stageTextures
                )
                guard let descriptor, handles.insert(texture.resourceHandle).inserted else { continue }
                descriptors.append(descriptor)
            }
        }
        return descriptors
    }

    private static func sidecarTextureDescriptor(
        modelName: String,
        model: GoldenEyeSourceModelV6,
        texture: GoldenEyeSourceModelV6.Texture,
        sidecars: GoldenEyeStageModelSidecarCatalogV6
    ) -> GoldenEyeSourceTextureDescriptorV6? {
        guard let payload = sidecars.payload(id: texture.payloadRecordID),
              payload.category == "texture_payload",
              Int(texture.mipStart) + Int(texture.mipCount) <= model.mips.count else { return nil }
        let levels: [GoldenEyeSourceTextureLevelUploadV6] = (0..<Int(texture.mipCount)).compactMap { offset in
            let mip = model.mips[Int(texture.mipStart) + offset]
            guard let levelPayload = sidecars.payload(id: mip.payloadRecordID),
                  let decoded = try? Data(contentsOf: levelPayload.decodedURL, options: [.mappedIfSafe]),
                  decoded.count == Int(mip.decodedByteCount) else { return nil }
            return GoldenEyeSourceTextureLevelUploadV6(
                level: mip.level, width: mip.width, height: mip.height,
                payloadRecordID: mip.payloadRecordID, sourceOffset: mip.sourceOffset,
                sourceRowHandle: mip.sourceRowHandle, rawByteCount: mip.rawByteCount,
                decodedByteCount: mip.decodedByteCount,
                decodedSHA256: levelPayload.decodedSHA256, decoded: decoded
            )
        }
        guard levels.count == Int(texture.mipCount),
              levels.first?.width == texture.width,
              levels.first?.height == texture.height else { return nil }
        var palette: GoldenEyeSourceTexturePaletteUploadV6?
        if texture.tlutIndex != GoldenEyeSourceModelV6.nullHandle,
           texture.tlutIndex < UInt32(model.tluts.count) {
            let tlut = model.tluts[Int(texture.tlutIndex)]
            guard let palettePayload = sidecars.payload(id: tlut.payloadRecordID),
                  palettePayload.category == "tlut_payload",
                  let decoded = try? Data(contentsOf: palettePayload.decodedURL, options: [.mappedIfSafe]) else {
                return nil
            }
            palette = GoldenEyeSourceTexturePaletteUploadV6(
                resourceHandle: texture.resourceHandle,
                entries: UInt32(decoded.count / 4), payloadRecordID: tlut.payloadRecordID,
                sourceOffset: tlut.sourceOffset, sourceRowHandle: tlut.sourceRowHandle,
                rawByteCount: tlut.rawByteCount, decodedByteCount: UInt32(decoded.count),
                decodedSHA256: palettePayload.decodedSHA256, decoded: decoded
            )
        }
        return GoldenEyeSourceTextureDescriptorV6(
            modelName: modelName, family: "ramrom-stage-model",
            resourceHandle: texture.resourceHandle, width: texture.width, height: texture.height,
            mipLevels: texture.mipCount, payloadRecordID: texture.payloadRecordID,
            payloadDecodedSHA256: levels[0].decodedSHA256,
            sourceOffset: texture.sourceOffset, sourceRowHandle: texture.sourceRowHandle,
            sourceSpan: texture.sourceSpan, levels: levels, palette: palette
        )
    }

    private static func stageTextureDescriptor(
        modelName: String,
        model: GoldenEyeSourceModelV6,
        texture: GoldenEyeSourceModelV6.Texture,
        stageTextures: GoldenEyeStageTextureCatalogV6
    ) -> GoldenEyeSourceTextureDescriptorV6? {
        guard let stageTexture = stageTexture(
            modelName: modelName, texture: texture, stageTextures: stageTextures
        ), texture.mipCount <= UInt32(stageTexture.levels.count),
              Int(texture.mipStart) + Int(texture.mipCount) <= model.mips.count else { return nil }
        let levels = Array(stageTexture.levels.prefix(Int(texture.mipCount))).enumerated().map { offset, level in
            let mip = model.mips[Int(texture.mipStart) + offset]
            return GoldenEyeSourceTextureLevelUploadV6(
                level: mip.level, width: level.width, height: level.height,
                payloadRecordID: mip.payloadRecordID, sourceOffset: mip.sourceOffset,
                sourceRowHandle: mip.sourceRowHandle, rawByteCount: mip.rawByteCount,
                decodedByteCount: UInt32(level.decoded.count), decodedSHA256: sha256(level.decoded),
                decoded: level.decoded
            )
        }
        guard levels.first?.width == texture.width, levels.first?.height == texture.height else { return nil }
        return GoldenEyeSourceTextureDescriptorV6(
            modelName: modelName, family: "ramrom-stage-model",
            resourceHandle: texture.resourceHandle, width: texture.width, height: texture.height,
            mipLevels: texture.mipCount, payloadRecordID: texture.payloadRecordID,
            payloadDecodedSHA256: levels[0].decodedSHA256,
            sourceOffset: texture.sourceOffset, sourceRowHandle: texture.sourceRowHandle,
            sourceSpan: texture.sourceSpan, levels: levels, palette: nil
        )
    }

    private static func normalizeTextureAliases(
        scene: GESourceSceneV6,
        modelName: String,
        model: GoldenEyeSourceModelV6
    ) -> GESourceSceneV6 {
        let commands = scene.commands.map { command -> GESourceCompiledCommandV6 in
            guard command.macro == "gsSPUseTexture", command.arguments.count >= 9,
                  let raw = textureArgument(command.arguments[8]),
                  let handle = resolveTextureHandle(raw, modelName: modelName, model: model),
                  handle != raw else { return command }
            var arguments = command.arguments
            arguments[8] = .handle(kind: .texture, value: handle)
            return GESourceCompiledCommandV6(
                displayListID: command.displayListID,
                ordinal: command.ordinal,
                macro: command.macro,
                macroHandle: command.macroHandle,
                opcode: command.opcode,
                arguments: arguments,
                word0: command.word0,
                word1: command.word1
            )
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

    private static func textureSetups(
        modelName: String,
        model: GoldenEyeSourceModelV6,
        commands: [GESourceCompiledCommandV6],
        descriptors: [UInt32: GoldenEyeSourceTextureDescriptorV6]
    ) -> [GoldenEyeSourceTextureSetupV6]? {
        var scaleS: UInt32?
        var scaleT: UInt32?
        var maxLOD: UInt32?
        var enabled: UInt32?
        var output: [GoldenEyeSourceTextureSetupV6] = []
        var keys = Set<String>()
        for command in commands {
            if command.macro == "gsSPTexture", command.arguments.count == 5 {
                scaleS = compact(command.arguments[0]); scaleT = compact(command.arguments[1])
                maxLOD = compact(command.arguments[2]); enabled = compact(command.arguments[4])
                continue
            }
            if command.macro == "gsSPTextureL", command.arguments.count == 6 {
                scaleS = compact(command.arguments[0]); scaleT = compact(command.arguments[1])
                maxLOD = compact(command.arguments[2]); enabled = compact(command.arguments[5])
                continue
            }
            let p: [UInt32]
            if command.macro == "gsSPUseTexture", command.arguments.count == 9 {
                p = command.arguments.map(compact)
            } else if command.macro == "rawGfx", command.word0 >> 24 == 0xc0 {
                let w0 = command.word0, w1 = command.word1
                p = [(w0 >> 22) & 3, (w0 >> 20) & 3, (w0 >> 18) & 3, (w0 >> 14) & 15, (w0 >> 10) & 15, w0 & 7, (w1 >> 24) & 0xff, (w1 >> 12) & 0xfff, w1 & 0xfff]
            } else {
                continue
            }
            guard let scaleS, let scaleT, let maxLOD, enabled == 1,
                  p.count == 9, p[2] < 8, p[5] <= 4,
                  p[6] <= maxLOD,
                  let rawHandle = textureArgument(command.arguments.last ?? .null),
                  let handle = resolveTextureHandle(rawHandle, modelName: modelName, model: model),
                  let texture = model.textures.first(where: { $0.resourceHandle == handle }),
                  let descriptor = descriptors[handle],
                  descriptor.levels.count == Int(texture.mipCount),
                  Int(texture.mipStart) + Int(texture.mipCount) <= model.mips.count,
                  maxLOD < 8 else { return nil }
            let levels = descriptor.levels.enumerated().map { offset, level in
                let mip = model.mips[Int(texture.mipStart) + offset]
                return GoldenEyeSourceTextureSetupLevelV6(
                    level: UInt32(offset), width: level.width, height: level.height,
                    payloadRecordID: mip.payloadRecordID, sourceOffset: mip.sourceOffset,
                    sourceRowHandle: mip.sourceRowHandle, rawByteCount: mip.rawByteCount,
                    decodedByteCount: UInt32(level.decoded.count), decodedSHA256: sha256(level.decoded)
                )
            }
            guard levels.first?.width == texture.width, levels.first?.height == texture.height else { return nil }
            let addressS = GoldenEyeSourceTextureAddressModeV6(rawValue: p[0])
            let addressT = GoldenEyeSourceTextureAddressModeV6(rawValue: p[1])
            guard let addressS, let addressT,
                  let maskS = mask(texture.sFlags, width: texture.width, mode: addressS),
                  let maskT = mask(texture.tFlags, width: texture.height, mode: addressT) else { return nil }
            let lrs = (texture.width - 1).multipliedReportingOverflow(by: 4)
            let lrt = (texture.height - 1).multipliedReportingOverflow(by: 4)
            guard !lrs.overflow, !lrt.overflow, lrs.partialValue <= 0xfff, lrt.partialValue <= 0xfff else { return nil }
            let tileState = GoldenEyeSourceTextureTileStateV6(
                tile: p[2], format: nil, size: texture.depth, line: nil, tmem: nil, palette: nil,
                addressS: addressS, addressT: addressT, maskS: maskS, maskT: maskT,
                shiftS: p[3], shiftT: p[4],
                bounds: GoldenEyeSourceTextureTileBoundsV6(
                    ulsQ2: 0, ultQ2: 0, lrsQ2: lrs.partialValue, lrtQ2: lrt.partialValue,
                    width: texture.width, height: texture.height, derivedFromPayloadDimensions: true
                ), derivedFromCustomCommand: true
            )
            let base = levels[0]
            let load = GoldenEyeSourceTextureLoadEvidenceV6(
                kind: .payload, tile: p[2], imageHandle: handle,
                payloadRecordID: base.payloadRecordID, level: 0,
                ulsQ2: 0, ultQ2: 0, lrsQ2: lrs.partialValue, lrtQ2: lrt.partialValue,
                dxt: nil, sourceOffset: base.sourceOffset,
                rawByteCount: base.rawByteCount, decodedByteCount: base.decodedByteCount
            )
            let key = "\(command.displayListID):\(command.ordinal):\(handle):\(p[2])"
            guard keys.insert(key).inserted else { continue }
            var hash = UInt64(1_469_598_103_934_665_603)
            for value in [command.displayListID, command.ordinal, handle, p[2], p[5], p[6], p[7], scaleS, scaleT, maxLOD, texture.payloadRecordID] {
                hash = mix(hash, UInt64(value))
            }
            for level in levels { hash = mix(hash, UInt64(level.payloadRecordID)); hash = mix(hash, UInt64(level.decodedByteCount)) }
            output.append(GoldenEyeSourceTextureSetupV6(
                sequence: command.ordinal, displayListID: command.displayListID, ordinal: command.ordinal,
                kind: .customGSetTex, modelName: modelName, resourceHandle: handle,
                aliasHandle: handle, tile: p[2], textureType: p[5], minLevel: p[6], detailID: p[7],
                textureScaleS: scaleS, textureScaleT: scaleT, maxLOD: maxLOD,
                imageFormat: nil, imageSize: texture.depth, imageWidth: texture.width,
                sourcePayloadRecordID: texture.payloadRecordID, sourceOffset: texture.sourceOffset,
                sourceRowHandle: texture.sourceRowHandle, sourceSpan: texture.sourceSpan,
                levels: levels, tileState: tileState, load: load, palette: nil,
                setupHash: hash == 0 ? 1 : hash
            ))
        }
        return output.isEmpty && !model.textures.isEmpty ? nil : output
    }

    private static func stageTexture(
        modelName: String,
        texture: GoldenEyeSourceModelV6.Texture,
        stageTextures: GoldenEyeStageTextureCatalogV6
    ) -> GoldenEyeStageTextureCatalogV6.Texture? {
        stageTextures.textures.first {
            fnv32("\(modelName):texture_row:\($0.imageName)") == texture.sourceRowHandle
                && $0.levels.first?.width == texture.width
                && $0.levels.first?.height == texture.height
        }
    }

    private static func matrixHandles(
        in commands: [GESourceCompiledCommandV6]
    ) -> (modelView: [UInt32], projection: [UInt32]) {
        var modelView = Set<UInt32>()
        var projection = Set<UInt32>()
        for command in commands where command.macro == "gsSPMatrix" && command.arguments.count >= 2 {
            guard let handle = textureArgument(command.arguments[0]) else { continue }
            let flags = compact(command.arguments[1])
            if flags & 1 != 0 { projection.insert(handle) } else { modelView.insert(handle) }
        }
        return (modelView.sorted(), projection.sorted())
    }

    /// Emits a zero-motion pose record for each source GroupRecord. Static
    /// props still use the portable model renderer's group-origin matrix
    /// path; an empty pose list would discard those origins and makes
    /// multi-part doors, vehicles, and consoles collapse onto the placement
    /// origin. The lowerer consumes the copied GroupRecord hierarchy and
    /// matrix selectors, so these records are source movement, not guessed
    /// animation.
    private static func staticGroupPoses(
        model: GoldenEyeSourceModelV6,
        modelName: String
    ) -> [GESourceAnimationPoseV6] {
        struct Group {
            let nodeID: UInt32
            let joint: UInt32
            let origin: [Int32]
            let parent: UInt32
        }
        var groups: [Group] = []
        var joints = Set<UInt32>()
        for node in model.nodes {
            guard node.scalarStart < UInt32(model.scalars.count) else { continue }
            let scalar = model.scalars[Int(node.scalarStart)]
            guard scalar.kindHandle == 0x2982_BA70,
                  let fields = splitTopLevel(scalar.semantic),
                  fields.count >= 5,
                  let joint = parseUnsigned(fields[1]),
                  joint != GoldenEyeSourceModelV6.nullHandle,
                  let origin = parseVectorQ16(fields[0]),
                  joints.insert(joint).inserted else {
                continue
            }
            var parent = node.parent
            var parentJoint: UInt32 = 0
            var seen = Set<UInt32>()
            while parent != GoldenEyeSourceModelV6.nullHandle,
                  parent < UInt32(model.nodes.count), seen.insert(parent).inserted {
                let parentNode = model.nodes[Int(parent)]
                if parentNode.scalarStart < UInt32(model.scalars.count) {
                    let parentScalar = model.scalars[Int(parentNode.scalarStart)]
                    if parentScalar.kindHandle == 0x2982_BA70,
                       let parentFields = splitTopLevel(parentScalar.semantic),
                       parentFields.count >= 2,
                       let parsedParent = parseUnsigned(parentFields[1]),
                       parsedParent != GoldenEyeSourceModelV6.nullHandle {
                        parentJoint = parsedParent + 1
                        break
                    }
                }
                parent = parentNode.parent
            }
            groups.append(Group(nodeID: node.id, joint: joint, origin: origin, parent: parentJoint))
        }
        guard !groups.isEmpty else { return [] }
        var output: [GESourceAnimationPoseV6] = []
        output.reserveCapacity(groups.count)
        for (index, group) in groups.enumerated() {
            var pose = GESourceAnimationPoseV6()
            pose.header.abi_version = UInt32(GE_NATIVE_ABI_VERSION)
            pose.header.struct_size = UInt32(MemoryLayout<GESourceAnimationPoseV6>.size)
            pose.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
            pose.pose_handle = 0xD700_0000 | UInt32(index + 1)
            pose.skeleton_handle = model.header.modelHandle
            pose.node_handle = group.joint + 1
            pose.parent_handle = group.parent
            pose.flags = 0
            pose.animation_tick = 0
            pose.reserved0 = 0
            pose.translation_q16 = (0, 0, 0)
            pose.rotation_q16 = (0, 0, 0, 65_536)
            pose.scale_q16 = (65_536, 65_536, 65_536)
            pose.pose_hash = poseHash(
                modelName: modelName,
                group: (nodeID: group.nodeID, joint: group.joint, origin: group.origin, parent: group.parent),
                index: index
            )
            pose.reserved1 = 0
            pose.reserved2 = 0
            output.append(pose)
        }
        return output
    }

    private static func splitTopLevel(_ text: String) -> [String]? {
        var values: [String] = []
        var start = text.startIndex
        var depth = 0
        for index in text.indices {
            switch text[index] {
            case "{", "(", "[": depth += 1
            case "}", ")", "]": depth = max(0, depth - 1)
            case "," where depth == 0:
                values.append(String(text[start..<index]).trimmingCharacters(in: .whitespacesAndNewlines))
                start = text.index(after: index)
            default: break
            }
        }
        values.append(String(text[start...]).trimmingCharacters(in: .whitespacesAndNewlines))
        return values
    }

    private static func parseUnsigned(_ text: String) -> UInt32? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&", with: "")
        if value.hasPrefix("0x") || value.hasPrefix("0X") {
            return UInt32(value.dropFirst(2), radix: 16)
        }
        return UInt32(value)
    }

    private static func parseVectorQ16(_ text: String) -> [Int32]? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
        let components = value.split(separator: ",", omittingEmptySubsequences: true)
        guard components.count >= 3 else { return nil }
        var output: [Int32] = []
        output.reserveCapacity(3)
        for component in components.prefix(3) {
            guard let number = Double(component.trimmingCharacters(in: .whitespacesAndNewlines)), number.isFinite else { return nil }
            let scaled = number * 65_536.0
            guard scaled >= Double(Int32.min), scaled <= Double(Int32.max) else { return nil }
            output.append(Int32(scaled.rounded(.toNearestOrAwayFromZero)))
        }
        return output.count == 3 ? output : nil
    }

    private static func poseHash(
        modelName: String,
        group: (nodeID: UInt32, joint: UInt32, origin: [Int32], parent: UInt32),
        index: Int
    ) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in modelName.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        for value in [UInt64(group.nodeID), UInt64(group.joint), UInt64(group.parent), UInt64(index)] {
            hash = (hash ^ value) &* 1_099_511_628_211
        }
        for value in group.origin { hash = (hash ^ UInt64(UInt32(bitPattern: value))) &* 1_099_511_628_211 }
        return hash == 0 ? 1 : hash
    }

    /// Some prepared prop graphs preserve the source's first vertex-load
    /// address token while later loads carry a typed group handle. The
    /// immutable model vertex stream is already group-ordered, so assign each
    /// guarded load to the next exact contiguous group window and expose the
    /// builder's deterministic per-load alias. This is a resource manifest,
    /// not a geometry rewrite.
    private static func vertexResourceOverrides(
        model: GoldenEyeSourceModelV6,
        scene: GESourceSceneV6
    ) throws -> [GEGBISourceVertexResourceV6] {
        struct Run { let handle: UInt32; let first: UInt32; let count: UInt32 }
        var runs: [Run] = []
        var index = 0
        while index < model.vertices.count {
            let handle = model.vertices[index].groupHandle
            let start = index
            index += 1
            while index < model.vertices.count, model.vertices[index].groupHandle == handle { index += 1 }
            runs.append(Run(handle: handle, first: UInt32(start), count: UInt32(index - start)))
        }
        var consumed = Array(repeating: UInt32(0), count: runs.count)
        var runIndex = 0
        var groupByDisplayList: [UInt32: UInt32] = [:]
        let displayListRecordKinds: Set<UInt32> = [
            0xA6AB_7D37, // ModelRoData_DisplayListPrimaryRecord
            0x029D_E761, // ModelRoData_DisplayListRecord
            0xA42D_EB1A, // ModelRoData_DisplayList_CollisionRecord
        ]
        for node in model.nodes where node.scalarStart < UInt32(model.scalars.count) {
            let scalar = model.scalars[Int(node.scalarStart)]
            guard displayListRecordKinds.contains(scalar.kindHandle),
                  scalar.metadata.count > 4,
                  scalar.metadata[4] != 0 else { continue }
            if node.primaryDisplayListID != GoldenEyeSourceModelV6.nullHandle {
                groupByDisplayList[node.primaryDisplayListID] = scalar.metadata[4]
            }
            if node.secondaryDisplayListID != GoldenEyeSourceModelV6.nullHandle {
                groupByDisplayList[node.secondaryDisplayListID] = scalar.metadata[4]
            }
        }
        var output: [GEGBISourceVertexResourceV6] = []
        var handles = Set<UInt32>()
        for command in scene.commands where command.macro == "gsSPVertex" {
            let requested = vertexLoadCount(command, model: model)
            guard requested > 0 else {
                throw GoldenEyeStageModelSceneCompositionV6.Error.invalidPlacement(
                    command.ordinal, "zero vertex load"
                )
            }
            let typedGroup: UInt32? = command.arguments.first.flatMap { value in
                if case let .handle(kind, value) = value, kind == .vertexGroup { return value }
                return nil
            }
            let targetGroup = typedGroup ?? groupByDisplayList[command.displayListID]
            let selectedRun: Int?
            if let targetGroup {
                if let exact = runs.firstIndex(where: { $0.handle == targetGroup }),
                   requested <= runs[exact].count - consumed[exact] {
                    selectedRun = exact
                } else {
                    while runIndex < runs.count
                            && consumed[runIndex] == runs[runIndex].count {
                        runIndex += 1
                    }
                    selectedRun = runs.indices.first {
                        $0 >= runIndex && requested <= runs[$0].count - consumed[$0]
                    }
                }
            } else {
                while runIndex < runs.count && consumed[runIndex] == runs[runIndex].count { runIndex += 1 }
                selectedRun = runIndex < runs.count ? runIndex : nil
            }
            guard let selectedRun,
                  requested <= runs[selectedRun].count - consumed[selectedRun] else {
                throw GoldenEyeStageModelSceneCompositionV6.Error.invalidPlacement(
                    command.ordinal, "vertex load exceeds source group window"
                )
            }
            let hash = (UInt32(2_166_136_261) ^ command.displayListID) &* 16_777_619
            let value = (hash ^ command.ordinal) &* 16_777_619
            let handle = 0xAC00_0000 | (value & 0x00ff_ffff == 0 ? 1 : value & 0x00ff_ffff)
            guard handles.insert(handle).inserted else {
                throw GoldenEyeStageModelSceneCompositionV6.Error.invalidPlacement(
                    command.ordinal, "duplicate vertex load alias"
                )
            }
            var resource = GEGBISourceVertexResourceV6()
            resource.handle = handle
            resource.first_vertex = runs[selectedRun].first + consumed[selectedRun]
            resource.vertex_count = requested
            resource.flags = UInt32(GE_SOURCE_GBI_V6_VERTEX_RESOURCE_FLAG_EXACT_ALIAS)
            output.append(resource)
            consumed[selectedRun] += requested
        }
        return output
    }

    private static func vertexLoadCount(
        _ command: GESourceCompiledCommandV6,
        model: GoldenEyeSourceModelV6
    ) -> UInt32 {
        let encoded = (command.word0 >> 16) & 0xff
        if encoded != 0 { return (encoded >> 4) + 1 }
        guard let source = model.commands.first(where: {
            $0.displayListID == command.displayListID && $0.ordinal == command.ordinal
        }), let open = source.semantic.firstIndex(of: "("),
              let close = source.semantic.lastIndex(of: ")") else { return 0 }
        let values = source.semantic[open..<close].split(separator: ",")
        guard values.count >= 2, let count = UInt32(String(values[values.count - 2]).trimmingCharacters(in: .whitespaces)) else { return 0 }
        return count
    }

    private static func compose(
        base: GoldenEyeSourceSceneSnapshotV6,
        modelResults: [GoldenEyeGBISceneBuildResultV6],
        unsupportedMask: UInt32,
        nativeTick: UInt64,
        stageID: UInt32,
        requireExactFogCoordinates: Bool
    ) throws -> GoldenEyeSourceSceneSnapshotV6 {
        var permissiveSummary = base.summary
        permissiveSummary.flags |= UInt32(GE_SOURCE_FRAME_V6_FLAG_PRESENTABLE)
        permissiveSummary.unsupported_visible_count = 0
        let permissiveBase = try GoldenEyeSourceSceneSnapshotV6(
            summary: permissiveSummary, resources: base.resources, transforms: base.transforms,
            animationPoses: base.animationPoses, vertices: base.vertices, indices: base.indices,
            renderStates: base.renderStates, drawCommands: base.drawCommands,
            textEvents: base.textEvents, audioEvents: base.audioEvents,
            // The environment adapter already decoded a source-local GBI
            // lighting sidecar for every stage material state.  Keep that
            // value-only context on the synthetic source result so the
            // composer can remap it alongside the copied render-state
            // handles below.  Dropping it here leaves the composed E2xx
            // state namespace without a geometry/model-view record and
            // makes the renderer fail closed even for a fully lowerable
            // room+prop subset.
            diagnostics: base.diagnostics, lightingFrameContext: base.lightingFrameContext,
            eyeSpaceZQ16: base.eyeSpaceZQ16,
            fogCoordinateQ16: base.fogCoordinateQ16
        )
        let synthetic = GoldenEyeGBISceneBuildResultV6(
            snapshot: permissiveBase, packetDialect: 0, packetCommandCount: 0,
            packetListCount: 0, packetVertexCount: UInt32(base.vertices.count),
            packetImageCount: UInt32(base.resources.count), sourceCommandWordHash: 0,
            packetCommandWordHash: 0, packetSourceCommandWordHash: 0,
            textureSetups: [], vertexResourceTotal: 0, vertexResourcePageCount: 0,
            vertexResourceManifestHash: 0,
            projectionConsumption: GoldenEyeGBIProjectionConsumptionEvidenceV6(
                sourceProjectionHandle: 1, sourceViewportHandle: 1,
                emittedProjectionTransformCount: 1, emittedViewportTransformCount: 1,
                combinedClipTransformHandle: 1, combinedClipTransformHandles: [1],
                requiredDrawCount: UInt32(base.drawCommands.count),
                consumedDrawCount: UInt32(base.drawCommands.count)
            ), decoderStatus: 0, decoderDraws: [], stateWordEvidence: [],
            decoderUnsupportedCount: 0, unsupportedVisibleCount: 0,
            unsupportedReasons: [], presentable: true,
            commandCount: UInt32(base.drawCommands.count), triangleCount: UInt32(base.drawCommands.count),
            sourceTriangleSlotCount: UInt32(base.drawCommands.count), decoderStateCount: 0,
            resourceCount: UInt32(base.resources.count), eventHash: base.summary.scene_hash,
            stateHash: base.summary.state_hash, geometryModesByState: [:], modelViewQ16ByState: [:],
            exactNodeTransformDrawCount: 0, fallbackNodeTransformDrawCount: 0,
            exactNodeTransformHandles: []
        )
        let combined = try GoldenEyeSourceSceneComposerV6.combine(
            // Model results carry decoded GBI geometry-mode/model-view
            // sidecars keyed by their source state handles.  Preserve them
            // so combine() can perform the same explicit state remap as it
            // does for render-state records; no defaults or inferred light
            // values cross this boundary.
            [synthetic] + modelResults,
            frame: try GoldenEyeGBISceneFrameContextV6(
                nativeTick: nativeTick, referenceTick: nativeTick >> 1,
                sourceTimer: 0, pairPhase: UInt32(nativeTick & 1),
                screen: UInt32(GE_SOURCE_FRAME_V6_SCREEN_RAMROM), subphase: stageID,
                viewportWidth: base.summary.viewport_width,
                viewportHeight: base.summary.viewport_height
            )
        )
        var summary = combined.summary
        summary.screen = UInt32(GE_SOURCE_FRAME_V6_SCREEN_RAMROM)
        summary.subphase = stageID
        summary.native_tick = nativeTick
        summary.reference_tick = nativeTick >> 1
        summary.pair_phase = UInt32(nativeTick & 1)
        summary.unsupported_visible_count = UInt32(unsupportedMask.nonzeroBitCount)
        if unsupportedMask == 0 {
            summary.flags |= UInt32(GE_SOURCE_FRAME_V6_FLAG_PRESENTABLE)
        } else {
            summary.flags &= ~UInt32(GE_SOURCE_FRAME_V6_FLAG_PRESENTABLE)
        }
        summary.scene_hash = mix(combined.summary.scene_hash, UInt64(unsupportedMask))
        summary.render_hash = mix(combined.summary.render_hash, UInt64(stageID))
        summary.state_hash = mix(combined.summary.state_hash, UInt64(nativeTick))
        summary.frame_hash = mix(combined.summary.frame_hash, UInt64(unsupportedMask) ^ nativeTick)
        let fogSidecars = try propagatedFogSidecars(
            base: base,
            modelResults: modelResults,
            combinedVertexCount: combined.vertices.count,
            stageID: stageID,
            requireExactFogCoordinates: requireExactFogCoordinates
        )
        return try GoldenEyeSourceSceneSnapshotV6(
            summary: summary, resources: combined.resources, transforms: combined.transforms,
            animationPoses: combined.animationPoses, vertices: combined.vertices, indices: combined.indices,
            renderStates: combined.renderStates, drawCommands: combined.drawCommands,
            textEvents: combined.textEvents, audioEvents: combined.audioEvents,
            diagnostics: combined.diagnostics, lightingFrameContext: combined.lightingFrameContext,
            eyeSpaceZQ16: fogSidecars.eyeSpaceZQ16,
            fogCoordinateQ16: fogSidecars.fogCoordinateQ16
        )
    }

    /// `GoldenEyeSourceSceneComposerV6.combine` predates the additive stage
    /// fog sidecars and therefore intentionally knows nothing about them.
    /// Rebuild the parallel arrays here in source order, and reject any
    /// composed stage frame whose fog-enabled draw would otherwise reach the
    /// renderer without an exact clip-Z/clip-W coordinate. Proven non-fog
    /// model vertices receive a neutral parallel sidecar entry only so the
    /// value-only GPU arrays retain one-to-one indexing.
    private static func propagatedFogSidecars(
        base: GoldenEyeSourceSceneSnapshotV6,
        modelResults: [GoldenEyeGBISceneBuildResultV6],
        combinedVertexCount: Int,
        stageID: UInt32,
        requireExactFogCoordinates: Bool
    ) throws -> (eyeSpaceZQ16: [Int32]?, fogCoordinateQ16: [Int32]?) {
        let sources = [base] + modelResults.map(\.snapshot)
        let hasEye = sources.contains { $0.eyeSpaceZQ16 != nil }
        let hasFog = sources.contains { $0.fogCoordinateQ16 != nil }
        guard hasEye == hasFog else {
            throw Error.composition("stage fog sidecars must be present as a pair")
        }
        guard sources.allSatisfy({ source in
            let eyeCount = source.eyeSpaceZQ16?.count
            let fogCount = source.fogCoordinateQ16?.count
            guard eyeCount == nil && fogCount == nil ||
                    eyeCount == source.vertices.count && fogCount == source.vertices.count else {
                return false
            }
            return (eyeCount == nil) == (fogCount == nil)
        }) else {
            throw Error.composition("stage fog sidecar count mismatch")
        }

        let fogEnabled = (try? GoldenEyeStageFogLoweringV6.make(stageID: stageID))?.enabled == true
        let missingFogCoordinates = fogEnabled && sources.contains { source in
            hasFogShadeDraw(source) &&
                (source.eyeSpaceZQ16 == nil || source.fogCoordinateQ16 == nil)
        }
        if missingFogCoordinates {
            if !requireExactFogCoordinates { return (nil, nil) }
            throw Error.composition(
                "fog-enabled stage draw lacks exact eye-space/fog coordinate arrays"
            )
        }

        guard hasEye else {
            return (nil, nil)
        }
        // Non-fog model draws do not need a source coordinate, but the
        // generic GPU vertex/index view remains one parallel array. Use the
        // typed neutral payload only for those proven non-fog draws; a
        // fog-enabled draw took the fail-closed path above instead of being
        // silently zero-filled.
        var eye: [Int32] = []
        var fog: [Int32] = []
        eye.reserveCapacity(combinedVertexCount)
        fog.reserveCapacity(combinedVertexCount)
        for source in sources {
            if let values = source.eyeSpaceZQ16 {
                eye.append(contentsOf: values)
            } else {
                eye.append(contentsOf: repeatElement(Int32(0), count: source.vertices.count))
            }
            if let values = source.fogCoordinateQ16 {
                fog.append(contentsOf: values)
            } else {
                fog.append(contentsOf: repeatElement(Int32(0), count: source.vertices.count))
            }
        }
        guard eye.count == combinedVertexCount, fog.count == combinedVertexCount else {
            throw Error.composition("stage fog sidecars are not parallel to composed vertices")
        }
        return (eye, fog)
    }

    /// Match the renderer's exact admitted geometry-fog blender tuple without
    /// importing its Metal-facing pipeline type into the packet composer.
    /// This keeps the source draw classification value-only and makes the
    /// fail-closed sidecar rule testable in the strict/ASan/UBSan packet lanes.
    private static func hasFogShadeDraw(
        _ snapshot: GoldenEyeSourceSceneSnapshotV6
    ) -> Bool {
        let states = Dictionary(uniqueKeysWithValues: snapshot.renderStates.map {
            ($0.state_handle, $0)
        })
        return snapshot.drawCommands.contains { draw in
            guard let state = states[draw.render_state_handle],
                  state.flags & UInt32(GE_SOURCE_RENDER_STATE_V6_FLAG_FOG) != 0 else {
                return false
            }
            let mode = state.raw_render_mode
            return ((mode >> 30) & 3) == 3 &&
                ((mode >> 26) & 3) == 2 &&
                ((mode >> 22) & 3) == 0 &&
                ((mode >> 18) & 3) == 0
        }
    }

    private static func resultWithoutLighting(
        _ result: GoldenEyeGBISceneBuildResultV6
    ) -> GoldenEyeGBISceneBuildResultV6 {
        guard let lighting = result.snapshot.lightingFrameContext else { return result }
        _ = lighting
        let snapshot: GoldenEyeSourceSceneSnapshotV6
        do {
            snapshot = try GoldenEyeSourceSceneSnapshotV6(
                summary: result.snapshot.summary,
                resources: result.snapshot.resources,
                transforms: result.snapshot.transforms,
                animationPoses: result.snapshot.animationPoses,
                vertices: result.snapshot.vertices,
                indices: result.snapshot.indices,
                renderStates: result.snapshot.renderStates,
                drawCommands: result.snapshot.drawCommands,
                textEvents: result.snapshot.textEvents,
                audioEvents: result.snapshot.audioEvents,
                diagnostics: result.snapshot.diagnostics,
                lightingFrameContext: nil,
                eyeSpaceZQ16: result.snapshot.eyeSpaceZQ16,
                fogCoordinateQ16: result.snapshot.fogCoordinateQ16
            )
        } catch {
            return result
        }
        return GoldenEyeGBISceneBuildResultV6(
            snapshot: snapshot,
            packetDialect: result.packetDialect,
            packetCommandCount: result.packetCommandCount,
            packetListCount: result.packetListCount,
            packetVertexCount: result.packetVertexCount,
            packetImageCount: result.packetImageCount,
            sourceCommandWordHash: result.sourceCommandWordHash,
            packetCommandWordHash: result.packetCommandWordHash,
            packetSourceCommandWordHash: result.packetSourceCommandWordHash,
            textureSetups: result.textureSetups,
            vertexResourceTotal: result.vertexResourceTotal,
            vertexResourcePageCount: result.vertexResourcePageCount,
            vertexResourceManifestHash: result.vertexResourceManifestHash,
            projectionConsumption: result.projectionConsumption,
            decoderStatus: result.decoderStatus,
            decoderDraws: result.decoderDraws,
            stateWordEvidence: result.stateWordEvidence,
            decoderUnsupportedCount: result.decoderUnsupportedCount,
            unsupportedVisibleCount: result.unsupportedVisibleCount,
            unsupportedReasons: result.unsupportedReasons,
            presentable: result.presentable,
            commandCount: result.commandCount,
            triangleCount: result.triangleCount,
            sourceTriangleSlotCount: result.sourceTriangleSlotCount,
            decoderStateCount: result.decoderStateCount,
            resourceCount: result.resourceCount,
            eventHash: result.eventHash,
            stateHash: result.stateHash,
            geometryModesByState: result.geometryModesByState,
            modelViewQ16ByState: result.modelViewQ16ByState,
            exactNodeTransformDrawCount: result.exactNodeTransformDrawCount,
            fallbackNodeTransformDrawCount: result.fallbackNodeTransformDrawCount,
            exactNodeTransformHandles: result.exactNodeTransformHandles
        )
    }

    private static func unsupportedMask(
        environment: GoldenEyeStageBackgroundDrawPacket,
        propPlacementCount: Int,
        drawablePropPlacementCount: Int,
        characterPlacementCount: Int,
        categoryPackets: [GoldenEyeRamRomVisibleCategoryPacketV6]
    ) -> UInt32 {
        var mask = environment.unsupportedMask
        if propPlacementCount != drawablePropPlacementCount {
            mask |= GoldenEyeStageBackgroundDrawPacket.unsupportedProps
        } else {
            mask &= ~GoldenEyeStageBackgroundDrawPacket.unsupportedProps
        }
        if characterPlacementCount > 0 {
            mask |= GoldenEyeStageBackgroundDrawPacket.unsupportedCharacters
        }
        if categoryPackets.contains(where: { !$0.isPresentable && ["effects", "projectiles", "particles", "glass", "explosions", "hud", "watch", "sky", "fades"].contains($0.category) }) {
            mask |= GoldenEyeStageBackgroundDrawPacket.unsupportedEffects
        }
        return mask
    }

    private static func compositionHash(
        snapshot: GoldenEyeSourceSceneSnapshotV6,
        categoryPackets: [GoldenEyeRamRomVisibleCategoryPacketV6]
    ) -> UInt64 {
        categoryPackets.reduce(snapshot.copiedRecordAggregateHash) { hash, packet in
            mix(mix(hash, packet.packetHash), UInt64(packet.records.count))
        }
    }

    private static func contiguousBatches(
        snapshot: GoldenEyeSourceSceneSnapshotV6
    ) -> [Int] {
        guard !snapshot.drawCommands.isEmpty else { return [] }
        var counts: [Int] = []
        var current = 0
        var previous: (UInt32, UInt32, UInt32, UInt32)?
        for draw in snapshot.drawCommands {
            let key = (
                draw.render_state_handle,
                draw.resource_handle,
                draw.transform_handle,
                draw.flags
            )
            if let previous, previous != key {
                counts.append(current)
                current = 0
            }
            previous = key
            current += 1
        }
        if current > 0 { counts.append(current) }
        return counts
    }

    private static func textureArgument(_ value: GoldenEyeSourceModelV6.TokenValue) -> UInt32? {
        switch value {
        case let .handle(_, value): return value == GoldenEyeSourceModelV6.nullHandle ? nil : value
        case let .integer(value): return value >= 0 ? UInt32(value) : nil
        case let .constant(_, value): return value == GoldenEyeSourceModelV6.nullHandle ? nil : value
        default: return nil
        }
    }

    private static func resolveTextureHandle(
        _ raw: UInt32,
        modelName: String?,
        model: GoldenEyeSourceModelV6
    ) -> UInt32? {
        if model.textures.contains(where: { $0.resourceHandle == raw }) { return raw }
        let matches = model.textures.filter { ($0.resourceHandle & 0x0000_0fff) == raw }
        if matches.count == 1 { return matches[0].resourceHandle }
        guard let modelName else { return nil }
        let rowMatches = model.textures.filter { texture in
            fnv32("\(modelName):texture_row:\(raw)") == texture.sourceRowHandle
                || fnv32("\(modelName):texture_row:IMAGE_\(raw)") == texture.sourceRowHandle
        }
        return rowMatches.count == 1 ? rowMatches[0].resourceHandle : nil
    }

    private static func compact(_ value: GoldenEyeSourceModelV6.TokenValue) -> UInt32 {
        textureArgument(value) ?? 0
    }

    private static func mask(
        _ sourceFlags: UInt32,
        width: UInt32,
        mode: GoldenEyeSourceTextureAddressModeV6
    ) -> UInt32? {
        if mode == .clamp || sourceFlags == 2 { return 0 }
        guard width > 0, width & (width - 1) == 0 else { return nil }
        return UInt32(width.trailingZeroBitCount)
    }

    private static func fnv32(_ value: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in value.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return hash == 0 ? 1 : hash
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func mix(_ hash: UInt64, _ value: UInt64) -> UInt64 {
        var result = hash
        for shift in stride(from: 0, through: 56, by: 8) {
            result = (result ^ ((value >> UInt64(shift)) & 0xff)) &* 1_099_511_628_211
        }
        return result == 0 ? 1 : result
    }
}

/// Source-visible non-model dependencies are represented as typed records
/// before their draw lowerers exist. This gives every attract route a stable,
/// bounded category packet and keeps the Release mask honest: a category is
/// not presentable merely because its manifest row was discovered.
struct GoldenEyeRamRomVisibleCategoryRecordV6: Sendable, Equatable {
    let ordinal: UInt32
    let categoryCode: UInt32
    let symbolHash: UInt32
    let modelIndex: UInt32
    let demoMask: UInt32
    let stageMask: UInt32
    let resourceHandle: UInt32
    let flags: UInt32
}

struct GoldenEyeRamRomVisibleCategoryPacketV6: Sendable, Equatable {
    let stageID: UInt32
    let demoID: UInt8?
    let category: String
    let records: [GoldenEyeRamRomVisibleCategoryRecordV6]
    let lowererVersion: UInt32
    let unsupportedCount: UInt32
    let packetHash: UInt64

    var isPresentable: Bool { unsupportedCount == 0 && !records.isEmpty }
}

enum GoldenEyeRamRomVisibleCategoryLowererV6 {
    static let categories = [
        "audio", "doors", "effects", "explosions", "fades", "glass", "guards", "heads",
        "hud", "particles", "props", "projectiles", "sky", "textures", "watch", "weapons",
    ]

    static func make(
        catalog: GoldenEyeRamRomVisibleDependencyCatalogV6?,
        stageID: UInt32,
        stageName: String,
        demoID: UInt8?
    ) -> [GoldenEyeRamRomVisibleCategoryPacketV6] {
        categories.map { category in
            let rows = catalog?.dependencies.filter {
                $0.category == category && $0.stages.contains(stageName)
                    && (demoID == nil || $0.demoIDs.contains(demoID!))
            } ?? []
            let records = rows.enumerated().map { offset, row in
                let modelIndex = row.modelIndex ?? UInt32.max
                return GoldenEyeRamRomVisibleCategoryRecordV6(
                    ordinal: UInt32(offset), categoryCode: categoryCode(category),
                    symbolHash: fnv32(row.symbol), modelIndex: modelIndex,
                    demoMask: row.demoIDs.reduce(UInt32(0)) { $0 | (UInt32(1) << UInt32($1)) },
                    stageMask: fnv32(row.stages.joined(separator: ",")),
                    resourceHandle: fnv32("ramrom-visible:\(category):\(row.symbol)"),
                    flags: 0
                )
            }
            // Category packets are source manifests, not draw packets. Keep
            // them explicitly unsupported until a category-specific source
            // producer and material lowerer has emitted every visible record.
            let unsupported = rows.isEmpty ? UInt32(0) : UInt32(rows.count)
            return GoldenEyeRamRomVisibleCategoryPacketV6(
                stageID: stageID, demoID: demoID, category: category,
                records: records, lowererVersion: 1,
                unsupportedCount: unsupported,
                packetHash: hash(stageID: stageID, demoID: demoID, category: category, records: records, unsupported: unsupported)
            )
        }
    }

    private static func categoryCode(_ category: String) -> UInt32 {
        UInt32(categories.firstIndex(of: category) ?? 0) + 1
    }

    private static func fnv32(_ value: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in value.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return hash == 0 ? 1 : hash
    }

    private static func hash(
        stageID: UInt32,
        demoID: UInt8?,
        category: String,
        records: [GoldenEyeRamRomVisibleCategoryRecordV6],
        unsupported: UInt32
    ) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for value in [UInt64(stageID), UInt64(demoID ?? UInt8.max), UInt64(unsupported)] {
            hash = mix(hash, value)
        }
        for byte in category.utf8 { hash = mix(hash, UInt64(byte)) }
        for record in records {
            for value in [UInt64(record.ordinal), UInt64(record.categoryCode), UInt64(record.symbolHash), UInt64(record.modelIndex), UInt64(record.demoMask), UInt64(record.stageMask), UInt64(record.resourceHandle), UInt64(record.flags)] {
                hash = mix(hash, value)
            }
        }
        return hash
    }

    private static func mix(_ hash: UInt64, _ value: UInt64) -> UInt64 {
        var result = hash
        for shift in stride(from: 0, through: 56, by: 8) {
            result = (result ^ ((value >> UInt64(shift)) & 0xff)) &* 1_099_511_628_211
        }
        return result == 0 ? 1 : result
    }
}
