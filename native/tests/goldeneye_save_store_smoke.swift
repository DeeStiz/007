import Foundation

@main
struct GoldenEyeSaveStoreSmoke {
    static func main() async throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("goldeneye-save-smoke-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: directory) }

        var state = GoldenEyeSaveState.blank
        let blankFixture = try GoldenEyeSaveCodec.encode(state)
        precondition(blankFixture.count == GoldenEyeSaveCodec.fileByteCount)
        let roundTrip = try GoldenEyeSaveCodec.decode(blankFixture)
        precondition(roundTrip == state)

        try GoldenEyeSaveActions.createFolder(&state, at: 1)
        state.folders[1].setStageTimeByte(0, value: 1)
        state.folders[1].flag007 = 1
        state.folders[1].options = 0x003a
        state.folders[1].checksum1 = -1
        let fixture = try GoldenEyeSaveCodec.encode(state)
        precondition(fixture.count == 596)
        let fixtureRoundTrip = try GoldenEyeSaveCodec.decode(fixture)
        precondition(fixtureRoundTrip == state)
        let copiedDestination = try GoldenEyeSaveActions.copyFolderToFirstBlank(&state, from: 1)
        precondition(copiedDestination == 0)
        precondition(state.folders[0].isUsable)

        let firstStore = GoldenEyeSaveStore(directoryURL: directory)
        let saved = try await firstStore.save(state)
        precondition(saved.generation == 1)
        let secondStore = GoldenEyeSaveStore(directoryURL: directory)
        let loaded = try await secondStore.load()
        precondition(loaded.source == .primary)
        precondition(loaded.state == saved)

        var secondState = saved
        try GoldenEyeSaveActions.createFolder(&secondState, at: 2)
        _ = try await secondStore.save(secondState)
        var corrupted = Array(try Data(contentsOf: secondStore.primaryURL))
        corrupted[100] ^= 0x01
        try Data(corrupted).write(to: secondStore.primaryURL, options: .atomic)

        let recoveryStore = GoldenEyeSaveStore(directoryURL: directory)
        let recovered = try await recoveryStore.load()
        precondition(recovered.source == .backup)
        precondition(recovered.recovered)
        precondition(recovered.quarantinedPath != nil)
        precondition(recovered.state == saved)

        let unknownURL = directory.appendingPathComponent("unknown.gesave")
        var unknown = try GoldenEyeSaveCodec.encode(saved)
        unknown[8] = 0
        unknown[9] = 2
        try Data(unknown).write(to: unknownURL, options: .atomic)
        let unknownStore = GoldenEyeSaveStore(directoryURL: directory.appendingPathComponent("unknown", isDirectory: true))
        try fileManager.createDirectory(at: unknownStore.directoryURL, withIntermediateDirectories: true)
        try fileManager.moveItem(at: unknownURL, to: unknownStore.primaryURL)
        let unknownResult = try await unknownStore.load()
        precondition(!unknownResult.persistenceEnabled)
        do {
            _ = try await unknownStore.save(saved)
            preconditionFailure("unknown schema save unexpectedly succeeded")
        } catch GoldenEyeSaveCodecError.persistenceDisabled {
        }

        print("goldeneye_save_store_smoke: PASS")
    }
}
