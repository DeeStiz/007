import Foundation

/// Additive, value-only cadence contract for the source-faithful native port.
///
/// This file is intentionally independent of the existing V1--V5 C records and
/// of the current owner loop.  It gives the next owner implementation one
/// source of truth for native ticks, source/reference pairing, presentation
/// selection, RAMROM authority, input-edge eligibility, and audio time.  Every
/// value that crosses this contract is fixed width; no clock, pointer, path,
/// renderer object, or independent subsystem counter is retained here.

@frozen public struct GETimelineAbiHeaderV6: Sendable, Equatable {
    public static let abiVersion: UInt32 = 1
    public static let contractVersion: UInt32 = 6

    public let abiVersion: UInt32
    public let structSize: UInt32
    public let contractVersion: UInt32
    public let reserved: UInt32

    public init(structSize: UInt32, contractVersion: UInt32 = GETimelineAbiHeaderV6.contractVersion) {
        self.abiVersion = GETimelineAbiHeaderV6.abiVersion
        self.structSize = structSize
        self.contractVersion = contractVersion
        self.reserved = 0
    }
}

@frozen public enum GETimelineFailureCodeV6: UInt32, Sendable, Equatable {
    case none = 0
    case invalidConfiguration = 1
    case bootstrapRepeated = 2
    case advanceBeforeBootstrap = 3
    case tickOverflow = 4
    case audioOverflow = 5
    case invalidPairPhase = 6
    case comparatorOverflow = 7
    case comparatorNotReached = 8
    case inputRejected = 9
    case invalidSnapshotSelection = 10
    case authorityMismatch = 11
}

@frozen public enum GETimelineFailureContextV6: UInt32, Sendable, Equatable {
    case none = 0
    case configuration = 1
    case bootstrap = 2
    case advance = 3
    case audio = 4
    case pairing = 5
    case comparator = 6
    case input = 7
    case presentation = 8
    case ramrom = 9
}

/// A deterministic failure record.  Diagnostics deliberately carry numbers
/// rather than a Swift error string so a C or Swift caller can hash and copy
/// them without retaining an object or a pointer.
@frozen public struct GETimelineDiagnosticV6: Error, Sendable, Equatable, CustomStringConvertible {
    public let header: GETimelineAbiHeaderV6
    public let code: GETimelineFailureCodeV6
    public let context: GETimelineFailureContextV6
    public let reserved: UInt32
    public let nativeTick: UInt64
    public let referenceTick: UInt64
    public let expected: UInt64
    public let actual: UInt64

    public init(
        code: GETimelineFailureCodeV6,
        context: GETimelineFailureContextV6,
        nativeTick: UInt64 = 0,
        referenceTick: UInt64 = 0,
        expected: UInt64 = 0,
        actual: UInt64 = 0
    ) {
        self.header = GETimelineAbiHeaderV6(
            structSize: UInt32(MemoryLayout<GETimelineDiagnosticV6>.size)
        )
        self.code = code
        self.context = context
        self.reserved = 0
        self.nativeTick = nativeTick
        self.referenceTick = referenceTick
        self.expected = expected
        self.actual = actual
    }

    public static let none = GETimelineDiagnosticV6(
        code: .none,
        context: .none
    )

    public var isFailure: Bool { code != .none }

    public var description: String {
        "GETimelineDiagnosticV6(code=\(code.rawValue), context=\(context.rawValue), "
            + "native=\(nativeTick), reference=\(referenceTick), expected=\(expected), actual=\(actual))"
    }
}

/// Exact source/reference/audio rates used by the V6 timeline.  The
/// initializer accepts arbitrary fixed-width values so malformed records can
/// be tested and rejected; the production initializer uses `goldenEye`.
@frozen public struct GETimebaseConfigV6: Sendable, Equatable {
    public static let goldenEye = GETimebaseConfigV6(
        nativeRateNumerator: 120,
        nativeRateDenominator: 1,
        referenceRateNumerator: 60,
        referenceRateDenominator: 1,
        pairedNativeTicksPerReference: 2,
        maxCatchUpTicks: 4,
        maxDebtTicks: 240,
        audioSampleRate: 22_050,
        audioSampleNumerator: 735,
        audioSampleDenominator: 4
    )

    public let header: GETimelineAbiHeaderV6
    public let nativeRateNumerator: UInt32
    public let nativeRateDenominator: UInt32
    public let referenceRateNumerator: UInt32
    public let referenceRateDenominator: UInt32
    public let pairedNativeTicksPerReference: UInt32
    public let maxCatchUpTicks: UInt32
    public let maxDebtTicks: UInt64
    public let audioSampleRate: UInt32
    public let audioSampleNumerator: UInt32
    public let audioSampleDenominator: UInt32

