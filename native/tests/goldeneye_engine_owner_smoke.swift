import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

private func exerciseDeterministicScheduler() {
    let configuration = GE120TimebaseConfiguration.goldenEye
    let epoch: UInt64 = 10_000_000_000
    let deadline: (UInt64) -> UInt64 = { tick in
        tick * UInt64(configuration.nativeRateDenominator) * 1_000_000_000
            / UInt64(configuration.nativeRateNumerator)
    }

    var scheduler = GE120FixedRateScheduler(configuration: configuration)
    scheduler.start(atNanoseconds: epoch)

    let bootstrap = try! scheduler.poll(atNanoseconds: epoch)
    require(bootstrap.count == 1, "tick zero must initialize exactly once")
    require(bootstrap[0].nativeTick == 0 && bootstrap[0].pairPhase == 0, "tick zero anchor")
    require(bootstrap[0].referenceTick == 0, "tick zero reference index")

    let beforeFirst = try! scheduler.poll(atNanoseconds: epoch + deadline(1) - 1)
    require(beforeFirst.isEmpty, "scheduler emitted before the first 120 Hz deadline")

    // A four-period wake is intentionally a bounded catch-up. The scheduler
    // must emit the four sequential due ticks and leave no silent skip.
    let catchUp = try! scheduler.poll(atNanoseconds: epoch + deadline(4))
    require(catchUp.map(\.nativeTick) == [1, 2, 3, 4], "sequential four-tick catch-up")
    require(catchUp.map(\.pairPhase) == [1, 0, 1, 0], "paired catch-up phases")
    let catchUpTelemetry = scheduler.telemetry()
    require(catchUpTelemetry.catchUpBatchCount == 1, "catch-up batch telemetry")
    require(catchUpTelemetry.catchUpTickCount == 3, "catch-up count excludes the first due tick")
    require(catchUpTelemetry.droppedTickCount == 0, "catch-up never drops logic")

    // A debt beyond the hard limit is a fatal, explicit cadence fault. It is
    // intentionally tested without iterating an unbounded wall-clock stall.
    var debtScheduler = GE120FixedRateScheduler(configuration: configuration)
    debtScheduler.start(atNanoseconds: epoch)
    _ = try! debtScheduler.poll(atNanoseconds: epoch)
    do {
        _ = try debtScheduler.poll(
            atNanoseconds: epoch + deadline(configuration.maxDebtTicks + 1)
        )
        preconditionFailure("debt over 240 ticks must fail closed")
    } catch let error as GE120SchedulerError {
        if case .deadlineDebtExceeded(let debt) = error {
            require(debt == configuration.maxDebtTicks + 1, "reported debt boundary")
        } else {
            preconditionFailure("unexpected scheduler error: \(error)")
        }
    } catch {
        preconditionFailure("unexpected scheduler error: \(error)")
    }
    require(
        debtScheduler.telemetry().fatalDebtTicks == configuration.maxDebtTicks + 1,
        "fatal debt telemetry"
    )

    // Pause/resume rebases the deadline series around the current raw-clock
    // sample. Resuming must preserve the next source tick, not manufacture a
    // backlog of paused time.
    var pausedScheduler = GE120FixedRateScheduler(configuration: configuration)
    pausedScheduler.start(atNanoseconds: epoch)
    _ = try! pausedScheduler.poll(atNanoseconds: epoch)
    try! pausedScheduler.setPaused(true, atNanoseconds: epoch + deadline(1))
    require(
        (try! pausedScheduler.poll(atNanoseconds: epoch + deadline(1000))).isEmpty,
        "paused scheduler emitted"
    )
    try! pausedScheduler.setPaused(false, atNanoseconds: epoch + deadline(1000))
    let resumed = try! pausedScheduler.poll(atNanoseconds: epoch + deadline(1000))
    require(resumed.count == 1 && resumed[0].nativeTick == 1, "resume preserved next tick")
    let pausedTelemetry = pausedScheduler.telemetry()
    require(pausedTelemetry.pauseCount == 1 && pausedTelemetry.resumeCount == 1, "pause/resume telemetry")
    require(pausedTelemetry.rebaseCount == 1, "resume rebase telemetry")

    // Reset returns the logical clock to an authoritative tick-zero anchor
    // without requiring a new owner thread.
    try! pausedScheduler.resetGame(atNanoseconds: epoch + deadline(2_000))
    let gameResetTick = try! pausedScheduler.poll(atNanoseconds: epoch + deadline(2_000))
    require(gameResetTick.count == 1 && gameResetTick[0].nativeTick == 0, "game reset tick zero")
}

private func exerciseHeadlessOwnerSoak() {
    let owner = GE120EngineOwner { _ in }
    owner.start()
    require(owner.waitUntilRunning(timeout: 2.0), "headless owner did not reach running state")
    Thread.sleep(forTimeInterval: 2.0)
    owner.stopAndWait()

    let telemetry = owner.telemetry()
    let scheduler = telemetry.scheduler
    let span = scheduler.lastSampledNanoseconds >= scheduler.firstSampledNanoseconds
        ? scheduler.lastSampledNanoseconds - scheduler.firstSampledNanoseconds
        : 0
    let elapsed = Double(span) / 1_000_000_000
    let rate = elapsed > 0
        ? Double(scheduler.emittedTickCount > 1 ? scheduler.emittedTickCount - 1 : scheduler.emittedTickCount) / elapsed
        : 0
    require(rate >= 119 && rate <= 121, "headless owner rate (rate) Hz")
    require(scheduler.droppedTickCount == 0, "headless owner dropped ticks")
    require(scheduler.fatalDebtTicks == 0, "headless owner fatal debt")
    print(
        "goldeneye_engine_owner_headless_soak: PASS "
            + "ticks=\(scheduler.emittedTickCount) rate=\(rate) "
            + "dropped=\(scheduler.droppedTickCount) maxDebt=\(scheduler.maximumDebtTicks)"
    )
}

