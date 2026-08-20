import Foundation

/// The small, value-only input used by the source-audio binding.  Keeping this
/// separate from the C record makes the scheduling rules testable without an
/// AVAudioEngine or a prepared-asset root.  The production adapter constructs
/// these values from `GoldenEyeSourceFrontendAudioEventV6` records.
struct GoldenEyeSourceAudioInputV6: Sendable, Equatable {
    let operation: UInt32
    let assetID: UInt32
    let nativeTick: UInt64
    let sourceSample: UInt64
    let flags: UInt32
    let sequence: UInt64

    init(
        operation: UInt32,
        assetID: UInt32,
        nativeTick: UInt64,
        sourceSample: UInt64 = 0,
        flags: UInt32 = 0,
        sequence: UInt64
    ) {
        self.operation = operation
        self.assetID = assetID
        self.nativeTick = nativeTick
        self.sourceSample = sourceSample
        self.flags = flags
        self.sequence = sequence
    }
}

enum GoldenEyeSourceAudioCommandKindV6: UInt32, Sendable {
    case stopMusic = 1
    case music = 2
    case sfx = 3
}

struct GoldenEyeSourceAudioCommandV6: Sendable, Equatable {
    let kind: GoldenEyeSourceAudioCommandKindV6
    let assetID: UInt32
    let nativeTick: UInt64
    let sampleIndex: UInt64
    let sequence: UInt64
}

enum GoldenEyeSourceAudioRejectionV6: Sendable, Equatable {
    case invalidSequence
    case invalidTick
    case unmappedMusic(UInt32)
    case unmappedSFX(UInt32)
    case invalidStopAsset(UInt32)
    case arithmeticOverflow
}

struct GoldenEyeSourceAudioRejectionRecordV6: Sendable, Equatable {
    let sequence: UInt64
    let reason: GoldenEyeSourceAudioRejectionV6
}

struct GoldenEyeSourceAudioBindingResultV6: Sendable, Equatable {
    let commands: [GoldenEyeSourceAudioCommandV6]
    let rejections: [GoldenEyeSourceAudioRejectionRecordV6]
    let duplicateCount: UInt32
    let suppressedCount: UInt32
}

/// Converts source frontend audio events into sample-indexed owner commands.
///
/// This type deliberately performs no playback and holds no host object.  It
/// is the once-only boundary between the source-authoritative frontend and
/// `GoldenEyeNativeAudioService`.  Source sequence numbers are monotonic for
/// the lifetime of the frontend state; consuming a sequence marks it handled
/// even if it is rejected or suppressed while paused, so a resume cannot
/// replay an old cue.
struct GoldenEyeSourceAudioBindingV6: Sendable {
    static let sampleRate: UInt32 = 22_050
    static let sampleNumerator: UInt64 = 735
    static let sampleDenominator: UInt64 = 4

    // These are the source MUSIC_TRACKS/SFX_ID values exposed by the native
    // frontend seam.  Music payloads are the only prepared title tracks;
    // arbitrary IDs are never guessed or silently routed to another track.
    static let musicIntroSwoosh: UInt32 = 44
    static let musicIntro: UInt32 = 2
    static let musicFolders: UInt32 = 23
    static let musicStop: UInt32 = 0
    static let sfxRarewareLogo: UInt32 = 258
    static let sfxOptionClick2: UInt32 = 18
    static let sfxGunRifle7Big1: UInt32 = 111

    private(set) var lastConsumedSequence: UInt64 = 0

    mutating func reset() {
        lastConsumedSequence = 0
    }

    static func sampleIndex(for nativeTick: UInt64) -> UInt64? {
        // Match the C source-rate helper: divide before multiplying and
        // saturate an impossible far-future host run rather than wrapping.
        let wholeTicks = nativeTick / sampleDenominator
        let remainder = nativeTick % sampleDenominator
        guard wholeTicks <= UInt64.max / sampleNumerator else {
            return nil
        }
        let base = wholeTicks * sampleNumerator
        let extra = (remainder * sampleNumerator) / sampleDenominator
        guard base <= UInt64.max - extra else {
            return nil
        }
        return base + extra
    }