    public init(
        nativeRateNumerator: UInt32,
        nativeRateDenominator: UInt32,
        referenceRateNumerator: UInt32,
        referenceRateDenominator: UInt32,
        pairedNativeTicksPerReference: UInt32,
        maxCatchUpTicks: UInt32,
        maxDebtTicks: UInt64,
        audioSampleRate: UInt32,
        audioSampleNumerator: UInt32,
        audioSampleDenominator: UInt32
    ) {
        self.header = GETimelineAbiHeaderV6(
            structSize: UInt32(MemoryLayout<GETimebaseConfigV6>.size)
        )
        self.nativeRateNumerator = nativeRateNumerator
        self.nativeRateDenominator = nativeRateDenominator
        self.referenceRateNumerator = referenceRateNumerator
        self.referenceRateDenominator = referenceRateDenominator
        self.pairedNativeTicksPerReference = pairedNativeTicksPerReference
        self.maxCatchUpTicks = maxCatchUpTicks
        self.maxDebtTicks = maxDebtTicks
        self.audioSampleRate = audioSampleRate
        self.audioSampleNumerator = audioSampleNumerator
        self.audioSampleDenominator = audioSampleDenominator
    }

    public var validationDiagnostic: GETimelineDiagnosticV6? {
        let expectedNative = UInt64(120)
        let expectedReference = UInt64(60)
        let nativeRate = UInt64(nativeRateNumerator)
        let nativeDenominator = UInt64(nativeRateDenominator)
        let referenceRate = UInt64(referenceRateNumerator)
        let referenceDenominator = UInt64(referenceRateDenominator)

        guard nativeRateNumerator > 0, nativeRateDenominator > 0,
              referenceRateNumerator > 0, referenceRateDenominator > 0,
              nativeRate * referenceDenominator == expectedNative * nativeDenominator,
              referenceRate * nativeDenominator == expectedReference * referenceDenominator,
              pairedNativeTicksPerReference == 2,
              maxCatchUpTicks > 0,
              maxDebtTicks >= UInt64(maxCatchUpTicks),
              audioSampleRate == 22_050,
              audioSampleNumerator == 735,
              audioSampleDenominator == 4 else {
            return GETimelineDiagnosticV6(
                code: .invalidConfiguration,
                context: .configuration,
                expected: 120,
                actual: UInt64(nativeRateNumerator)
            )
        }
        return nil
    }

    public var isValid: Bool { validationDiagnostic == nil }
}

@frozen public enum GEOriginalComparatorV6: UInt8, Sendable, Equatable {
    case equal = 0
    case notEqual = 1
    case less = 2
    case lessOrEqual = 3
    case greater = 4
    case greaterOrEqual = 5
}

/// A source comparator may become visible at the reference anchor or during
/// the odd native half-step.  The latter preserves strict post-increment
/// ordering such as `g_MenuTimer++ > 180`, whose native threshold is 361.
@frozen public enum GEComparatorEvaluationPhaseV6: UInt8, Sendable, Equatable {
    case referenceAnchor = 0
    case previewHalfStep = 1
}

@frozen public enum GEInputDecisionCodeV6: UInt32, Sendable, Equatable {
    case accepted = 0
    case bootstrapNotEligible = 1
    case futureEvent = 2
    case unfocused = 3
    case controllerDisconnected = 4
}

@frozen public struct GEInputEventV6: Sendable, Equatable {
    public static let focusedFlag: UInt16 = 1 << 0
    public static let controllerConnectedFlag: UInt16 = 1 << 1

    public let header: GETimelineAbiHeaderV6
    public let sequence: UInt64
    public let capturedNativeTick: UInt64
    public let held: UInt32
    public let pressed: UInt32
    public let released: UInt32
    public let flags: UInt16
    public let source: UInt16

    public init(
        sequence: UInt64,
        capturedNativeTick: UInt64,
        held: UInt32 = 0,
        pressed: UInt32 = 0,
        released: UInt32 = 0,
        focused: Bool = true,
        controllerConnected: Bool = true,
        source: UInt16 = 0
    ) {
        self.header = GETimelineAbiHeaderV6(
            structSize: UInt32(MemoryLayout<GEInputEventV6>.size)
        )
        self.sequence = sequence
        self.capturedNativeTick = capturedNativeTick
        self.held = held
        self.pressed = pressed
        self.released = released
        self.flags = (focused ? Self.focusedFlag : 0)
            | (controllerConnected ? Self.controllerConnectedFlag : 0)
        self.source = source
    }

    public var focused: Bool { (flags & Self.focusedFlag) != 0 }
    public var controllerConnected: Bool { (flags & Self.controllerConnectedFlag) != 0 }
}

@frozen public struct GEInputEdgeDecisionV6: Sendable, Equatable {
    public let header: GETimelineAbiHeaderV6
    public let sequence: UInt64
    public let nativeTick: UInt64
    public let code: GEInputDecisionCodeV6
    public let accepted: UInt8
    public let reserved: UInt8

    public init(
        sequence: UInt64,
        nativeTick: UInt64,
        code: GEInputDecisionCodeV6
    ) {
        self.header = GETimelineAbiHeaderV6(
            structSize: UInt32(MemoryLayout<GEInputEdgeDecisionV6>.size)
        )
        self.sequence = sequence
        self.nativeTick = nativeTick
        self.code = code
        self.accepted = code == .accepted ? 1 : 0
        self.reserved = 0
    }
}

@frozen public enum GEPresentationModeV6: UInt8, Sendable, Equatable {
    case native120 = 0
    case fixed60 = 1
}

