#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif
import Foundation
import Metal
import QuartzCore

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), "goldeneye_gunbarrel_metal_reference_capture_v6_smoke: \(message)")
}

private let arguments = Array(CommandLine.arguments.dropFirst())
private let root = URL(fileURLWithPath: arguments.first ?? "build/native/source-frontend-v6-image-decoder-v6", isDirectory: true)
private let metallibURL = URL(fileURLWithPath: arguments.dropFirst().first ?? "build/native/source-scene-renderer-v6/GoldenEyeSourceSceneV6.metallib")
private let sidecarURL = URL(fileURLWithPath: arguments.dropFirst(2).first ?? "build/native/gunbarrel-v6-prepared/gunbarrel.gbar")
private let outputRoot = URL(fileURLWithPath: arguments.dropFirst(3).first ?? "build/native/gunbarrel-metal-reference-capture-v6", isDirectory: true)

private func firstMatrixHandle(_ model: GoldenEyeSourceModelV6) throws -> UInt32 {
    for (index, command) in model.commands.enumerated() where command.semantic.hasPrefix("gsSPMatrix") {
        if let token = model.tokens(for: index).first, token.encodedValue != 0 {
            return token.encodedValue
        }
    }
    throw GoldenEyeSourceFrontendMatricesV6Error.missingModelMatrixHandle("gunbarrel")
}

