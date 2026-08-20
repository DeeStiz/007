import Foundation
import CryptoKit
import Darwin

public enum GoldenEyeSaveCodecError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidLength(expected: Int, actual: Int)
    case invalidMagic
    case unsupportedVersion(UInt16)
    case invalidHeaderLength(UInt16)
    case invalidPayloadLength(UInt32)
    case invalidReservedBytes(offset: Int)
    case checksumMismatch
    case invalidFolder(index: Int)
    case invalidFolderCount(Int)
    case invalidSelection
    case generationOverflow
    case io(String)
    case persistenceDisabled

    public var description: String {
        switch self {
        case let .invalidLength(expected, actual): return "save length \(actual), expected \(expected)"
        case .invalidMagic: return "save magic mismatch"
        case let .unsupportedVersion(version): return "unsupported save version \(version)"
        case let .invalidHeaderLength(length): return "header length \(length), expected \(GoldenEyeSaveCodec.headerByteCount)"
        case let .invalidPayloadLength(length): return "payload length \(length), expected \(GoldenEyeSaveCodec.payloadByteCount)"
        case let .invalidReservedBytes(offset): return "nonzero reserved bytes at offset \(offset)"
        case .checksumMismatch: return "save payload SHA-256 mismatch"
        case let .invalidFolder(index): return "invalid folder \(index)"
        case let .invalidFolderCount(count): return "folder count \(count), expected \(GoldenEyeSaveState.folderCount)"
        case .invalidSelection: return "invalid selected folder or Bond"
        case .generationOverflow: return "save generation overflow"
        case let .io(message): return message
        case .persistenceDisabled: return "save persistence is disabled by an unknown schema"
        }
    }
}

/// The native semantic projection of the source `save_data` record.  The
/// first 94 bytes match its defined fields in big-endian wire order; the final
/// two bytes preserve the source struct's alignment padding and must be zero.
public struct GoldenEyeSaveFolder: Sendable, Equatable {
    public static let byteCount = 96
    public static let timesByteCount = 76

    private var storage: [UInt8]

    public init(bytes: [UInt8]) throws {
        guard bytes.count == Self.byteCount else {
            throw GoldenEyeSaveCodecError.invalidLength(expected: Self.byteCount, actual: bytes.count)
        }
        storage = bytes
    }

    public static func blank(folder: Int = 0) -> Self {
        var bytes = Array(repeating: UInt8(0), count: byteCount)
        let folderNumber = UInt8(max(0, min(folder, 3)))
        // BLANKSAVEDATA: Brosnan (0), reset flag set, default options,
        // music/SFX volume at the source's 0xff defaults.
        bytes[8] = 0x80 | folderNumber
        bytes[10] = 0xff
        bytes[11] = 0xff
        bytes[12] = 0x00
        bytes[13] = 0x3a // OPTION_AUTOAIM | SIGHTONSCREEN | LOOKAHEAD | DISPLAYAMMO
        return try! Self(bytes: bytes)
    }

    /// An empty, usable folder corresponding to `fileBuildWriteNewSave`.
    public static func created(folder: Int) -> Self {
        var result = blank(folder: folder)
        result.setFolderNumber(folder)
        result.setSelectedBond(folder)
        result.setReset(false)
        result.setSlot(0)
        return result
    }

    public var bytes: [UInt8] { storage }

    public var checksum1: Int32 {
        get { Int32(bitPattern: Self.readBE32(storage, at: 0)) }
        set { Self.writeBE32(UInt32(bitPattern: newValue), into: &storage, at: 0) }
    }

    public var checksum2: Int32 {
        get { Int32(bitPattern: Self.readBE32(storage, at: 4)) }
        set { Self.writeBE32(UInt32(bitPattern: newValue), into: &storage, at: 4) }
    }

    public var completionBitflags: UInt8 {
        get { storage[8] }
        set { storage[8] = newValue }
    }

    public var flag007: UInt8 {
        get { storage[9] }
        set { storage[9] = newValue }
    }

    public var musicVolume: UInt8 {
        get { storage[10] }
        set { storage[10] = newValue }
    }

    public var sfxVolume: UInt8 {
        get { storage[11] }
        set { storage[11] = newValue }
    }

