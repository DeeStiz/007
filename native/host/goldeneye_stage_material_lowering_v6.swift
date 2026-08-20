import Compression
import Foundation

#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

/// Copied source GBI/RDP state at one room-triangle boundary. The state is a
/// value-only sidecar: it is not a Metal pipeline or a source pointer.
public struct GoldenEyeStageSourceMaterialStateV6: Sendable, Equatable {
    public let stateIndex: UInt32
    public let stageID: UInt32
    public let roomIndex: UInt32
    public let commandOffset: UInt32
    public let otherModeHigh: UInt32
    public let otherModeLow: UInt32
    public let geometryMode: UInt32
    public let combineWord0: UInt32
    public let combineWord1: UInt32
    public let primitiveColor: UInt32
    public let environmentColor: UInt32
    public let blendColor: UInt32
    public let fogColor: UInt32
    public let textureWord0: UInt32
    public let textureWord1: UInt32
    /// The source custom G_SETTEX/G_NOOP command's selected base texture.
    /// This additive value is intentionally excluded from the historical
    /// material state hash; the independent stage texture manifest owns the
    /// command-to-IMAGE provenance hash.
    public let resolvedTextureID: UInt32?
    /// 0 = source row order (the runtime upload payload); 1 would indicate
    /// canonical inspection order. The stage texture sidecar currently binds
    /// only source-row-order payloads.
    public let textureRowOrder: UInt32
    public let tileWord0: UInt32
    public let tileWord1: UInt32
    public let stateHash: UInt64
}

public struct GoldenEyeStageSourceMaterialPacketV6: Sendable, Equatable {
    public let stageID: UInt32
    public let states: [GoldenEyeStageSourceMaterialStateV6]
    public let drawStateIndices: [UInt32]
    public let textureStateCommandCount: UInt32
    public let unsupportedTextureBindingCount: UInt32
    public let unsupportedCommandCount: UInt32
    public let packetHash: UInt64

    public var hasSourceState: Bool { !states.isEmpty && !drawStateIndices.isEmpty }
}

public enum GoldenEyeStageSourceMaterialLoweringError: Error, Sendable, Equatable, CustomStringConvertible {
    case missingBackground
    case malformedRange(UInt32, UInt32, UInt32)
    case inflateFailed(UInt32, UInt32)
    case malformedCommand(UInt32, UInt32)
    case noTriangleState

    public var description: String {
        switch self {
        case .missingBackground: return "stage material lowering is missing background payload"
        case let .malformedRange(room, offset, bytes): return "room \(room) payload range 0x\(String(offset, radix: 16))/\(bytes) is malformed"
        case let .inflateFailed(offset, bytes): return "stage material payload inflate failed at 0x\(String(offset, radix: 16)) (\(bytes) bytes)"
        case let .malformedCommand(room, offset): return "room \(room) material command malformed at 0x\(String(offset, radix: 16))"
        case .noTriangleState: return "stage material stream contains no triangle state"
        }
    }
}

