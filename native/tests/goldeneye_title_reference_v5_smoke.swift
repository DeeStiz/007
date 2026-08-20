import Foundation

@main
struct GoldenEyeTitleReferenceV5Smoke {
    static func main() {
        var flow = GoldenEyeBootFlow(
            ramRomCatalog: fixtureCatalog(),
            randomSeed: 1
        )
        precondition(flow.requestRamRomDemo(catalogIndex: 0))
        var reference = ge_title_reference_initial_v5()
        var previousScreen = flow.screen
        var comparedAnchors = 0

        for _ in 0..<20000 {
            let snapshot = flow.step()
            guard snapshot.pairPhase == 0 else { continue }

            reference = ge_title_reference_step_v5(reference)
            comparedAnchors += 1

            if snapshot.screen.rawValue != reference.screen {
                print("screen mismatch at native tick \(snapshot.nativeTick): swift=\(snapshot.screen.rawValue) c=\(reference.screen)")
                Foundation.exit(1)
            }
            if snapshot.screen != .gunbarrel && snapshot.screen != .goldenEye && snapshot.timer120 != reference.timer * 2 {
                print("timer mismatch at native tick \(snapshot.nativeTick): swift=\(snapshot.timer120) c=\(reference.timer * 2)")
                Foundation.exit(1)
            }
            if snapshot.screen == .cast,
               reference.screen == UInt32(GE_TITLE_SCREEN_CAST),
               reference.transition_remaining == 0,
               snapshot.timer120 == reference.timer * 2,
               snapshot.subphase != reference.selection {
                print("cast subphase mismatch at native tick \(snapshot.nativeTick): swift=\(snapshot.subphase) c=\(reference.selection)")
                Foundation.exit(1)
            }
            if snapshot.screen == .ramrom {
                let expectedDemoID = reference.demo_index + 1
                if snapshot.subphase != expectedDemoID || snapshot.demoIndex != reference.demo_index {
                    print("RAMROM identity mismatch at native tick \(snapshot.nativeTick): swift demo=\(snapshot.demoIndex)/subphase=\(snapshot.subphase) c demo=\(reference.demo_index)")
                    Foundation.exit(1)
                }
            }

            if snapshot.screen != previousScreen {
                print("title_reference transition native=\(snapshot.nativeTick) reference=\(reference.reference_tick) screen=\(snapshot.screen.rawValue)")
                previousScreen = snapshot.screen
            }
        }

        precondition(comparedAnchors == 10000)
        print("goldeneye_title_reference_v5_smoke: PASS anchors=\(comparedAnchors) cast-ramrom=verified unsupported=gunbarrel_dynamics,goldeneye_odd_timer,render_hash")
    }

    private static func fixtureCatalog() -> GoldenEyeRamRomRouteCatalog {
        let entries = (0..<14).map { index in
            let catalogIndex = UInt8(index)
            let demoID = UInt8(index + 1)
            let stageID = UInt32(index + 1)
            let variant = UInt32(index)
            let recordingHash = UInt64(0x1000) + UInt64(index)
            let rngHash = UInt64(0x2000) + UInt64(index)
            let assetName = String("fixture-ramrom-\(index).bin")
            return GoldenEyeRamRomDemoRoute(
                catalogIndex: catalogIndex,
                demoID: demoID,
                stageID: stageID,
                variant: variant,
                controllerCount: 1,
                totalTime60: 600,
                declaredFileBytes: 128,
                assetFileBytes: 128,
                packetCount: 4,
                recordCount: 4,
                recordingHash: recordingHash,
                rngHash: rngHash,
                assetName: assetName
            )
        }
        var hashWords: [UInt64] = []
        for entry in entries {
            hashWords.append(contentsOf: [
                UInt64(entry.catalogIndex), UInt64(entry.demoID), UInt64(entry.stageID),
                UInt64(entry.variant), UInt64(entry.controllerCount),
                UInt64(entry.totalTime60), UInt64(entry.packetCount),
                UInt64(entry.recordCount), entry.recordingHash, entry.rngHash,
            ])
        }
        return GoldenEyeRamRomRouteCatalog(
            entries: entries,
            catalogHash: GoldenEyeTitleHash.fnv1a(hashWords),
            failure: nil
        )
    }
}