    public var options: UInt16 {
        get { Self.readBE16(storage, at: 12) }
        set { Self.writeBE16(newValue, into: &storage, at: 12) }
    }

    public var unlockedCheats1: UInt8 {
        get { storage[14] }
        set { storage[14] = newValue }
    }

    public var unlockedCheats2: UInt8 {
        get { storage[15] }
        set { storage[15] = newValue }
    }

    public var unlockedCheats3: UInt8 {
        get { storage[16] }
        set { storage[16] = newValue }
    }

    public var folderNumber: Int {
        Int(completionBitflags & 0x07)
    }

    public var slot: Int {
        Int((completionBitflags & 0x18) >> 3)
    }

    public var selectedBond: Int {
        Int((completionBitflags & 0x60) >> 5)
    }

    public var isReset: Bool {
        (completionBitflags & 0x80) != 0
    }

    public var isUsable: Bool {
        !isReset && folderNumber < 4 && slot < 4 && selectedBond < 4
    }

    public var isBlank: Bool {
        isReset || (storage[18..<Self.byteCount - 2].allSatisfy { $0 == 0 } && checksum1 == 0 && checksum2 == 0)
    }

    public var hasCompletedMission: Bool {
        stageTimeBytes().contains { $0 != 0 }
    }

    public func stageTimeBytes() -> [UInt8] {
        Array(storage[18..<(18 + Self.timesByteCount)])
    }

    public mutating func setStageTimeByte(_ index: Int, value: UInt8) {
        guard (0..<Self.timesByteCount).contains(index) else { return }
        storage[18 + index] = value
    }

    public mutating func setFolderNumber(_ folder: Int) {
        let value = UInt8(max(0, min(folder, 3)))
        completionBitflags = (completionBitflags & ~0x07) | value
    }

    public mutating func setSlot(_ slot: Int) {
        let value = UInt8(max(0, min(slot, 3)))
        completionBitflags = (completionBitflags & ~0x18) | ((value << 3) & 0x18)
    }

    public mutating func setSelectedBond(_ bond: Int) {
        let value = UInt8(max(0, min(bond, 3)))
        completionBitflags = (completionBitflags & ~0x60) | ((value << 5) & 0x60)
    }

    public mutating func setReset(_ reset: Bool) {
        if reset {
            completionBitflags |= 0x80
        } else {
            completionBitflags &= ~0x80
        }
    }

    fileprivate func validate(index: Int) throws {
        guard storage.count == Self.byteCount else {
            throw GoldenEyeSaveCodecError.invalidFolder(index: index)
        }
        guard folderNumber < 4, slot < 4, selectedBond < 4 else {
            throw GoldenEyeSaveCodecError.invalidFolder(index: index)
        }
        guard storage[94] == 0, storage[95] == 0 else {
            throw GoldenEyeSaveCodecError.invalidFolder(index: index)
        }
    }

    private static func readBE16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }

    private static func readBE32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) << 24
            | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8
            | UInt32(bytes[offset + 3])
    }

    private static func writeBE16(_ value: UInt16, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8((value >> 8) & 0xff)
        bytes[offset + 1] = UInt8(value & 0xff)
    }

    private static func writeBE32(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8((value >> 24) & 0xff)
        bytes[offset + 1] = UInt8((value >> 16) & 0xff)
        bytes[offset + 2] = UInt8((value >> 8) & 0xff)
        bytes[offset + 3] = UInt8(value & 0xff)
    }
}

public struct GoldenEyeSaveState: Sendable, Equatable {
    public static let folderCount = 4

    public var folders: [GoldenEyeSaveFolder]
    public var selectedFolder: UInt8
    public var selectedBond: UInt8
    public var generation: UInt64

    public init(
        folders: [GoldenEyeSaveFolder] = (0..<GoldenEyeSaveState.folderCount).map { GoldenEyeSaveFolder.blank(folder: $0) },
        selectedFolder: UInt8 = 0,
        selectedBond: UInt8 = 0,
        generation: UInt64 = 0
    ) {
        precondition(folders.count == Self.folderCount, "GoldenEyeSaveState requires four folders")
        self.folders = folders
        self.selectedFolder = selectedFolder
        self.selectedBond = selectedBond
        self.generation = generation
    }

