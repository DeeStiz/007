import Foundation

@main
struct GoldenEyeSaveRuntimeSmoke {
    static func main() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("goldeneye-save-runtime-\(UUID().uuidString)", isDirectory: true)
        let diagnostics = root.appendingPathComponent("diagnostics.log")
        defer { try? fileManager.removeItem(at: root) }

        let store = GoldenEyeSaveStore(directoryURL: root.appendingPathComponent("Saves", isDirectory: true))
        let runtime = GoldenEyeSaveRuntime(store: store, diagnosticsURL: diagnostics)
        runtime.start()
        let loaded = try await waitFor(runtime) { snapshot in
            snapshot.state != nil && snapshot.status != .loading
        }
        precondition(loaded.persistenceEnabled)
        precondition(loaded.sourceStatusIsDefaults)

        var changed = loaded.state!
        try GoldenEyeSaveActions.createFolder(&changed, at: 1)
        runtime.submit(state: changed)
        let saved = try await waitFor(runtime) { snapshot in
            snapshot.state?.generation == 1 && snapshot.state?.folders[1].isUsable == true
        }
        precondition(saved.status == .ready)
        let persisted = try GoldenEyeSaveCodec.decode(
            Array(Data(contentsOf: store.primaryURL))
        )
        precondition(persisted == saved.state)

        let unknownRoot = root.appendingPathComponent("Unknown", isDirectory: true)
        let unknownStore = GoldenEyeSaveStore(directoryURL: unknownRoot)
        _ = try await unknownStore.save(changed)
        var unknownBytes = Array(try Data(contentsOf: unknownStore.primaryURL))
        unknownBytes[8] = 0
        unknownBytes[9] = 2
        try Data(unknownBytes).write(to: unknownStore.primaryURL, options: .atomic)
        let unknownDiagnostics = root.appendingPathComponent("unknown.log")
        let unknownRuntime = GoldenEyeSaveRuntime(store: unknownStore, diagnosticsURL: unknownDiagnostics)
        unknownRuntime.start()
        let disabled = try await waitFor(unknownRuntime) { snapshot in
            snapshot.status == .disabledUnknownSchema
        }
        precondition(!disabled.persistenceEnabled)
        unknownRuntime.submit(state: GoldenEyeSaveState.blank)
        try await Task.sleep(nanoseconds: 20_000_000)
        let unchangedUnknownBytes = Array(try Data(contentsOf: unknownStore.primaryURL))
        precondition(unchangedUnknownBytes == unknownBytes)

        let diagnosticText = try String(contentsOf: diagnostics, encoding: .utf8)
        precondition(diagnosticText.contains("status="))
        print("goldeneye_save_runtime_smoke: PASS")
    }

    private static func waitFor(
        _ runtime: GoldenEyeSaveRuntime,
        predicate: @Sendable (GoldenEyeSaveRuntimeSnapshot) -> Bool
    ) async throws -> GoldenEyeSaveRuntimeSnapshot {
        for _ in 0..<500 {
            let snapshot = runtime.snapshot()
            if predicate(snapshot) {
                return snapshot
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw NSError(domain: "GoldenEyeSaveRuntimeSmoke", code: 1)
    }
}

private extension GoldenEyeSaveRuntimeSnapshot {
    var sourceStatusIsDefaults: Bool {
        status == .defaults || status == .ready
    }
}