private func sourcePoseRecord(_ pose: GoldenEyeGunbarrelPoseV6) -> GESourceAnimationPoseV6 {
    var value = GESourceAnimationPoseV6()
    value.header.abi_version = GE_NATIVE_ABI_VERSION
    value.header.struct_size = UInt32(MemoryLayout<GESourceAnimationPoseV6>.size)
    value.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
    value.pose_handle = UInt32(truncatingIfNeeded: pose.poseHash | 0xD700_0000)
    value.skeleton_handle = pose.skeletonHandle
    value.node_handle = pose.nodeHandle
    value.parent_handle = pose.parentHandle
    value.flags = UInt32(GE_SOURCE_POSE_V6_FLAG_INTERPOLATABLE)
        | (pose.jointIndex == 0 ? UInt32(GE_SOURCE_POSE_V6_FLAG_ROOT) : 0)
        | (pose.modelHandle == 9 ? UInt32(GE_SOURCE_POSE_V6_FLAG_WEAPON_ATTACHMENT) : 0)
    value.animation_tick = pose.animationTick
    value.translation_q16 = (pose.translationQ16.x, pose.translationQ16.y, pose.translationQ16.z)
    value.rotation_q16 = (pose.rotationQ16.x, pose.rotationQ16.y, pose.rotationQ16.z, pose.rotationQ16.w)
    value.scale_q16 = (pose.scaleQ16.x, pose.scaleQ16.y, pose.scaleQ16.z)
    value.pose_hash = pose.poseHash
    return value
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

private struct GunbarrelProjectedBoundsV6 {
    var points: Int = 0
    var minX = Double.infinity
    var minY = Double.infinity
    var maxX = -Double.infinity
    var maxY = -Double.infinity

    mutating func include(_ x: Double, _ y: Double) {
        points += 1
        minX = min(minX, x)
        minY = min(minY, y)
        maxX = max(maxX, x)
        maxY = max(maxY, y)
    }
}

private func gunbarrelProjectedBoundsV6(
    _ snapshot: GoldenEyeSourceSceneSnapshotV6
) throws -> GunbarrelProjectedBoundsV6 {
    let transforms = Dictionary(uniqueKeysWithValues: snapshot.transforms.map { ($0.handle, $0) })
    var result = GunbarrelProjectedBoundsV6()
    for draw in snapshot.drawCommands {
        guard let transform = transforms[draw.transform_handle] else { continue }
        let transformValues = gunbarrelMatrixQ16V6(transform)
        let start = Int(draw.first_index)
        let end = start + Int(draw.index_count)
        guard start >= 0, end <= snapshot.indices.count else { continue }
        for index in snapshot.indices[start..<end] {
            for vertexIndex in [index.vertex0, index.vertex1, index.vertex2] {
                guard Int(vertexIndex) < snapshot.vertices.count else { continue }
                let source = snapshot.vertices[Int(vertexIndex)]
                let position = withUnsafeBytes(of: source.position_q16) {
                    Array($0.bindMemory(to: Int32.self).prefix(3))
                }
                let projected = try GoldenEyeSourceProjectionBindingV6.apply(
                    matrixQ16: transformValues,
                    pointQ16: (position[0], position[1], position[2])
                )
                guard projected.w > 0 else { continue }
                result.include(
                    Double(projected.x) / Double(projected.w),
                    Double(projected.y) / Double(projected.w)
                )
            }
        }
    }
    return result
}

private struct GunbarrelDrawProjectedEvidenceV6 {
    let index: Int
    let resourceHandle: UInt32
    let transformHandle: UInt32
    let bounds: GunbarrelProjectedBoundsV6
}

private func gunbarrelDrawProjectedEvidenceV6(
    _ snapshot: GoldenEyeSourceSceneSnapshotV6
) throws -> [GunbarrelDrawProjectedEvidenceV6] {
    let transforms = Dictionary(uniqueKeysWithValues: snapshot.transforms.map { ($0.handle, $0) })
    var output: [GunbarrelDrawProjectedEvidenceV6] = []
    output.reserveCapacity(snapshot.drawCommands.count)
    for (drawIndex, draw) in snapshot.drawCommands.enumerated() {
        guard let transform = transforms[draw.transform_handle] else { continue }
        let transformValues = gunbarrelMatrixQ16V6(transform)
        let start = Int(draw.first_index)
        let end = start + Int(draw.index_count)
        guard start >= 0, end <= snapshot.indices.count else { continue }
        var bounds = GunbarrelProjectedBoundsV6()
        for index in snapshot.indices[start..<end] {
            for vertexIndex in [index.vertex0, index.vertex1, index.vertex2] {
                guard Int(vertexIndex) < snapshot.vertices.count else { continue }
                let source = snapshot.vertices[Int(vertexIndex)]
                let position = withUnsafeBytes(of: source.position_q16) {
                    Array($0.bindMemory(to: Int32.self).prefix(3))
                }
                let projected = try GoldenEyeSourceProjectionBindingV6.apply(
                    matrixQ16: transformValues,
                    pointQ16: (position[0], position[1], position[2])
                )
                guard projected.w > 0 else { continue }
                bounds.include(
                    Double(projected.x) / Double(projected.w),
                    Double(projected.y) / Double(projected.w)
                )
            }
        }
        output.append(GunbarrelDrawProjectedEvidenceV6(
            index: drawIndex,
            resourceHandle: draw.resource_handle,
            transformHandle: draw.transform_handle,
            bounds: bounds
        ))
    }
    return output
}

private struct GunbarrelPixelBoundsV6 {
    var nonBlackPixels = 0
    var minX = Int.max
    var minY = Int.max
    var maxX = -1
    var maxY = -1

    mutating func include(x: Int, y: Int) {
        nonBlackPixels += 1
        minX = min(minX, x)
        minY = min(minY, y)
        maxX = max(maxX, x)
        maxY = max(maxY, y)
    }
}

private func gunbarrelPixelBoundsV6(
    _ bytes: Data,
    width: Int = 320,
    height: Int = 240
) -> GunbarrelPixelBoundsV6 {
    var result = GunbarrelPixelBoundsV6()
    guard bytes.count >= width * height * 4 else { return result }
    for y in 0..<height {
        for x in 0..<width {
            let offset = (y * width + x) * 4
            if bytes[offset] != 0 || bytes[offset + 1] != 0 || bytes[offset + 2] != 0 {
                result.include(x: x, y: y)
            }
        }
    }
    return result
}

private func gunbarrelAggregateHashV6(_ values: [UInt64]) -> UInt64 {
    // This is an inspection-only hash.  Source summary/record hashes remain
    // authoritative; the aggregate simply lets the cadence audit identify
    // pose- and vertex-dependent work without changing the source packet.
    var hash: UInt64 = 1_469_598_103_934_665_603
    hash ^= UInt64(values.count)
    hash &*= 1_099_511_628_211
    for value in values {
        hash ^= value
        hash &*= 1_099_511_628_211
    }
    return hash == 0 ? 1 : hash
}

private func gunbarrelCombinedHashV6(_ groups: [[UInt64]]) -> UInt64 {
    var hash: UInt64 = 1_469_598_103_934_665_603
    for (index, group) in groups.enumerated() {
        hash ^= UInt64(index + 1)
        hash &*= 1_099_511_628_211
        hash ^= gunbarrelAggregateHashV6(group)
        hash &*= 1_099_511_628_211
    }
    return hash == 0 ? 1 : hash
}

private struct GunbarrelTimingFingerprintV6: Equatable {
    let sceneHash: UInt64
    let renderHash: UInt64
    let stateHash: UInt64
    let frameHash: UInt64
    let copiedRecordAggregateHash: UInt64
    let poseHashes: [UInt64]
    let sourceTopologyHash: UInt64
    let dynamicVertexHash: UInt64
    let dynamicTransformHash: UInt64
    let captureSHA256: String
}

private struct GunbarrelTimingSampleV6 {
    let label: String
    let mode: Int
    let timer: UInt32
    let nativeTick: UInt64
    let buildMs: Double
    let modelBuildMs: Double
    let composeMs: Double
    let reference320WallMs: Double
    let reference320EncodeMs: Double
    let reference320PostEncodeMs: Double
    let faithfulHDWallMs: Double
    let drawCount: Int
    let metalDrawCount: Int
    let triangleCount: Int
    let poseCount: Int
    let fingerprint: GunbarrelTimingFingerprintV6

    var tsv: String {
        let f = { (value: Double) in String(format: "%.3f", value) }
        let hex = { (value: UInt64) in String(value, radix: 16) }
        return [
            label,
            String(mode),
            String(timer),
            String(nativeTick),
            f(buildMs),
            f(modelBuildMs),
            f(composeMs),
            f(reference320WallMs),
            f(reference320EncodeMs),
            f(reference320PostEncodeMs),
            f(faithfulHDWallMs),
            String(drawCount),
            String(metalDrawCount),
            String(triangleCount),
            String(poseCount),
            hex(fingerprint.sceneHash),
            hex(fingerprint.renderHash),
            hex(fingerprint.stateHash),
            hex(fingerprint.frameHash),
            hex(fingerprint.copiedRecordAggregateHash),
            hex(gunbarrelAggregateHashV6(fingerprint.poseHashes)),
            hex(fingerprint.sourceTopologyHash),
            hex(fingerprint.dynamicVertexHash),
            hex(fingerprint.dynamicTransformHash),
            fingerprint.captureSHA256
        ].joined(separator: "\t")
    }
}

private final class GunbarrelTimingAuditV6 {
    private(set) var samples: [GunbarrelTimingSampleV6] = []
    private var fingerprintsByKey: [String: GunbarrelTimingFingerprintV6] = [:]

    let enabled: Bool

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        enabled = environment["GE_GUNBARREL_TIMING_AUDIT"] == "1"
    }

    func append(_ sample: GunbarrelTimingSampleV6, key: String) {
        guard enabled else { return }
        if let previous = fingerprintsByKey[key] {
            // The capture list intentionally repeats timer 137 and 212 (and
            // 230) in its temporal sweep.  These checks prove that any
            // future cache seam preserves the exact source frame and pose,
            // rather than merely producing a similar image.
            expect(previous == sample.fingerprint,
                   "repeated Gunbarrel source frame changed for \(key)")
        } else {
            fingerprintsByKey[key] = sample.fingerprint
        }
        samples.append(sample)
    }

    func writeArtifacts(to root: URL) throws {
        guard enabled else { return }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let header = [
            "label", "mode", "timer", "nativeTick", "buildMs", "modelBuildMs",
            "composeMs", "reference320WallMs", "reference320EncodeMs",
            "reference320PostEncodeMs", "faithfulHDWallMs", "drawCount",
            "metalDrawCount", "triangleCount", "poseCount", "sceneHash",
            "renderHash", "stateHash", "frameHash", "copiedRecordAggregateHash",
            "poseAggregateHash", "sourceTopologyHash", "dynamicVertexHash",
            "dynamicTransformHash", "captureSHA256"
        ].joined(separator: "\t")
        let tsv = ([header] + samples.map(\.tsv)).joined(separator: "\n") + "\n"
        try Data(tsv.utf8).write(
            to: root.appendingPathComponent("gunbarrel-cadence-timing.tsv"),
            options: .atomic
        )

        let buildValues = samples.map(\.buildMs)
        let modelValues = samples.map(\.modelBuildMs)
        let composeValues = samples.map(\.composeMs)
        let submitValues = samples.map(\.reference320PostEncodeMs)
        let percentile: ( [Double], Double) -> Double = { values, fraction in
            guard !values.isEmpty else { return 0 }
            let sorted = values.sorted()
            let position = max(0, min(sorted.count - 1, Int(ceil(fraction * Double(sorted.count))) - 1))
            return sorted[position]
        }
        let f = { (value: Double) in String(format: "%.3f", value) }
        let uniquePoseHashes = Set(samples.map { gunbarrelAggregateHashV6($0.fingerprint.poseHashes) })
        let uniqueVertexHashes = Set(samples.map(\.fingerprint.dynamicVertexHash))
        let uniqueTransformHashes = Set(samples.map(\.fingerprint.dynamicTransformHash))
        let uniqueTopologyHashes = Set(samples.map(\.fingerprint.sourceTopologyHash))
        let reframeSafe = uniqueVertexHashes.count == 1
            && uniqueTransformHashes.count == 1
            && uniquePoseHashes.count == 1
        let decision = reframeSafe ? "NOT_REQUIRED_FOR_SAMPLED_FRAMES" : "NOT_PROMOTED"
        let summary = [
            "samples=\(samples.count)",
            "build_p50_ms=\(f(percentile(buildValues, 0.50)))",
            "build_p95_ms=\(f(percentile(buildValues, 0.95)))",
            "model_build_p95_ms=\(f(percentile(modelValues, 0.95)))",
            "compose_p95_ms=\(f(percentile(composeValues, 0.95)))",
            "reference320_post_encode_p95_ms=\(f(percentile(submitValues, 0.95)))",
            "source_topology_variants=\(uniqueTopologyHashes.count)",
            "dynamic_vertex_variants=\(uniqueVertexHashes.count)",
            "dynamic_transform_variants=\(uniqueTransformHashes.count)",
            "pose_variants=\(uniquePoseHashes.count)",
            "cache_decision=\(decision)"
        ].joined(separator: "\n") + "\n"
        try Data(summary.utf8).write(
            to: root.appendingPathComponent("gunbarrel-cadence-summary.txt"),
            options: .atomic
        )

        let cacheReason: String
        if reframeSafe {
            cacheReason = "The sampled source frames share vertex, transform, and pose aggregates; no cache was promoted because the audit does not cover every source animation branch or display-list route."
        } else {
            cacheReason = "A full-scene reframe cache was not promoted. Gunbarrel pose, attachment, and/or transformed-vertex hashes vary across source timers; reusing the built snapshot would change source frame data. The current builder also selects the PP7 display-list route from the source timer/pair phase. A safe optimization needs a separate immutable decode/topology cache plus a source-authoritative pose/attachment reframe boundary, which is outside this diagnostic lane and the generic builder ownership boundary."
        }
        let report = [
            "# Gunbarrel cadence/cache audit V6",
            "",
            "This diagnostic is source-semantic only and does not alter production authority or the generic scene builder.",
            "",
            "- Samples: \(samples.count)",
            "- Source-topology hash variants: \(uniqueTopologyHashes.count)",
            "- Dynamic vertex hash variants: \(uniqueVertexHashes.count)",
            "- Dynamic transform hash variants: \(uniqueTransformHashes.count)",
            "- Pose hash variants: \(uniquePoseHashes.count)",
            "- Cache decision: `\(decision)`",
            "",
            cacheReason,
            "",
            "The TSV records source scene hashes, exact pose hashes, CPU encoder time, and wall time through the synchronous 320x240 readback path. `reference320PostEncodeMs` is wall time after the renderer's measured CPU command encoding interval; it includes queue submission, GPU completion/readback, and capture-file overhead.",
            ""
        ].joined(separator: "\n")
        try Data(report.utf8).write(
            to: root.appendingPathComponent("gunbarrel-cache-decision.md"),
            options: .atomic
        )
    }
}

