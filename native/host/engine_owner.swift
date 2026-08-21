import Darwin
import Foundation
import QuartzCore

/// The fixed-rate clock used by the native GoldenEye owner.  The clock is
/// deliberately independent from display refresh; CAMetalDisplayLink only
/// supplies presentation opportunities.
enum GE120RawClock {
    static func nowNanoseconds() -> UInt64 {
        clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
    }
}

struct GE120TimebaseConfiguration: Sendable {
    let nativeRateNumerator: UInt32
    let nativeRateDenominator: UInt32
    let referenceRateNumerator: UInt32
    let referenceRateDenominator: UInt32
    let maxCatchUpTicks: UInt32
    let maxDebtTicks: UInt64

    static let goldenEye = GE120TimebaseConfiguration(
        nativeRateNumerator: 120,
        nativeRateDenominator: 1,
        referenceRateNumerator: 60,
        referenceRateDenominator: 1,
        maxCatchUpTicks: 4,
        maxDebtTicks: 240
    )

    init(
        nativeRateNumerator: UInt32,
        nativeRateDenominator: UInt32,
        referenceRateNumerator: UInt32,
        referenceRateDenominator: UInt32,
        maxCatchUpTicks: UInt32,
        maxDebtTicks: UInt64
    ) {
        precondition(nativeRateNumerator > 0 && nativeRateDenominator > 0)
        precondition(referenceRateNumerator > 0 && referenceRateDenominator > 0)
        precondition(maxCatchUpTicks > 0)
        precondition(maxDebtTicks >= UInt64(maxCatchUpTicks))
        self.nativeRateNumerator = nativeRateNumerator
        self.nativeRateDenominator = nativeRateDenominator
        self.referenceRateNumerator = referenceRateNumerator
        self.referenceRateDenominator = referenceRateDenominator
        self.maxCatchUpTicks = maxCatchUpTicks
        self.maxDebtTicks = maxDebtTicks
    }
}

struct GE120Tick: Sendable, Equatable {
    let nativeTick: UInt64
    let referenceTick: UInt64
    let pairPhase: UInt8
    let scheduledNanoseconds: UInt64
    let sampledNanoseconds: UInt64
    let latenessNanoseconds: UInt64

    var isReferenceAnchor: Bool { pairPhase == 0 }
}

struct GE120SchedulerTelemetry: Sendable {
    let measurementEpochNanoseconds: UInt64
    let wakeCount: UInt64
    let emittedTickCount: UInt64
    let lateWakeCount: UInt64
    let catchUpBatchCount: UInt64
    let catchUpTickCount: UInt64
    let maximumLatenessNanoseconds: UInt64
    let maximumDebtTicks: UInt64
    let pauseCount: UInt64
    let resumeCount: UInt64
    let rebaseCount: UInt64
    let fatalDebtTicks: UInt64
    let firstScheduledNanoseconds: UInt64
    let lastScheduledNanoseconds: UInt64
    let firstSampledNanoseconds: UInt64
    let lastSampledNanoseconds: UInt64
    let droppedTickCount: UInt64
    let paused: Bool
    let nextNativeTick: UInt64
}

enum GE120SchedulerError: Error, CustomStringConvertible {
    case deadlineDebtExceeded(UInt64)
    case arithmeticOverflow

    var description: String {
        switch self {
        case .deadlineDebtExceeded(let debt):
            return "GE120 scheduler deadline debt exceeded limit: \(debt) ticks"
        case .arithmeticOverflow:
            return "GE120 scheduler rational deadline arithmetic overflow"
        }
    }
}

/// Exact rational 120 Hz scheduler.  It never drops due ticks: the owner
/// emits at most `maxCatchUpTicks` on one wake and continues from the next
/// deadline on the following wake.  Debt over the configured hard limit is a
/// fatal evidence condition rather than a silent simulation skip.
struct GE120FixedRateScheduler {
    private let configuration: GE120TimebaseConfiguration
    private let periodNumerator: UInt64
    private let periodDenominator: UInt64
    private var epochNanoseconds: UInt64?
    private var measurementEpochNanoseconds: UInt64 = 0
    private var nextNativeTick: UInt64 = 0
    private var paused = false

