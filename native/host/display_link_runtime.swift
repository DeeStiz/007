import Darwin
import Foundation
import Metal
import QuartzCore

/// Immutable timing values supplied by CAMetalDisplayLink for a presentation
/// callback.  The callback receives the display-link-owned drawable directly;
/// the owner never acquires a second drawable while rendering this update.
@available(macOS 26.0, *)
struct GE120DisplayTiming: Sendable {
    let targetTimestamp: CFTimeInterval
    let targetPresentationTimestamp: CFTimeInterval
    let drawableWidth: Int
    let drawableHeight: Int
    let callbackSequence: UInt64
    let measurementEpochGeneration: UInt64
    /// Monotonic focus/pause generation. A drawable acquired before a focus
    /// transition must never be rendered after the app resumes.
    let pauseGeneration: UInt64

    init(
        targetTimestamp: CFTimeInterval,
        targetPresentationTimestamp: CFTimeInterval,
        drawableWidth: Int,
        drawableHeight: Int,
        callbackSequence: UInt64,
        measurementEpochGeneration: UInt64 = 0,
        pauseGeneration: UInt64 = 0
    ) {
        self.targetTimestamp = targetTimestamp
        self.targetPresentationTimestamp = targetPresentationTimestamp
        self.drawableWidth = drawableWidth
        self.drawableHeight = drawableHeight
        self.callbackSequence = callbackSequence
        self.measurementEpochGeneration = measurementEpochGeneration
        self.pauseGeneration = pauseGeneration
    }
}

@available(macOS 26.0, *)
struct GE120DisplayLinkTelemetry: Sendable {
    let measurementEpochNanoseconds: UInt64
    let measurementEpochGeneration: UInt64
    let callbackCount: UInt64
    let callbacksOnUnexpectedThread: UInt64
    let callbacksMarshaledToOwner: UInt64
    let migrationMarshalTimeouts: UInt64
    let marshaledCallbackDropCount: UInt64
    let staleCallbackDropCount: UInt64
    let unhandledUnexpectedCallbacks: UInt64
    let marshalQueueHighWater: UInt64
    let deferredInitialFrameCount: UInt64
    let renderFailureCount: UInt64
    let appliedResizeCount: UInt64
    let appliedRateCount: UInt64
    let lastTargetTimestamp: CFTimeInterval
    let lastTargetPresentationTimestamp: CFTimeInterval
    let firstTargetPresentationTimestamp: CFTimeInterval
    let targetDeltaCount: UInt64
    let minimumTargetDelta: CFTimeInterval
    let maximumTargetDelta: CFTimeInterval
    let targetDeltaMedian: CFTimeInterval
    let targetDeltaP95: CFTimeInterval
    let presentedTimeSampleCount: UInt64
    let rejectedPresentedTimeSampleCount: UInt64
    let firstPresentedTime: CFTimeInterval
    let lastPresentedTime: CFTimeInterval
    let minimumPresentedDelta: CFTimeInterval
    let maximumPresentedDelta: CFTimeInterval
    let presentedDeltaMedian: CFTimeInterval
    let presentedDeltaP95: CFTimeInterval
    let minimumPresentedOneSecondFrames: UInt64
    let presentedOneSecondWindowCount: UInt64
    let lastPresentedWindowHash: UInt64
    let callbackDurationCount: UInt64
    let maximumCallbackDuration: CFTimeInterval
    let callbackDurationMedian: CFTimeInterval
    let callbackDurationP95: CFTimeInterval
    let preferredFrameRateMinimum: Float
    let preferredFrameRateMaximum: Float
    let preferredFrameRatePreferred: Float
    let frameRateRangeOverrideVersion: String
    /// Metal 4 does not expose a portable GPU timestamp for this supplied
    /// drawable path. Keep this explicit in the evidence rather than
    /// presenting CPU submission time as GPU execution time.
    let gpuTimingAvailable: Bool
    let running: Bool
    let paused: Bool
}