@frozen public struct GEFrameSelectionV6: Sendable, Equatable {
    public static let newSnapshotFlag: UInt16 = 1 << 0
    public static let fixed60RepeatFlag: UInt16 = 1 << 1
    public static let interpolatedFlag: UInt16 = 1 << 2

    public let header: GETimelineAbiHeaderV6
    public let mode: GEPresentationModeV6
    public let pairPhase: UInt8
    public let flags: UInt16
    public let nativeTick: UInt64
    public let selectedNativeTick: UInt64
    public let sourceReferenceTick: UInt64
    public let interpolationQ16: UInt32
    public let reserved: UInt32

    public init(
        mode: GEPresentationModeV6,
        pairPhase: UInt8,
        flags: UInt16,
        nativeTick: UInt64,
        selectedNativeTick: UInt64,
        sourceReferenceTick: UInt64,
        interpolationQ16: UInt32
    ) {
        self.header = GETimelineAbiHeaderV6(
            structSize: UInt32(MemoryLayout<GEFrameSelectionV6>.size)
        )
        self.mode = mode
        self.pairPhase = pairPhase
        self.flags = flags
        self.nativeTick = nativeTick
        self.selectedNativeTick = selectedNativeTick
        self.sourceReferenceTick = sourceReferenceTick
        self.interpolationQ16 = interpolationQ16
        self.reserved = 0
    }

    public var presentsNewSnapshot: Bool { (flags & Self.newSnapshotFlag) != 0 }
    public var repeatsPreviousSnapshot: Bool { (flags & Self.fixed60RepeatFlag) != 0 }
    public var interpolatesContinuousState: Bool { (flags & Self.interpolatedFlag) != 0 }
}

@frozen public enum GEPresentationWindowRejectionV6: UInt32, Sendable, Equatable {
    case none = 0
    case nonPositive = 1
    case nonFinite = 2
    case nonMonotonic = 3
}

/// Fixed-width result copied out of the pure presentation-window accumulator.
/// A result is emitted on every accepted sample that has a retained boundary
/// at least one second old.  The boundary sample itself is excluded from the
/// frame count and retained as the next rolling window's first sample.
@frozen public struct GEPresentationWindowSampleV6: Sendable, Equatable {
    public static let acceptedFlag: UInt16 = 1 << 0
    public static let emittedWindowFlag: UInt16 = 1 << 1

    public let header: GETimelineAbiHeaderV6
    public let flags: UInt16
    public let rejection: GEPresentationWindowRejectionV6
    public let reserved: UInt32
    public let presentedTime: Double
    public let boundaryPresentedTime: Double
    public let windowDurationSeconds: Double
    public let windowFrames: UInt64
    public let minimumWindowFrames: UInt64
    public let windowCount: UInt64
    public let acceptedSampleCount: UInt64
    public let rejectedSampleCount: UInt64
    public let windowHash: UInt64

    public init(
        flags: UInt16,
        rejection: GEPresentationWindowRejectionV6,
        presentedTime: Double,
        boundaryPresentedTime: Double,
        windowDurationSeconds: Double,
        windowFrames: UInt64,
        minimumWindowFrames: UInt64,
        windowCount: UInt64,
        acceptedSampleCount: UInt64,
        rejectedSampleCount: UInt64,
        windowHash: UInt64
    ) {
        self.header = GETimelineAbiHeaderV6(
            structSize: UInt32(MemoryLayout<GEPresentationWindowSampleV6>.size)
        )
        self.flags = flags
        self.rejection = rejection
        self.reserved = 0
        self.presentedTime = presentedTime
        self.boundaryPresentedTime = boundaryPresentedTime
        self.windowDurationSeconds = windowDurationSeconds
        self.windowFrames = windowFrames
        self.minimumWindowFrames = minimumWindowFrames
        self.windowCount = windowCount
        self.acceptedSampleCount = acceptedSampleCount
        self.rejectedSampleCount = rejectedSampleCount
        self.windowHash = windowHash
    }

    public var accepted: Bool { (flags & Self.acceptedFlag) != 0 }
    public var emittedWindow: Bool { (flags & Self.emittedWindowFlag) != 0 }
}

/// Deterministic rolling presented-time evidence.  This is a Swift-only
/// accumulator; callers copy its fixed-width `GEPresentationWindowSampleV6`
/// result into runtime telemetry.  It keeps the newest sample at or before
/// `presentedTime - 1.0` instead of deleting that boundary, which makes a
/// one-second window reachable at both 60 and 120 Hz.
public struct GEPresentationWindowAccumulatorV6: Sendable, Equatable {
    private static let boundaryEpsilonSeconds = 1.0e-12

    private var presentedTimes: [Double] = []
    private var acceptedCount: UInt64 = 0
    private var rejectedCount: UInt64 = 0
    private var rollingWindowCount: UInt64 = 0
    private var minimumFrames: UInt64 = 0
    private var latestWindowFrames: UInt64 = 0
    private var lastWindowDuration: Double = 0
    private var boundaryTime: Double = 0

    public init() {}