    public static var blank: Self { Self() }

    fileprivate func validated() throws {
        guard folders.count == Self.folderCount else {
            throw GoldenEyeSaveCodecError.invalidFolderCount(folders.count)
        }
        guard selectedFolder < Self.folderCount, selectedBond < 4 else {
            throw GoldenEyeSaveCodecError.invalidSelection
        }
        for (index, folder) in folders.enumerated() {
            try folder.validate(index: index)
        }
    }
}

public enum GoldenEyeSaveLoadSource: UInt8, Sendable, Equatable {
    case primary = 1
    case backup = 2
    case defaults = 3
}

public struct GoldenEyeSaveLoadResult: Sendable, Equatable {
    public let state: GoldenEyeSaveState
    public let source: GoldenEyeSaveLoadSource
    public let recovered: Bool
    public let persistenceEnabled: Bool
    public let quarantinedPath: String?

    public init(
        state: GoldenEyeSaveState,
        source: GoldenEyeSaveLoadSource,
        recovered: Bool,
        persistenceEnabled: Bool,
        quarantinedPath: String? = nil
    ) {
        self.state = state
        self.source = source
        self.recovered = recovered
        self.persistenceEnabled = persistenceEnabled
        self.quarantinedPath = quarantinedPath
    }
}

public enum GoldenEyeSaveActionError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidFolder(Int)
    case sourceFolderUnavailable(Int)
    case destinationOccupied(Int)
    case noFreeFolder

    public var description: String {
        switch self {
        case let .invalidFolder(folder): return "invalid folder \(folder)"
        case let .sourceFolderUnavailable(folder): return "source folder \(folder) is unavailable"
        case let .destinationOccupied(folder): return "destination folder \(folder) is occupied"
        case .noFreeFolder: return "no free folder is available"
        }
    }
}

public enum GoldenEyeSaveActions {
    public static func createFolder(_ state: inout GoldenEyeSaveState, at index: Int) throws {
        try validateFolderIndex(index)
        state.folders[index] = .created(folder: index)
        state.selectedFolder = UInt8(index)
        state.selectedBond = UInt8(index)
    }

    public static func eraseFolder(_ state: inout GoldenEyeSaveState, at index: Int) throws {
        try validateFolderIndex(index)
        state.folders[index] = .created(folder: index)
        state.selectedFolder = UInt8(index)
        state.selectedBond = UInt8(index)
    }

    public static func selectFolder(_ state: inout GoldenEyeSaveState, index: Int) throws {
        try validateFolderIndex(index)
        state.selectedFolder = UInt8(index)
        state.selectedBond = UInt8(state.folders[index].selectedBond)
    }

    public static func copyFolder(_ state: inout GoldenEyeSaveState, from source: Int, to destination: Int) throws {
        try validateFolderIndex(source)
        try validateFolderIndex(destination)
        guard state.folders[source].isUsable,
              state.folders[source].hasCompletedMission else {
            throw GoldenEyeSaveActionError.sourceFolderUnavailable(source)
        }
        guard source != destination else { return }
        var copy = state.folders[source]
        copy.setFolderNumber(destination)
        copy.setSlot(0)
        copy.setReset(false)
        state.folders[destination] = copy
        state.selectedFolder = UInt8(destination)
        state.selectedBond = UInt8(copy.selectedBond)
    }

    @discardableResult
    public static func copyFolderToFirstBlank(_ state: inout GoldenEyeSaveState, from source: Int) throws -> Int {
        guard let destination = state.folders.firstIndex(where: { !$0.isUsable }) else {
            throw GoldenEyeSaveActionError.noFreeFolder
        }
        try copyFolder(&state, from: source, to: destination)
        return destination
    }

    public static func validate(_ state: GoldenEyeSaveState) throws {
        try state.validated()
    }

    private static func validateFolderIndex(_ index: Int) throws {
        guard (0..<GoldenEyeSaveState.folderCount).contains(index) else {
            throw GoldenEyeSaveActionError.invalidFolder(index)
        }
    }
}