    private var wakeCount: UInt64 = 0
    private var emittedTickCount: UInt64 = 0
    private var lateWakeCount: UInt64 = 0
    private var catchUpBatchCount: UInt64 = 0
    private var catchUpTickCount: UInt64 = 0
    private var maximumLatenessNanoseconds: UInt64 = 0
    private var maximumDebtTicks: UInt64 = 0
    private var pauseCount: UInt64 = 0
    private var resumeCount: UInt64 = 0
    private var rebaseCount: UInt64 = 0
    private var fatalDebtTicks: UInt64 = 0
    private var firstScheduledNanoseconds: UInt64 = 0
    private var lastScheduledNanoseconds: UInt64 = 0
    private var firstSampledNanoseconds: UInt64 = 0
    private var lastSampledNanoseconds: UInt64 = 0

    init(configuration: GE120TimebaseConfiguration = .goldenEye) {
        self.configuration = configuration
        self.periodNumerator = UInt64(configuration.nativeRateDenominator) * 1_000_000_000
        self.periodDenominator = UInt64(configuration.nativeRateNumerator)
    }

    var nextTick: UInt64 { nextNativeTick }
    var isPaused: Bool { paused }

    mutating func start(atNanoseconds now: UInt64) {
        precondition(epochNanoseconds == nil, "GE120 scheduler may only start once")
        epochNanoseconds = now
        measurementEpochNanoseconds = now
        nextNativeTick = 0
        paused = false
    }

    /// Reset only measurement counters while retaining the authoritative
    /// source tick and rational deadline series. This is called exclusively
    /// on the owner thread after a cadence warmup, so no tick can be silently
    /// skipped or counted in both epochs.
    mutating func resetMeasurementTelemetry(atNanoseconds now: UInt64) {
        measurementEpochNanoseconds = now
        wakeCount = 0
        emittedTickCount = 0
        lateWakeCount = 0
        catchUpBatchCount = 0
        catchUpTickCount = 0
        maximumLatenessNanoseconds = 0
        maximumDebtTicks = 0
        fatalDebtTicks = 0
        firstScheduledNanoseconds = 0
        lastScheduledNanoseconds = 0
        firstSampledNanoseconds = 0
        lastSampledNanoseconds = 0
        // Dropped ticks are structurally impossible in this scheduler, but
        // keep this assignment explicit so a future implementation cannot
        // leak an earlier epoch into a bounded acceptance report.
        // `droppedTickCount` is a derived zero in telemetry today.
    }

    mutating func poll(atNanoseconds now: UInt64) throws -> [GE120Tick] {
        guard let epochNanoseconds else {
            preconditionFailure("GE120 scheduler must start before polling")
        }
        wakeCount &+= 1
        guard !paused else { return [] }

        let firstDeadline = try deadline(for: nextNativeTick, epoch: epochNanoseconds)
        guard now >= firstDeadline else { return [] }

        let debt = try dueTickCount(atNanoseconds: now, epoch: epochNanoseconds)
        maximumDebtTicks = max(maximumDebtTicks, debt)
        if debt > configuration.maxDebtTicks {
            fatalDebtTicks = debt
            throw GE120SchedulerError.deadlineDebtExceeded(debt)
        }

        let emitCount = min(UInt64(configuration.maxCatchUpTicks), debt)
        if emitCount > 1 {
            catchUpBatchCount &+= 1
            catchUpTickCount &+= emitCount - 1
        }
        if now > firstDeadline {
            let lateness = now - firstDeadline
            maximumLatenessNanoseconds = max(maximumLatenessNanoseconds, lateness)
            if lateness >= 1_000_000 {
                lateWakeCount &+= 1
            }
        }

        var ticks: [GE120Tick] = []
        ticks.reserveCapacity(Int(emitCount))
        for _ in 0..<emitCount {
            let nativeTick = nextNativeTick
            let scheduledNanoseconds = try deadline(for: nativeTick, epoch: epochNanoseconds)
            let lateness = now >= scheduledNanoseconds ? now - scheduledNanoseconds : 0
            if firstScheduledNanoseconds == 0 { firstScheduledNanoseconds = scheduledNanoseconds }
            lastScheduledNanoseconds = scheduledNanoseconds
            if firstSampledNanoseconds == 0 { firstSampledNanoseconds = now }
            lastSampledNanoseconds = now
            ticks.append(
                GE120Tick(
                    nativeTick: nativeTick,
                    referenceTick: nativeTick >> 1,
                    pairPhase: UInt8(nativeTick & 1),
                    scheduledNanoseconds: scheduledNanoseconds,
                    sampledNanoseconds: now,
                    latenessNanoseconds: lateness
                )
            )
            let nextTick = nextNativeTick.addingReportingOverflow(1)
            guard !nextTick.overflow else { throw GE120SchedulerError.arithmeticOverflow }
            nextNativeTick = nextTick.partialValue
            emittedTickCount &+= 1
        }
        return ticks
    }