    static func frameCount(for nativeTick: UInt64) -> UInt32? {
        guard let current = sampleIndex(for: nativeTick) else { return nil }
        guard nativeTick > 0, let previous = sampleIndex(for: nativeTick - 1) else {
            return nativeTick == 0 ? 0 : nil
        }
        let delta = current - previous
        guard delta <= UInt64(UInt32.max) else { return nil }
        return UInt32(delta)
    }

    mutating func consume(
        _ events: [GoldenEyeSourceAudioInputV6],
        nativeTick: UInt64,
        paused: Bool = false
    ) -> GoldenEyeSourceAudioBindingResultV6 {
        var commands: [GoldenEyeSourceAudioCommandV6] = []
        var rejections: [GoldenEyeSourceAudioRejectionRecordV6] = []
        var duplicateCount: UInt32 = 0
        var suppressedCount: UInt32 = 0

        for event in events {
            // A source event sequence is the stable identity.  Older or
            // repeated records are never re-emitted after a route resume.
            guard event.sequence != 0 else {
                rejections.append(.init(sequence: event.sequence, reason: .invalidSequence))
                continue
            }
            guard event.sequence > lastConsumedSequence else {
                duplicateCount &+= 1
                continue
            }
            lastConsumedSequence = event.sequence

            // Tick zero is the source initialization boundary.  It may emit
            // lifecycle audio such as STOP_MUSIC at sample zero; rejecting it
            // would make the host silently skip part of the source init.
            guard event.nativeTick <= nativeTick else {
                rejections.append(.init(sequence: event.sequence, reason: .invalidTick))
                continue
            }
            guard let sampleIndex = Self.sampleIndex(for: event.nativeTick) else {
                rejections.append(.init(sequence: event.sequence, reason: .arithmeticOverflow))
                continue
            }

            let kind: GoldenEyeSourceAudioCommandKindV6
            switch event.operation {
            case 1: // GE_SOURCE_FRONTEND_RUNTIME_V6_AUDIO_OP_STOP_MUSIC
                guard event.assetID == Self.musicStop else {
                    rejections.append(.init(sequence: event.sequence, reason: .invalidStopAsset(event.assetID)))
                    continue
                }
                kind = .stopMusic
            case 2: // GE_SOURCE_FRONTEND_RUNTIME_V6_AUDIO_OP_PLAY_MUSIC
                guard event.assetID == Self.musicIntroSwoosh ||
                    event.assetID == Self.musicIntro ||
                    event.assetID == Self.musicFolders else {
                    rejections.append(.init(sequence: event.sequence, reason: .unmappedMusic(event.assetID)))
                    continue
                }
                kind = .music
            case 3: // GE_SOURCE_FRONTEND_RUNTIME_V6_AUDIO_OP_PLAY_SFX
                guard event.assetID == Self.sfxRarewareLogo ||
                    event.assetID == Self.sfxOptionClick2 ||
                    event.assetID == Self.sfxGunRifle7Big1 else {
                    rejections.append(.init(sequence: event.sequence, reason: .unmappedSFX(event.assetID)))
                    continue
                }
                kind = .sfx
            default:
                rejections.append(.init(sequence: event.sequence, reason: .unmappedSFX(event.operation)))
                continue
            }

            if paused {
                suppressedCount &+= 1
                continue
            }
            commands.append(
                GoldenEyeSourceAudioCommandV6(
                    kind: kind,
                    assetID: event.assetID,
                    nativeTick: event.nativeTick,
                    sampleIndex: sampleIndex,
                    sequence: event.sequence
                )
            )
        }

        return GoldenEyeSourceAudioBindingResultV6(
            commands: commands,
            rejections: rejections,
            duplicateCount: duplicateCount,
            suppressedCount: suppressedCount
        )
    }
}