/// A display-link adapter whose mutable state belongs to the engine owner
/// thread.  AppKit may publish resize, refresh-rate and pause requests from a
/// different thread; those requests are copied into a small mailbox and are
/// applied by the owner after a presented frame.  This keeps Core Animation
/// and Metal layer mutation out of AppKit callbacks and keeps the drawable
/// lifecycle in one place.
@available(macOS 26.0, *)
final class GE120DisplayLinkRuntime: NSObject, CAMetalDisplayLinkDelegate, @unchecked Sendable {
    typealias DrawHandler = (_ drawable: any CAMetalDrawable, _ timing: GE120DisplayTiming) -> Bool

    private final class MarshaledCallback {
        let drawable: any CAMetalDrawable
        let timing: GE120DisplayTiming
        let completion = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var cancelled = false
        private var result = false

        init(drawable: any CAMetalDrawable, timing: GE120DisplayTiming) {
            self.drawable = drawable
            self.timing = timing
        }

        func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }

        func complete(result: Bool) {
            lock.lock()
            self.result = result
            lock.unlock()
            completion.signal()
        }

        func waitResult(timeout: DispatchTime) -> Bool? {
            guard completion.wait(timeout: timeout) == .success else { return nil }
            lock.lock()
            let result = self.result
            lock.unlock()
            return result
        }