public enum GoldenEyeStageSourceMaterialLowererV6 {
    public static func make(scene: GoldenEyeStageScenePacket) throws -> GoldenEyeStageSourceMaterialPacketV6 {
        guard let background = scene.resources.first(where: { $0.kind == .background }) else {
            throw GoldenEyeStageSourceMaterialLoweringError.missingBackground
        }

        var states: [GoldenEyeStageSourceMaterialStateV6] = []
        var drawStateIndices: [UInt32] = []
        var textureCommands: UInt32 = 0
        var unsupportedTextures: UInt32 = 0
        var unsupportedCommands: UInt32 = 0
        var state = State()

        for room in scene.rooms {
            let candidateStreams: [(offset: UInt32, bytes: UInt32)] = [
                (offset: room.primaryOffset, bytes: room.primaryBytes),
                (offset: room.secondaryOffset, bytes: room.secondaryBytes),
            ]
            var seenStreamOffsets: Set<UInt32> = []
            let streams = candidateStreams.filter {
                $0.bytes > 0 && seenStreamOffsets.insert($0.offset).inserted
                    && hasRoomPayloadMarker(
                        background.payload,
                        offset: Int($0.offset),
                        byteCount: Int($0.bytes)
                    )
            }
            for stream in streams {
                let displayList = try inflate(
                    background.payload,
                    offset: Int(stream.offset),
                    byteCount: Int(stream.bytes)
                )
                var offset = 0
                while offset + 8 <= displayList.count {
                let word0 = try readBE32(displayList, offset: offset, room: room.roomIndex)
                let word1 = try readBE32(displayList, offset: offset + 4, room: room.roomIndex)
                let opcode = UInt8(truncatingIfNeeded: word0 >> 24)
                switch opcode {
                case 0x04: // G_VTX
                    break
                case 0xb1, 0xbf: // G_TRI2 / G_TRI1
                    let snapshot = state.snapshot(
                        stateIndex: UInt32(states.count), stageID: scene.stageID,
                        roomIndex: room.roomIndex, commandOffset: UInt32(offset)
                    )
                    states.append(snapshot)
                    // The GE extension overloads the G_TRI2 opcode with
                    // packed TRI4.  The environment lowerer emits one
                    // source draw per decoded triangle, so carry the same
                    // state index four times for this command.
                    let triangleCount = opcode == 0xb1 ? 4 : 1
                    drawStateIndices.append(contentsOf: repeatElement(
                        snapshot.stateIndex,
                        count: triangleCount
                    ))
                case 0xba: // G_SETOTHERMODE_H
                    state.otherModeHigh = word1
                case 0xb9: // G_SETOTHERMODE_L
                    state.otherModeLow = word1
                case 0xbb: // G_TEXTURE
                    state.textureWord0 = word0 & 0x00ff_ffff
                    state.textureWord1 = word1
                    textureCommands += 1
                    unsupportedTextures += 1
                case 0xfd: // G_SETTIMG
                    state.textureWord0 = word0
                    state.textureWord1 = word1
                    textureCommands += 1
                    unsupportedTextures += 1
                case 0xf0, 0xf3, 0xf4: // G_LOADTLUT / G_LOADBLOCK / G_LOADTILE
                    state.tileWord0 = word0
                    state.tileWord1 = word1
                    textureCommands += 1
                    unsupportedTextures += 1
                case 0xb6: // G_SETGEOMETRYMODE
                    state.geometryMode |= word1
                case 0xb7: // G_CLEARGEOMETRYMODE
                    state.geometryMode &= ~word1
                case 0xfc: // G_SETCOMBINE
                    state.combineWord0 = word0
                    state.combineWord1 = word1
                case 0xfa: // G_SETPRIMCOLOR
                    state.primitiveColor = word1
                case 0xfb: // G_SETENVCOLOR
                    state.environmentColor = word1
                case 0xf9: // G_SETBLENDCOLOR
                    state.blendColor = word1
                case 0xf8: // G_SETFOGCOLOR
                    state.fogColor = word1
                case 0xf5, 0xf2: // tile setup/state
                    state.tileWord0 = word0
                    state.tileWord1 = word1
                    textureCommands += 1
                    unsupportedTextures += 1
                case 0xc0: // source G_SETTEX/G_NOOP texture-number selector
                    state.resolvedTextureID = word1 & 0x0fff
                case 0xb8, 0xdf: // G_ENDDL variants
                    offset = displayList.count
                    continue
                case 0xe7: // pipe sync/no-op
                    break
                default:
                    unsupportedCommands += 1
                }
                offset += 8
            }
            }
        }

        guard !states.isEmpty else {
            throw GoldenEyeStageSourceMaterialLoweringError.noTriangleState
        }
        var hash = GoldenEyeStageMaterialHash.offset
        hash = GoldenEyeStageMaterialHash.word(hash, scene.stageID)
        hash = GoldenEyeStageMaterialHash.word(hash, UInt32(states.count))
        hash = GoldenEyeStageMaterialHash.word(hash, UInt32(drawStateIndices.count))
        hash = GoldenEyeStageMaterialHash.word(hash, textureCommands)
        hash = GoldenEyeStageMaterialHash.word(hash, unsupportedTextures)
        hash = GoldenEyeStageMaterialHash.word(hash, unsupportedCommands)
        for state in states {
            hash = GoldenEyeStageMaterialHash.word(hash, state.stateHash)
        }
        for index in drawStateIndices {
            hash = GoldenEyeStageMaterialHash.word(hash, index)
        }
        return GoldenEyeStageSourceMaterialPacketV6(
            stageID: scene.stageID,
            states: states,
            drawStateIndices: drawStateIndices,
            textureStateCommandCount: textureCommands,
            unsupportedTextureBindingCount: unsupportedTextures,
            unsupportedCommandCount: unsupportedCommands,
            packetHash: hash
        )
    }

    private struct State {
        var otherModeHigh: UInt32 = 0
        var otherModeLow: UInt32 = 0
        var geometryMode: UInt32 = 0
        var combineWord0: UInt32 = 0
        var combineWord1: UInt32 = 0
        var primitiveColor: UInt32 = 0
        var environmentColor: UInt32 = 0
        var blendColor: UInt32 = 0
        var fogColor: UInt32 = 0
        var textureWord0: UInt32 = 0
        var textureWord1: UInt32 = 0
        var tileWord0: UInt32 = 0
        var tileWord1: UInt32 = 0
        var resolvedTextureID: UInt32?
        var textureRowOrder: UInt32 = 0