    mutating func setPaused(_ requested: Bool, atNanoseconds now: UInt64) throws {
        guard paused != requested else { return }
        paused = requested
        if requested {
            pauseCount &+= 1
        } else {
            resumeCount &+= 1
            try rebase(atNanoseconds: now)
        }
    }

    /// Rebase the deadline series around the current raw-clock sample while
    /// preserving the source tick index.  Resuming therefore cannot skip the
    /// intro or manufacture a burst of old ticks.
    mutating func rebase(atNanoseconds now: UInt64) throws {
        guard nextNativeTick > 0 else {
            epochNanoseconds = now
            rebaseCount &+= 1
            return
        }
        let elapsed = try rationalOffset(for: nextNativeTick)
        guard now >= elapsed else { throw GE120SchedulerError.arithmeticOverflow }
        epochNanoseconds = now - elapsed
        rebaseCount &+= 1
    }

    /// Restart the authoritative simulation clock at native tick zero while
    /// retaining the owner thread and display-link lifetime. This is used by
    /// the user-facing Reset Game command; it deliberately does not pretend
    /// that the renderer or source authority has been reset.
    mutating func resetGame(atNanoseconds now: UInt64) throws {
        guard epochNanoseconds != nil else {
            throw GE120SchedulerError.arithmeticOverflow
        }
        epochNanoseconds = now
        nextNativeTick = 0
        paused = false
        resetMeasurementTelemetry(atNanoseconds: now)
    }

    func waitNanoseconds(atNanoseconds now: UInt64) throws -> UInt64 {
        guard !paused, let epochNanoseconds else { return 1_000_000_000 }
        let deadline = try deadline(for: nextNativeTick, epoch: epochNanoseconds)
        return deadline > now ? deadline - now : 0
    }

    func telemetry() -> GE120SchedulerTelemetry {
        GE120SchedulerTelemetry(
            measurementEpochNanoseconds: measurementEpochNanoseconds,
            wakeCount: wakeCount,
            emittedTickCount: emittedTickCount,
            lateWakeCount: lateWakeCount,
            catchUpBatchCount: catchUpBatchCount,
            catchUpTickCount: catchUpTickCount,
            maximumLatenessNanoseconds: maximumLatenessNanoseconds,
            maximumDebtTicks: maximumDebtTicks,
            pauseCount: pauseCount,
            resumeCount: resumeCount,
            rebaseCount: rebaseCount,
            fatalDebtTicks: fatalDebtTicks,
            firstScheduledNanoseconds: firstScheduledNanoseconds,
            lastScheduledNanoseconds: lastScheduledNanoseconds,
            firstSampledNanoseconds: firstSampledNanoseconds,
            lastSampledNanoseconds: lastSampledNanoseconds,
            droppedTickCount: 0,
            paused: paused,
            nextNativeTick: nextNativeTick
        )
    }

    private func rationalOffset(for tick: UInt64) throws -> UInt64 {
        let product = tick.multipliedReportingOverflow(by: periodNumerator)
        guard !product.overflow else { throw GE120SchedulerError.arithmeticOverflow }
        return product.partialValue / periodDenominator
    }

    private func deadline(for tick: UInt64, epoch: UInt64) throws -> UInt64 {
        let offset = try rationalOffset(for: tick)
        let result = epoch.addingReportingOverflow(offset)
        guard !result.overflow else { throw GE120SchedulerError.arithmeticOverflow }
        return result.partialValue
    }

