import Foundation

@main
struct GoldenEyeCastSceneComposerV6Smoke {
    static func main() throws {
        guard CommandLine.arguments.count >= 2 else {
            fatalError("usage: goldeneye_cast_scene_composer_v6_smoke /absolute/source-frontend-root")
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(".gesm") }
            .map { String($0.dropLast(5)) }
            .sorted()
        precondition(names.count >= 75, "extended cast model root")
        var handles: [String: UInt32] = [:]
        for name in names {
            let model = try GoldenEyeSourceModelV6.load(
                from: root.appendingPathComponent("\(name).gesm")
            )
            handles[name] = model.header.modelHandle
            precondition(model.header.modelHandle != 0, "nonzero \(name) handle")
        }
        let identity = try GoldenEyeCastSourceTableV6.identity(sourceIndex: 1)
        let animation = try GoldenEyeCastSceneComposerV6.animation(for: identity)
        precondition(animation.animationID == 66)
        let binding = try GoldenEyeCastSceneComposerV6.resolveModels(
            identity: identity,
            animation: animation,
            availableModelNames: Set(names),
            availableHandles: handles
        )
        precondition(binding.bodyName == "boilerbond")
        precondition(binding.headName == "headbrosnanboiler")
        precondition(binding.weaponName == "chrwppk")

        // Source front.c consumes a second random word for identity row 2:
        // even selects Natalya's embedded body, while odd selects the
        // source-prepared Spicebond alternate. Keep this authority separate
        // from the identity row and prove both branches against the same
        // prepared model catalog.
        let row2 = try GoldenEyeCastSourceTableV6.identity(sourceIndex: 2)
        let row2Animation = try GoldenEyeCastSceneComposerV6.animation(for: row2)
        let evenRow2 = try GoldenEyeCastSceneComposerV6.resolveModels(
            identity: row2,
            animation: row2Animation,
            availableModelNames: Set(names),
            availableHandles: handles,
            randomWord: 2
        )
        let oddRow2 = try GoldenEyeCastSceneComposerV6.resolveModels(
            identity: row2,
            animation: row2Animation,
            availableModelNames: Set(names),
            availableHandles: handles,
            randomWord: 3
        )
        precondition(evenRow2.bodyName == "natalya")
        precondition(oddRow2.bodyName == "spicebond")
        precondition(evenRow2.headName.isEmpty && oddRow2.headName.isEmpty)
        let bodyGroups = try GoldenEyeCastSkeletonTransformV6.groups(
            model: try GoldenEyeSourceModelV6.load(
                from: root.appendingPathComponent("boilerbond.gesm")
            )
        )
        precondition(!bodyGroups.isEmpty, "source body GroupRecords")
        precondition(
            bodyGroups.flatMap(\.matrixIDs).allSatisfy { $0 != 0xFFFF },
            "GroupRecord null MatrixIDs are not renderable handles"
        )

        let overlay = try GoldenEyeCastSceneComposerV6.textFadePacket(
            identity: identity,
            fadeQ16: 32_768,
            fullActorIntro: false
        )
        precondition(overlay.sourceTextHashes == [
            identity.text1SourceID, identity.text2SourceID, identity.text3SourceID
        ])
        precondition(overlay.visibleTextHashes.count == 3)
        precondition(overlay.source2DFullActorIntro)
        precondition(overlay.fadeAlphaQ8 == 128)
        precondition(overlay.fadeOverlayRequired)
        precondition(overlay.textYQ16 == [108 << 16, 152 << 16, 174 << 16])
        precondition(overlay.colorRGBA & 0xFF == 128)

        var resolved = 0
        var missing = 0
        var missingDetails: [String] = []
        for sourceIndex in GoldenEyeCastSceneComposerV6.validIdentityIndices {
            let row = try GoldenEyeCastSourceTableV6.identity(sourceIndex: sourceIndex)
            do {
                let rowAnimation = try GoldenEyeCastSceneComposerV6.animation(randomWord: UInt32(sourceIndex))
                _ = try GoldenEyeCastSceneComposerV6.resolveModels(
                    identity: row,
                    animation: rowAnimation,
                    availableModelNames: Set(names),
                    availableHandles: handles,
                    randomWord: UInt32(sourceIndex)
                )
                resolved += 1
            } catch GoldenEyeCastSceneComposerV6Error.missingModel {
                missing += 1
                missingDetails.append("\(sourceIndex):model")
            } catch GoldenEyeCastSceneComposerV6Error.missingAnimation {
                missing += 1
                missingDetails.append("\(sourceIndex):animation")
            } catch GoldenEyeCastSceneComposerV6Error.missingWeapon {
                missing += 1
                missingDetails.append("\(sourceIndex):weapon")
            }
        }
        guard resolved == 30 && missing == 0 else {
            fatalError("cast roster resolution resolved=\(resolved) missing=\(missing) details=\(missingDetails)")
        }

        var selected: Set<UInt16> = []
        for randomWord in UInt32(0)..<UInt32(30) {
            selected.insert(
                try GoldenEyeCastSceneComposerV6.selectIdentity(randomWord: randomWord).sourceIndex
            )
        }
        precondition(selected.count == 30, "bounded source random selection")
        var camera = GoldenEyeCastCameraStateV6()
        let cameraFrame = camera.update(
            suboffset: SIMD3<Float>(0.1, 10.0, 0.2),
            transformedVelocity: SIMD3<Float>(0.11, 10.0, 0.22),
            clockTimer: 1,
            globalTimerDelta: 1
        )
        precondition(abs(cameraFrame.rootOffset.y - 10.0) < 0.001, "cast root reset")
        precondition(abs(cameraFrame.targetOffset.y) < 0.001, "cast target offset")
        precondition(camera.reset == false, "cast camera reset consumed")
        do {
            _ = try GoldenEyeCastSourceTableV6.identity(sourceIndex: 30)
            preconditionFailure("sentinel row was selected")
        } catch GoldenEyeCastSceneV6Error.invalidSourceIndex {
            // expected source sentinel rejection
        }
        print(
            "goldeneye_cast_scene_composer_v6_smoke: PASS identities=30 "
                + "animations=22 preparedModelCombinations=30 missingClosed=0"
                + " castTextFade=PASS row2RandomBody=natalya/spicebond"
        )
    }
}