    public var acceptedSampleCount: UInt64 { acceptedCount }
    public var rejectedSampleCount: UInt64 { rejectedCount }
    public var windowCount: UInt64 { rollingWindowCount }
    public var minimumWindowFrames: UInt64 { minimumFrames }
    public var lastWindowFrames: UInt64 { latestWindowFrames }
    public var lastWindowDurationSeconds: Double { lastWindowDuration }
    public var boundaryPresentedTime: Double { boundaryTime }
    public var lastPresentedTime: Double { presentedTimes.last ?? 0 }

    public mutating func ingest(_ presentedTime: Double) -> GEPresentationWindowSampleV6 {
        guard presentedTime.isFinite else {
            rejectedCount &+= 1
            return result(
                presentedTime: presentedTime,
                rejection: .nonFinite,
                emitted: false,
                windowDuration: 0,
                windowFrames: 0
            )
        }
        guard presentedTime > 0 else {
            rejectedCount &+= 1
            return result(
                presentedTime: presentedTime,
                rejection: .nonPositive,
                emitted: false,
                windowDuration: 0,
                windowFrames: 0
            )
        }
        if let previous = presentedTimes.last, presentedTime <= previous {
            rejectedCount &+= 1
            return result(
                presentedTime: presentedTime,
                rejection: .nonMonotonic,
                emitted: false,
                windowDuration: 0,
                windowFrames: 0
            )
        }

        presentedTimes.append(presentedTime)
        acceptedCount &+= 1
        if boundaryTime == 0 {
            boundaryTime = presentedTime
        }

        // The array is kept in ascending order.  Advance to the newest
        // boundary at least one second old, then remove only samples before
        // that boundary.  The boundary sample remains at index zero for the
        // next rolling window.
        var boundaryIndex = 0
        while boundaryIndex + 1 < presentedTimes.count,
              presentedTime - presentedTimes[boundaryIndex + 1]
                >= 1.0 - Self.boundaryEpsilonSeconds {
            boundaryIndex += 1
        }

        guard presentedTime - presentedTimes[boundaryIndex]
                >= 1.0 - Self.boundaryEpsilonSeconds else {
            return result(
                presentedTime: presentedTime,
                rejection: .none,
                emitted: false,
                windowDuration: 0,
                windowFrames: 0
            )
        }

        let boundary = presentedTimes[boundaryIndex]
        let frames = UInt64(presentedTimes.count - boundaryIndex - 1)
        let rawDuration = presentedTime - boundary
        // Keep the emitted contract at >= 1.0 seconds even when binary
        // representation leaves an exact one-second pair a few ulps short.
        let duration = max(1.0, rawDuration)
        boundaryTime = boundary
        latestWindowFrames = frames
        lastWindowDuration = duration
        rollingWindowCount &+= 1
        if rollingWindowCount == 1 || frames < minimumFrames {
            minimumFrames = frames
        }
        if boundaryIndex > 0 {
            presentedTimes.removeFirst(boundaryIndex)
        }
        return result(
            presentedTime: presentedTime,
            rejection: .none,
            emitted: true,
            windowDuration: duration,
            windowFrames: frames
        )
    }

    private func result(
        presentedTime: Double,
        rejection: GEPresentationWindowRejectionV6,
        emitted: Bool,
        windowDuration: Double,
        windowFrames: UInt64
    ) -> GEPresentationWindowSampleV6 {
        var flags: UInt16 = 0
        if rejection == .none {
            flags |= GEPresentationWindowSampleV6.acceptedFlag
        }
        if emitted {
            flags |= GEPresentationWindowSampleV6.emittedWindowFlag
        }
        let boundary = boundaryTime != 0 ? boundaryTime : presentedTimes.first ?? 0
        let hashInput = rejection == .none && presentedTime.isFinite
            ? [
                presentedTime.bitPattern,
                boundary.bitPattern,
                windowDuration.bitPattern,
                windowFrames,
                minimumFrames,
                rollingWindowCount,
                acceptedCount,
                rejectedCount
            ]
            : [
                UInt64(rejection.rawValue),
                acceptedCount,
                rejectedCount
            ]
        return GEPresentationWindowSampleV6(
            flags: flags,
            rejection: rejection,
            presentedTime: presentedTime,
            boundaryPresentedTime: boundary,
            windowDurationSeconds: windowDuration,
            windowFrames: windowFrames,
            minimumWindowFrames: minimumFrames,
            windowCount: rollingWindowCount,
            acceptedSampleCount: acceptedCount,
            rejectedSampleCount: rejectedCount,
            windowHash: GETimelineHashV6.fnv1a(hashInput)
        )
    }
}

@frozen public struct GERamRomCadenceV6: Sendable, Equatable {
    public static let authorityStepFlag: UInt16 = 1 << 0
    public static let previewFlag: UInt16 = 1 << 1
    public static let packetConsumeFlag: UInt16 = 1 << 2

    public let header: GETimelineAbiHeaderV6
    public let nativeTick: UInt64
    public let authorityNativeTick: UInt64
    public let authorityReferenceTick: UInt64
    public let pairPhase: UInt8
    public let flags: UInt16
    public let interpolationQ16: UInt32
    public let authorityHash: UInt64

