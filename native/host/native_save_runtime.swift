import Foundation

public enum GoldenEyeSaveRuntimeStatus: UInt8, Sendable, Equatable {
    case idle = 0
    case loading = 1
    case ready = 2
    case recoveredBackup = 3
    case defaults = 4
    case disabledUnknownSchema = 5
    case failed = 6
    case stopped = 7
}

public struct GoldenEyeSaveRuntimeSnapshot: Sendable, Equatable {
    public let status: GoldenEyeSaveRuntimeStatus
    public let state: GoldenEyeSaveState?
    public let persistenceEnabled: Bool
    public let message: String
    public let quarantinedPath: String?
    public let revision: UInt64

    public init(
        status: GoldenEyeSaveRuntimeStatus,
        state: GoldenEyeSaveState?,
        persistenceEnabled: Bool,
        message: String,
        quarantinedPath: String?,
        revision: UInt64
    ) {
        self.status = status
        self.state = state
        self.persistenceEnabled = persistenceEnabled
        self.message = message
        self.quarantinedPath = quarantinedPath
        self.revision = revision
    }
}

/// Bridges the owner thread to the actor-isolated store. Filesystem I/O runs
/// in detached tasks; the owner only performs short lock-protected operations.
public final class GoldenEyeSaveRuntime: @unchecked Sendable {
    private let store: GoldenEyeSaveStore
    private let diagnosticsURL: URL?
    private let lock = NSLock()
    private var status: GoldenEyeSaveRuntimeStatus = .idle
    private var state: GoldenEyeSaveState?
    private var persistenceEnabled = true
    private var message = "not started"
    private var quarantinedPath: String?
    private var revision: UInt64 = 0
    private var started = false
    private var stopped = false
    private var writeInFlight = false
    private var pendingState: GoldenEyeSaveState?
    private var loadTask: Task<Void, Never>?
    private var writeTask: Task<Void, Never>?

    public init(
        store: GoldenEyeSaveStore = GoldenEyeSaveStore(),
        diagnosticsURL: URL? = URL(fileURLWithPath: "/tmp/goldeneye-save-runtime.log")
    ) {
        self.store = store
        self.diagnosticsURL = diagnosticsURL
    }

    deinit {
        loadTask?.cancel()
        writeTask?.cancel()
    }

    public func start() {
        lock.lock()
        guard !started, !stopped else {
            lock.unlock()
            return
        }
        started = true
        status = .loading
        message = "loading"
        revision &+= 1
        let store = self.store
        let diagnosticsURL = self.diagnosticsURL
        let revision = self.revision
        lock.unlock()
        Self.appendDiagnostic("status=loading revision=\(revision)", to: diagnosticsURL)

        loadTask = Task.detached(priority: .userInitiated) { [weak self, store] in
            do {
                let result = try await store.load()
                self?.finishLoad(result)
            } catch {
                self?.finishLoad(error: error)
            }
        }
    }

    public func stop() {
        lock.lock()
        guard !stopped else {
            lock.unlock()
            return
        }
        stopped = true
        status = .stopped
        message = "stopped"
        revision &+= 1
        let diagnosticsURL = self.diagnosticsURL
        let revision = self.revision
        lock.unlock()
        loadTask?.cancel()
        writeTask?.cancel()
        Self.appendDiagnostic("status=stopped revision=\(revision)", to: diagnosticsURL)
    }

