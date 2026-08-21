import CryptoKit
import Foundation

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

private func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
    digest.map { String(format: "%02x", $0) }.joined()
}

private let arguments = Array(CommandLine.arguments.dropFirst())
private let preparedRoot = URL(
    fileURLWithPath: arguments.first ?? "build/native/boot-assets",
    isDirectory: true
)

@main
struct GoldenEyeGunbarrelV6Smoke {
    static func main() throws {
        let first = try GoldenEyeGunbarrelSourceManifestV6.load(preparedRoot: preparedRoot)
        let second = try GoldenEyeGunbarrelSourceManifestV6.load(preparedRoot: preparedRoot)
        check(first == second, "manifest is not deterministic")
        check(first.models.map(\.modelHandle) == [7, 8, 9], "model handles/source order")
        check(first.models.allSatisfy { !$0.sourceSHA256.isEmpty && !$0.packetSHA256.isEmpty }, "model digests")
        check(first.background.width == 440 && first.background.height == 299, "background dimensions")
        check(first.holeVertexCount == 30 && first.holeTriangleCount == 28, "hole geometry counts")
        check(first.attachment.gunParentSwitch == 3, "weapon attachment parent")
        check(first.attachment.muzzleFlashSwitch == 0 && first.attachment.muzzleLightSwitch == 2, "muzzle switches")
        check(first.camera.aspectNumerator == 4 && first.camera.aspectDenominator == 3, "camera aspect")
        check(first.camera.fovDegreesQ16 == 3_014_656, "camera fov")
        check(first.manifestHash != 0, "manifest hash")

        var runtime = GoldenEyeGunbarrelRuntimeV6(manifest: first)
        let frame1 = try runtime.step(nativeTick: 1)
        let frame2 = try runtime.step(nativeTick: 2)
        check(frame1.pairPhase == 1 && frame2.pairPhase == 0, "paired cadence phases")
        check(frame1.nativeTick == 1 && frame2.nativeTick == 2, "native ticks")
        check(frame1.gunbarrelTimerSubstep == 1 && frame2.gunbarrelTimerSubstep == 2, "one model substep per native tick")
        check(frame1.titleXQ16 == -1_769_472, "odd title midpoint")
        check(frame1.rifleCue == false && frame2.rifleCue == false, "no early rifle cue")
        check(frame1.parts.count == 3 && frame1.parts[2].attachmentNode == 3, "body/head/weapon parts")
        check(frame1.parts.allSatisfy { $0.visible }, "initial model visibility")
        check(frame1.backgroundVisible == false && frame1.holeVisible,
              "mode-2 uses the generated dot mesh without the barrel backdrop")
        let mode2Pass = GoldenEyeGunbarrelRenderPassV6.make(
            nativeTick: 2,
            mode: 2,
            poseCount: 0,
            bloodPayloadAvailable: false,
            bloodVisible: false,
            muzzleFlashVisible: false,
            fade: .none,
            fadeAlphaQ8: 0,
            titleXQ16: frame2.titleXQ16,
            transitionXQ16: frame2.transitionXQ16
        )
        check(mode2Pass.backgroundVisible == false
            && mode2Pass.holeVisible
            && mode2Pass.holePassCount == 2
            && mode2Pass.titleXQ16 != mode2Pass.transitionXQ16,
              "mode-2 compositor submits both moving hole passes")
        let mode3Pass = GoldenEyeGunbarrelRenderPassV6.make(
            nativeTick: 3,
            mode: 3,
            poseCount: 0,
            bloodPayloadAvailable: false,
            bloodVisible: false,
            muzzleFlashVisible: false,
            fade: .none,
            fadeAlphaQ8: 0,
            titleXQ16: 1_276 * 65_536
        )
        check(mode3Pass.backgroundVisible && mode3Pass.holeVisible
            && mode3Pass.holePassCount == 1,
              "mode-3 switches to one enlarged sight/backdrop pass")

        var cueFrame: GoldenEyeGunbarrelFrameV6?
        var routeModes = Set<UInt32>([frame1.mode, frame2.mode])
        var last = frame2
        if last.gunbarrelTimerSubstep < 230 {
            for tick in 3...230 {
                last = try runtime.step(nativeTick: UInt64(tick))
                routeModes.insert(last.mode)
                if last.rifleCue { cueFrame = last }
            }
        }
        check(cueFrame?.nativeTick == 230, "rifle cue source substep")
        check(cueFrame?.parts.first(where: { $0.role == .weapon })?.muzzleFlashVisible == true, "muzzle flash switch")
        check(last.captureReady == false, "partial assets must fail capture readiness")
        do {
            _ = try GoldenEyeGunbarrelCaptureV6.make(frame: last, manifest: first)
            preconditionFailure("partial Gunbarrel capture was accepted")
        } catch let error as GoldenEyeGunbarrelCaptureV6.Error {
            if case .notReady = error {
                print("gunbarrel_capture_gate=PASS")
            } else {
                preconditionFailure("unexpected Gunbarrel capture error: \(error)")
            }
        }

        // Complete the logical route with a model adapter acknowledgement. It
        // still remains capture-deferred if the prepared geometry packets are
        // partial, but every source mode and fade is exercised headlessly.
        var completeRuntime = GoldenEyeGunbarrelRuntimeV6(manifest: first, bloodFrameAvailable: true)
        var completeModes = Set<UInt32>()
        var completeLast = try completeRuntime.step(nativeTick: 1)
        completeModes.insert(completeLast.mode)
        for tick in 2...1_500 {
            completeLast = try completeRuntime.step(nativeTick: UInt64(tick))
            completeModes.insert(completeLast.mode)
        }
        check(completeModes.isSuperset(of: Set([2, 3, 4, 5, 6, 7, 8, 9])), "source mode route (completeModes)")
        check(completeLast.mode == 9, "source route terminal mode")
        check(completeLast.fade == .clearBlack || completeLast.mode == 9, "terminal fade")

        // The real renderer starts mode 5 without a completion signal and
        // advances only as decoded blood frames are acknowledged. Exercise
        // the full 42-frame handshake instead of using the compatibility
        // `bloodFrameAvailable` initializer above.
        var streamedRuntime = GoldenEyeGunbarrelRuntimeV6(manifest: first)
        var streamedFrames = Set<UInt32>()
        var nextStreamedFrame: UInt32 = 0
        var streamedLast = try streamedRuntime.step(nativeTick: 1)
        for tick in 2...1_500 {
            streamedLast = try streamedRuntime.step(nativeTick: UInt64(tick))
            if streamedLast.mode == 5 {
                if streamedLast.pairPhase == 0 {
                    streamedFrames.insert(nextStreamedFrame)
                    streamedRuntime.acknowledgeBloodFrame(
                        index: nextStreamedFrame,
                        complete: nextStreamedFrame >= 41
                    )
                    nextStreamedFrame = min(nextStreamedFrame + 1, 41)
                }
            }
            if streamedLast.mode == 6 { break }
        }
        guard streamedFrames == Set(0...41) else {
            fatalError("blood mode acknowledges frames \(streamedFrames.sorted()), terminalMode=\(streamedLast.mode)")
        }
        print("blood_stream_frames=42 terminalMode=\(streamedLast.mode)")
        check(streamedLast.mode == 6, "blood completion transitions to red-overlay mode")

        if arguments.count > 1 {
            let bloodURL = URL(fileURLWithPath: arguments[1])
            let bloodData = try Data(contentsOf: bloodURL, options: [.mappedIfSafe])
            check(bloodData.count == 2_524, "blood encoded payload size")
            check(hex(SHA256.hash(data: bloodData)) == "cc960835635ee32b1ef793e6c30f9ec8ed199cd416c5dd8d418db1307ed2dda2", "blood encoded payload hash")
            let firstBlood = try GoldenEyeGunbarrelBloodDecoderV6.decodeInitial(bloodData)
            let secondBlood = try GoldenEyeGunbarrelBloodDecoderV6.decodeInitial(bloodData)
            let bloodStream = try GoldenEyeGunbarrelBloodDecoderV6.decodeAll(bloodData)
            check(firstBlood == secondBlood, "blood decode determinism")
            check(bloodStream.isComplete && bloodStream.frames.count == 42,
                  "blood stream contains exactly 42 complete frames")
            check(bloodStream.frames.first == firstBlood,
                  "blood stream frame zero matches decodeInitial")
            check(firstBlood.width == 96 && firstBlood.height == 80, "blood texture dimensions")
            check(firstBlood.pixels.count == 96 * 80, "blood texture payload size")
            check(firstBlood.pixels.contains(0xff) && firstBlood.pixels.contains(0), "blood frame content")
            do {
                _ = try GoldenEyeGunbarrelBloodDecoderV6.decodeInitial(Data([0]))
                preconditionFailure("truncated blood stream accepted")
            } catch is GoldenEyeGunbarrelBloodDecoderV6.Error {
                print("blood_truncation_guard=PASS")
            }
            print("blood_frame_sha256=\(firstBlood.digest)")
        }

        let manifestPath = URL(fileURLWithPath: arguments.count > 2 ? arguments[2] : "/tmp/goldeneye-gunbarrel-v6.manifest")
        try (first.manifestLines().joined(separator: "\n") + "\n").write(to: manifestPath, atomically: true, encoding: .utf8)
        if arguments.count > 3 {
            let sidecar = try GoldenEyeGunbarrelDynamicSidecarV6(
                loading: URL(fileURLWithPath: arguments[3])
            )
            check(sidecar.resolvesGunbarrelModels, "dynamic Gunbarrel resolver completeness")
            let walk = try sidecar.clip(named: "bond_eye_walk")
            let fire = try sidecar.clip(named: "bond_eye_fire")
            check(walk.frameCount == 35 && walk.frameBytes == 68 && walk.entryWords.count == 595, "Bond eye walk clip")
            check(fire.frameCount == 124 && fire.frameBytes == 68 && fire.entryWords.count == 2_108, "Bond eye fire clip")
            let bodyPose0 = try sidecar.poses(modelHandle: 8, clipName: "bond_eye_walk", frame: 0)
            let bodyPose1 = try sidecar.poses(modelHandle: 8, clipName: "bond_eye_walk", frame: 1)
            let root0 = try sidecar.rootMotion(clipName: "bond_eye_walk", frame: 0)
            let root1 = try sidecar.rootMotion(clipName: "bond_eye_walk", frame: 1)
            let integrated0 = try sidecar.integratedRootMotion(sourceSubstep: 0)
            let integrated1 = try sidecar.integratedRootMotion(sourceSubstep: 1)
            let integrated2 = try sidecar.integratedRootMotion(sourceSubstep: 2)
            let integrated40 = try sidecar.integratedRootMotion(sourceSubstep: 40)
            let integrated50 = try sidecar.integratedRootMotion(sourceSubstep: 50)
            let integrated74 = try sidecar.integratedRootMotion(sourceSubstep: 74)
            let integrated75 = try sidecar.integratedRootMotion(sourceSubstep: 75)
            let integrated136 = try sidecar.integratedRootMotion(sourceSubstep: 136)
            let integrated137 = try sidecar.integratedRootMotion(sourceSubstep: 137)
            let integrated152 = try sidecar.integratedRootMotion(sourceSubstep: 152)
            let integrated168 = try sidecar.integratedRootMotion(sourceSubstep: 168)
            let integrated169 = try sidecar.integratedRootMotion(sourceSubstep: 169)
            let integrated212 = try sidecar.integratedRootMotion(sourceSubstep: 212)
            let integrated230 = try sidecar.integratedRootMotion(sourceSubstep: 230)
            let integrated348 = try sidecar.integratedRootMotion(sourceSubstep: 348)
            let integrated400 = try sidecar.integratedRootMotion(sourceSubstep: 400)
            check(integrated0.translationQ16.x == 0 && integrated0.translationQ16.z == 0, "root integrator initial X/Z zero")
            check(integrated0.translationQ16.y == integrated1.translationQ16.y
                && integrated1.translationQ16.y == integrated2.translationQ16.y,
                  "root integrator initial Y seed")
            check(integrated40.translationQ16.z > 0 && integrated50.translationQ16.z > integrated40.translationQ16.z, "root integrator accumulation")
            check(integrated74.frameQ16 < Int64(35) << 16 && integrated75.frameQ16 < Int64(35) << 16, "walk loop frame normalization")
            check(integrated136.translationQ16.z > integrated50.translationQ16.z, "root integrator pre-fire path")
            check(integrated137.clipName == "bond_eye_fire", "root integrator fire transition")
            check(integrated137.frameQ16 > Int64(2) << 16, "fire transition advances from source frame 2")
            check(integrated152.frameQ16 > integrated137.frameQ16
                && integrated168.frameQ16 > integrated152.frameQ16
                && integrated169.frameQ16 > integrated168.frameQ16,
                  "fire merge frame progression")
            check(integrated152.translationQ16.z > integrated137.translationQ16.z
                && integrated168.translationQ16.z > integrated152.translationQ16.z
                && integrated169.translationQ16.z > integrated168.translationQ16.z,
                  "fire merge root progression")
            check(integrated212.frameQ16 > integrated169.frameQ16
                && integrated230.frameQ16 > integrated212.frameQ16,
                  "source speed ramp progression")
            check(integrated348.frameQ16 == Int64(123) << 16
                && integrated400.frameQ16 == integrated348.frameQ16
                && integrated400.translationQ16 == integrated348.translationQ16,
                  "non-loop fire terminal clamp")
            let integratedRootPose = try sidecar.poses(
                modelHandle: 8,
                clipName: integrated137.clipName,
                frame: UInt32(integrated137.frameQ16 >> 16),
                integratedRootMotion: integrated137
            ).first { $0.jointIndex == 0 }
            check(integratedRootPose?.rotationQ16 == SIMD4(0, integrated137.headingQ16, 0, 65_536),
                  "header root consumes heading only")
            print("gunbarrel_integrated_root=PASS tick40=\(integrated40.translationQ16.x),\(integrated40.translationQ16.y),\(integrated40.translationQ16.z) tick50=\(integrated50.translationQ16.x),\(integrated50.translationQ16.y),\(integrated50.translationQ16.z) tick136=\(integrated136.translationQ16.x),\(integrated136.translationQ16.y),\(integrated136.translationQ16.z) tick137=\(integrated137.translationQ16.x),\(integrated137.translationQ16.y),\(integrated137.translationQ16.z) merge152=\(integrated152.frameQ16) merge168=\(integrated168.frameQ16) merge169=\(integrated169.frameQ16) ramp212=\(integrated212.frameQ16) terminal348=\(integrated348.frameQ16)")
            let headPose = try sidecar.poses(modelHandle: 7, clipName: "bond_eye_fire", frame: 2)
            let weaponPose = try sidecar.poses(modelHandle: 9, clipName: "bond_eye_fire", frame: 2)
            check(bodyPose0.count == 16 && bodyPose1.count == 16, "guard pose joint count")
            check(headPose.count == 16 && weaponPose.count == 7, "head/weapon pose joint count")
            check(bodyPose0 != bodyPose1, "walk clip produces distinct poses")
            check(root0.descriptorHash == root1.descriptorHash && root0.scaleQ16 == 12_307, "root motion descriptor provenance")
            check(root0.translationQ16 != root1.translationQ16 || root0.headingQ16 != root1.headingQ16, "root motion frame progression")
            check(sidecar.attachment.weaponParentSwitch == 3, "dynamic weapon parent")
            check(sidecar.attachment.muzzleFlashSwitch == 0 && sidecar.attachment.muzzleLightSwitch == 2, "dynamic muzzle switches")
            check(sidecar.bloodEncoded.count == 2_524, "guarded blood payload")
            let guardedBlood = try GoldenEyeGunbarrelBloodDecoderV6.decodeInitial(sidecar.bloodEncoded)
            check(guardedBlood.pixels.count == 96 * 80, "guarded blood decode")
            var poseRuntime = GoldenEyeGunbarrelRuntimeV6(
                manifest: first,
                dynamicSidecar: sidecar
            )
            let poseFrame = try poseRuntime.step(nativeTick: 1)
            check(poseFrame.poses.count == 32, "immutable body/head pose packet")
            check(poseFrame.poses.contains {
                $0.modelHandle == 8 && $0.jointIndex == 0 && $0.animationTick == 2
            }, "walk animation starts at source frame 2")
            check(poseFrame.poses.contains { $0.modelHandle == 8 && $0.jointIndex == 0 }, "body root pose")
            check(poseFrame.poses.contains { $0.modelHandle == 7 && $0.jointIndex == 0 }, "head root pose")
            print("gunbarrel_dynamic_resolver=PASS")
            print("gunbarrel_root_motion=PASS frame0=\(root0.translationQ16.x),\(root0.translationQ16.y),\(root0.translationQ16.z),heading=\(root0.headingQ16) frame1=\(root1.translationQ16.x),\(root1.translationQ16.y),\(root1.translationQ16.z),heading=\(root1.headingQ16)")
            print("gunbarrel_pose_counts=body:\(bodyPose0.count),head:\(headPose.count),weaponSynthetic:0")
            print("gunbarrel_sidecar_sha256=\(sidecar.packetSHA256)")
        }
        print("gunbarrel_manifest_hash=\(first.manifestHash)")
        print("gunbarrel_manifest_models=\(first.models.count)")
        print("gunbarrel_modes=\(routeModes.sorted().map(String.init).joined(separator: ","))")
        print("gunbarrel_complete_modes=\(completeModes.sorted().map(String.init).joined(separator: ","))")
        print("gunbarrel_capture_ready=\(first.captureReady ? 1 : 0)")
        print("goldeneye_gunbarrel_v6_smoke: PASS")
    }
}
