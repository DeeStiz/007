import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("source audio binding V6 failure: \(message)\n", stderr)
        exit(1)
    }
}

private func input(
    operation: UInt32,
    assetID: UInt32,
    nativeTick: UInt64,
    sequence: UInt64
) -> GoldenEyeSourceAudioInputV6 {
    GoldenEyeSourceAudioInputV6(
        operation: operation,
        assetID: assetID,
        nativeTick: nativeTick,
        sequence: sequence
    )
}

@main
struct GoldenEyeSourceAudioBindingV6Smoke {
    static func main() {
        run()
    }

    private static func run() {
require(GoldenEyeSourceAudioBindingV6.sampleIndex(for: 0) == 0, "tick zero sample")
require(GoldenEyeSourceAudioBindingV6.sampleIndex(for: 1) == 183, "tick one sample")
require(GoldenEyeSourceAudioBindingV6.sampleIndex(for: 2) == 367, "tick two sample")
require(GoldenEyeSourceAudioBindingV6.sampleIndex(for: 3) == 551, "tick three sample")
require(GoldenEyeSourceAudioBindingV6.sampleIndex(for: 4) == 735, "tick four sample")
require(GoldenEyeSourceAudioBindingV6.sampleIndex(for: .max) == nil, "overflow fails closed")
require(GoldenEyeSourceAudioBindingV6.frameCount(for: 1) == 183, "first quantum")
require(GoldenEyeSourceAudioBindingV6.frameCount(for: 2) == 184, "second quantum")
require(GoldenEyeSourceAudioBindingV6.frameCount(for: 3) == 184, "third quantum")
require(GoldenEyeSourceAudioBindingV6.frameCount(for: 4) == 184, "fourth quantum")

var binding = GoldenEyeSourceAudioBindingV6()
let initStop = binding.consume(
    [input(operation: 1, assetID: GoldenEyeSourceAudioBindingV6.musicStop, nativeTick: 0, sequence: 1)],
    nativeTick: 0
)
require(initStop.commands.count == 1, "tick-zero lifecycle stop accepted")
require(initStop.commands[0].sampleIndex == 0, "tick-zero lifecycle sample")

let first = binding.consume(
    [input(operation: 2, assetID: GoldenEyeSourceAudioBindingV6.musicIntro, nativeTick: 1, sequence: 2)],
    nativeTick: 1
)
require(first.commands.count == 1, "music event accepted")
require(first.commands[0].sampleIndex == 183, "event is sample-indexed")
require(first.commands[0].kind == .music, "music command kind")

let duplicate = binding.consume(
    [input(operation: 2, assetID: GoldenEyeSourceAudioBindingV6.musicIntro, nativeTick: 1, sequence: 2)],
    nativeTick: 2
)
require(duplicate.commands.isEmpty, "duplicate is not replayed")
require(duplicate.duplicateCount == 1, "duplicate is counted")

let unknownMusic = binding.consume(
    [input(operation: 2, assetID: 999, nativeTick: 2, sequence: 3)],
    nativeTick: 2
)
require(unknownMusic.commands.isEmpty, "unmapped music is silent")
require(
    unknownMusic.rejections == [
        GoldenEyeSourceAudioRejectionRecordV6(sequence: 3, reason: .unmappedMusic(999))
    ],
    "unmapped music diagnostic"
)

let unknownSFX = binding.consume(
    [input(operation: 3, assetID: 999, nativeTick: 3, sequence: 4)],
    nativeTick: 3
)
require(unknownSFX.commands.isEmpty, "unmapped SFX is silent")
require(
    unknownSFX.rejections == [
        GoldenEyeSourceAudioRejectionRecordV6(sequence: 4, reason: .unmappedSFX(999))
    ],
    "unmapped SFX diagnostic"
)

let paused = binding.consume(
    [input(operation: 3, assetID: GoldenEyeSourceAudioBindingV6.sfxRarewareLogo, nativeTick: 4, sequence: 5)],
    nativeTick: 4,
    paused: true
)
require(paused.commands.isEmpty, "paused event is not scheduled")
require(paused.suppressedCount == 1, "paused event is counted")

let resumeDuplicate = binding.consume(
    [input(operation: 3, assetID: GoldenEyeSourceAudioBindingV6.sfxRarewareLogo, nativeTick: 4, sequence: 5)],
    nativeTick: 5
)
require(resumeDuplicate.commands.isEmpty, "resume does not replay paused event")
require(resumeDuplicate.duplicateCount == 1, "paused sequence remains consumed")

let stop = binding.consume(
    [input(operation: 1, assetID: GoldenEyeSourceAudioBindingV6.musicStop, nativeTick: 5, sequence: 6)],
    nativeTick: 5
)
require(stop.commands.count == 1 && stop.commands[0].kind == .stopMusic, "stop command")
require(stop.commands[0].sampleIndex == 918, "stop sample index")

// File/Mode owns a separate source event-sequence namespace. The service
// forwards these sidecar SFX through an independent binding so a menu event
// with sequence 1 cannot suppress frontend sequence 1.
var menuBinding = GoldenEyeSourceAudioBindingV6()
for (offset, soundIndex) in GoldenEyeSourceAudioBindingV6.supportedSFXIDs.enumerated() {
    let menuEvent = menuBinding.consume(
        [input(
            operation: GoldenEyeSourceAudioBindingV6.playSFXOperation,
            assetID: soundIndex,
            nativeTick: UInt64(6 + offset),
            sequence: UInt64(offset + 1)
        )],
        nativeTick: UInt64(6 + offset)
    )
    require(menuEvent.commands.count == 1, "menu namespace SFX (soundIndex) accepted")
    require(menuEvent.commands[0].kind == .sfx, "menu namespace SFX command kind")
}
let menuDuplicate = menuBinding.consume(
    [input(
        operation: GoldenEyeSourceAudioBindingV6.playSFXOperation,
        assetID: GoldenEyeSourceAudioBindingV6.sfxRarewareLogo,
        nativeTick: 6,
        sequence: 1
    )],
    nativeTick: 20
)
require(menuDuplicate.commands.isEmpty && menuDuplicate.duplicateCount == 1, "menu SFX duplicate suppressed")
menuBinding.reset()
let menuSessionReset = menuBinding.consume(
    [input(
        operation: GoldenEyeSourceAudioBindingV6.playSFXOperation,
        assetID: GoldenEyeSourceAudioBindingV6.sfxOptionClick2,
        nativeTick: 21,
        sequence: 1
    )],
    nativeTick: 21
)
require(menuSessionReset.commands.count == 1, "menu session reset accepts sequence one")
var independentFrontendBinding = GoldenEyeSourceAudioBindingV6()
let independentFrontend = independentFrontendBinding.consume(
    [input(
        operation: GoldenEyeSourceAudioBindingV6.playSFXOperation,
        assetID: GoldenEyeSourceAudioBindingV6.sfxOptionClick2,
        nativeTick: 6,
        sequence: 1
    )],
    nativeTick: 6
)
require(independentFrontend.commands.count == 1, "frontend namespace remains independent")

print("goldeneye_source_audio_binding_v6_smoke: PASS")
    }
}
