import AppKit
import Darwin
import Metal
import QuartzCore
import GoldenEyeNative

private final class GoldenEyeView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func makeBackingLayer() -> CALayer {
        let metalLayer = CAMetalLayer()
        metalLayer.isOpaque = true
        metalLayer.framebufferOnly = true
        metalLayer.pixelFormat = .bgra8Unorm
        return metalLayer
    }

    var metalLayer: CAMetalLayer {
        guard let metalLayer = layer as? CAMetalLayer else {
            preconditionFailure("GoldenEyeView must be backed by CAMetalLayer")
        }
        return metalLayer
    }

    override func layout() {
        super.layout()
        updateDrawableSize()
    }

    func updateDrawableSize() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }
}

private final class GoldenEyeOwnerLoop: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.goldeneye.swift.owner", qos: .userInteractive)
    private let lock = NSLock()
    private var stopRequested = false
    private var running = false
    private var paused = false
    private var pendingInput = GoldenEyeKeyboardSnapshot(sequence: 0, held: 0, pressed: 0, released: 0)
    private var frameRenderer: (any GoldenEyeFrameRenderer)?

    func submit(input: GoldenEyeKeyboardSnapshot) {
        lock.lock()
        pendingInput = GoldenEyeKeyboardSnapshot(
            sequence: input.sequence,
            held: input.held,
            pressed: pendingInput.pressed | input.pressed,
            released: pendingInput.released | input.released
        )
        lock.unlock()
    }

    func resetInput() {
        lock.lock()
        pendingInput = GoldenEyeKeyboardSnapshot(sequence: pendingInput.sequence, held: 0, pressed: 0, released: 0)
        lock.unlock()
    }

    func setPaused(_ paused: Bool) {
        lock.lock()
        self.paused = paused
        lock.unlock()
    }

    func start(renderer: (any GoldenEyeFrameRenderer)? = nil) {
        lock.lock()
        guard !running else {
            lock.unlock()
            return
        }
        running = true
        stopRequested = false
        frameRenderer = renderer
        lock.unlock()

        queue.async { [weak self] in
            self?.runBoundedLifecycle()
        }
    }

    func stop() {
        lock.lock()
        let wasRunning = running
        stopRequested = true
        lock.unlock()
        guard wasRunning else { return }

        // Wait until the owner queue has returned to its idle state. Later
        // renderer milestones extend this owner-thread fence around GPU work.
        queue.sync {}
    }

    private func shouldStop() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopRequested
    }

    private func shouldPause() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return paused
    }

    private func takeInput(for tick: Int) -> GoldenEyeKeyboardSnapshot {
        lock.lock()
        let input = pendingInput
        pendingInput = GoldenEyeKeyboardSnapshot(sequence: UInt64(tick), held: input.held, pressed: 0, released: 0)
        lock.unlock()
        return GoldenEyeKeyboardSnapshot(
            sequence: UInt64(tick),
            held: input.held,
            pressed: input.pressed,
            released: input.released
        )
    }

    private func runBoundedLifecycle() {
        var request = GEInitRequestV1()
        request.header.abi_version = UInt32(GE_NATIVE_ABI_VERSION)
        request.header.struct_size = UInt32(MemoryLayout<GEInitRequestV1>.size)
        request.flags = 0
        request.reserved = 0

        let initializeStatus = ge_native_initialize(request)
        guard initializeStatus == GE_STATUS_OK else {
            print("GoldenEye owner initialize failed: \(initializeStatus)")
            finish()
            return
        }

        var ticksCompleted = 0
        let tickLimit = ProcessInfo.processInfo.environment["GOLDENEYE_M3_EVENT_PROBE"] == "1" ? 180 : 60
        var tick = 1
        while tick <= tickLimit {
            if shouldStop() { break }
            if shouldPause() {
                usleep(8_000)
                continue
            }
            let keyboardInput = takeInput(for: tick)
            var input = GEInputSnapshotV1()
            input.header.abi_version = UInt32(GE_NATIVE_ABI_VERSION)
            input.header.struct_size = UInt32(MemoryLayout<GEInputSnapshotV1>.size)
            input.sequence = keyboardInput.sequence
            input.held = keyboardInput.held
            input.pressed = keyboardInput.pressed
            input.released = keyboardInput.released
            input.reserved = 0
            let frame = ge_native_step(input)
            guard frame.status == GE_STATUS_OK else {
                print("GoldenEye owner step failed: \(frame.status)")
                break
            }
            ticksCompleted = tick
            tick += 1
            if let frameRenderer, !frameRenderer.renderFrame() {
                print("GoldenEye owner renderer failed")
                break
            }
            usleep(8_000)
        }

        let shutdownStatus = ge_native_shutdown()
        frameRenderer?.shutdown()
        print("GoldenEye owner loop stopped: status=\(shutdownStatus)")
        let evidence = "initialized=1 ticks=\(ticksCompleted) shutdown=\(shutdownStatus)\n"
        try? evidence.write(
            toFile: "/tmp/goldeneye-m2-owner-loop.log",
            atomically: true,
            encoding: .utf8
        )
        finish()
    }

    private func finish() {
        lock.lock()
        running = false
        lock.unlock()
    }
}