    public init(
        nativeTick: UInt64,
        authorityNativeTick: UInt64,
        authorityReferenceTick: UInt64,
        pairPhase: UInt8,
        flags: UInt16,
        interpolationQ16: UInt32,
        authorityHash: UInt64
    ) {
        self.header = GETimelineAbiHeaderV6(
            structSize: UInt32(MemoryLayout<GERamRomCadenceV6>.size)
        )
        self.nativeTick = nativeTick
        self.authorityNativeTick = authorityNativeTick
        self.authorityReferenceTick = authorityReferenceTick
        self.pairPhase = pairPhase
        self.flags = flags
        self.interpolationQ16 = interpolationQ16
        self.authorityHash = authorityHash
    }

    public var isAuthorityStep: Bool { (flags & Self.authorityStepFlag) != 0 }
    public var isPreview: Bool { (flags & Self.previewFlag) != 0 }
    public var consumesPacket: Bool { (flags & Self.packetConsumeFlag) != 0 }
}

@frozen public struct GEPairedDeltaV6: Sendable, Equatable {
    public let firstStep: Int64
    public let secondStep: Int64

    public init(firstStep: Int64, secondStep: Int64) {
        self.firstStep = firstStep
        self.secondStep = secondStep
    }

    public var exactDelta: Int64 { firstStep &+ secondStep }
}

@frozen public struct GETimelineTickV6: Sendable, Equatable {
    public static let bootstrapFlag: UInt16 = 1 << 0
    public static let updateFlag: UInt16 = 1 << 1
    public static let referenceAnchorFlag: UInt16 = 1 << 2
    public static let previewFlag: UInt16 = 1 << 3
    public static let inputEdgesEligibleFlag: UInt16 = 1 << 4

    public let header: GETimelineAbiHeaderV6
    public let nativeTick: UInt64
    public let referenceTick: UInt64
    public let pairPhase: UInt8
    public let flags: UInt16
    public let audioSampleIndex: UInt64
    public let audioFrameCount: UInt64
    public let stateHash: UInt64
    public let eventHash: UInt64

    init(
        nativeTick: UInt64,
        referenceTick: UInt64,
        pairPhase: UInt8,
        flags: UInt16,
        audioSampleIndex: UInt64,
        audioFrameCount: UInt64
    ) {
        self.header = GETimelineAbiHeaderV6(
            structSize: UInt32(MemoryLayout<GETimelineTickV6>.size)
        )
        self.nativeTick = nativeTick
        self.referenceTick = referenceTick
        self.pairPhase = pairPhase
        self.flags = flags
        self.audioSampleIndex = audioSampleIndex
        self.audioFrameCount = audioFrameCount
        self.stateHash = GETimelineHashV6.tickStateHash(
            nativeTick: nativeTick,
            referenceTick: referenceTick,
            pairPhase: pairPhase,
            flags: flags,
            audioSampleIndex: audioSampleIndex,
            audioFrameCount: audioFrameCount
        )
        self.eventHash = GETimelineHashV6.tickEventHash(
            nativeTick: nativeTick,
            referenceTick: referenceTick,
            pairPhase: pairPhase,
            flags: flags
        )
    }

    public var isBootstrap: Bool { (flags & Self.bootstrapFlag) != 0 }
    public var isUpdate: Bool { (flags & Self.updateFlag) != 0 }
    public var isReferenceAnchor: Bool { (flags & Self.referenceAnchorFlag) != 0 }
    public var isPreview: Bool { (flags & Self.previewFlag) != 0 }
    public var inputEdgesEligible: Bool { (flags & Self.inputEdgesEligibleFlag) != 0 }
}

/// Namespaced static helpers keep all cadence conversions on the same
/// contract.  Callers should not maintain a second native/reference/audio
/// counter beside `GEAuthoritativeTimelineV6`.
public enum GESourceTimelineV6 {
    public static let nativeRate: UInt32 = 120
    public static let referenceRate: UInt32 = 60
    public static let pairSpan: UInt32 = 2
    public static let audioSampleRate: UInt32 = 22_050
    public static let audioSampleNumerator: UInt32 = 735
    public static let audioSampleDenominator: UInt32 = 4

    public static func referenceTick(forNativeTick nativeTick: UInt64) -> UInt64 {
        nativeTick >> 1
    }

    public static func pairPhase(forNativeTick nativeTick: UInt64) -> UInt8 {
        UInt8(nativeTick & 1)
    }

    public static func nativeTick(
        referenceTick: UInt64,
        pairPhase: UInt8
    ) -> UInt64? {
        guard pairPhase <= 1 else { return nil }
        let shifted = referenceTick.multipliedReportingOverflow(by: 2)
        guard !shifted.overflow else { return nil }
        let result = shifted.partialValue.addingReportingOverflow(UInt64(pairPhase))
        return result.overflow ? nil : result.partialValue
    }

    /// `floor(nativeTick * 735 / 4)` is the only audio cursor conversion.
    public static func audioSampleIndex(
        forNativeTick nativeTick: UInt64,
        config: GETimebaseConfigV6 = .goldenEye
    ) -> UInt64? {
        let product = nativeTick.multipliedReportingOverflow(by: UInt64(config.audioSampleNumerator))
        guard !product.overflow, config.audioSampleDenominator > 0 else { return nil }
        return product.partialValue / UInt64(config.audioSampleDenominator)
    }