@main
struct GoldenEyeEngineOwnerSmoke {
    static func main() {
        exerciseDeterministicScheduler()

        let condition = NSCondition()
        var ticks: [GE120Tick] = []
        let resetHandlerCondition = NSCondition()
        var resetHandlerStarted = 0
        var resetHandlerCompleted = 0
        var allowResetHandlerCompletion = false
        let owner = GE120EngineOwner(
            measurementResetHandler: { _, _ in
                resetHandlerCondition.lock()
                resetHandlerStarted += 1
                resetHandlerCondition.broadcast()
                while !allowResetHandlerCompletion {
                    resetHandlerCondition.wait()
                }
                resetHandlerCompleted += 1
                resetHandlerCondition.broadcast()
                resetHandlerCondition.unlock()
            },
            gameResetHandler: {
                true
            }
        ) { tick in
            condition.lock()
            ticks.append(tick)
            condition.broadcast()
            condition.unlock()
        }

        owner.start()
        precondition(owner.waitUntilRunning(timeout: 2.0), "owner did not reach running state")

        condition.lock()
        let deadline = Date().addingTimeInterval(0.25)
        while ticks.count < 8 && condition.wait(until: deadline) {}
        condition.unlock()
        precondition(ticks.count >= 8, "owner did not emit eight native ticks")
        precondition(ticks[0].pairPhase == 0 && ticks[1].pairPhase == 1)
        precondition(ticks[1].referenceTick == ticks[0].referenceTick)

        // Two callers racing the epoch boundary must both receive an
        // acknowledgement, while the owner applies the scheduler reset and
        // any presentation/source reset handlers serially on its own thread.
        let resetGroup = DispatchGroup()
        let resetLock = NSLock()
        var resetResults: [Bool] = []
        for _ in 0..<2 {
            resetGroup.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let result = owner.resetMeasurementEpoch(timeout: 2.0)
                resetLock.lock()
                resetResults.append(result)
                resetLock.unlock()
                resetGroup.leave()
            }
        }
        // The first handler intentionally blocks. A correct reset API must
        // keep both waiting callers blocked until this handler returns; the
        // old publication-before-reset ordering let one caller return early.
        resetHandlerCondition.lock()
        precondition(
            resetHandlerCondition.wait(
                until: Date().addingTimeInterval(1.0)
            ) || resetHandlerStarted > 0,
            "measurement reset handler did not start"
        )
        precondition(resetHandlerStarted > 0)
        resetLock.lock()
        precondition(resetResults.isEmpty, "reset acknowledged before handler completion")
        resetLock.unlock()
        allowResetHandlerCompletion = true
        resetHandlerCondition.broadcast()
        resetHandlerCondition.unlock()
        precondition(resetGroup.wait(timeout: .now() + 3.0) == .success)
        resetHandlerCondition.lock()
        let completedHandlers = resetHandlerCompleted
        resetHandlerCondition.unlock()
        precondition(completedHandlers == 2, "all measurement reset handlers completed")
        resetLock.lock()
        let acknowledgedResets = resetResults
        resetLock.unlock()
        precondition(acknowledgedResets.count == 2 && acknowledgedResets.allSatisfy { $0 })
        let resetTelemetry = owner.telemetry()
        precondition(resetTelemetry.measurementEpochGeneration == 2)
        precondition(
            resetTelemetry.scheduler.measurementEpochNanoseconds
                == resetTelemetry.measurementEpochNanoseconds
        )

        precondition(owner.resetGame(timeout: 2.0), "game reset acknowledgement")

        owner.requestPaused(true)
        Thread.sleep(forTimeInterval: 0.03)
        let pausedCount = owner.telemetry().scheduler.emittedTickCount
        Thread.sleep(forTimeInterval: 0.03)
        precondition(owner.telemetry().scheduler.emittedTickCount == pausedCount, "pause admitted ticks")

        owner.requestPaused(false)
        Thread.sleep(forTimeInterval: 0.03)
        owner.stopAndWait()
        let telemetry = owner.telemetry()
        precondition(telemetry.state == .stopped)
        precondition(telemetry.scheduler.pauseCount == 1)
        precondition(telemetry.scheduler.resumeCount == 1)
        precondition(telemetry.scheduler.rebaseCount == 1)

        print(
            "goldeneye_engine_owner_smoke: PASS "
                + "ticks=\(telemetry.scheduler.emittedTickCount) "
                + "pauses=\(telemetry.scheduler.pauseCount) "
                + "resumes=\(telemetry.scheduler.resumeCount)"
        )

        exerciseHeadlessOwnerSoak()
    }
}