    public func snapshot() -> GoldenEyeSaveRuntimeSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return GoldenEyeSaveRuntimeSnapshot(
            status: status,
            state: state,
            persistenceEnabled: persistenceEnabled,
            message: message,
            quarantinedPath: quarantinedPath,
            revision: revision
        )
    }

    public func submit(state nextState: GoldenEyeSaveState) {
        lock.lock()
        guard started, !stopped, status != .loading, persistenceEnabled else {
            lock.unlock()
            return
        }
        if let state, semanticallyEqual(state, nextState), pendingState == nil, !writeInFlight {
            lock.unlock()
            return
        }
        if let pendingState, semanticallyEqual(pendingState, nextState) {
            lock.unlock()
            return
        }
        pendingState = nextState
        let shouldStartWrite = !writeInFlight
        lock.unlock()
        if shouldStartWrite {
            startNextWriteIfNeeded()
        }
    }

    private func finishLoad(_ result: GoldenEyeSaveLoadResult) {
        lock.lock()
        guard !stopped else {
            lock.unlock()
            return
        }
        state = result.state
        persistenceEnabled = result.persistenceEnabled
        quarantinedPath = result.quarantinedPath
        switch (result.source, result.persistenceEnabled) {
        case (.primary, true):
            status = .ready
            message = "loaded primary generation=\(result.state.generation)"
        case (.backup, true):
            status = .recoveredBackup
            message = "recovered backup generation=\(result.state.generation)"
        case (.defaults, true):
            status = .defaults
            message = "using blank defaults"
        case (.defaults, false), (.primary, false), (.backup, false):
            status = .disabledUnknownSchema
            message = "persistence disabled: unknown newer schema"
        }
        revision &+= 1
        let snapshot = GoldenEyeSaveRuntimeSnapshot(
            status: status,
            state: state,
            persistenceEnabled: persistenceEnabled,
            message: message,
            quarantinedPath: quarantinedPath,
            revision: revision
        )
        let diagnosticsURL = self.diagnosticsURL
        lock.unlock()
        Self.appendDiagnostic(Self.diagnosticLine(snapshot), to: diagnosticsURL)
    }

    private func finishLoad(error: Error) {
        lock.lock()
        guard !stopped else {
            lock.unlock()
            return
        }
        state = nil
        persistenceEnabled = false
        status = .failed
        message = "load failed: \(error)"
        revision &+= 1
        let snapshot = GoldenEyeSaveRuntimeSnapshot(
            status: status,
            state: nil,
            persistenceEnabled: false,
            message: message,
            quarantinedPath: nil,
            revision: revision
        )
        let diagnosticsURL = self.diagnosticsURL
        lock.unlock()
        Self.appendDiagnostic(Self.diagnosticLine(snapshot), to: diagnosticsURL)
    }

    private func startNextWriteIfNeeded() {
        lock.lock()
        guard !stopped, !writeInFlight, persistenceEnabled, let nextState = pendingState else {
            lock.unlock()
            return
        }
        pendingState = nil
        writeInFlight = true
        let store = self.store
        lock.unlock()

        writeTask = Task.detached(priority: .userInitiated) { [weak self, store] in
            do {
                let saved = try await store.save(nextState)
                self?.finishWrite(saved)
            } catch {
                self?.finishWrite(error: error, attemptedState: nextState)
            }
        }
    }

    private func finishWrite(_ saved: GoldenEyeSaveState) {
        lock.lock()
        guard !stopped else {
            lock.unlock()
            return
        }
        state = saved
        status = .ready
        persistenceEnabled = true
        message = "saved generation=\(saved.generation)"
        revision &+= 1
        writeInFlight = false
        let hasPending = pendingState != nil
        let snapshot = GoldenEyeSaveRuntimeSnapshot(
            status: status,
            state: state,
            persistenceEnabled: persistenceEnabled,
            message: message,
            quarantinedPath: quarantinedPath,
            revision: revision
        )
        let diagnosticsURL = self.diagnosticsURL
        lock.unlock()
        Self.appendDiagnostic(Self.diagnosticLine(snapshot), to: diagnosticsURL)
        if hasPending {
            startNextWriteIfNeeded()
        }
    }

    private func finishWrite(error: Error, attemptedState: GoldenEyeSaveState) {
        lock.lock()
        guard !stopped else {
            lock.unlock()
            return
        }
        writeInFlight = false
        status = .failed
        persistenceEnabled = false
        message = "save failed: \(error)"
        revision &+= 1
        let snapshot = GoldenEyeSaveRuntimeSnapshot(
            status: status,
            state: state ?? attemptedState,
            persistenceEnabled: false,
            message: message,
            quarantinedPath: quarantinedPath,
            revision: revision
        )
        pendingState = nil
        let diagnosticsURL = self.diagnosticsURL
        lock.unlock()
        Self.appendDiagnostic(Self.diagnosticLine(snapshot), to: diagnosticsURL)
    }

    private func semanticallyEqual(_ lhs: GoldenEyeSaveState, _ rhs: GoldenEyeSaveState) -> Bool {
        lhs.folders == rhs.folders
            && lhs.selectedFolder == rhs.selectedFolder
            && lhs.selectedBond == rhs.selectedBond
    }

    private static func diagnosticLine(_ snapshot: GoldenEyeSaveRuntimeSnapshot) -> String {
        let quarantine = snapshot.quarantinedPath ?? "-"
        return "status=\(snapshot.status.rawValue) persistence=\(snapshot.persistenceEnabled ? 1 : 0) generation=\(snapshot.state?.generation ?? 0) revision=\(snapshot.revision) message=\(snapshot.message) quarantine=\(quarantine)"
    }

    private static func appendDiagnostic(_ line: String, to url: URL?) {
        guard let url else { return }
        let data = Data((line + "\n").utf8)
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }
}