private func makeMatrixResources(
    models: [String: GoldenEyeSourceModelV6],
    nativeTick: UInt64,
    sourceTimer: UInt32
) throws -> GoldenEyeSourceProductFrameResourcesV6 {
    let input = try GoldenEyeSourceFrontendMatrixInputV6(
        screen: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL),
        nativeTick: nativeTick,
        referenceTick: nativeTick >> 1,
        sourceTimer: sourceTimer,
        pairPhase: UInt32(nativeTick & 1)
    )
    var matrices: [GoldenEyeGBIMatrixResourceV6] = []
    var viewports: [GoldenEyeGBIViewportResourceV6] = []
    for name in ["suitbond", "headbrosnansuit", "chrwppk"] {
        guard let model = models[name] else { preconditionFailure("missing \(name)") }
        let frame = try GoldenEyeSourceFrontendMatricesV6.make(
            input: input,
            modelMatrixHandle: try firstMatrixHandle(model),
            viewportWidth: 440,
            viewportHeight: 330
        )
        for matrix in frame.resources.matrices where !matrices.contains(where: { $0.handle == matrix.handle }) {
            matrices.append(matrix)
        }
        guard let modelMatrix = frame.resources.matrices.first(where: {
            $0.roleFlags & GoldenEyeSourceMatrixRoleSidecarV6.modelView != 0
        }) else { preconditionFailure("missing model matrix") }
        for (index, command) in model.commands.enumerated() where command.semantic.hasPrefix("gsSPMatrix") {
            guard let token = model.tokens(for: index).first, token.encodedValue != 0 else { continue }
            if !matrices.contains(where: { $0.handle == token.encodedValue }) {
                matrices.append(try GoldenEyeGBIMatrixResourceV6(
                    handle: token.encodedValue,
                    values: modelMatrix.values,
                    roleFlags: GoldenEyeSourceMatrixRoleSidecarV6.modelView
                ))
            }
        }
        for viewport in frame.resources.viewports where !viewports.contains(where: { $0.handle == viewport.handle }) {
            viewports.append(viewport)
        }
    }
    return try GoldenEyeSourceProductFrameResourcesV6(
        matrices: matrices,
        viewports: viewports,
        viewportWidth: 440,
        viewportHeight: 330
    )
}