public enum GoldenEyeSaveCodec {
    public static let magic = Array("GESWSAVE".utf8)
    public static let version: UInt16 = 1
    public static let headerByteCount = 64
    public static let payloadByteCount = 532
    public static let fileByteCount = headerByteCount + payloadByteCount
    public static let folderWireByteCount = 132
    private static let payloadHeaderByteCount = 4

    public static func encode(_ state: GoldenEyeSaveState) throws -> [UInt8] {
        try state.validated()
        var payload = Array(repeating: UInt8(0), count: payloadByteCount)
        payload[0] = state.selectedFolder
        // Payload bytes 1...3 are reserved for future native-global fields.
        for index in 0..<GoldenEyeSaveState.folderCount {
            let bytes = state.folders[index].bytes
            let start = payloadHeaderByteCount + index * folderWireByteCount
            payload.replaceSubrange(start..<(start + GoldenEyeSaveFolder.byteCount), with: bytes)
        }

        let digest = Array(SHA256.hash(data: Data(payload)))
        var result = Array(repeating: UInt8(0), count: fileByteCount)
        result.replaceSubrange(0..<magic.count, with: magic)
        writeBE16(version, into: &result, at: 8)
        writeBE16(UInt16(headerByteCount), into: &result, at: 10)
        writeBE32(UInt32(payloadByteCount), into: &result, at: 12)
        writeBE64(state.generation, into: &result, at: 16)
        result.replaceSubrange(24..<56, with: digest)
        result.replaceSubrange(headerByteCount..<fileByteCount, with: payload)
        return result
    }

    public static func decode(_ bytes: [UInt8]) throws -> GoldenEyeSaveState {
        guard bytes.count == fileByteCount else {
            throw GoldenEyeSaveCodecError.invalidLength(expected: fileByteCount, actual: bytes.count)
        }
        guard Array(bytes[0..<magic.count]) == magic else {
            throw GoldenEyeSaveCodecError.invalidMagic
        }
        let version = readBE16(bytes, at: 8)
        guard version == Self.version else {
            throw GoldenEyeSaveCodecError.unsupportedVersion(version)
        }
        let headerLength = readBE16(bytes, at: 10)
        guard headerLength == headerByteCount else {
            throw GoldenEyeSaveCodecError.invalidHeaderLength(headerLength)
        }
        let payloadLength = readBE32(bytes, at: 12)
        guard payloadLength == payloadByteCount else {
            throw GoldenEyeSaveCodecError.invalidPayloadLength(payloadLength)
        }
        guard bytes[56..<headerByteCount].allSatisfy({ $0 == 0 }) else {
            throw GoldenEyeSaveCodecError.invalidReservedBytes(offset: 56)
        }
        let payload = Array(bytes[headerByteCount..<fileByteCount])
        let expectedDigest = Array(bytes[24..<56])
        let actualDigest = Array(SHA256.hash(data: Data(payload)))
        guard expectedDigest == actualDigest else {
            throw GoldenEyeSaveCodecError.checksumMismatch
        }
        guard payload[1..<payloadHeaderByteCount].allSatisfy({ $0 == 0 }) else {
            throw GoldenEyeSaveCodecError.invalidReservedBytes(offset: headerByteCount + 1)
        }
        for index in 0..<GoldenEyeSaveState.folderCount {
            let start = payloadHeaderByteCount + index * folderWireByteCount + GoldenEyeSaveFolder.byteCount
            let end = payloadHeaderByteCount + (index + 1) * folderWireByteCount
            guard payload[start..<end].allSatisfy({ $0 == 0 }) else {
                throw GoldenEyeSaveCodecError.invalidReservedBytes(offset: headerByteCount + start)
            }
        }
        guard payload.count == payloadHeaderByteCount + GoldenEyeSaveState.folderCount * folderWireByteCount else {
            throw GoldenEyeSaveCodecError.invalidPayloadLength(UInt32(payload.count))
        }

        var folders: [GoldenEyeSaveFolder] = []
        folders.reserveCapacity(GoldenEyeSaveState.folderCount)
        for index in 0..<GoldenEyeSaveState.folderCount {
            let start = payloadHeaderByteCount + index * folderWireByteCount
            let folder = try GoldenEyeSaveFolder(bytes: Array(payload[start..<(start + GoldenEyeSaveFolder.byteCount)]))
            try folder.validate(index: index)
            folders.append(folder)
        }
        let selectedFolder = payload[0]
        guard selectedFolder < GoldenEyeSaveState.folderCount else {
            throw GoldenEyeSaveCodecError.invalidSelection
        }
        let selectedBond = UInt8(folders[Int(selectedFolder)].selectedBond)
        return GoldenEyeSaveState(
            folders: folders,
            selectedFolder: selectedFolder,
            selectedBond: selectedBond,
            generation: readBE64(bytes, at: 16)
        )
    }