private final class GoldenEyeViewController: NSViewController {
    private let ownerLoop = GoldenEyeOwnerLoop()
    private var keyboardState = GoldenEyeKeyboardInputState()
    private var didRegisterFocusObserver = false
    private var didScheduleInputProbe = false
    private var metalDeviceState: AnyObject?
    private var frameRenderer: (any GoldenEyeFrameRenderer)?
    private var baselinePipeline: AnyObject?
    private var gameView: GoldenEyeView { view as! GoldenEyeView }

    private var eventProbeEnabled: Bool {
        ProcessInfo.processInfo.environment["GOLDENEYE_M3_EVENT_PROBE"] == "1"
    }

    private var pauseProbeEnabled: Bool {
        ProcessInfo.processInfo.environment["GOLDENEYE_M5_PAUSE_PROBE"] == "1"
    }

    private func recordInputEvidence(_ line: String) {
        guard eventProbeEnabled || pauseProbeEnabled else { return }
        let paths: [String] = [
            eventProbeEnabled ? "/tmp/goldeneye-m3-events.log" : "",
            pauseProbeEnabled ? "/tmp/goldeneye-m5-pause.log" : "",
        ].filter { !$0.isEmpty }
        let data = Data((line + "\n").utf8)
        for path in paths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func loadView() {
        view = GoldenEyeView(frame: NSRect(x: 0, y: 0, width: 960, height: 540))
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        recordInputEvidence("event=probeStarted")
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("GoldenEye Metal device unavailable")
            return
        }
        if #available(macOS 26.0, *) {
            do {
                let state = try GoldenEyeMetalDeviceState(device: device, layer: gameView.metalLayer)
                metalDeviceState = state
                frameRenderer = GoldenEyeMetalClearRenderer(state: state, layer: gameView.metalLayer)
                try? state.evidenceLine.write(
                    toFile: "/tmp/goldeneye-m4-device.log",
                    atomically: true,
                    encoding: .utf8
                )
                print("GoldenEye Metal device ready: \(state.evidenceLine)")
                let wantsClassicProp = ProcessInfo.processInfo.environment["GOLDENEYE_M10_PROP"] == "1"
                let wantsClassicTexturedProp = ProcessInfo.processInfo.environment["GOLDENEYE_M11_TEXTURED_PROP"] == "1"
                let wantsPipeline = ProcessInfo.processInfo.environment["GOLDENEYE_M6_PIPELINE"] == "1"
                    || ProcessInfo.processInfo.environment["GOLDENEYE_M8_TRIANGLE"] == "1"
                    || wantsClassicProp
                    || wantsClassicTexturedProp
                if wantsPipeline {
                    do {
                        if wantsClassicTexturedProp {
                            guard let libraryURL = Bundle.main.url(forResource: "GoldenEyeClassicTexturedProp", withExtension: "metallib") else {
                                print("GoldenEye classic textured prop metallib is missing")
                                return
                            }
                            let pipeline = try GoldenEyeClassicTexturedPropPipeline(device: device, libraryURL: libraryURL)
                            baselinePipeline = pipeline
                            let propBlob = try GoldenEyeClassicPropAsset.loadFromEnvironment()
                            let textureBlobs = try GoldenEyeClassicPropAsset.loadTextureBlobsFromEnvironment()
                            let materials = GoldenEyeClassicPropAsset.textureMaterials()
                            frameRenderer = try GoldenEyeMetalClassicTexturedPropRenderer(
                                state: state,
                                layer: gameView.metalLayer,
                                pipeline: pipeline,
                                propBlob: propBlob,
                                materials: materials,
                                textureBlobs: textureBlobs
                            )
                        } else if wantsClassicProp {
                            guard let libraryURL = Bundle.main.url(forResource: "GoldenEyeClassicProp", withExtension: "metallib") else {
                                print("GoldenEye classic prop metallib is missing")
                                return
                            }
                            let pipeline = try GoldenEyeClassicPropPipeline(device: device, libraryURL: libraryURL)
                            baselinePipeline = pipeline
                            let asset = try GoldenEyeClassicPropAsset.loadFromEnvironment()
                            frameRenderer = GoldenEyeMetalClassicPropRenderer(
                                state: state,
                                layer: gameView.metalLayer,
                                pipeline: pipeline,
                                assetBlob: asset
                            )
                        } else {
                            guard let libraryURL = Bundle.main.url(forResource: "GoldenEyeBaseline", withExtension: "metallib") else {
                                print("GoldenEye baseline metallib is missing")
                                return
                            }
                            let pipeline = try GoldenEyeBaselinePipeline(device: device, libraryURL: libraryURL)
                            baselinePipeline = pipeline
                            if ProcessInfo.processInfo.environment["GOLDENEYE_M8_TRIANGLE"] == "1" {
                            frameRenderer = try GoldenEyeMetalTriangleRenderer(
                                state: state,
                                layer: gameView.metalLayer,
                                pipeline: pipeline
                            )
                            } else {
                                try? "pipeline=1 label=\(pipeline.label) draws=0\n".write(
                                    toFile: "/tmp/goldeneye-m6-pipeline.log",
                                    atomically: true,
                                    encoding: .utf8
                                )
                                frameRenderer = nil
                            }
                        }
                    } catch {
                        print("GoldenEye render pipeline failed: \(error)")
                        return
                    }
                }
            } catch {
                print("GoldenEye Metal 4 setup failed: \(error)")
                return
            }
        } else {
            print("GoldenEye requires macOS 27 Metal 4")
            return
        }
        gameView.updateDrawableSize()
        view.window?.makeFirstResponder(self)
        if !didRegisterFocusObserver {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(applicationWillResignActive(_:)),
                name: NSApplication.willResignActiveNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(applicationDidBecomeActive(_:)),
                name: NSApplication.didBecomeActiveNotification,
                object: nil
            )
            didRegisterFocusObserver = true
        }
        ownerLoop.start(renderer: frameRenderer)
        scheduleInputProbe()
        schedulePauseProbe()
        if ProcessInfo.processInfo.environment["GOLDENEYE_M9_RESIZE"] == "1" {
            scheduleResizeProbe()
        }
    }

    override func viewWillDisappear() {
        ownerLoop.stop()
        super.viewWillDisappear()
    }

    override func keyDown(with event: NSEvent) {
        keyboardState.keyDown(keyCode: event.keyCode, isRepeat: event.isARepeat)
        let snapshot = keyboardState.snapshot()
        recordInputEvidence("event=keyDown keyCode=\(event.keyCode) repeat=\(event.isARepeat ? 1 : 0) sequence=\(snapshot.sequence) held=\(snapshot.held) pressed=\(snapshot.pressed) released=\(snapshot.released)")
        ownerLoop.submit(input: snapshot)
    }

    override func keyUp(with event: NSEvent) {
        keyboardState.keyUp(keyCode: event.keyCode)
        let snapshot = keyboardState.snapshot()
        recordInputEvidence("event=keyUp keyCode=\(event.keyCode) sequence=\(snapshot.sequence) held=\(snapshot.held) pressed=\(snapshot.pressed) released=\(snapshot.released)")
        ownerLoop.submit(input: snapshot)
    }

    override func flagsChanged(with event: NSEvent) {
        let isDown: Bool
        switch event.keyCode {
        case 0x37: isDown = event.modifierFlags.contains(.command)
        case 0x38: isDown = event.modifierFlags.contains(.shift)
        case 0x39: isDown = event.modifierFlags.contains(.capsLock)
        case 0x3A: isDown = event.modifierFlags.contains(.option)
        case 0x3B: isDown = event.modifierFlags.contains(.control)
        default: return
        }
        keyboardState.flagsChanged(keyCode: event.keyCode, isDown: isDown)
        let snapshot = keyboardState.snapshot()
        recordInputEvidence("event=flagsChanged keyCode=\(event.keyCode) down=\(isDown ? 1 : 0) sequence=\(snapshot.sequence) held=\(snapshot.held) pressed=\(snapshot.pressed) released=\(snapshot.released)")
        ownerLoop.submit(input: snapshot)
    }

    @objc private func applicationWillResignActive(_ notification: Notification) {
        recordInputEvidence("event=focusLost reset=1 paused=1")
        keyboardState.reset()
        ownerLoop.resetInput()
        ownerLoop.setPaused(true)
    }

    @objc private func applicationDidBecomeActive(_ notification: Notification) {
        recordInputEvidence("event=focusGained paused=0")
        ownerLoop.setPaused(false)
    }

    private func scheduleInputProbe() {
        guard eventProbeEnabled, !didScheduleInputProbe else { return }
        didScheduleInputProbe = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
            guard let self else { return }
            let windowNumber = self.view.window?.windowNumber ?? 0
            let makeKeyEvent: (NSEvent.EventType, Bool) -> NSEvent? = { type, repeatFlag in
                NSEvent.keyEvent(
                    with: type,
                    location: .zero,
                    modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: windowNumber,
                    context: nil,
                    characters: "w",
                    charactersIgnoringModifiers: "w",
                    isARepeat: repeatFlag,
                    keyCode: 0x0D
                )
            }
            self.recordInputEvidence("event=probeSend keyDown source=AppKit.sendEvent")
            if let keyDown = makeKeyEvent(.keyDown, false) { NSApp.sendEvent(keyDown) }
            if let keyUp = makeKeyEvent(.keyUp, false) { NSApp.sendEvent(keyUp) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let self else { return }
                self.recordInputEvidence("event=probeDeactivate")
                NSApp.deactivate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
                    guard let self else { return }
                    self.recordInputEvidence("event=probeActivate")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
    }

    private func scheduleResizeProbe() {
        guard let window = view.window else { return }
        let first = window.contentView?.bounds.size ?? .zero
        window.setContentSize(NSSize(width: 800, height: 450))
        gameView.updateDrawableSize()
        let second = window.contentView?.bounds.size ?? .zero
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, let window = self.view.window else { return }
            window.setContentSize(NSSize(width: 1024, height: 576))
            self.gameView.updateDrawableSize()
            let third = window.contentView?.bounds.size ?? .zero
            try? "resize=1 first=\(Int(first.width))x\(Int(first.height)) second=\(Int(second.width))x\(Int(second.height)) third=\(Int(third.width))x\(Int(third.height))\n".write(
                toFile: "/tmp/goldeneye-m9-resize.log",
                atomically: true,
                encoding: .utf8
            )
        }
    }

    private func schedulePauseProbe() {
        guard pauseProbeEnabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            self.recordInputEvidence("event=syntheticWillResignActive source=NotificationCenter")
            NotificationCenter.default.post(
                name: NSApplication.willResignActiveNotification,
                object: NSApp
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
                guard let self else { return }
                self.recordInputEvidence("event=syntheticDidBecomeActive source=NotificationCenter")
                NotificationCenter.default.post(
                    name: NSApplication.didBecomeActiveNotification,
                    object: NSApp
                )
            }
        }
    }
}

private final class GoldenEyeAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var viewController: GoldenEyeViewController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        viewController = GoldenEyeViewController()
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "GoldenEye Swift"
        window.contentViewController = viewController
        window.minSize = NSSize(width: 640, height: 360)
        window.isRestorable = false
        window.setContentSize(NSSize(width: 960, height: 540))
        // Do not trust a restored/off-screen AppKit frame in a multi-display
        // or remote session: keep the validation window inside a real screen
        // so CoreGraphics captures the same pixels the user can see.
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let visible = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: visible.minX + 80, y: visible.minY + 80))
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        print("GoldenEye AppKit host launched")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewController?.viewIfLoaded?.window?.performClose(nil)
        try? "shutdown=1\n".write(
            toFile: "/tmp/goldeneye-m9-shutdown.log",
            atomically: true,
            encoding: .utf8
        )
        print("GoldenEye AppKit host terminating")
    }
}

private let app = NSApplication.shared
private let delegate = GoldenEyeAppDelegate()
app.delegate = delegate
app.run()