        func shouldRender() -> Bool {
            lock.lock()
            let result = !cancelled
            lock.unlock()
            return result
        }
    }

    private let layer: CAMetalLayer
    private let drawHandler: DrawHandler
    private let condition = NSCondition()
    private var displayLink: CAMetalDisplayLink?
    private var ownerThreadIdentifier: UInt64 = 0
    private var ownerRunLoop: CFRunLoop?
    private var isRunning = false
    private var isInvalidated = false
    private var pausedState = false
    private var pauseGeneration: UInt64 = 0
    private var pendingDrawableSize: CGSize?
    private var pendingFrameRateRange: CAFrameRateRange?
    private var pendingPaused: Bool?
    private var marshaledCallbacks: [MarshaledCallback] = []
    private var marshalDrainScheduled = false
    private var callbackSequence: UInt64 = 0
    private var callbackCount: UInt64 = 0
    private var callbacksOnUnexpectedThread: UInt64 = 0
    private var callbacksMarshaledToOwner: UInt64 = 0
    private var migrationMarshalTimeouts: UInt64 = 0
    private var marshaledCallbackDropCount: UInt64 = 0
    private var staleCallbackDropCount: UInt64 = 0
    private var unhandledUnexpectedCallbacks: UInt64 = 0
    private var marshalQueueHighWater: UInt64 = 0
    private var deferredInitialFrameCount: UInt64 = 0
    private var renderFailureCount: UInt64 = 0
    private var appliedResizeCount: UInt64 = 0
    private var appliedRateCount: UInt64 = 0
    private var lastTargetTimestamp: CFTimeInterval = 0
    private var lastTargetPresentationTimestamp: CFTimeInterval = 0
    private var firstTargetPresentationTimestamp: CFTimeInterval = 0
    private var previousTargetTimestamp: CFTimeInterval = 0
    private var targetDeltaCount: UInt64 = 0
    private var minimumTargetDelta: CFTimeInterval = 0
    private var maximumTargetDelta: CFTimeInterval = 0
    private static let intervalHistogramBinSeconds: CFTimeInterval = 0.0001
    private static let intervalHistogramCount = 20_480 // 0.1 ms bins through 2.048 s
    private var targetDeltaHistogram = Array(repeating: UInt64(0), count: intervalHistogramCount)
    private var presentedTimeSampleCount: UInt64 = 0
    private var rejectedPresentedTimeSampleCount: UInt64 = 0
    private var firstPresentedTime: CFTimeInterval = 0
    private var lastPresentedTime: CFTimeInterval = 0
    private var previousPresentedTime: CFTimeInterval = 0
    private var minimumPresentedDelta: CFTimeInterval = 0
    private var maximumPresentedDelta: CFTimeInterval = 0
    private var presentedDeltaHistogram = Array(repeating: UInt64(0), count: intervalHistogramCount)
    private var presentedWindowAccumulator = GEPresentationWindowAccumulatorV6()
    private var minimumPresentedOneSecondFrames: UInt64 = 0
    private var presentedOneSecondWindowCount: UInt64 = 0
    private var lastPresentedWindowHash: UInt64 = 0
    private var callbackDurationCount: UInt64 = 0
    private var maximumCallbackDuration: CFTimeInterval = 0
    private var callbackDurationHistogram = Array(repeating: UInt64(0), count: intervalHistogramCount)
    private var measurementEpochNanoseconds: UInt64 = 0
    private var measurementEpochGeneration: UInt64 = 0
    private let cadenceFrameRateOverride: CAFrameRateRange?
    private var configuredFrameRateRange: CAFrameRateRange
    private let frameRateRangeOverrideVersion: String
    private static let maximumMarshaledCallbackCount = 2

    init(
        layer: CAMetalLayer,
        preferredFrameRateRange: CAFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120),
        drawHandler: @escaping DrawHandler
    ) {
        self.layer = layer
        self.drawHandler = drawHandler
        let cadenceOverride = Self.cadenceFrameRateOverride()
        self.cadenceFrameRateOverride = cadenceOverride
        self.configuredFrameRateRange = cadenceOverride ?? preferredFrameRateRange
        self.frameRateRangeOverrideVersion = cadenceOverride == nil ? "none" : "v1"
        super.init()

        // These are layer properties rather than Metal command-queue state.
        // Configure them once before the first display-link callback.  The
        // device itself is supplied by the caller before `start`.
        layer.isOpaque = true
        layer.framebufferOnly = true
        layer.pixelFormat = .bgra8Unorm
        layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        layer.maximumDrawableCount = 2
        layer.displaySyncEnabled = true
        layer.allowsNextDrawableTimeout = true
        layer.presentsWithTransaction = false
        self.pendingFrameRateRange = cadenceOverride ?? preferredFrameRateRange
    }

    var currentLayer: CAMetalLayer { layer }

    var isOwnerThread: Bool {
        let identifier = Self.currentThreadIdentifier()
        condition.lock()
        let owner = ownerThreadIdentifier
        condition.unlock()
        return owner != 0 && owner == identifier
    }

    func start(on runLoop: RunLoop) {
        precondition(!Thread.isMainThread || isOwnerThread, "Display link must start on the engine owner thread")
        condition.lock()
        precondition(!isRunning, "Display link may only start once")
        precondition(!isInvalidated, "Display link cannot start after invalidation")
        ownerThreadIdentifier = Self.currentThreadIdentifier()
        ownerRunLoop = CFRunLoopGetCurrent()
        let link = CAMetalDisplayLink(metalLayer: layer)
        link.delegate = self
        let preferredLatency = ProcessInfo.processInfo.environment["GOLDENEYE_CADENCE_FRAME_LATENCY"]
            .flatMap(Int.init)
            .map { max(1, min($0, 2)) } ?? 2
        link.preferredFrameLatency = Float(preferredLatency)
        if let pendingFrameRateRange {
            link.preferredFrameRateRange = pendingFrameRateRange
            self.pendingFrameRateRange = nil
        }
        displayLink = link
        isRunning = true
        pausedState = false
        condition.unlock()

        link.add(to: runLoop, forMode: .common)
        link.isPaused = false
    }

    /// Publishes a resize request from AppKit.  The layer's drawable size is
    /// applied only after the current display callback returns, preserving the
    /// apply-after-present rule.
    func requestDrawableSize(_ size: CGSize) {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return }
        condition.lock()
        pendingDrawableSize = size
        let runLoop = ownerRunLoop
        condition.unlock()
        if let runLoop {
            CFRunLoopWakeUp(runLoop)
        }
    }

    func requestPreferredFrameRateRange(_ range: CAFrameRateRange) {
        let minimum = max(1, range.minimum)
        let maximum = max(minimum, range.maximum)
        let preferred = min(max(range.preferred ?? maximum, minimum), maximum)
        let normalized = cadenceFrameRateOverride ?? CAFrameRateRange(
            minimum: minimum,
            maximum: maximum,
            preferred: preferred
        )
        condition.lock()
        pendingFrameRateRange = normalized
        let runLoop = ownerRunLoop
        condition.unlock()
        if let runLoop {
            CFRunLoopWakeUp(runLoop)
        }
    }

    func requestPaused(_ paused: Bool) {
        var cancelledCallbacks: [MarshaledCallback] = []
        condition.lock()
        pauseGeneration &+= 1
        pendingPaused = paused
        if paused {
            // A CAMetalDisplayLink callback owns a drawable as soon as it is
            // delivered. Do not carry pre-focus-loss drawables across the
            // pause/resume boundary; WindowServer may have already reclaimed
            // their backing surfaces while the app was inactive.
            cancelledCallbacks = marshaledCallbacks
            marshaledCallbacks.removeAll(keepingCapacity: true)
            marshalDrainScheduled = false
        }
        let runLoop = ownerRunLoop
        condition.unlock()
        for callback in cancelledCallbacks {
            callback.cancel()
            callback.complete(result: false)
        }
        if let runLoop {
            CFRunLoopWakeUp(runLoop)
        }
    }

    /// Apply requests on the owner thread.  `afterPresent` should be true from
    /// the display-link callback and false from the owner scheduler.  While a
    /// link is paused (or before it has started), resize and rate changes are
    /// applied immediately so lifecycle requests cannot remain stranded.
    func applyPendingCommands(afterPresent: Bool) {
        precondition(isOwnerThread, "Display-link control belongs to the owner thread")

        condition.lock()
        let paused = pendingPaused
        pendingPaused = nil
        let shouldApplyFrameState = afterPresent || pausedState || !isRunning
        let size = shouldApplyFrameState ? pendingDrawableSize : nil
        if size != nil { pendingDrawableSize = nil }
        let range = shouldApplyFrameState ? pendingFrameRateRange : nil
        if range != nil { pendingFrameRateRange = nil }
        let link = displayLink
        condition.unlock()

        if let paused, let link {
            link.isPaused = paused
            condition.lock()
            pausedState = paused
            condition.unlock()
        }
        if let size {
            layer.drawableSize = size
            condition.lock()
            appliedResizeCount += 1
            condition.unlock()
        }
        if let range, let link {
            link.preferredFrameRateRange = range
            condition.lock()
            configuredFrameRateRange = range
            appliedRateCount += 1
            condition.unlock()
        }
    }

    func telemetry() -> GE120DisplayLinkTelemetry {
        condition.lock()
        let result = GE120DisplayLinkTelemetry(
            measurementEpochNanoseconds: measurementEpochNanoseconds,
            measurementEpochGeneration: measurementEpochGeneration,
            callbackCount: callbackCount,
            callbacksOnUnexpectedThread: callbacksOnUnexpectedThread,
            callbacksMarshaledToOwner: callbacksMarshaledToOwner,
            migrationMarshalTimeouts: migrationMarshalTimeouts,
            marshaledCallbackDropCount: marshaledCallbackDropCount,
            staleCallbackDropCount: staleCallbackDropCount,
            unhandledUnexpectedCallbacks: unhandledUnexpectedCallbacks,
            marshalQueueHighWater: marshalQueueHighWater,
            deferredInitialFrameCount: deferredInitialFrameCount,
            renderFailureCount: renderFailureCount,
            appliedResizeCount: appliedResizeCount,
            appliedRateCount: appliedRateCount,
            lastTargetTimestamp: lastTargetTimestamp,
            lastTargetPresentationTimestamp: lastTargetPresentationTimestamp,
            firstTargetPresentationTimestamp: firstTargetPresentationTimestamp,
            targetDeltaCount: targetDeltaCount,
            minimumTargetDelta: minimumTargetDelta,
            maximumTargetDelta: maximumTargetDelta,
            targetDeltaMedian: percentile(
                0.50,
                histogram: targetDeltaHistogram,
                sampleCount: targetDeltaCount
            ),
            targetDeltaP95: percentile(
                0.95,
                histogram: targetDeltaHistogram,
                sampleCount: targetDeltaCount
            ),
            presentedTimeSampleCount: presentedTimeSampleCount,
            rejectedPresentedTimeSampleCount: rejectedPresentedTimeSampleCount,
            firstPresentedTime: firstPresentedTime,
            lastPresentedTime: lastPresentedTime,
            minimumPresentedDelta: minimumPresentedDelta,
            maximumPresentedDelta: maximumPresentedDelta,
            presentedDeltaMedian: percentile(
                0.50,
                histogram: presentedDeltaHistogram,
                sampleCount: presentedTimeSampleCount > 0 ? presentedTimeSampleCount - 1 : 0
            ),
            presentedDeltaP95: percentile(
                0.95,
                histogram: presentedDeltaHistogram,
                sampleCount: presentedTimeSampleCount > 0 ? presentedTimeSampleCount - 1 : 0
            ),
            minimumPresentedOneSecondFrames: minimumPresentedOneSecondFrames,
            presentedOneSecondWindowCount: presentedOneSecondWindowCount,
            lastPresentedWindowHash: lastPresentedWindowHash,
            callbackDurationCount: callbackDurationCount,
            maximumCallbackDuration: maximumCallbackDuration,
            callbackDurationMedian: percentile(
                0.50,
                histogram: callbackDurationHistogram,
                sampleCount: callbackDurationCount
            ),
            callbackDurationP95: percentile(
                0.95,
                histogram: callbackDurationHistogram,
                sampleCount: callbackDurationCount
            ),
            preferredFrameRateMinimum: configuredFrameRateRange.minimum,
            preferredFrameRateMaximum: configuredFrameRateRange.maximum,
            preferredFrameRatePreferred: configuredFrameRateRange.preferred ?? configuredFrameRateRange.maximum,
            frameRateRangeOverrideVersion: frameRateRangeOverrideVersion,
            gpuTimingAvailable: false,
            running: isRunning,
            paused: pausedState
        )
        condition.unlock()
        return result
    }

    /// Reset presentation counters and histograms at an owner-thread epoch.
    /// Handlers attached to pre-epoch drawables capture the previous
    /// generation and are ignored when Core Animation reports them later.
    func resetMeasurementTelemetry(atNanoseconds now: UInt64, generation: UInt64) {
        precondition(isOwnerThread, "Display-link telemetry reset belongs to the owner thread")
        condition.lock()
        measurementEpochNanoseconds = now
        measurementEpochGeneration = generation
        callbackSequence = 0
        callbackCount = 0
        callbacksOnUnexpectedThread = 0
        callbacksMarshaledToOwner = 0
        migrationMarshalTimeouts = 0
        marshaledCallbackDropCount = 0
        staleCallbackDropCount = 0
        unhandledUnexpectedCallbacks = 0
        marshalQueueHighWater = 0
        deferredInitialFrameCount = 0
        renderFailureCount = 0
        // Resize/rate applications are lifecycle evidence rather than
        // steady-state histogram samples. Keep their cumulative counts so a
        // warmup resize still proves the apply-after-present contract.
        lastTargetTimestamp = 0
        lastTargetPresentationTimestamp = 0
        firstTargetPresentationTimestamp = 0
        previousTargetTimestamp = 0
        targetDeltaCount = 0
        minimumTargetDelta = 0
        maximumTargetDelta = 0
        for index in targetDeltaHistogram.indices {
            targetDeltaHistogram[index] = 0
        }
        presentedTimeSampleCount = 0
        rejectedPresentedTimeSampleCount = 0
        firstPresentedTime = 0
        lastPresentedTime = 0
        previousPresentedTime = 0
        minimumPresentedDelta = 0
        maximumPresentedDelta = 0
        for index in presentedDeltaHistogram.indices {
            presentedDeltaHistogram[index] = 0
        }
        presentedWindowAccumulator = GEPresentationWindowAccumulatorV6()
        minimumPresentedOneSecondFrames = 0
        presentedOneSecondWindowCount = 0
        lastPresentedWindowHash = 0
        callbackDurationCount = 0
        maximumCallbackDuration = 0
        for index in callbackDurationHistogram.indices {
            callbackDurationHistogram[index] = 0
        }
        // Cancel in place so retaining the pending array does not trigger a
        // copy-on-write allocation at the measured epoch boundary.
        for callback in marshaledCallbacks {
            callback.cancel()
            callback.complete(result: false)
        }
        marshaledCallbacks.removeAll(keepingCapacity: true)
        marshalDrainScheduled = false
        condition.unlock()
    }

    /// Invalidates the link and releases its delegate on the owner thread.
    /// GPU command-buffer draining remains the renderer's responsibility; this
    /// method only closes the Core Animation callback source deterministically.
    func shutdown() {
        precondition(isOwnerThread, "Display-link shutdown belongs to the owner thread")
        condition.lock()
        guard !isInvalidated else {
            condition.unlock()
            return
        }
        isRunning = false
        isInvalidated = true
        pausedState = true
        let link = displayLink
        displayLink = nil
        let pendingCallbacks = marshaledCallbacks
        marshaledCallbacks.removeAll(keepingCapacity: false)
        marshalDrainScheduled = false
        condition.unlock()

        for callback in pendingCallbacks {
            callback.cancel()
            callback.complete(result: false)
        }

        guard let link else { return }
        link.isPaused = true
        let runLoop = CFRunLoopGetCurrent()
        link.remove(from: RunLoop.current, forMode: .common)
        link.delegate = nil
        link.invalidate()
        CFRunLoopWakeUp(runLoop)
    }

    func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        autoreleasepool {
            let currentThread = Self.currentThreadIdentifier()
            condition.lock()
            let owner = ownerThreadIdentifier
            let running = isRunning && !isInvalidated
            let measurementGeneration = measurementEpochGeneration
            let callbackPauseGeneration = pauseGeneration
            callbackSequence &+= 1
            let sequence = callbackSequence
            callbackCount &+= 1
            lastTargetTimestamp = update.targetTimestamp
            lastTargetPresentationTimestamp = update.targetPresentationTimestamp
            if firstTargetPresentationTimestamp == 0 {
                firstTargetPresentationTimestamp = update.targetPresentationTimestamp
            }
            if previousTargetTimestamp > 0 {
                let delta = update.targetPresentationTimestamp - previousTargetTimestamp
                if delta > 0, delta.isFinite {
                    targetDeltaCount &+= 1
                    if minimumTargetDelta == 0 || delta < minimumTargetDelta {
                        minimumTargetDelta = delta
                    }
                    maximumTargetDelta = max(maximumTargetDelta, delta)
                    recordHistogram(delta, into: &targetDeltaHistogram)
                }
            }
            previousTargetTimestamp = update.targetPresentationTimestamp
            let unexpectedThread = currentThread != owner
            if unexpectedThread { callbacksOnUnexpectedThread += 1 }
            condition.unlock()

            let drawable = update.drawable
            let timing = GE120DisplayTiming(
                targetTimestamp: update.targetTimestamp,
                targetPresentationTimestamp: update.targetPresentationTimestamp,
                drawableWidth: drawable.texture.width,
                drawableHeight: drawable.texture.height,
                callbackSequence: sequence,
                measurementEpochGeneration: measurementGeneration,
                pauseGeneration: callbackPauseGeneration
            )

            guard running else { return }
            if unexpectedThread {
                let callback = MarshaledCallback(drawable: drawable, timing: timing)
                _ = marshalToOwner(callback)
                return
            }

            _ = renderOnOwner(drawable: drawable, timing: timing, link: link)
        }
    }

    /// Hand a callback that arrived on a Core Animation migration thread to
    /// the owner run loop without blocking Core Animation. The two-drawable
    /// bound mirrors CAMetalLayer.maximumDrawableCount; when migration floods
    /// the queue, the older unrendered drawable is discarded in favor of the
    /// newest state. A presentation miss is telemetry, never a reason to pause
    /// or alter the authoritative simulation timeline.
    private func marshalToOwner(_ callback: MarshaledCallback) -> Bool {
        condition.lock()
        guard isRunning, !isInvalidated, let runLoop = ownerRunLoop else {
            unhandledUnexpectedCallbacks &+= 1
            condition.unlock()
            callback.cancel()
            callback.complete(result: false)
            return false
        }
        var superseded: MarshaledCallback?
        if marshaledCallbacks.count >= Self.maximumMarshaledCallbackCount {
            superseded = marshaledCallbacks.removeFirst()
            marshaledCallbackDropCount &+= 1
        }
        marshaledCallbacks.append(callback)
        callbacksMarshaledToOwner &+= 1
        marshalQueueHighWater = max(marshalQueueHighWater, UInt64(marshaledCallbacks.count))
        let shouldScheduleDrain = !marshalDrainScheduled
        marshalDrainScheduled = true
        condition.unlock()

        if let superseded {
            superseded.cancel()
            superseded.complete(result: false)
        }

        if shouldScheduleDrain {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes as AnyObject) { [weak self] in
                self?.drainMarshaledCallbacks()
            }
        }
        CFRunLoopWakeUp(runLoop)
        return true
    }

    private func drainMarshaledCallbacks() {
        precondition(isOwnerThread, "Marshaled display callbacks belong to the owner thread")
        while true {
            condition.lock()
            guard !marshaledCallbacks.isEmpty else {
                marshalDrainScheduled = false
                condition.unlock()
                return
            }
            let callback = marshaledCallbacks.removeFirst()
            let link = displayLink
            condition.unlock()

            guard callback.shouldRender(), let link else {
                callback.complete(result: false)
                continue
            }
            let result = renderOnOwner(drawable: callback.drawable, timing: callback.timing, link: link)
            callback.complete(result: result)
        }
    }

    private func renderOnOwner(
        drawable: any CAMetalDrawable,
        timing: GE120DisplayTiming,
        link: CAMetalDisplayLink
    ) -> Bool {
        precondition(isOwnerThread, "Display rendering belongs to the owner thread")
        let callbackStart = CACurrentMediaTime()
        condition.lock()
        let presentationGeneration = measurementEpochGeneration
        let staleEpoch = timing.measurementEpochGeneration != presentationGeneration
        let stalePause = timing.pauseGeneration != pauseGeneration
        if staleEpoch || stalePause { staleCallbackDropCount &+= 1 }
        condition.unlock()
        guard !staleEpoch, !stalePause else { return false }
        condition.lock()
        let pauseRequested = pausedState || pendingPaused == true
        condition.unlock()
        guard !pauseRequested else { return false }
        // Register before the renderer calls present(). MTLDrawable documents
        // this as the presentation callback; registering after present can
        // miss it entirely and leave Release evidence with no presented times.
        drawable.addPresentedHandler { [weak self] presentedDrawable in
            self?.recordPresentedTime(
                presentedDrawable.presentedTime,
                generation: presentationGeneration,
                pauseGeneration: timing.pauseGeneration
            )
        }
        defer {
            let elapsed = CACurrentMediaTime() - callbackStart
            condition.lock()
            callbackDurationCount &+= 1
            maximumCallbackDuration = max(maximumCallbackDuration, elapsed)
            recordHistogram(elapsed, into: &callbackDurationHistogram)
            condition.unlock()
        }
        guard drawHandler(drawable, timing) else {
            // The display link can legitimately deliver its first drawable
            // before the owner has published tick-one's immutable source
            // frame. Drop that unrenderable drawable and keep the link alive;
            // pausing here would permanently strand a normal launch before
            // the first frame exists. Subsequent false results remain fatal
            // and pause presentation, preserving the fail-closed renderer
            // contract for real lowering errors.
            if timing.callbackSequence <= 2 {
                condition.lock()
                deferredInitialFrameCount &+= 1
                condition.unlock()
                return false
            }
            condition.lock()
            renderFailureCount &+= 1
            pausedState = true
            condition.unlock()
            link.isPaused = true
            return false
        }

        // Resize and rate changes are intentionally applied only after the
        // handler has returned, i.e. after this drawable was rendered.
        applyPendingCommands(afterPresent: true)
        return true
    }

    private func recordPresentedTime(
        _ time: CFTimeInterval,
        generation: UInt64,
        pauseGeneration callbackPauseGeneration: UInt64
    ) {
        condition.lock()
        guard generation == measurementEpochGeneration else {
            condition.unlock()
            return
        }
        // A presented handler can run after Core Animation has completed a
        // drawable that was queued before focus loss. Keep that completion
        // out of the resumed epoch even when the measurement epoch itself did
        // not change. This prevents a delayed pre-pause timestamp from
        // bridging the pause gap or inflating a one-second window.
        guard callbackPauseGeneration == pauseGeneration else {
            staleCallbackDropCount &+= 1
            condition.unlock()
            return
        }
        let window = presentedWindowAccumulator.ingest(time)
        rejectedPresentedTimeSampleCount = window.rejectedSampleCount
        lastPresentedWindowHash = window.windowHash
        guard window.accepted else {
            condition.unlock()
            return
        }
        if firstPresentedTime == 0 { firstPresentedTime = time }
        if previousPresentedTime > 0 {
            let delta = time - previousPresentedTime
            if delta > 0, delta.isFinite {
                if minimumPresentedDelta == 0 || delta < minimumPresentedDelta {
                    minimumPresentedDelta = delta
                }
                maximumPresentedDelta = max(maximumPresentedDelta, delta)
                recordHistogram(delta, into: &presentedDeltaHistogram)
            }
        }
        previousPresentedTime = time
        presentedTimeSampleCount &+= 1
        lastPresentedTime = time
        if window.emittedWindow {
            minimumPresentedOneSecondFrames = window.minimumWindowFrames
            presentedOneSecondWindowCount = window.windowCount
        }
        condition.unlock()
    }

    private func recordHistogram(_ value: CFTimeInterval, into histogram: inout [UInt64]) {
        guard value.isFinite, value > 0 else { return }
        let rawIndex = Int(value / Self.intervalHistogramBinSeconds)
        let index = min(max(rawIndex, 0), histogram.count - 1)
        histogram[index] &+= 1
    }

    private func percentile(
        _ fraction: Double,
        histogram: [UInt64],
        sampleCount: UInt64
    ) -> CFTimeInterval {
        guard sampleCount > 0 else { return 0 }
        let target = max(UInt64(1), UInt64(ceil(Double(sampleCount) * fraction)))
        var cumulative: UInt64 = 0
        for (index, count) in histogram.enumerated() {
            cumulative &+= count
            if cumulative >= target {
                return (Double(index) + 0.5) * Self.intervalHistogramBinSeconds
            }
        }
        return Double(Self.intervalHistogramCount) * Self.intervalHistogramBinSeconds
    }

    /// Cadence-only override used to distinguish a compositor/display-link
    /// selection issue from renderer throughput. Production keeps the
    /// caller-provided 60-120/120 range unless the cadence probe is active.
    private static func cadenceFrameRateOverride() -> CAFrameRateRange? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["GOLDENEYE_CADENCE_PROBE"] == "1" else { return nil }
        guard let rawMinimum = environment["GOLDENEYE_CADENCE_FRAME_RATE_MINIMUM"],
              let rawMaximum = environment["GOLDENEYE_CADENCE_FRAME_RATE_MAXIMUM"],
              let rawPreferred = environment["GOLDENEYE_CADENCE_FRAME_RATE_PREFERRED"],
              let minimum = Float(rawMinimum),
              let maximum = Float(rawMaximum),
              let preferred = Float(rawPreferred),
              minimum.isFinite, maximum.isFinite, preferred.isFinite,
              minimum > 0, maximum >= minimum,
              preferred >= minimum, preferred <= maximum else {
            return nil
        }
        return CAFrameRateRange(minimum: minimum, maximum: maximum, preferred: preferred)
    }

    private static func currentThreadIdentifier() -> UInt64 {
        var identifier: UInt64 = 0
        let status = pthread_threadid_np(nil, &identifier)
        precondition(status == 0, "pthread_threadid_np failed: \(status)")
        return identifier
    }
}