    public static func audioFrameCount(
        forNativeTick nativeTick: UInt64,
        config: GETimebaseConfigV6 = .goldenEye
    ) -> UInt64? {
        // Tick 0 is bootstrap-only.  The first executed audio quantum belongs
        // to tick 1, so this is the difference between the current tick's
        // sample cursor and the preceding tick's cursor.
        guard nativeTick > 0,
              let current = audioSampleIndex(forNativeTick: nativeTick, config: config),
              let previous = audioSampleIndex(forNativeTick: nativeTick - 1, config: config) else {
            return nativeTick == 0 ? 0 : nil
        }
        guard current >= previous else {
            return nil
        }
        return current - previous
    }

    /// Splits one source-anchor delta into two native steps.  Truncation is
    /// toward zero and the second step is derived as the exact remainder, so
    /// `firstStep + secondStep == delta` for positive and negative odd values.
    public static func splitPairedDelta(_ delta: Int64) -> GEPairedDeltaV6 {
        let first = delta / 2
        return GEPairedDeltaV6(firstStep: first, secondStep: delta - first)
    }

    /// Returns the half-step for phase 1 and the exact source endpoint for
    /// phase 0.  A caller supplies immutable previous/current source anchors;
    /// this helper never accumulates a native value independently.
    public static func exactPairedContinuousValue(
        previousAnchor: Int64,
        currentAnchor: Int64,
        pairPhase: UInt8
    ) -> Int64? {
        guard pairPhase <= 1 else { return nil }
        guard pairPhase == 0 else {
            let delta = currentAnchor.subtractingReportingOverflow(previousAnchor)
            guard !delta.overflow else { return nil }
            let first = splitPairedDelta(delta.partialValue).firstStep
            let value = previousAnchor.addingReportingOverflow(first)
            return value.overflow ? nil : value.partialValue
        }
        return currentAnchor
    }

    /// Equivalent helper when the source anchor is represented as a start and
    /// a fixed delta.  Phase 0 is the exact endpoint; phase 1 is the first
    /// native half-step.
    public static func exactPairedContinuousValue(
        start: Int64,
        delta: Int64,
        pairPhase: UInt8
    ) -> Int64? {
        guard pairPhase <= 1 else { return nil }
        let step = pairPhase == 0 ? delta : splitPairedDelta(delta).firstStep
        let value = start.addingReportingOverflow(step)
        return value.overflow ? nil : value.partialValue
    }

    public static func compare(
        _ lhs: Int64,
        _ comparator: GEOriginalComparatorV6,
        _ rhs: Int64
    ) -> Bool {
        switch comparator {
        case .equal: return lhs == rhs
        case .notEqual: return lhs != rhs
        case .less: return lhs < rhs
        case .lessOrEqual: return lhs <= rhs
        case .greater: return lhs > rhs
        case .greaterOrEqual: return lhs >= rhs
        }
    }

    /// Finds the first source counter step at which the original comparator
    /// becomes true.  `postIncrement` models the common C idiom where the
    /// counter is incremented before its comparator is evaluated.
    public static func firstSourceStep(
        initialValue: Int64,
        increment: Int64,
        comparator: GEOriginalComparatorV6,
        target: Int64,
        postIncrement: Bool,
        maximumSteps: UInt64 = 1_000_000
    ) -> Result<UInt64, GETimelineDiagnosticV6> {
        guard maximumSteps > 0 else {
            return .failure(GETimelineDiagnosticV6(
                code: .comparatorNotReached,
                context: .comparator,
                expected: 1,
                actual: 0
            ))
        }

        var index: UInt64 = postIncrement ? 1 : 0
        while index <= maximumSteps {
            let multiplier = Int64(index)
            let product = increment.multipliedReportingOverflow(by: multiplier)
            guard !product.overflow else {
                return .failure(GETimelineDiagnosticV6(
                    code: .comparatorOverflow,
                    context: .comparator,
                    expected: UInt64.max,
                    actual: index
                ))
            }
            let value = initialValue.addingReportingOverflow(product.partialValue)
            guard !value.overflow else {
                return .failure(GETimelineDiagnosticV6(
                    code: .comparatorOverflow,
                    context: .comparator,
                    expected: UInt64.max,
                    actual: index
                ))
            }
            if compare(value.partialValue, comparator, target) {
                return .success(index)
            }
            if index == maximumSteps { break }
            index += 1
        }
        return .failure(GETimelineDiagnosticV6(
            code: .comparatorNotReached,
            context: .comparator,
            expected: maximumSteps,
            actual: 0
        ))
    }