    /// Count currently due ticks without iterating an unbounded stall.  The
    /// probe stops once the hard debt limit is exceeded; this is what turns a
    /// prolonged suspension into explicit failure evidence instead of an
    /// accidental catch-up loop.
    private func dueTickCount(atNanoseconds now: UInt64, epoch: UInt64) throws -> UInt64 {
        var probe = nextNativeTick
        var count: UInt64 = 0
        while count <= configuration.maxDebtTicks {
            let deadline = try deadline(for: probe, epoch: epoch)
            guard deadline <= now else { return count }
            count &+= 1
            let nextProbe = probe.addingReportingOverflow(1)
            guard !nextProbe.overflow else { throw GE120SchedulerError.arithmeticOverflow }
            probe = nextProbe.partialValue
        }
        return count
    }
}

enum GE120EngineOwnerState: Sendable, Equatable {
    case idle
    case starting
    case running
    case stopping
    case stopped
    case failed
}

struct GE120EngineOwnerTelemetry: Sendable {
    let state: GE120EngineOwnerState
    let ownerThreadIdentifier: UInt64
    let scheduler: GE120SchedulerTelemetry
    let display: GE120DisplayLinkTelemetry?
    let measurementEpochGeneration: UInt64
    let measurementEpochNanoseconds: UInt64
    let failure: String?
}

/// Dedicated native engine owner.  The owner thread is the sole mutator of
/// scheduler, source-derived state and display-link callbacks.  AppKit-facing
/// methods only publish value requests through NSCondition mailboxes and wake
/// the owner's CFRunLoop.
@available(macOS 26.0, *)
final class GE120EngineOwner: @unchecked Sendable {
    typealias TickHandler = (_ tick: GE120Tick) -> Void
    typealias MeasurementResetHandler = (_ generation: UInt64, _ rawNanoseconds: UInt64) -> Void
    typealias GameResetHandler = () -> Bool

    private let configuration: GE120TimebaseConfiguration
    private let tickHandler: TickHandler
    private let measurementResetHandler: MeasurementResetHandler?
    private let gameResetHandler: GameResetHandler?
    private let displayLink: GE120DisplayLinkRuntime?
    private let condition = NSCondition()
    private var ownerThread: Thread?
    private var ownerThreadIdentifier: UInt64 = 0
    private var ownerRunLoop: CFRunLoop?
    private var state: GE120EngineOwnerState = .idle
    private var stopRequested = false
    private var pendingPaused: Bool?
    private var pendingMeasurementResetCount: UInt64 = 0
    private var pendingGameResetCount: UInt64 = 0
    private var gameResetGeneration: UInt64 = 0
    private var gameResetIssuedGeneration: UInt64 = 0
    private var lastGameResetSucceeded = true
    private var gameResetResults: [UInt64: Bool] = [:]
    private var measurementEpochGeneration: UInt64 = 0
    private var measurementEpochIssuedGeneration: UInt64 = 0
    private var measurementEpochNanoseconds: UInt64 = 0
    private let schedulerLock = NSLock()
    private var scheduler: GE120FixedRateScheduler
    private var failure: String?

    init(
        configuration: GE120TimebaseConfiguration = .goldenEye,
        displayLink: GE120DisplayLinkRuntime? = nil,
        measurementResetHandler: MeasurementResetHandler? = nil,
        gameResetHandler: GameResetHandler? = nil,
        tickHandler: @escaping TickHandler
    ) {
        self.configuration = configuration
        self.displayLink = displayLink
        self.measurementResetHandler = measurementResetHandler
        self.gameResetHandler = gameResetHandler
        self.tickHandler = tickHandler
        self.scheduler = GE120FixedRateScheduler(configuration: configuration)
    }

    var isOwnerThread: Bool {
        let identifier = Self.currentThreadIdentifier()
        condition.lock()
        let owner = ownerThreadIdentifier
        condition.unlock()
        return owner != 0 && owner == identifier
    }