    private static func readBE16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }

    private static func readBE32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) << 24
            | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8
            | UInt32(bytes[offset + 3])
    }

    private static func readBE64(_ bytes: [UInt8], at offset: Int) -> UInt64 {
        UInt64(bytes[offset]) << 56
            | UInt64(bytes[offset + 1]) << 48
            | UInt64(bytes[offset + 2]) << 40
            | UInt64(bytes[offset + 3]) << 32
            | UInt64(bytes[offset + 4]) << 24
            | UInt64(bytes[offset + 5]) << 16
            | UInt64(bytes[offset + 6]) << 8
            | UInt64(bytes[offset + 7])
    }

    private static func writeBE16(_ value: UInt16, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8((value >> 8) & 0xff)
        bytes[offset + 1] = UInt8(value & 0xff)
    }

    private static func writeBE32(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8((value >> 24) & 0xff)
        bytes[offset + 1] = UInt8((value >> 16) & 0xff)
        bytes[offset + 2] = UInt8((value >> 8) & 0xff)
        bytes[offset + 3] = UInt8(value & 0xff)
    }

    private static func writeBE64(_ value: UInt64, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8((value >> 56) & 0xff)
        bytes[offset + 1] = UInt8((value >> 48) & 0xff)
        bytes[offset + 2] = UInt8((value >> 40) & 0xff)
        bytes[offset + 3] = UInt8((value >> 32) & 0xff)
        bytes[offset + 4] = UInt8((value >> 24) & 0xff)
        bytes[offset + 5] = UInt8((value >> 16) & 0xff)
        bytes[offset + 6] = UInt8((value >> 8) & 0xff)
        bytes[offset + 7] = UInt8(value & 0xff)
    }
}