        func snapshot(
            stateIndex: UInt32,
            stageID: UInt32,
            roomIndex: UInt32,
            commandOffset: UInt32
        ) -> GoldenEyeStageSourceMaterialStateV6 {
            var hash = GoldenEyeStageMaterialHash.offset
            for word in [
                stateIndex, stageID, roomIndex, commandOffset, otherModeHigh,
                otherModeLow, geometryMode, combineWord0, combineWord1,
                primitiveColor, environmentColor, blendColor, fogColor,
                textureWord0, textureWord1, tileWord0, tileWord1,
            ] {
                hash = GoldenEyeStageMaterialHash.word(hash, word)
            }
            return GoldenEyeStageSourceMaterialStateV6(
                stateIndex: stateIndex, stageID: stageID, roomIndex: roomIndex,
                commandOffset: commandOffset, otherModeHigh: otherModeHigh,
                otherModeLow: otherModeLow, geometryMode: geometryMode,
                combineWord0: combineWord0, combineWord1: combineWord1,
                primitiveColor: primitiveColor, environmentColor: environmentColor,
                blendColor: blendColor, fogColor: fogColor,
                textureWord0: textureWord0, textureWord1: textureWord1,
                resolvedTextureID: resolvedTextureID,
                textureRowOrder: textureRowOrder,
                tileWord0: tileWord0, tileWord1: tileWord1, stateHash: hash
            )
        }
    }

    private static func inflate(_ data: Data, offset: Int, byteCount: Int) throws -> Data {
        guard offset >= 0, byteCount >= 2, offset <= data.count,
              byteCount <= data.count - offset,
              data[offset] == 0x11, data[offset + 1] == 0x72 else {
            throw GoldenEyeStageSourceMaterialLoweringError.inflateFailed(
                UInt32(max(offset, 0)), UInt32(max(byteCount, 0))
            )
        }
        let input = data.subdata(in: (offset + 2)..<(offset + byteCount))
        var capacity = max(16 * 1024, byteCount * 32)
        while capacity <= 16 * 1024 * 1024 {
            var output = Data(count: capacity)
            let produced = output.withUnsafeMutableBytes { outputBytes -> Int in
                input.withUnsafeBytes { inputBytes -> Int in
                    guard let outputBase = outputBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                          let inputBase = inputBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
                    return compression_decode_buffer(
                        outputBase, outputBytes.count, inputBase, inputBytes.count,
                        nil, COMPRESSION_ZLIB
                    )
                }
            }
            if produced > 0, produced < capacity {
                output.removeSubrange(produced..<output.count)
                return output
            }
            capacity *= 2
        }
        throw GoldenEyeStageSourceMaterialLoweringError.inflateFailed(
            UInt32(offset), UInt32(byteCount)
        )
    }

    private static func hasRoomPayloadMarker(
        _ data: Data,
        offset: Int,
        byteCount: Int
    ) -> Bool {
        guard offset >= 0, byteCount >= 2,
              offset <= data.count, byteCount <= data.count - offset else {
            return false
        }
        return data[offset] == 0x11 && data[offset + 1] == 0x72
    }

    private static func readBE32(_ data: Data, offset: Int, room: UInt32) throws -> UInt32 {
        guard offset >= 0, offset <= data.count, data.count - offset >= 4 else {
            throw GoldenEyeStageSourceMaterialLoweringError.malformedCommand(room, UInt32(max(offset, 0)))
        }
        return UInt32(data[offset]) << 24 |
            UInt32(data[offset + 1]) << 16 |
            UInt32(data[offset + 2]) << 8 |
            UInt32(data[offset + 3])
    }
}

private enum GoldenEyeStageMaterialHash {
    static let offset: UInt64 = 1_469_598_103_934_665_603
    static let prime: UInt64 = 1_099_511_628_211

    static func word(_ initial: UInt64, _ value: UInt32) -> UInt64 {
        var hash = initial
        for shift in stride(from: 0, to: 32, by: 8) {
            hash = (hash ^ UInt64((value >> UInt32(shift)) & 0xff)) &* prime
        }
        return hash
    }

    static func word(_ initial: UInt64, _ value: UInt64) -> UInt64 {
        var hash = initial
        for shift in stride(from: 0, to: 64, by: 8) {
            hash = (hash ^ ((value >> UInt64(shift)) & 0xff)) &* prime
        }
        return hash
    }
}
