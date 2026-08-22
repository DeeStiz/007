import Foundation

@main
struct GoldenEyeStageTransferQueueV6Smoke {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fputs("usage: goldeneye_stage_transfer_queue_v6_smoke <stage-asset-root>\n", stderr)
            exit(2)
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let catalog = try GoldenEyeStageAssetCatalog.load(stageAssetRoot: root)
        let index = try GoldenEyeStageFileIndexV6(catalog: catalog)
        let repeatedIndex = try GoldenEyeStageFileIndexV6(catalog: catalog)
        precondition(index == repeatedIndex, "file-index must be deterministic")
        precondition(index.entries.count == 21, "expected 21 source file-index rows")

        // The public value initializer must not bypass the C source catalog
        // contract. A stage-label drift is rejected before a queue exists.
        var tamperedStages = catalog.stages
        let firstStage = tamperedStages[0]
        tamperedStages[0] = GoldenEyeStageAssetStage(
            stageID: firstStage.stageID,
            stageName: "Tampered",
            demoMask: firstStage.demoMask,
            resources: firstStage.resources
        )
        let tamperedCatalog = GoldenEyeStageAssetCatalog(
            rootURL: catalog.rootURL,
            manifestURL: catalog.manifestURL,
            stages: tamperedStages,
            bootstrapReport: catalog.bootstrapReport
        )
        do {
            _ = try GoldenEyeStageFileIndexV6(catalog: tamperedCatalog)
            preconditionFailure("source catalog drift must fail closed")
        } catch let error as GoldenEyeStageFileIndexErrorV6 {
            if case .sourceCatalogMismatch = error {} else {
                preconditionFailure("unexpected source parity error: \(error)")
            }
        }

        for stage in catalog.stages {
            let stageEntryCount = index.entries.filter { entry in
                entry.stageID == stage.stageID
            }.count
            precondition(stageEntryCount == 3)
            for kind in GoldenEyeStageAssetKind.allCases {
                let entry = index.entry(stageID: stage.stageID, kind: kind)
                precondition(entry?.assetHandle != 0)
                precondition(entry?.decodedBytes ?? 0 > 0)
            }
        }

        var queue = try GoldenEyeStageTransferQueueV6(
            catalog: catalog,
            maxPending: 2,
            maxChunkBytes: 4_096
        )
        let stages = catalog.stages.sorted { $0.stageID < $1.stageID }
        let first = stages[0]
        let second = stages[1]
        let background = try requireEntry(index, stageID: first.stageID, kind: .background)
        let setup = try requireEntry(index, stageID: first.stageID, kind: .setup)

        do {
            _ = try queue.submit(
                stageID: first.stageID,
                kind: .background,
                decodedOffset: 0,
                byteCount: 4
            )
            preconditionFailure("submit without an active stage must fail")
        } catch let error as GoldenEyeStageTransferQueueErrorV6 {
            precondition(error == .noActiveStage)
        }

        _ = try queue.activate(stageID: first.stageID)
        let requestA = try queue.submit(
            stageID: first.stageID,
            kind: .background,
            decodedOffset: 0,
            byteCount: 32
        )
        do {
            _ = try queue.submit(
                stageID: second.stageID,
                kind: .background,
                decodedOffset: 0,
                byteCount: 4
            )
            preconditionFailure("cross-stage transfer must fail closed")
        } catch let error as GoldenEyeStageTransferQueueErrorV6 {
            if case .activeStageMismatch = error {} else { preconditionFailure("unexpected stage error: \(error)") }
        }
        do {
            _ = try queue.submit(
                stageID: first.stageID,
                kind: .background,
                decodedOffset: background.decodedBytes - 2,
                byteCount: 4
            )
            preconditionFailure("out-of-range transfer must fail closed")
        } catch let error as GoldenEyeStageTransferQueueErrorV6 {
            if case .invalidRange = error {} else { preconditionFailure("unexpected range error: \(error)") }
        }
        let requestB = try queue.submit(
            stageID: first.stageID,
            kind: .setup,
            decodedOffset: 4,
            byteCount: 24
        )
        precondition(requestA.requestID == 1 && requestB.requestID == 2)
        do {
            _ = try queue.submit(
                stageID: first.stageID,
                kind: .stan,
                decodedOffset: 0,
                byteCount: 4
            )
            preconditionFailure("queue capacity must be bounded")
        } catch let error as GoldenEyeStageTransferQueueErrorV6 {
            if case .queueFull = error {} else { preconditionFailure("unexpected queue error: \(error)") }
        }

        let completions = try queue.drain()
        precondition(completions.count == 2)
        precondition(completions[0].request.requestID == requestA.requestID)
        precondition(completions[1].request.requestID == requestB.requestID)
        precondition(completions[0].bytes.count == 32)
        precondition(completions[1].bytes.count == 24)
        precondition(completions[0].decodedSHA256 == background.decodedSHA256)
        precondition(completions[1].decodedSHA256 == setup.decodedSHA256)
        do {
            _ = try queue.complete(requestID: requestA.requestID)
            preconditionFailure("completed request must not be replayed")
        } catch let error as GoldenEyeStageTransferQueueErrorV6 {
            precondition(error == .duplicateRequest(requestA.requestID))
        }

        do {
            try queue.deactivate(stageID: first.stageID)
            try queue.unload(stageID: first.stageID)
            _ = try queue.activate(stageID: second.stageID)
            let requestC = try queue.submit(
                stageID: second.stageID,
                kind: .background,
                decodedOffset: 0,
                byteCount: 16
            )
            let completionC = try queue.complete(requestID: requestC.requestID)
            precondition(completionC.bytes.count == 16)
            try queue.deactivate(stageID: second.stageID)
            try queue.unload(stageID: second.stageID)
            try queue.reset()
        } catch {
            preconditionFailure("stage replacement/reset failed: \(error)")
        }

        let snapshot = queue.snapshot
        precondition(snapshot.activeStageID == nil)
        precondition(snapshot.pendingCount == 0)
        precondition(snapshot.completedCount == 3)
        precondition(snapshot.transferHash != 0)
        let summary = "goldeneye_stage_transfer_queue_v6_smoke: PASS " +
            "stages=\(stages.count) entries=\(index.entries.count) " +
            "fileIndexHash=\(index.indexHash) requests=\(snapshot.completedCount) " +
            "transferHash=\(snapshot.transferHash) " +
            "singleActive=1 rangeGuard=1 queueGuard=1 reset=1 sourceParity=1"
        print(summary)
    }

    private static func requireEntry(
        _ index: GoldenEyeStageFileIndexV6,
        stageID: UInt32,
        kind: GoldenEyeStageAssetKind
    ) throws -> GoldenEyeStageFileIndexEntryV6 {
        guard let entry = index.entry(stageID: stageID, kind: kind) else {
            throw GoldenEyeStageFileIndexErrorV6.missingResource(stageID, kind)
        }
        return entry
    }
}