/// Actor-isolated persistence for the native four-folder semantic save.  The
/// actor serializes all filesystem operations; callers only exchange copied
/// `Sendable` values and never receive a live file handle.
public actor GoldenEyeSaveStore {
    public static func defaultDirectoryURL() -> URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return applicationSupport
            .appendingPathComponent("com.goldeneye.swift.host", isDirectory: true)
            .appendingPathComponent("Saves", isDirectory: true)
    }

    public let directoryURL: URL
    public let primaryURL: URL
    public let backupURL: URL
    public private(set) var persistenceDisabled = false
    public private(set) var currentState = GoldenEyeSaveState.blank
    public private(set) var lastLoadResult: GoldenEyeSaveLoadResult?
    private var loaded = false

    public init(directoryURL: URL = GoldenEyeSaveStore.defaultDirectoryURL()) {
        self.directoryURL = directoryURL
        self.primaryURL = directoryURL.appendingPathComponent("profile.gesave", isDirectory: false)
        self.backupURL = directoryURL.appendingPathComponent("profile.gesave.bak", isDirectory: false)
    }

    @discardableResult
    public func load() throws -> GoldenEyeSaveLoadResult {
        if persistenceDisabled {
            let result = GoldenEyeSaveLoadResult(
                state: currentState,
                source: .defaults,
                recovered: false,
                persistenceEnabled: false
            )
            lastLoadResult = result
            loaded = true
            return result
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: primaryURL.path) else {
            if fileManager.fileExists(atPath: backupURL.path) {
                do {
                    let state = try decodeFile(at: backupURL)
                    currentState = state
                    loaded = true
                    let result = GoldenEyeSaveLoadResult(state: state, source: .backup, recovered: true, persistenceEnabled: true)
                    lastLoadResult = result
                    try writePrimaryRecovery(state)
                    return result
                } catch let error as GoldenEyeSaveCodecError {
                    if case .unsupportedVersion = error {
                        persistenceDisabled = true
                        return defaultsResult(enabled: false)
                    }
                }
            }
            return defaultsResult(enabled: true)
        }

        do {
            let state = try decodeFile(at: primaryURL)
            currentState = state
            loaded = true
            let result = GoldenEyeSaveLoadResult(state: state, source: .primary, recovered: false, persistenceEnabled: true)
            lastLoadResult = result
            return result
        } catch let error as GoldenEyeSaveCodecError {
            if case .unsupportedVersion = error {
                // Never quarantine or overwrite a schema newer than this
                // native build.  Disable writes so a future build can read it.
                persistenceDisabled = true
                return defaultsResult(enabled: false)
            }
            let quarantinePath: URL
            do {
                quarantinePath = try quarantinePrimary()
            } catch {
                // Never overwrite a corrupt primary when it cannot be moved
                // to a unique quarantine path.  A valid backup can still be
                // read, but this store becomes read-only for this process.
                persistenceDisabled = true
                if fileManager.fileExists(atPath: backupURL.path), let backupState = try? decodeFile(at: backupURL) {
                    currentState = backupState
                    loaded = true
                    let result = GoldenEyeSaveLoadResult(
                        state: backupState,
                        source: .backup,
                        recovered: true,
                        persistenceEnabled: false
                    )
                    lastLoadResult = result
                    return result
                }
                return defaultsResult(enabled: false)
            }
            if fileManager.fileExists(atPath: backupURL.path) {
                do {
                    let state = try decodeFile(at: backupURL)
                    currentState = state
                    loaded = true
                    let result = GoldenEyeSaveLoadResult(
                        state: state,
                        source: .backup,
                        recovered: true,
                        persistenceEnabled: true,
                        quarantinedPath: quarantinePath.path
                    )
                    lastLoadResult = result
                    try writePrimaryRecovery(state)
                    return result
                } catch let backupError as GoldenEyeSaveCodecError {
                    if case .unsupportedVersion = backupError {
                        persistenceDisabled = true
                        return defaultsResult(enabled: false)
                    }
                }
            }
            let result = GoldenEyeSaveLoadResult(
                state: .blank,
                source: .defaults,
                recovered: true,
                persistenceEnabled: true,
                quarantinedPath: quarantinePath.path
            )
            currentState = .blank
            loaded = true
            lastLoadResult = result
            return result
        }
    }

    @discardableResult
    public func save(_ state: GoldenEyeSaveState) throws -> GoldenEyeSaveState {
        guard !persistenceDisabled else { throw GoldenEyeSaveCodecError.persistenceDisabled }
        try state.validated()
        let generation: UInt64
        if loaded {
            guard currentState.generation != UInt64.max else { throw GoldenEyeSaveCodecError.generationOverflow }
            generation = currentState.generation &+ 1
        } else {
            generation = state.generation == UInt64.max ? 0 : state.generation &+ 1
        }
        var next = state
        next.generation = generation
        try persist(next, updateBackup: true)
        currentState = next
        loaded = true
        return next
    }

    @discardableResult
    public func selectFolder(_ index: Int) throws -> GoldenEyeSaveState {
        try ensureLoaded()
        var next = currentState
        try GoldenEyeSaveActions.selectFolder(&next, index: index)
        return try save(next)
    }

    @discardableResult
    public func createFolder(at index: Int) throws -> GoldenEyeSaveState {
        try ensureLoaded()
        var next = currentState
        try GoldenEyeSaveActions.createFolder(&next, at: index)
        return try save(next)
    }

    @discardableResult
    public func copyFolder(from source: Int, to destination: Int) throws -> GoldenEyeSaveState {
        try ensureLoaded()
        var next = currentState
        try GoldenEyeSaveActions.copyFolder(&next, from: source, to: destination)
        return try save(next)
    }

    @discardableResult
    public func copyFolderToFirstBlank(from source: Int) throws -> GoldenEyeSaveState {
        try ensureLoaded()
        var next = currentState
        _ = try GoldenEyeSaveActions.copyFolderToFirstBlank(&next, from: source)
        return try save(next)
    }

    @discardableResult
    public func eraseFolder(at index: Int) throws -> GoldenEyeSaveState {
        try ensureLoaded()
        var next = currentState
        try GoldenEyeSaveActions.eraseFolder(&next, at: index)
        return try save(next)
    }

    private func ensureLoaded() throws {
        if !loaded {
            _ = try load()
        }
        guard !persistenceDisabled else { throw GoldenEyeSaveCodecError.persistenceDisabled }
    }

    private func defaultsResult(enabled: Bool) -> GoldenEyeSaveLoadResult {
        let result = GoldenEyeSaveLoadResult(
            state: .blank,
            source: .defaults,
            recovered: false,
            persistenceEnabled: enabled,
            quarantinedPath: nil
        )
        currentState = .blank
        lastLoadResult = result
        loaded = true
        return result
    }

    private func decodeFile(at url: URL) throws -> GoldenEyeSaveState {
        do {
            return try GoldenEyeSaveCodec.decode(Array(Data(contentsOf: url)))
        } catch let error as GoldenEyeSaveCodecError {
            throw error
        } catch {
            throw GoldenEyeSaveCodecError.io("read \(url.path): \(error)")
        }
    }

    private func writePrimaryRecovery(_ state: GoldenEyeSaveState) throws {
        // Recovery preserves the validated generation and does not replace a
        // valid backup with a second copy of itself.
        try persist(state, updateBackup: false)
        currentState = state
    }

    private func persist(_ state: GoldenEyeSaveState, updateBackup: Bool) throws {
        try GoldenEyeSaveActions.validate(state)
        let bytes = try GoldenEyeSaveCodec.encode(state)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        if updateBackup, fileManager.fileExists(atPath: primaryURL.path), (try? decodeFile(at: primaryURL)) != nil {
            let oldBytes = Array(try Data(contentsOf: primaryURL))
            try writeFileAtomically(oldBytes, to: backupURL)
        }
        try writeFileAtomically(bytes, to: primaryURL)
        syncDirectory()
    }

    private func writeFileAtomically(_ bytes: [UInt8], to destination: URL) throws {
        let fileManager = FileManager.default
        let temporary = uniqueURL(for: destination, suffix: ".tmp")
        do {
            guard fileManager.createFile(atPath: temporary.path, contents: nil) else {
                throw GoldenEyeSaveCodecError.io("create \(temporary.path) failed")
            }
            let handle = try FileHandle(forWritingTo: temporary)
            try handle.write(contentsOf: Data(bytes))
            try handle.synchronize()
            try handle.close()
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: destination)
            }
        } catch let error as GoldenEyeSaveCodecError {
            try? fileManager.removeItem(at: temporary)
            throw error
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw GoldenEyeSaveCodecError.io("write \(destination.path): \(error)")
        }
    }

    private func quarantinePrimary() throws -> URL {
        let fileManager = FileManager.default
        let stamp = DispatchTime.now().uptimeNanoseconds
        for counter in 0..<1000 {
            let candidate = directoryURL.appendingPathComponent("profile.gesave.corrupt-\(stamp)-\(counter)")
            if !fileManager.fileExists(atPath: candidate.path) {
                do {
                    try fileManager.moveItem(at: primaryURL, to: candidate)
                    return candidate
                } catch {
                    throw GoldenEyeSaveCodecError.io("quarantine \(primaryURL.path): \(error)")
                }
            }
        }
        throw GoldenEyeSaveCodecError.io("no unique quarantine path for \(primaryURL.path)")
    }

    private func uniqueURL(for destination: URL, suffix: String) -> URL {
        let stamp = DispatchTime.now().uptimeNanoseconds
        var counter = 0
        while true {
            let name = ".\(destination.lastPathComponent).\(stamp)-\(counter)\(suffix)"
            let candidate = destination.deletingLastPathComponent().appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }

    private func syncDirectory() {
        let descriptor = open(directoryURL.path, O_RDONLY)
        guard descriptor >= 0 else { return }
        _ = fsync(descriptor)
        _ = close(descriptor)
    }
}