    /// Converts a source comparator step into a native tick while retaining
    /// strict ordering.  `previewHalfStep` maps source step N to `2*N - 1`;
    /// `referenceAnchor` maps it to `2*N`.
    public static func nativeTickForSourceComparator(
        initialValue: Int64,
        increment: Int64,
        comparator: GEOriginalComparatorV6,
        target: Int64,
        postIncrement: Bool,
        evaluationPhase: GEComparatorEvaluationPhaseV6 = .referenceAnchor,
        maximumSteps: UInt64 = 1_000_000
    ) -> Result<UInt64, GETimelineDiagnosticV6> {
        switch firstSourceStep(
            initialValue: initialValue,
            increment: increment,
            comparator: comparator,
            target: target,
            postIncrement: postIncrement,
            maximumSteps: maximumSteps
        ) {
        case let .failure(diagnostic):
            return .failure(diagnostic)
        case let .success(sourceStep):
            let scaled = sourceStep.multipliedReportingOverflow(by: 2)
            guard !scaled.overflow else {
                return .failure(GETimelineDiagnosticV6(
                    code: .comparatorOverflow,
                    context: .comparator,
                    expected: UInt64.max,
                    actual: sourceStep
                ))
            }
            if evaluationPhase == .referenceAnchor {
                return .success(scaled.partialValue)
            }
            guard scaled.partialValue > 0 else {
                return .failure(GETimelineDiagnosticV6(
                    code: .invalidPairPhase,
                    context: .pairing,
                    expected: 1,
                    actual: 0
                ))
            }
            return .success(scaled.partialValue - 1)
        }
    }

    public static func inputEdgeDecision(
        event: GEInputEventV6,
        at tick: GETimelineTickV6
    ) -> GEInputEdgeDecisionV6 {
        let code: GEInputDecisionCodeV6
        if !tick.inputEdgesEligible {
            code = .bootstrapNotEligible
        } else if event.capturedNativeTick > tick.nativeTick {
            code = .futureEvent
        } else if !event.focused {
            code = .unfocused
        } else if !event.controllerConnected {
            code = .controllerDisconnected
        } else {
            code = .accepted
        }
        return GEInputEdgeDecisionV6(
            sequence: event.sequence,
            nativeTick: tick.nativeTick,
            code: code
        )
    }

    public static func frameSelection(
        for tick: GETimelineTickV6,
        mode: GEPresentationModeV6
    ) -> GEFrameSelectionV6 {
        switch mode {
        case .native120:
            var flags = GEFrameSelectionV6.newSnapshotFlag
            if tick.isPreview { flags |= GEFrameSelectionV6.interpolatedFlag }
            return GEFrameSelectionV6(
                mode: mode,
                pairPhase: tick.pairPhase,
                flags: flags,
                nativeTick: tick.nativeTick,
                selectedNativeTick: tick.nativeTick,
                sourceReferenceTick: tick.referenceTick,
                interpolationQ16: tick.isPreview ? 32_768 : 0
            )
        case .fixed60:
            let selectedNativeTick = tick.nativeTick - UInt64(tick.pairPhase)
            let isNew = tick.pairPhase == 0
            let flags: UInt16 = isNew ? GEFrameSelectionV6.newSnapshotFlag : GEFrameSelectionV6.fixed60RepeatFlag
            return GEFrameSelectionV6(
                mode: mode,
                pairPhase: tick.pairPhase,
                flags: flags,
                nativeTick: tick.nativeTick,
                selectedNativeTick: selectedNativeTick,
                sourceReferenceTick: selectedNativeTick >> 1,
                interpolationQ16: 0
            )
        }
    }

    public static func ramRomCadence(for tick: GETimelineTickV6) -> GERamRomCadenceV6 {
        let authorityNativeTick = tick.nativeTick - UInt64(tick.pairPhase)
        let authorityReferenceTick = authorityNativeTick >> 1
        var flags: UInt16 = 0
        if tick.isReferenceAnchor {
            flags |= GERamRomCadenceV6.authorityStepFlag
            flags |= GERamRomCadenceV6.packetConsumeFlag
        }
        if tick.isPreview {
            flags |= GERamRomCadenceV6.previewFlag
        }
        return GERamRomCadenceV6(
            nativeTick: tick.nativeTick,
            authorityNativeTick: authorityNativeTick,
            authorityReferenceTick: authorityReferenceTick,
            pairPhase: tick.pairPhase,
            flags: flags,
            interpolationQ16: tick.isPreview ? 32_768 : 0,
            authorityHash: GETimelineHashV6.ramRomAuthorityHash(
                authorityNativeTick: authorityNativeTick,
                authorityReferenceTick: authorityReferenceTick,
                flags: flags
            )
        )
    }
}

/// The sole mutable tick owner for V6.  Bootstrap emits tick 0; the first call
/// to `advance()` emits tick 1.  `nextNativeTick` is the only counter, and all
/// reference/audio/presentation metadata is derived from that value.
public struct GEAuthoritativeTimelineV6: Sendable {
    public let configuration: GETimebaseConfigV6
    private var nextNativeTick: UInt64?
    public private(set) var diagnostic: GETimelineDiagnosticV6

    public init(configuration: GETimebaseConfigV6 = .goldenEye) {
        precondition(configuration.isValid, configuration.validationDiagnostic?.description ?? "invalid V6 configuration")
        self.configuration = configuration
        self.nextNativeTick = nil
        self.diagnostic = .none
    }

    public init(validating configuration: GETimebaseConfigV6) throws {
        if let diagnostic = configuration.validationDiagnostic {
            throw diagnostic
        }
        self.configuration = configuration
        self.nextNativeTick = nil
        self.diagnostic = .none
    }

    public var hasBootstrapped: Bool { nextNativeTick != nil }

