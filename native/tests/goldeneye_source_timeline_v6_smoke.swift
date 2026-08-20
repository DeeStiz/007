import Foundation

@main
struct GoldenEyeSourceTimelineV6Smoke {
    static func main() throws {
        let configuration = GETimebaseConfigV6.goldenEye
        precondition(configuration.isValid)
        precondition(configuration.header.reserved == 0)
        precondition(configuration.header.structSize == UInt32(MemoryLayout<GETimebaseConfigV6>.size))

        var timeline = GEAuthoritativeTimelineV6(configuration: configuration)
        precondition(timeline.currentNativeTick == nil)
        precondition(timeline.nextTickToEmit == nil)

        let bootstrap = try timeline.bootstrap()
        precondition(bootstrap.nativeTick == 0)
        precondition(bootstrap.referenceTick == 0)
        precondition(bootstrap.pairPhase == 0)
        precondition(bootstrap.isBootstrap)
        precondition(!bootstrap.isUpdate)
        precondition(!bootstrap.isReferenceAnchor)
        precondition(!bootstrap.inputEdgesEligible)
        precondition(bootstrap.audioSampleIndex == 0)
        precondition(bootstrap.audioFrameCount == 0)
        precondition(timeline.currentNativeTick == 0)
        precondition(timeline.nextTickToEmit == 1)

        var ticks = [bootstrap]
        for _ in 0..<8 {
            ticks.append(try timeline.advance())
        }
        precondition(ticks[1].nativeTick == 1)
        precondition(ticks[1].isUpdate)
        precondition(ticks[1].isPreview)
        precondition(ticks[1].inputEdgesEligible)
        precondition(!ticks[1].isReferenceAnchor)
        precondition(ticks[2].nativeTick == 2)
        precondition(ticks[2].referenceTick == 1)
        precondition(ticks[2].isReferenceAnchor)

        for tick in ticks {
            precondition(tick.referenceTick == GESourceTimelineV6.referenceTick(forNativeTick: tick.nativeTick))
            precondition(tick.pairPhase == GESourceTimelineV6.pairPhase(forNativeTick: tick.nativeTick))
            precondition(GESourceTimelineV6.nativeTick(
                referenceTick: tick.referenceTick,
                pairPhase: tick.pairPhase
            ) == tick.nativeTick)
        }

        let expectedSamples: [UInt64] = [0, 183, 367, 551, 735, 918, 1102, 1286, 1470]
        let expectedFrames: [UInt64] = [0, 183, 184, 184, 184, 183, 184, 184, 184]
        for (index, tick) in ticks.enumerated() {
            precondition(tick.audioSampleIndex == expectedSamples[index])
            precondition(tick.audioFrameCount == expectedFrames[index])
        }

        var repeatTimeline = GEAuthoritativeTimelineV6(configuration: configuration)
        var repeatTicks = [try repeatTimeline.bootstrap()]
        for _ in 0..<8 {
            repeatTicks.append(try repeatTimeline.advance())
        }
        precondition(ticks == repeatTicks)
        precondition(ticks.map(\.stateHash) == repeatTicks.map(\.stateHash))
        precondition(ticks.map(\.eventHash) == repeatTicks.map(\.eventHash))

        for delta in [-5, -3, -1, 0, 1, 3, 5] as [Int64] {
            let pair = GESourceTimelineV6.splitPairedDelta(delta)
            precondition(pair.exactDelta == delta)
            let start: Int64 = 100
            let midpoint = GESourceTimelineV6.exactPairedContinuousValue(
                start: start,
                delta: delta,
                pairPhase: 1
            )
            let endpoint = GESourceTimelineV6.exactPairedContinuousValue(
                start: start,
                delta: delta,
                pairPhase: 0
            )
            precondition(midpoint == start + pair.firstStep)
            precondition(endpoint == start + delta)
            precondition(GESourceTimelineV6.exactPairedContinuousValue(
                previousAnchor: start,
                currentAnchor: start + delta,
                pairPhase: 0
            ) == endpoint)
        }
        precondition(GESourceTimelineV6.exactPairedContinuousValue(
            start: 0,
            delta: 1,
            pairPhase: 2
        ) == nil)

        precondition(GESourceTimelineV6.compare(3, .less, 4))
        precondition(GESourceTimelineV6.compare(4, .lessOrEqual, 4))
        precondition(GESourceTimelineV6.compare(4, .greater, 3))
        precondition(GESourceTimelineV6.compare(4, .greaterOrEqual, 4))
        precondition(GESourceTimelineV6.compare(4, .equal, 4))
        precondition(GESourceTimelineV6.compare(4, .notEqual, 5))

        let legalThreshold = try nativeThreshold(
            initialValue: 0,
            increment: 1,
            comparator: .greaterOrEqual,
            target: 241,
            postIncrement: true,
            phase: .referenceAnchor
        )
        precondition(legalThreshold == 482)

        let strictCastThreshold = try nativeThreshold(
            initialValue: 0,
            increment: 1,
            comparator: .greater,
            target: 180,
            postIncrement: true,
            phase: .previewHalfStep
        )
        precondition(strictCastThreshold == 361)

        let strictSecondaryThreshold = try nativeThreshold(
            initialValue: 0,
            increment: 1,
            comparator: .greater,
            target: 90,
            postIncrement: true,
            phase: .previewHalfStep
        )
        precondition(strictSecondaryThreshold == 181)

        let castThreshold = try nativeThreshold(
            initialValue: 0,
            increment: 1,
            comparator: .greaterOrEqual,
            target: 181,
            postIncrement: true,
            phase: .referenceAnchor
        )
        precondition(castThreshold == 362)

        let gunbarrelThreshold = try nativeThreshold(
            initialValue: 20,
            increment: -1,
            comparator: .less,
            target: 0,
            postIncrement: true,
            phase: .referenceAnchor
        )
        precondition(gunbarrelThreshold == 42)

        let input = GEInputEventV6(
            sequence: 7,
            capturedNativeTick: 1,
            held: 0x01,
            pressed: 0x01,
            released: 0
        )
        precondition(GESourceTimelineV6.inputEdgeDecision(event: input, at: ticks[0]).code == .bootstrapNotEligible)
        precondition(GESourceTimelineV6.inputEdgeDecision(event: input, at: ticks[1]).code == .accepted)
        let futureInput = GEInputEventV6(sequence: 8, capturedNativeTick: 3, pressed: 1)
        precondition(GESourceTimelineV6.inputEdgeDecision(event: futureInput, at: ticks[1]).code == .futureEvent)
        let unfocusedInput = GEInputEventV6(sequence: 9, capturedNativeTick: 1, pressed: 1, focused: false)
        precondition(GESourceTimelineV6.inputEdgeDecision(event: unfocusedInput, at: ticks[1]).code == .unfocused)
        let disconnectedInput = GEInputEventV6(sequence: 10, capturedNativeTick: 1, pressed: 1, controllerConnected: false)
        precondition(GESourceTimelineV6.inputEdgeDecision(event: disconnectedInput, at: ticks[1]).code == .controllerDisconnected)

        let nativePreview = GESourceTimelineV6.frameSelection(for: ticks[3], mode: .native120)
        precondition(nativePreview.selectedNativeTick == 3)
        precondition(nativePreview.sourceReferenceTick == 1)
        precondition(nativePreview.presentsNewSnapshot)
        precondition(nativePreview.interpolatesContinuousState)
        precondition(nativePreview.interpolationQ16 == 32_768)

        let fixedAnchor = GESourceTimelineV6.frameSelection(for: ticks[2], mode: .fixed60)
        precondition(fixedAnchor.selectedNativeTick == 2)
        precondition(fixedAnchor.presentsNewSnapshot)
        precondition(!fixedAnchor.repeatsPreviousSnapshot)
        let fixedRepeat = GESourceTimelineV6.frameSelection(for: ticks[3], mode: .fixed60)
        precondition(fixedRepeat.selectedNativeTick == 2)
        precondition(!fixedRepeat.presentsNewSnapshot)
        precondition(fixedRepeat.repeatsPreviousSnapshot)
        precondition(!fixedRepeat.interpolatesContinuousState)

        let ramromBootstrap = GESourceTimelineV6.ramRomCadence(for: ticks[0])
        precondition(!ramromBootstrap.isAuthorityStep)
        precondition(!ramromBootstrap.consumesPacket)
        let ramromAnchor = GESourceTimelineV6.ramRomCadence(for: ticks[2])
        precondition(ramromAnchor.isAuthorityStep)
        precondition(ramromAnchor.consumesPacket)
        precondition(ramromAnchor.authorityNativeTick == 2)
        precondition(ramromAnchor.authorityReferenceTick == 1)
        let ramromPreview = GESourceTimelineV6.ramRomCadence(for: ticks[3])
        precondition(ramromPreview.isPreview)
        precondition(!ramromPreview.isAuthorityStep)
        precondition(ramromPreview.authorityNativeTick == 2)
        precondition(ramromPreview.authorityReferenceTick == 1)
        precondition(ramromPreview.interpolationQ16 == 32_768)

        var beforeBootstrap = GEAuthoritativeTimelineV6(configuration: configuration)
        do {
            _ = try beforeBootstrap.advance()
            preconditionFailure("advance before bootstrap unexpectedly succeeded")
        } catch let diagnostic as GETimelineDiagnosticV6 {
            precondition(diagnostic.code == .advanceBeforeBootstrap)
            precondition(beforeBootstrap.diagnostic == diagnostic)
        }

        var repeatedBootstrap = GEAuthoritativeTimelineV6(configuration: configuration)
        _ = try repeatedBootstrap.bootstrap()
        do {
            _ = try repeatedBootstrap.bootstrap()
            preconditionFailure("repeated bootstrap unexpectedly succeeded")
        } catch let diagnostic as GETimelineDiagnosticV6 {
            precondition(diagnostic.code == .bootstrapRepeated)
            precondition(repeatedBootstrap.diagnostic == diagnostic)
        }

        let malformed = GETimebaseConfigV6(
            nativeRateNumerator: 60,
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
        do {
            _ = try GEAuthoritativeTimelineV6(validating: malformed)
            preconditionFailure("malformed configuration unexpectedly succeeded")
        } catch let diagnostic as GETimelineDiagnosticV6 {
            precondition(diagnostic.code == .invalidConfiguration)
        }

        switch GESourceTimelineV6.firstSourceStep(
            initialValue: 0,
            increment: 1,
            comparator: .greater,
            target: 10,
            postIncrement: true,
            maximumSteps: 4
        ) {
        case .success:
            preconditionFailure("bounded comparator unexpectedly reached")
        case let .failure(diagnostic):
            precondition(diagnostic.code == .comparatorNotReached)
        }

        var exact120 = GEPresentationWindowAccumulatorV6()
        var exact120Emissions: [GEPresentationWindowSampleV6] = []
        for index in 1...241 {
            let sample = exact120.ingest(Double(index) / 120.0)
            if sample.emittedWindow {
                exact120Emissions.append(sample)
            }
        }
        precondition(exact120Emissions.count == 121)
        precondition(exact120Emissions.allSatisfy { $0.windowFrames == 120 })
        precondition(exact120.minimumWindowFrames == 120)
        precondition(exact120.windowCount == 121)
        precondition(exact120Emissions.first?.windowDurationSeconds ?? 0 >= 1.0)
        precondition(
            exact120Emissions.first?.boundaryPresentedTime == (1.0 / 120.0)
        )
        precondition(
            exact120.boundaryPresentedTime == (121.0 / 120.0)
        )

        var exact60 = GEPresentationWindowAccumulatorV6()
        var exact60Emissions: [GEPresentationWindowSampleV6] = []
        for index in 1...121 {
            let sample = exact60.ingest(Double(index) / 60.0)
            if sample.emittedWindow {
                exact60Emissions.append(sample)
            }
        }
        precondition(exact60Emissions.count == 61)
        precondition(exact60Emissions.allSatisfy { $0.windowFrames == 60 })
        precondition(exact60.minimumWindowFrames == 60)
        precondition(exact60.windowCount == 61)
        precondition(exact60Emissions.first?.windowDurationSeconds ?? 0 >= 1.0)

        var jittered = GEPresentationWindowAccumulatorV6()
        var jitterEmissions: [GEPresentationWindowSampleV6] = []
        var firstJitterSample = 0.0
        for index in 1...121 {
            let adjustment = index.isMultiple(of: 2) ? 0.00009 : -0.00009
            let time = Double(index) / 120.0 + adjustment
            if index == 1 { firstJitterSample = time }
            let sample = jittered.ingest(time)
            if sample.emittedWindow {
                jitterEmissions.append(sample)
            }
        }
        precondition(!jitterEmissions.isEmpty)
        precondition(jitterEmissions.first?.windowFrames == 120)
        precondition(jitterEmissions.first?.windowDurationSeconds ?? 0 >= 1.0)
        precondition(jitterEmissions.first?.boundaryPresentedTime == firstJitterSample)
        precondition(jittered.minimumWindowFrames == 120)

        // A one-second boundary must not require a hard-coded 120-sample
        // minimum.  This sparse pair proves the old unreachable-window logic
        // cannot recur on a fixed-60 or sparse presented-time stream.
        var sparse = GEPresentationWindowAccumulatorV6()
        precondition(!sparse.ingest(0.5).emittedWindow)
        let sparseWindow = sparse.ingest(1.5)
        precondition(sparseWindow.emittedWindow)
        precondition(sparseWindow.windowFrames == 1)
        precondition(sparseWindow.windowDurationSeconds >= 1.0)
        precondition(sparse.boundaryPresentedTime == 0.5)

        var rejected = GEPresentationWindowAccumulatorV6()
        let zero = rejected.ingest(0)
        let infinity = rejected.ingest(.infinity)
        let firstValid = rejected.ingest(1)
        let duplicate = rejected.ingest(1)
        let older = rejected.ingest(0.5)
        precondition(zero.rejection == .nonPositive && !zero.accepted)
        precondition(infinity.rejection == .nonFinite && !infinity.accepted)
        precondition(firstValid.accepted)
        precondition(duplicate.rejection == .nonMonotonic && !duplicate.accepted)
        precondition(older.rejection == .nonMonotonic && !older.accepted)
        precondition(rejected.acceptedSampleCount == 1)
        precondition(rejected.rejectedSampleCount == 4)
        precondition(rejected.windowCount == 0)

        var repeatWindow = GEPresentationWindowAccumulatorV6()
        var repeatEvents: [GEPresentationWindowSampleV6] = []
        for index in 1...121 {
            let adjustment = index.isMultiple(of: 2) ? 0.00009 : -0.00009
            let event = repeatWindow.ingest(Double(index) / 120.0 + adjustment)
            repeatEvents.append(event)
        }
        precondition(jittered == repeatWindow)
        precondition(jitterEmissions == repeatEvents.filter(\.emittedWindow))

        print(
            "goldeneye_source_timeline_v6_smoke: PASS "
                + "ticks=\(ticks.count) "
                + "audio=\(ticks.last?.audioSampleIndex ?? 0) "
                + "stateHash=\(String(ticks.last?.stateHash ?? 0, radix: 16)) "
                + "fixed60=verified ramrom=verified windows=120,60,jitter diagnostics=verified"
        )
    }

    private static func nativeThreshold(
        initialValue: Int64,
        increment: Int64,
        comparator: GEOriginalComparatorV6,
        target: Int64,
        postIncrement: Bool,
        phase: GEComparatorEvaluationPhaseV6
    ) throws -> UInt64 {
        switch GESourceTimelineV6.nativeTickForSourceComparator(
            initialValue: initialValue,
            increment: increment,
            comparator: comparator,
            target: target,
            postIncrement: postIncrement,
            evaluationPhase: phase
        ) {
        case let .success(value): return value
        case let .failure(diagnostic): throw diagnostic
        }
    }
}
