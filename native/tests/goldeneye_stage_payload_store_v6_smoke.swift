import Foundation

@main
struct GoldenEyeStagePayloadStoreV6Smoke {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw Failure("usage: goldeneye_stage_payload_store_v6_smoke /absolute/stage-root")
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let catalog = try GoldenEyeStageAssetCatalog.load(stageAssetRoot: root)
        var store = try GoldenEyeStagePayloadStoreV6(catalog: catalog)
        precondition(store.stageIDs == catalog.stages.map(\.stageID).sorted())
        precondition(store.activeStageID == nil)

        do {
            _ = try store.read(stageID: 33, kind: .background, offset: 0, count: 1)
            throw Failure("unloaded payload read unexpectedly succeeded")
        } catch GoldenEyeStagePayloadStoreErrorV6.stageNotLoaded(33) {
            // expected
        }

        let firstStage = store.stageIDs[0]
        let secondStage = store.stageIDs[1]
        let firstLoaded = try store.load(stageID: firstStage)
        precondition(firstLoaded.loaded && !firstLoaded.active)
        precondition(firstLoaded.resourceCount == 3)
        let firstActive = try store.activate(stageID: firstStage)
        precondition(firstActive.active && store.activeStageID == firstStage)

        let firstResources = catalog.stages.first { $0.stageID == firstStage }!.resources
        var aggregate = UInt64(1_469_598_103_934_665_603)
        for resource in firstResources {
            let entire = try store.read(
                stageID: firstStage,
                kind: resource.kind,
                offset: 0,
                count: resource.decodedBytes
            )
            precondition(entire.bytes.count == Int(resource.decodedBytes))
            precondition(entire.assetHandle == resource.assetHandle)
            precondition(entire.decodedHash == resource.decodedSHA256)
            aggregate = mix(aggregate, UInt64(entire.bytes.count))
            aggregate = mix(aggregate, UInt64(resource.assetHandle))
            for byte in entire.bytes.prefix(64) {
                aggregate = mix(aggregate, UInt64(byte))
            }

            let prefix = try store.read(
                stageID: firstStage,
                kind: resource.kind,
                offset: 0,
                count: min(64, resource.decodedBytes)
            )
            precondition(prefix.bytes == Data(entire.bytes.prefix(prefix.bytes.count)))
        }

        do {
            _ = try store.read(stageID: firstStage, kind: .background, offset: UInt32.max, count: 1)
            throw Failure("overflowing payload range unexpectedly succeeded")
        } catch GoldenEyeStagePayloadStoreErrorV6.invalidRange {
            // expected
        }
        do {
            _ = try store.read(
                stageID: firstStage,
                kind: .background,
                offset: 0,
                count: GoldenEyeStagePayloadStoreV6.defaultMaxReadBytes + 1
            )
            throw Failure("oversized payload read unexpectedly succeeded")
        } catch GoldenEyeStagePayloadStoreErrorV6.oversizedRead {
            // expected
        }
        do {
            _ = try store.activate(stageID: secondStage)
            throw Failure("active-stage replacement unexpectedly succeeded")
        } catch GoldenEyeStagePayloadStoreErrorV6.invalidTransition {
            // expected
        }
        do {
            _ = try store.unload(stageID: firstStage)
            throw Failure("active-stage unload unexpectedly succeeded")
        } catch GoldenEyeStagePayloadStoreErrorV6.invalidTransition {
            // expected
        }

        _ = try store.deactivate(stageID: firstStage)
        let firstUnloaded = try store.unload(stageID: firstStage)
        precondition(!firstUnloaded.loaded && !firstUnloaded.active)
        let secondActive = try store.activate(stageID: secondStage)
        precondition(secondActive.active && secondActive.loaded)
        _ = try store.deactivate(stageID: secondStage)
        try store.reset()
        precondition(store.activeStageID == nil)
        for stageID in store.stageIDs {
            let snapshot = try store.snapshot(stageID: stageID)
            precondition(!snapshot.loaded && !snapshot.active)
        }

        var allStagesStore = try GoldenEyeStagePayloadStoreV6(catalog: catalog)
        var allStageAggregate = UInt64(1_469_598_103_934_665_603)
        for stage in catalog.stages.sorted(by: { $0.stageID < $1.stageID }) {
            let active = try allStagesStore.activate(stageID: stage.stageID)
            precondition(active.loaded && active.active && active.resourceCount == 3)
            for resource in stage.resources {
                let read = try allStagesStore.read(
                    stageID: stage.stageID,
                    kind: resource.kind,
                    offset: 0,
                    count: resource.decodedBytes
                )
                precondition(read.bytes.count == Int(resource.decodedBytes))
                precondition(read.decodedHash == resource.decodedSHA256)
                allStageAggregate = mix(allStageAggregate, UInt64(stage.stageID))
                allStageAggregate = mix(allStageAggregate, UInt64(read.bytes.count))
                for byte in read.bytes.prefix(32) {
                    allStageAggregate = mix(allStageAggregate, UInt64(byte))
                }
            }
            _ = try allStagesStore.deactivate(stageID: stage.stageID)
            _ = try allStagesStore.unload(stageID: stage.stageID)
        }
        precondition(allStagesStore.activeStageID == nil)

        var replay = try GoldenEyeStagePayloadStoreV6(catalog: catalog)
        let replayLoaded = try replay.activate(stageID: firstStage)
        precondition(replayLoaded.decodedHash == firstLoaded.decodedHash)
        let replayPrefix = try replay.read(
            stageID: firstStage,
            kind: firstResources[0].kind,
            offset: 0,
            count: min(64, firstResources[0].decodedBytes)
        )
        let expectedPrefix = try storeReadFromCatalog(firstResources[0])
        precondition(replayPrefix.bytes == expectedPrefix)
        print(
            "goldeneye_stage_payload_store_v6_smoke: PASS stages=\(store.stageIDs.count) "
                + "resources=3 aggregate=\(aggregate) allStageAggregate=\(allStageAggregate) "
                + "singleActive=1 rangeGuard=1 digestGuard=1 reset=1"
        )
    }

    private static func storeReadFromCatalog(_ resource: GoldenEyeStageAssetResource) throws -> Data {
        try Data(contentsOf: resource.decodedURL, options: [.mappedIfSafe])
            .prefix(min(64, Int(resource.decodedBytes)))
            .withUnsafeBytes { Data($0) }
    }

    private static func mix(_ hash: UInt64, _ value: UInt64) -> UInt64 {
        var result = hash
        var word = value
        for _ in 0..<8 {
            result ^= word & 0xff
            result &*= 1_099_511_628_211
            word >>= 8
        }
        return result == 0 ? 1 : result
    }

    private struct Failure: Error, CustomStringConvertible {
        let message: String
        init(_ message: String) { self.message = message }
        var description: String { message }
    }
}