@available(macOS 26.0, *)
@main
struct GoldenEyeGunbarrelMetalReferenceCaptureV6Smoke {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4) else {
            print("goldeneye_gunbarrel_metal_reference_capture_v6_smoke: SKIP (Metal 4 device unavailable)")
            return
        }
        try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)
        let catalog = try GoldenEyeSourceFrontendCatalog.load(preparedAssetRoot: root)
        let sidecar = try GoldenEyeGunbarrelDynamicSidecarV6(loading: sidecarURL)
        expect(sidecar.resolvesGunbarrelModels, "dynamic resolver")
        let names = ["suitbond", "headbrosnansuit", "chrwppk"]
        var models: [String: GoldenEyeSourceModelV6] = [:]
        for name in names {
            models[name] = try GoldenEyeSourceModelV6.load(from: root.appendingPathComponent("\(name).gesm"))
        }
        let pairs = names.compactMap { name in models[name].map { (name: name, model: $0) } }
        let plan = try GoldenEyeSourceTextureUploadPlanV6.make(catalog: catalog, models: pairs)
        let layer = CAMetalLayer()
        layer.device = device
        let state = try GoldenEyeMetalDeviceState(device: device, layer: layer)
        guard let uploadEvent = device.makeSharedEvent() else { throw GoldenEyeGunbarrelPassRendererV6Error.sourceBuild("capture upload event") }
        let store = try GoldenEyeSourceTextureStoreV6(context: .init(
            device: device,
            queue: state.queue,
            residency: state.sceneResidency,
            completionEvent: uploadEvent
        ))
        _ = try store.upload(plan: plan)
        try store.drain()
        let binding = try GoldenEyeSourceSceneTextureBindingAdapterV6(store: store, plan: plan)
        let sourcePipeline = try GoldenEyeSourceScenePipelineV6(device: device, libraryURL: metallibURL)
        let passData = try catalog.copyOut(
            .decoded,
            for: catalog.record(kind: .background, name: "gunbarrel-background", family: "gunbarrel")
        )
        let passRenderer = try GoldenEyeGunbarrelPassRendererV6(
            state: state,
            sourcePipeline: sourcePipeline,
            backgroundData: passData,
            bloodData: sidecar.bloodEncoded
        )
        let sourceRenderer = try GoldenEyeSourceSceneRendererV6(
            state: state,
            pipeline: sourcePipeline,
            textureResolver: { store.texture(handle: $0) },
            textureBindingAdapter: binding,
            outputMode: .reference320x240,
            frontFacing: .counterClockwise
        )
        let hdRenderer = try GoldenEyeSourceSceneRendererV6(
            state: state,
            pipeline: sourcePipeline,
            textureResolver: { store.texture(handle: $0) },
            textureBindingAdapter: binding,
            outputMode: .faithfulHD,
            frontFacing: .counterClockwise
        )
        let clockwiseDiagnosticRenderer: GoldenEyeSourceSceneRendererV6?
        if ProcessInfo.processInfo.environment["GE_GUNBARREL_ISOLATED_EVIDENCE"] == "1" {
            clockwiseDiagnosticRenderer = try GoldenEyeSourceSceneRendererV6(
                state: state,
                pipeline: sourcePipeline,
                textureResolver: { store.texture(handle: $0) },
                textureBindingAdapter: binding,
                outputMode: .reference320x240,
                frontFacing: .clockwise
            )
        } else {
            clockwiseDiagnosticRenderer = nil
        }

        var baselineHash: String?
        var captureCases: [(label: String, mode: Int, timer: UInt32, nativeTick: UInt64, hd: Bool)] =
            (2...9).map { mode in
                let timer: UInt32 = mode == 2 ? 0 : (mode == 3 ? 137 : (mode == 4 ? 212 : (mode == 5 ? 230 : UInt32(mode * 32))))
                return (
                    label: "mode-\(mode)",
                    mode: mode,
                    timer: timer,
                    nativeTick: timer == 0 ? 2 : UInt64(timer),
                    hd: true
                )
            }
        if ProcessInfo.processInfo.environment["GE_GUNBARREL_TEMPORAL_SWEEP"] == "1" {
            captureCases += [
                ("timer-40", 3, 40, 40, false),
                ("timer-50", 3, 50, 50, false),
                ("timer-100", 3, 100, 100, false),
                ("timer-136", 3, 136, 136, false),
                ("timer-137", 3, 137, 137, false),
                ("timer-152", 3, 152, 152, false),
                ("timer-168", 3, 168, 168, false),
                ("timer-169", 3, 169, 169, false),
                ("timer-212", 3, 212, 212, false),
                ("timer-230", 3, 230, 230, false),
                ("timer-348", 3, 348, 348, false),
                ("timer-400", 3, 400, 400, false)
            ]
        }
        let timingAudit = GunbarrelTimingAuditV6()
        for captureCase in captureCases {
            let label = captureCase.label
            let mode = captureCase.mode
            let timer = captureCase.timer
            let nativeTick = captureCase.nativeTick
            let buildStart = DispatchTime.now().uptimeNanoseconds
            let frame = try GoldenEyeGBISceneFrameContextV6(
                nativeTick: nativeTick,
                referenceTick: nativeTick >> 1,
                sourceTimer: timer,
                pairPhase: UInt32(nativeTick & 1),
                screen: UInt32(GE_SOURCE_FRAME_V6_SCREEN_GUNBARREL),
                subphase: UInt32(mode - 2),
                viewportWidth: 440,
                viewportHeight: 330
            )
            let resources = try makeMatrixResources(models: models, nativeTick: nativeTick, sourceTimer: timer)
            let integratedRootMotion = try sidecar.integratedRootMotion(
                sourceSubstep: timer
            )
            let selection = (
                clipName: integratedRootMotion.clipName,
                frame: UInt32(max(0, integratedRootMotion.frameQ16 / 65_536))
                    % (try sidecar.clip(named: integratedRootMotion.clipName)).frameCount
            )
            guard let bodyModel = models["suitbond"] else {
                preconditionFailure("missing suitbond model")
            }
            let bodyPoses = try sidecar.poses(
                modelHandle: bodyModel.header.modelHandle,
                clipName: selection.clipName,
                frame: selection.frame,
                integratedRootMotion: integratedRootMotion
            ).map(sourcePoseRecord)
            let bodyCompilation = GESourceModelCompilerV6.compile(
                bodyModel,
                modelName: "suitbond",
                dynamicResolver: sidecar.dynamicResolver
            )
            guard let bodyScene = bodyCompilation.scene,
                  bodyCompilation.status == .complete,
                  bodyCompilation.diagnostics.isEmpty,
                  bodyScene.unsupportedCount == 0 else {
                throw GoldenEyeGunbarrelPassRendererV6Error.sourceBuild(
                    "missing complete body scene for attachments"
                )
            }
            let bodyLowering = try GoldenEyeSourceNodeTransformLowererV6.lower(
                model: bodyModel,
                scene: bodyScene,
                poses: bodyPoses,
                modelName: "suitbond"
            )
            let bodyBaseHandle = try firstMatrixHandle(bodyModel)
            guard let bodyBase = resources.matrices.first(where: {
                $0.handle == bodyBaseHandle
            }) else {
                throw GoldenEyeGunbarrelPassRendererV6Error.sourceBuild(
                    "missing body base matrix"
                )
            }
            let boneMatrices = Dictionary(uniqueKeysWithValues: bodyLowering.transforms.map {
                ($0.handle, gunbarrelMatrixQ16V6($0))
            })
            let headAttachmentHandle = GoldenEyeCastSkeletonTransformV6.matrixHandle(
                modelName: "suitbond", matrixID: 0
            )
            let weaponAttachmentHandle = GoldenEyeCastSkeletonTransformV6.matrixHandle(
                modelName: "suitbond", matrixID: 15
            )
            guard let headAssociation = bodyLowering.exactMatrixAssociations[headAttachmentHandle],
                  let headBoneValues = boneMatrices[headAssociation.transformHandle],
                  let weaponAssociation = bodyLowering.exactMatrixAssociations[weaponAttachmentHandle],
                  let weaponBoneValues = boneMatrices[weaponAssociation.transformHandle] else {
                throw GoldenEyeGunbarrelPassRendererV6Error.sourceBuild(
                    "missing exact source attachment matrix associations"
                )
            }
            let headAttachmentValues = GoldenEyeSourceProjectionBindingV6.multiply(
                bodyBase.values, headBoneValues
            )
            let weaponAttachmentValues = GoldenEyeSourceProjectionBindingV6.multiply(
                bodyBase.values, weaponBoneValues
            )
            if ProcessInfo.processInfo.environment["GE_GUNBARREL_NDC_EVIDENCE"] == "1",
               timer == 230 {
                print("gunbarrel_attachment_q16=bodyBase:\(bodyBase.values[12]),\(bodyBase.values[13]),\(bodyBase.values[14]):headBone:\(headBoneValues[12]),\(headBoneValues[13]),\(headBoneValues[14]):headAttached:\(headAttachmentValues[12]),\(headAttachmentValues[13]),\(headAttachmentValues[14]):weaponBone:\(weaponBoneValues[12]),\(weaponBoneValues[13]),\(weaponBoneValues[14]):weaponAttached:\(weaponAttachmentValues[12]),\(weaponAttachmentValues[13]),\(weaponAttachmentValues[14])")
            }
            var built: [GoldenEyeGBISceneBuildResultV6] = []
            var builtByName: [(name: String, result: GoldenEyeGBISceneBuildResultV6)] = []
            for name in names {
                guard let model = models[name] else { preconditionFailure("missing \(name)") }
                let compilation = GESourceModelCompilerV6.compile(model, modelName: name, dynamicResolver: sidecar.dynamicResolver)
                guard let compiled = compilation.scene else { preconditionFailure("missing compiled \(name)") }
                let setup = try GoldenEyeSourceTextureSetupResolverV6.resolve(
                    modelName: name,
                    model: model,
                    catalog: catalog,
                    compiledCommands: compiled.commands
                )
                let poses: [GESourceAnimationPoseV6]
                switch name {
                case "suitbond":
                    poses = bodyPoses
                case "headbrosnansuit":
                    poses = [makeGunbarrelAttachmentPoseV6(modelHandle: model.header.modelHandle)]
                default:
                    // PP7 inherits body matrix15/joint9 and receives no
                    // independent or synthetic weapon pose.
                    poses = []
                }
                // The generic V6 builder now owns pose-to-bone lowering and
                // emits one clip×bone transform per source draw. Keep matrix
                // resources at their source camera/model values here;
                // applying the legacy mutation in addition would double-
                // apply the same joint rotations.
                let attachmentValues: [Int32]?
                switch name {
                case "headbrosnansuit": attachmentValues = headAttachmentValues
                case "chrwppk": attachmentValues = weaponAttachmentValues
                default: attachmentValues = nil
                }
                // Keep source camera/model matrix resources untouched for the
                // generic V6 builder. Parent-world body lowering is only the
                // attachment oracle for head joint3 and weapon joint9; using
                // it as the body input would apply the same pose a second
                // time when node/clip lowering consumes `animationPoses`.
                var sourceMatrices = resources.matrices
                if let attachmentValues {
                    for (index, command) in model.commands.enumerated()
                        where command.semantic.hasPrefix("gsSPMatrix") {
                        guard let token = model.tokens(for: index).first,
                              token.encodedValue != 0,
                              let matrixIndex = sourceMatrices.firstIndex(where: {
                                  $0.handle == token.encodedValue
                              }) else { continue }
                        let existing = sourceMatrices[matrixIndex]
                        sourceMatrices[matrixIndex] = try GoldenEyeGBIMatrixResourceV6(
                            handle: existing.handle,
                            values: attachmentValues,
                            roleFlags: existing.roleFlags
                        )
                    }
                }
                let roles = try sourceMatrices.map {
                    try GoldenEyeSourceMatrixRoleSidecarV6(handle: $0.handle, roleFlags: $0.roleFlags)
                }
                let result = try GoldenEyeGBISceneBuilderV6.build(
                    model: model,
                    modelName: name,
                    matrices: sourceMatrices,
                    viewports: resources.viewports,
                    matrixRoles: roles,
                    frame: frame,
                    dynamicResolver: sidecar.dynamicResolver,
                    animationPoses: poses,
                    textureSetups: setup.setups,
                    omittedDisplayListIDs: name == "chrwppk" && !(timer == 230 && nativeTick & 1 == 0)
                        ? Set<UInt32>([1])
                        : []
                )
                expect(result.presentable && result.unsupportedVisibleCount == 0 && !result.snapshot.drawCommands.isEmpty, "\(name) source draws")
                if name == "chrwppk" {
                    expect(result.exactNodeTransformDrawCount == 0
                        && result.fallbackNodeTransformDrawCount == 0,
                        "\(name) capture has no synthetic weapon skeleton")
                } else {
                    expect(result.exactNodeTransformDrawCount == result.triangleCount,
                           "\(name) every visible triangle has exact source node provenance")
                    expect(result.fallbackNodeTransformDrawCount == 0,
                           "\(name) capture consumed no display-list transform fallback")
                }
                built.append(result)
                builtByName.append((name: name, result: result))
                if ProcessInfo.processInfo.environment["GE_GUNBARREL_NDC_EVIDENCE"] == "1" {
                    let bounds = try gunbarrelProjectedBoundsV6(result.snapshot)
                    print("gunbarrel_ndc=\(label):\(name):points=\(bounds.points):x=\(bounds.minX)...\(bounds.maxX):y=\(bounds.minY)...\(bounds.maxY)")
                }
            }
            let modelBuildEnd = DispatchTime.now().uptimeNanoseconds
            let composeStart = modelBuildEnd
            let snapshot = try GoldenEyeSourceSceneComposerV6.combine(built, frame: frame)
            let composeEnd = DispatchTime.now().uptimeNanoseconds
            for draw in snapshot.drawCommands {
                let indexStart = Int(draw.first_index)
                let indexEnd = indexStart + Int(draw.index_count)
                let vertexStart = draw.first_vertex
                let vertexEnd = vertexStart &+ draw.vertex_count
                expect(indexStart >= 0 && indexEnd <= snapshot.indices.count,
                       "composed draw index range")
                for index in snapshot.indices[indexStart..<indexEnd] {
                    expect(index.vertex0 >= vertexStart && index.vertex0 < vertexEnd
                        && index.vertex1 >= vertexStart && index.vertex1 < vertexEnd
                       && index.vertex2 >= vertexStart && index.vertex2 < vertexEnd,
                           "composed draw vertex references are rebased")
                }
            }
            let buildEnd = DispatchTime.now().uptimeNanoseconds
            let pass = GoldenEyeGunbarrelRenderPassV6.make(
                nativeTick: nativeTick,
                mode: UInt32(mode),
                poseCount: snapshot.summary.pose_count,
                bloodPayloadAvailable: !sidecar.bloodEncoded.isEmpty,
                bloodVisible: mode == 5,
                muzzleFlashVisible: timer == 230 && nativeTick & 1 == 0,
                fade: mode == 8 ? .clearBlack : ((mode == 6 || mode == 7) ? .red : .none),
                fadeAlphaQ8: mode == 8 ? 255 : ((mode == 6 || mode == 7) ? 180 : 0),
                titleXQ16: mode == 2 ? -30 * 65_536 : 1276 * 65_536,
                bloodFrameIndex: 0
            )
            let captureURL = outputRoot.appendingPathComponent("gunbarrel-\(label)-320x240.raw")
            let captureStart = DispatchTime.now().uptimeNanoseconds
            let capture = try sourceRenderer.captureReference320x240(
                snapshot: snapshot,
                to: captureURL,
                underlay: { encoder, slot in
                    try passRenderer.encodeUnderlay(pass: pass, encoder: encoder, slotIndex: slot)
                },
                overlay: { encoder, slot in
                    try passRenderer.encodeOverlay(pass: pass, encoder: encoder, slotIndex: slot)
                }
            )
            let captureEnd = DispatchTime.now().uptimeNanoseconds
            expect(capture.width == 320 && capture.height == 240, "mode \(mode) dimensions")
            expect(capture.bytes.contains(where: { $0 != 0 }), "mode \(mode) nonblack capture")
            if mode == 2 { baselineHash = capture.rawSHA256 }
            if ProcessInfo.processInfo.environment["GE_GUNBARREL_ISOLATED_EVIDENCE"] == "1",
               timer == 230 {
                for (name, result) in builtByName {
                    let isolatedURL = outputRoot.appendingPathComponent(
                        "gunbarrel-\(label)-isolated-\(name)-320x240.raw"
                    )
                    let isolated = try sourceRenderer.captureReference320x240(
                        snapshot: result.snapshot,
                        to: isolatedURL
                    )
                    let pixels = gunbarrelPixelBoundsV6(isolated.bytes)
                    let isolatedPNGPath = isolated.pngURL?.path ?? "none"
                    print("gunbarrel_isolated=\(label):\(name):draws=\(isolated.evidence.drawCount):triangles=\(isolated.evidence.triangleCount):pixels=\(pixels.nonBlackPixels):pixelBounds=\(pixels.minX),\(pixels.minY),\(pixels.maxX),\(pixels.maxY):sha256=\(isolated.rawSHA256):png=\(isolatedPNGPath)")
                    if name == "chrwppk" {
                        let colors = Set(result.snapshot.vertices.map(\.color_rgba))
                        let resources = result.snapshot.resources.map {
                            "0x\(String($0.handle, radix: 16))/kind\($0.resource_kind)/flags0x\(String($0.flags, radix: 16))"
                        }.joined(separator: ",")
                        print("gunbarrel_weapon_materials=colors:\(colors.map { String($0, radix: 16) }.sorted().joined(separator: ",")):resources:\(resources)")
                        let setupDescriptions = result.snapshot.resources.map { resource in
                            "resource=0x\(String(resource.handle, radix: 16))/kind=\(resource.resource_kind)/mips=\(resource.mip_count)/levels=\(resource.level_count)/flags=0x\(String(resource.flags, radix: 16))"
                        }.joined(separator: ";")
                        let sourceX = result.snapshot.vertices.map { $0.position_q16.0 }
                        let sourceY = result.snapshot.vertices.map { $0.position_q16.1 }
                        let sourceZ = result.snapshot.vertices.map { $0.position_q16.2 }
                        print("gunbarrel_weapon_setups=\(setupDescriptions)")
                        print("gunbarrel_weapon_source_bounds_q16=\(sourceX.min() ?? 0),\(sourceX.max() ?? 0),\(sourceY.min() ?? 0),\(sourceY.max() ?? 0),\(sourceZ.min() ?? 0),\(sourceZ.max() ?? 0)")
                        for draw in result.snapshot.drawCommands {
                            let state = result.snapshot.renderStateByHandle[draw.render_state_handle]
                            print("gunbarrel_weapon_state=draw0x\(String(draw.draw_handle, radix: 16)):resource=0x\(String(draw.resource_handle, radix: 16)):transform=0x\(String(draw.transform_handle, radix: 16)):vertices=\(draw.first_vertex)+\(draw.vertex_count):indices=\(draw.first_index)+\(draw.index_count):scissor=\(draw.scissor_x),\(draw.scissor_y),\(draw.scissor_width),\(draw.scissor_height):state=0x\(String(draw.render_state_handle, radix: 16)):cull=\(state?.cull_mode ?? 99):alpha=\(state?.alpha_mode ?? 99):depth=\(state?.depth_mode ?? 99):rawH=0x\(String(state?.raw_othermode_h ?? 0, radix: 16)):rawL=0x\(String(state?.raw_othermode_l ?? 0, radix: 16)):prim=0x\(String(state?.primitive_rgba ?? 0, radix: 16)):comb0=\(state?.cycle0_color_a ?? 99),\(state?.cycle0_color_b ?? 99),\(state?.cycle0_color_c ?? 99),\(state?.cycle0_color_d ?? 99):alpha0=\(state?.cycle0_alpha_a ?? 99),\(state?.cycle0_alpha_b ?? 99),\(state?.cycle0_alpha_c ?? 99),\(state?.cycle0_alpha_d ?? 99)")
                        }
                    }
                    if name == "chrwppk", let clockwiseDiagnosticRenderer {
                        let clockwiseURL = outputRoot.appendingPathComponent(
                            "gunbarrel-\(label)-isolated-\(name)-clockwise-320x240.raw"
                        )
                        let clockwise = try clockwiseDiagnosticRenderer.captureReference320x240(
                            snapshot: result.snapshot,
                            to: clockwiseURL
                        )
                        let clockwisePixels = gunbarrelPixelBoundsV6(clockwise.bytes)
                        let clockwisePNGPath = clockwise.pngURL?.path ?? "none"
                        print("gunbarrel_isolated_clockwise=\(label):\(name):pixels=\(clockwisePixels.nonBlackPixels):pixelBounds=\(clockwisePixels.minX),\(clockwisePixels.minY),\(clockwisePixels.maxX),\(clockwisePixels.maxY):sha256=\(clockwise.rawSHA256):png=\(clockwisePNGPath)")
                    }
                    if name == "chrwppk" {
                        let hdIsolated = try hdRenderer.renderOffscreen(
                            snapshot: result.snapshot,
                            width: 1_280,
                            height: 960
                        )
                        let hdRawURL = outputRoot.appendingPathComponent(
                            "gunbarrel-\(label)-isolated-\(name)-1280x960.raw"
                        )
                        let hdPNGURL = outputRoot.appendingPathComponent(
                            "gunbarrel-\(label)-isolated-\(name)-1280x960.png"
                        )
                        try hdIsolated.bytes.write(to: hdRawURL, options: .atomic)
                        let hdPNG = try GoldenEyeReferenceCaptureCodecV6.encodePNG(
                            bgra8: hdIsolated.bytes,
                            width: hdIsolated.width,
                            height: hdIsolated.height,
                            bytesPerRow: hdIsolated.bytesPerRow
                        )
                        try hdPNG.write(to: hdPNGURL, options: .atomic)
                        print("gunbarrel_isolated_hd=\(label):\(name):sha256=\(hdIsolated.rawSHA256):raw=\(hdRawURL.path):png=\(hdPNGURL.path)")
                    }
                    for evidence in try gunbarrelDrawProjectedEvidenceV6(result.snapshot) {
                        let bounds = evidence.bounds
                        print("gunbarrel_isolated_draw=\(label):\(name):index=\(evidence.index):resource=0x\(String(evidence.resourceHandle, radix: 16)):transform=0x\(String(evidence.transformHandle, radix: 16)):points=\(bounds.points):ndc=\(bounds.minX)...\(bounds.maxX),\(bounds.minY)...\(bounds.maxY)")
                    }
                }
            }
            print("gunbarrel_capture=\(label):draws=\(capture.evidence.drawCount):triangles=\(capture.evidence.triangleCount):sha256=\(capture.rawSHA256):png=\(capture.pngURL?.path ?? "none")")
            var faithfulHDWallMs = 0.0
            if captureCase.hd {
                let hdStart = DispatchTime.now().uptimeNanoseconds
                let hdCapture = try hdRenderer.renderOffscreen(
                    snapshot: snapshot,
                    width: 1_280,
                    height: 960,
                    underlay: { encoder, slot in
                        try passRenderer.encodeUnderlay(pass: pass, encoder: encoder, slotIndex: slot)
                    },
                    overlay: { encoder, slot in
                        try passRenderer.encodeOverlay(pass: pass, encoder: encoder, slotIndex: slot)
                    }
                )
                let hdEnd = DispatchTime.now().uptimeNanoseconds
                faithfulHDWallMs = Double(hdEnd &- hdStart) / 1_000_000.0
                expect(hdCapture.width == 1_280 && hdCapture.height == 960, "mode \(mode) faithful HD dimensions")
                expect(hdCapture.bytes.contains(where: { $0 != 0 }), "mode \(mode) faithful HD nonblack capture")
                let hdRawURL = outputRoot.appendingPathComponent("gunbarrel-\(label)-1280x960.raw")
                let hdPNGURL = outputRoot.appendingPathComponent("gunbarrel-\(label)-1280x960.png")
                try hdCapture.bytes.write(to: hdRawURL, options: .atomic)
                let hdPNG = try GoldenEyeReferenceCaptureCodecV6.encodePNG(
                    bgra8: hdCapture.bytes,
                    width: hdCapture.width,
                    height: hdCapture.height,
                    bytesPerRow: hdCapture.bytesPerRow
                )
                try hdPNG.write(to: hdPNGURL, options: .atomic)
                let decodedHD = try GoldenEyeReferenceCaptureCodecV6.decodePNG(hdPNG)
                expect(decodedHD.width == 1_280 && decodedHD.height == 960, "mode \(mode) faithful HD PNG dimensions")
                print("gunbarrel_hd_capture=mode\(mode):sha256=\(hdCapture.rawSHA256):raw=\(hdRawURL.path):png=\(hdPNGURL.path)")
            }
            if timingAudit.enabled {
                let fingerprint = GunbarrelTimingFingerprintV6(
                    sceneHash: snapshot.summary.scene_hash,
                    renderHash: snapshot.summary.render_hash,
                    stateHash: snapshot.summary.state_hash,
                    frameHash: snapshot.summary.frame_hash,
                    copiedRecordAggregateHash: snapshot.copiedRecordAggregateHash,
                    poseHashes: snapshot.animationPoseHashes,
                    sourceTopologyHash: gunbarrelCombinedHashV6([
                        snapshot.resourceHashes,
                        snapshot.indexHashes,
                        snapshot.drawCommandHashes,
                        snapshot.renderStateHashes
                    ]),
                    dynamicVertexHash: gunbarrelAggregateHashV6(snapshot.vertexHashes),
                    dynamicTransformHash: gunbarrelAggregateHashV6(snapshot.transformHashes),
                    captureSHA256: capture.rawSHA256
                )
                let buildMs = Double(buildEnd &- buildStart) / 1_000_000.0
                let modelBuildMs = Double(modelBuildEnd &- buildStart) / 1_000_000.0
                let composeMs = Double(composeEnd &- composeStart) / 1_000_000.0
                let reference320WallMs = Double(captureEnd &- captureStart) / 1_000_000.0
                let reference320EncodeMs = Double(capture.evidence.cpuEncodeNanoseconds) / 1_000_000.0
                let reference320PostEncodeMs = max(0, reference320WallMs - reference320EncodeMs)
                timingAudit.append(
                    GunbarrelTimingSampleV6(
                        label: label,
                        mode: mode,
                        timer: timer,
                        nativeTick: nativeTick,
                        buildMs: buildMs,
                        modelBuildMs: modelBuildMs,
                        composeMs: composeMs,
                        reference320WallMs: reference320WallMs,
                        reference320EncodeMs: reference320EncodeMs,
                        reference320PostEncodeMs: reference320PostEncodeMs,
                        faithfulHDWallMs: faithfulHDWallMs,
                        drawCount: capture.evidence.drawCount,
                        metalDrawCount: capture.evidence.metalDrawCount,
                        triangleCount: capture.evidence.triangleCount,
                        poseCount: snapshot.animationPoses.count,
                        fingerprint: fingerprint
                    ),
                    key: "mode=\(mode):timer=\(timer):nativeTick=\(nativeTick)"
                )
                let timingBuild = String(format: "%.3f", buildMs)
                let timingModelBuild = String(format: "%.3f", modelBuildMs)
                let timingCompose = String(format: "%.3f", composeMs)
                let timingReferenceWall = String(format: "%.3f", reference320WallMs)
                let timingReferenceEncode = String(format: "%.3f", reference320EncodeMs)
                print(
                    "gunbarrel_timing=\(label):buildMs=\(timingBuild):modelBuildMs=\(timingModelBuild):composeMs=\(timingCompose):reference320WallMs=\(timingReferenceWall):reference320EncodeMs=\(timingReferenceEncode):draws=\(capture.evidence.drawCount):metalDraws=\(capture.evidence.metalDrawCount):triangles=\(capture.evidence.triangleCount):sceneHash=0x\(String(snapshot.summary.scene_hash, radix: 16)):frameHash=0x\(String(snapshot.summary.frame_hash, radix: 16)):poseHash=0x\(String(gunbarrelAggregateHashV6(snapshot.animationPoseHashes), radix: 16))"
                )
            }
        }
        expect(baselineHash != nil, "capture baseline")
        try timingAudit.writeArtifacts(to: outputRoot)
        clockwiseDiagnosticRenderer?.shutdown()
        hdRenderer.shutdown()
        sourceRenderer.shutdown()
        try? store.shutdown()
        print("goldeneye_gunbarrel_metal_reference_capture_v6_smoke: PASS modes=2...9")
    }
}