    public var currentNativeTick: UInt64? {
        guard let nextNativeTick else { return nil }
        return nextNativeTick == 0 ? nil : nextNativeTick - 1
    }

    public var nextTickToEmit: UInt64? { nextNativeTick }

    public mutating func bootstrap() throws -> GETimelineTickV6 {
        guard !diagnostic.isFailure else { throw diagnostic }
        guard nextNativeTick == nil else {
            try fail(
                code: .bootstrapRepeated,
                context: .bootstrap,
                expected: 0,
                actual: currentNativeTick ?? 0
            )
        }
        nextNativeTick = 1
        return try makeTick(nativeTick: 0)
    }

    public mutating func advance() throws -> GETimelineTickV6 {
        guard !diagnostic.isFailure else { throw diagnostic }
        guard let nativeTick = nextNativeTick else {
            try fail(
                code: .advanceBeforeBootstrap,
                context: .advance,
                expected: 1,
                actual: 0
            )
        }
        guard nativeTick < UInt64.max else {
            try fail(
                code: .tickOverflow,
                context: .advance,
                expected: UInt64.max - 1,
                actual: nativeTick
            )
        }
        let tick = try makeTick(nativeTick: nativeTick)
        nextNativeTick = nativeTick + 1
        return tick
    }

    private mutating func makeTick(nativeTick: UInt64) throws -> GETimelineTickV6 {
        guard let sampleIndex = GESourceTimelineV6.audioSampleIndex(
            forNativeTick: nativeTick,
            config: configuration
        ), let frameCount = GESourceTimelineV6.audioFrameCount(
            forNativeTick: nativeTick,
            config: configuration
        ) else {
            try fail(
                code: .audioOverflow,
                context: .audio,
                nativeTick: nativeTick,
                referenceTick: GESourceTimelineV6.referenceTick(forNativeTick: nativeTick),
                expected: UInt64.max,
                actual: nativeTick
            )
        }

        let referenceTick = GESourceTimelineV6.referenceTick(forNativeTick: nativeTick)
        let pairPhase = GESourceTimelineV6.pairPhase(forNativeTick: nativeTick)
        var flags: UInt16 = 0
        if nativeTick == 0 {
            flags |= GETimelineTickV6.bootstrapFlag
        } else {
            flags |= GETimelineTickV6.updateFlag
            flags |= GETimelineTickV6.inputEdgesEligibleFlag
            if pairPhase == 0 {
                flags |= GETimelineTickV6.referenceAnchorFlag
            } else {
                flags |= GETimelineTickV6.previewFlag
            }
        }
        return GETimelineTickV6(
            nativeTick: nativeTick,
            referenceTick: referenceTick,
            pairPhase: pairPhase,
            flags: flags,
            audioSampleIndex: sampleIndex,
            audioFrameCount: frameCount
        )
    }

    private mutating func fail(
        code: GETimelineFailureCodeV6,
        context: GETimelineFailureContextV6,
        nativeTick: UInt64 = 0,
        referenceTick: UInt64 = 0,
        expected: UInt64,
        actual: UInt64
    ) throws -> Never {
        let failure = GETimelineDiagnosticV6(
            code: code,
            context: context,
            nativeTick: nativeTick,
            referenceTick: referenceTick,
            expected: expected,
            actual: actual
        )
        diagnostic = failure
        throw failure
    }
}

public enum GETimelineHashV6 {
    public static let offsetBasis: UInt64 = 0xcbf29ce484222325
    public static let prime: UInt64 = 0x100000001b3

    public static func fnv1a(_ words: [UInt64]) -> UInt64 {
        var hash = offsetBasis
        for word in words {
            var littleEndian = word.littleEndian
            withUnsafeBytes(of: &littleEndian) { bytes in
                for byte in bytes {
                    hash ^= UInt64(byte)
                    hash &*= prime
                }
            }
        }
        return hash
    }

    public static func tickStateHash(
        nativeTick: UInt64,
        referenceTick: UInt64,
        pairPhase: UInt8,
        flags: UInt16,
        audioSampleIndex: UInt64,
        audioFrameCount: UInt64
    ) -> UInt64 {
        fnv1a([
            UInt64(GETimelineAbiHeaderV6.contractVersion),
            nativeTick,
            referenceTick,
            UInt64(pairPhase),
            UInt64(flags),
            audioSampleIndex,
            audioFrameCount
        ])
    }

    public static func tickEventHash(
        nativeTick: UInt64,
        referenceTick: UInt64,
        pairPhase: UInt8,
        flags: UInt16
    ) -> UInt64 {
        fnv1a([
            UInt64(GETimelineAbiHeaderV6.contractVersion),
            nativeTick,
            referenceTick,
            UInt64(pairPhase),
            UInt64(flags)
        ])
    }

    public static func ramRomAuthorityHash(
        authorityNativeTick: UInt64,
        authorityReferenceTick: UInt64,
        flags: UInt16
    ) -> UInt64 {
        fnv1a([
            UInt64(GETimelineAbiHeaderV6.contractVersion),
            authorityNativeTick,
            authorityReferenceTick,
            UInt64(flags)
        ])
    }
}