    func start() {
        condition.lock()
        precondition(state == .idle, "GE120 engine owner may only start once")
        state = .starting
        stopRequested = false
        condition.unlock()

        // Capture only an integer context in Thread's @Sendable closure.  The
        // owner object remains alive until stopAndWait has observed stopped.
        let contextAddress = UInt(bitPattern: Unmanaged.passUnretained(self).toOpaque())
        let thread = Thread {
            guard let context = UnsafeMutableRawPointer(bitPattern: contextAddress) else {
                preconditionFailure("GE120 engine owner context must be non-nil")
            }
            Unmanaged<GE120EngineOwner>.fromOpaque(context)
                .takeUnretainedValue()
                .runOnOwnerThread()
        }
        thread.name = "GoldenEye Native 120 Hz Owner"
        thread.qualityOfService = .userInteractive
        condition.lock()
        ownerThread = thread
        condition.unlock()
        thread.start()
    }

    func waitUntilRunning(timeout: TimeInterval = 5.0) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(timeout)
        while state == .starting || state == .idle {
            if !condition.wait(until: deadline) { return false }
        }
        return state == .running
    }

    func requestPaused(_ paused: Bool) {
        condition.lock()
        pendingPaused = paused
        let runLoop = ownerRunLoop
        let displayLink = self.displayLink
        condition.unlock()
        // Stop accepting pre-focus-loss drawables immediately. The owner
        // thread still applies the scheduler pause/rebase below, but the
        // presentation mailbox must be fenced at the AppKit notification
        // boundary rather than waiting for the next fixed-rate poll.
        displayLink?.requestPaused(paused)
        if let runLoop {
            CFRunLoopWakeUp(runLoop)
        }
    }

    func requestDrawableSize(_ size: CGSize) {
        displayLink?.requestDrawableSize(size)
        wakeOwnerRunLoop()
    }

    func requestPreferredFrameRateRange(_ range: CAFrameRateRange) {
        displayLink?.requestPreferredFrameRateRange(range)
        wakeOwnerRunLoop()
    }

    /// Request an atomic owner-thread measurement boundary. Multiple callers
    /// may race safely; each request is acknowledged after its own scheduler,
    /// display-link, and source/audio reset handler have completed.
    @discardableResult
    func resetMeasurementEpoch(timeout: TimeInterval = 5.0) -> Bool {
        if isOwnerThread {
            condition.lock()
            measurementEpochIssuedGeneration &+= 1
            let generation = measurementEpochIssuedGeneration
            condition.unlock()
            performMeasurementReset(
                atNanoseconds: GE120RawClock.nowNanoseconds(),
                generation: generation
            )
            return true
        }

        condition.lock()
        guard state == .running else {
            condition.unlock()
            return false
        }
        measurementEpochIssuedGeneration &+= 1
        let targetGeneration = measurementEpochIssuedGeneration
        pendingMeasurementResetCount &+= 1
        let runLoop = ownerRunLoop
        condition.broadcast()
        condition.unlock()
        if let runLoop {
            CFRunLoopWakeUp(runLoop)
        }

        condition.lock()
        let deadline = Date().addingTimeInterval(timeout)
        while measurementEpochGeneration < targetGeneration,
              state != .failed,
              state != .stopped {
            if !condition.wait(until: deadline) { break }
        }
        let completed = measurementEpochGeneration >= targetGeneration
        condition.unlock()
        return completed
    }

    /// Request an owner-thread game restart. The source/game state reset is
    /// acknowledged only after the scheduler has been moved back to native
    /// tick zero, so the next tick cannot race a partially reset authority.
    @discardableResult
    func resetGame(timeout: TimeInterval = 5.0) -> Bool {
        if isOwnerThread {
            let succeeded = performGameReset(atNanoseconds: GE120RawClock.nowNanoseconds())
            return succeeded
        }

        condition.lock()
        guard state == .running else {
            condition.unlock()
            return false
        }
        gameResetIssuedGeneration &+= 1
        let targetGeneration = gameResetIssuedGeneration
        pendingGameResetCount &+= 1
        let runLoop = ownerRunLoop
        condition.broadcast()
        condition.unlock()
        if let runLoop {
            CFRunLoopWakeUp(runLoop)
        }

        condition.lock()
        let deadline = Date().addingTimeInterval(timeout)
        while gameResetGeneration < targetGeneration,
              state != .failed,
              state != .stopped {
            if !condition.wait(until: deadline) { break }
        }
        let succeeded = gameResetResults.removeValue(forKey: targetGeneration)
            ?? (gameResetGeneration >= targetGeneration ? lastGameResetSucceeded : false)
        let completed = gameResetGeneration >= targetGeneration && succeeded
        condition.unlock()
        return completed
    }

    func telemetry() -> GE120EngineOwnerTelemetry {
        condition.lock()
        let state = self.state
        let ownerThreadIdentifier = self.ownerThreadIdentifier
        let failure = self.failure
        let measurementEpochGeneration = self.measurementEpochGeneration
        let measurementEpochNanoseconds = self.measurementEpochNanoseconds
        condition.unlock()

        schedulerLock.lock()
        let schedulerTelemetry = scheduler.telemetry()
        schedulerLock.unlock()
        let displayTelemetry = displayLink?.telemetry()
        let result = GE120EngineOwnerTelemetry(
            state: state,
            ownerThreadIdentifier: ownerThreadIdentifier,
            scheduler: schedulerTelemetry,
            display: displayTelemetry,
            measurementEpochGeneration: measurementEpochGeneration,
            measurementEpochNanoseconds: measurementEpochNanoseconds,
            failure: failure
        )
        return result
    }

    /// Synchronously stop the owner thread, invalidate its display link and
    /// wait until all owner-thread state has been released.  Calling from the
    /// owner callback itself only publishes the request; waiting there would
    /// deadlock the scheduler.
    func stopAndWait() {
        if isOwnerThread {
            requestStop()
            return
        }

        condition.lock()
        guard state != .idle, state != .stopped, state != .failed else {
            condition.unlock()
            return
        }
        stopRequested = true
        state = .stopping
        let runLoop = ownerRunLoop
        condition.broadcast()
        condition.unlock()

        if let runLoop {
            CFRunLoopStop(runLoop)
            CFRunLoopWakeUp(runLoop)
        }

        condition.lock()
        while state != .stopped && state != .failed {
            condition.wait()
        }
        condition.unlock()
    }

    private func runOnOwnerThread() {
        let identifier = Self.currentThreadIdentifier()
        condition.lock()
        ownerThreadIdentifier = identifier
        ownerRunLoop = CFRunLoopGetCurrent()
        condition.broadcast()
        condition.unlock()

        do {
            schedulerLock.lock()
            scheduler.start(atNanoseconds: GE120RawClock.nowNanoseconds())
            schedulerLock.unlock()
            if let displayLink {
                displayLink.start(on: RunLoop.current)
            }
            condition.lock()
            state = .running
            condition.broadcast()
            condition.unlock()

            while !shouldStop() {
                let now = GE120RawClock.nowNanoseconds()
                try consumeMailbox(atNanoseconds: now)
                schedulerLock.lock()
                let ticks: [GE120Tick]
                do {
                    ticks = try scheduler.poll(atNanoseconds: now)
                } catch {
                    schedulerLock.unlock()
                    throw error
                }
                schedulerLock.unlock()
                for tick in ticks {
                    tickHandler(tick)
                    if shouldStop() { break }
                }
                displayLink?.applyPendingCommands(afterPresent: false)
                if shouldStop() { break }

                schedulerLock.lock()
                let waitNanoseconds: UInt64
                do {
                    waitNanoseconds = try scheduler.waitNanoseconds(atNanoseconds: GE120RawClock.nowNanoseconds())
                } catch {
                    schedulerLock.unlock()
                    throw error
                }
                schedulerLock.unlock()
                let waitSeconds = min(max(Double(waitNanoseconds) / 1_000_000_000, 0.000_1), 1.0)
                _ = CFRunLoopRunInMode(.defaultMode, waitSeconds, true)
            }
        } catch {
            condition.lock()
            failure = String(describing: error)
            state = .failed
            stopRequested = true
            condition.broadcast()
            condition.unlock()
        }

        displayLink?.shutdown()
        condition.lock()
        if state != .failed { state = .stopped }
        ownerRunLoop = nil
        condition.broadcast()
        condition.unlock()
    }

    private func consumeMailbox(atNanoseconds now: UInt64) throws {
        consumePendingGameResets(atNanoseconds: now)
        consumePendingMeasurementResets(atNanoseconds: now)
        condition.lock()
        let paused = pendingPaused
        pendingPaused = nil
        condition.unlock()

        if let paused {
            schedulerLock.lock()
            do {
                try scheduler.setPaused(paused, atNanoseconds: now)
            } catch {
                schedulerLock.unlock()
                throw error
            }
            schedulerLock.unlock()
            // `requestPaused` publishes the display-link mailbox immediately
            // at the caller boundary; applyPendingCommands below consumes it
            // on the owner run loop after the scheduler state changes.
        }
        displayLink?.applyPendingCommands(afterPresent: false)
    }

    private func consumePendingGameResets(atNanoseconds now: UInt64) {
        while true {
            condition.lock()
            guard pendingGameResetCount > 0 else {
                condition.unlock()
                return
            }
            pendingGameResetCount -= 1
            condition.unlock()

            let succeeded = performGameReset(atNanoseconds: now)
            condition.lock()
            gameResetGeneration &+= 1
            lastGameResetSucceeded = succeeded
            gameResetResults[gameResetGeneration] = succeeded
            if gameResetResults.count > 16,
               let oldest = gameResetResults.keys.min() {
                gameResetResults.removeValue(forKey: oldest)
            }
            condition.broadcast()
            condition.unlock()
        }
    }

    private func performGameReset(atNanoseconds now: UInt64) -> Bool {
        guard gameResetHandler?() ?? true else { return false }
        schedulerLock.lock()
        defer { schedulerLock.unlock() }
        do {
            try scheduler.resetGame(atNanoseconds: now)
        } catch {
            condition.lock()
            failure = String(describing: error)
            condition.unlock()
            return false
        }
        // Reset is a user action, so a game that was paused by focus loss
        // starts from a neutral, running state once the next loop iteration
        // applies the display-link mailbox.
        displayLink?.requestPaused(false)
        return true
    }

    private func consumePendingMeasurementResets(atNanoseconds now: UInt64) {
        while true {
            condition.lock()
            guard pendingMeasurementResetCount > 0 else {
                condition.unlock()
                return
            }
            pendingMeasurementResetCount -= 1
            let generation = measurementEpochGeneration &+ 1
            condition.unlock()
            performMeasurementReset(
                atNanoseconds: now,
                generation: generation
            )
        }
    }

    private func performMeasurementReset(
        atNanoseconds now: UInt64,
        generation: UInt64
    ) {
        schedulerLock.lock()
        scheduler.resetMeasurementTelemetry(atNanoseconds: now)
        schedulerLock.unlock()
        displayLink?.resetMeasurementTelemetry(
            atNanoseconds: now,
            generation: generation
        )
        measurementResetHandler?(generation, now)

        condition.lock()
        // Publish the completed epoch only after every owner-side reset and
        // boundary handler has returned. Waiting callers therefore cannot
        // observe a generation that is only partially reset.
        measurementEpochGeneration = generation
        measurementEpochNanoseconds = now
        condition.broadcast()
        condition.unlock()
    }

    private func shouldStop() -> Bool {
        condition.lock()
        let result = stopRequested
        condition.unlock()
        return result
    }

    private func requestStop() {
        condition.lock()
        stopRequested = true
        if state == .running { state = .stopping }
        let runLoop = ownerRunLoop
        condition.broadcast()
        condition.unlock()
        if let runLoop {
            CFRunLoopStop(runLoop)
            CFRunLoopWakeUp(runLoop)
        }
    }

    private func wakeOwnerRunLoop() {
        condition.lock()
        let runLoop = ownerRunLoop
        condition.unlock()
        if let runLoop {
            CFRunLoopWakeUp(runLoop)
        }
    }

    private static func currentThreadIdentifier() -> UInt64 {
        var identifier: UInt64 = 0
        let status = pthread_threadid_np(nil, &identifier)
        precondition(status == 0, "pthread_threadid_np failed: \(status)")
        return identifier
    }
}
