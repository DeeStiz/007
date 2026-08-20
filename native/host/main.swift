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
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        return metalLayer
    }

    var metalLayer: CAMetalLayer {
        guard let metalLayer = layer as? CAMetalLayer else {
            preconditionFailure("GoldenEyeView must be backed by CAMetalLayer")
        }
        return metalLayer
    }

    /// Product mode routes backing-size changes to the owner thread. Legacy
    /// evidence probes leave this nil and retain their direct layer update.
    var drawableSizePublisher: ((CGSize) -> Void)?

    override func layout() {
        super.layout()
        updateDrawableSize()
    }

    func updateDrawableSize() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0
        metalLayer.contentsScale = scale
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        if let drawableSizePublisher {
            drawableSizePublisher(size)
        } else {
            metalLayer.drawableSize = size
        }
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
    private var titleFlow = GoldenEyeBootFlow()

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
        titleFlow = GoldenEyeBootFlow()
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

    private func titleInput(from keyboard: GoldenEyeKeyboardSnapshot) -> GoldenEyeTitleInput {
        var pressed: UInt16 = 0
        if keyboard.pressed & (1 << 4) != 0 { pressed |= 1 << 0 } // Space -> A
        if keyboard.pressed & (1 << 5) != 0 { pressed |= 1 << 1 } // Escape -> B
        if keyboard.pressed & (1 << 15) != 0 { pressed |= 1 << 2 } // Return -> Start
        if keyboard.pressed & (1 << 16) != 0 { pressed |= 1 << 3 } // Z -> Z
        if keyboard.pressed & (1 << 17) != 0 { pressed |= 1 << 0 } // C -> A
        var stickX: Int8 = 0
        var stickY: Int8 = 0
        if keyboard.held & (1 << 6) != 0 { stickX = -75 }
        if keyboard.held & (1 << 7) != 0 { stickX = 75 }
        if keyboard.held & (1 << 8) != 0 { stickY = -75 }
        if keyboard.held & (1 << 9) != 0 { stickY = 75 }
        return GoldenEyeTitleInput(
            held: 0,
            pressed: pressed,
            released: 0,
            stickX: stickX,
            stickY: stickY,
            focused: true
        )
    }

    private func runBoundedLifecycle() {
        if ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_ORIGINAL_SOURCE"] == "1" {
            let sourceStatus = GoldenEyeOriginalFrontendProductionLink.initialize()
            guard sourceStatus == GE_STATUS_OK else {
                print("GoldenEye original source frontend failed closed: \(sourceStatus)")
                finish()
                return
            }
        }
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
        let titleRuntimeEnabled = ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_TITLE"] == "1"
            || (GoldenEyeFidelityBuildFlavor.current == .debug
                && ProcessInfo.processInfo.environment["GOLDENEYE_DIAGNOSTIC_TITLE_FLOW"] == "1")
        let tickLimit = titleRuntimeEnabled
            ? Int.max
            : (ProcessInfo.processInfo.environment["GOLDENEYE_M3_EVENT_PROBE"] == "1" ? 180 : 60)
        var tick = 1
        while tick <= tickLimit {
            if shouldStop() { break }
            if shouldPause() {
                usleep(titleRuntimeEnabled ? 8_333 : 8_000)
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
            if titleRuntimeEnabled {
                let titleSnapshot = titleFlow.step(input: titleInput(from: keyboardInput))
                (frameRenderer as? GoldenEyeTitleSnapshotRenderer)?.submit(titleSnapshot: titleSnapshot)
            }
            if let frameRenderer, !frameRenderer.renderFrame() {
                print("GoldenEye owner renderer failed")
                break
            }
            usleep(titleRuntimeEnabled ? 8_333 : 8_000)
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
    private var didScheduleCadenceWarmup = false
    private var didScheduleCadenceSafetyTermination = false
    private var cadenceMeasurementStarted = false
    private var cadenceWarmupReadinessDeadline = Date.distantPast
    private var metalDeviceState: AnyObject?
    private var frameRenderer: (any GoldenEyeFrameRenderer)?
    private var nativeTitleOwner: GoldenEyeNativeTitleOwner?
    private var nativeAudioService: GoldenEyeNativeAudioService?
    private let nativeInputMailbox = GoldenEyeInputMailbox()
    private var gameControllerAdapter: GoldenEyeGameControllerAdapter?
    private var baselinePipeline: AnyObject?
    private var gameView: GoldenEyeView { view as! GoldenEyeView }

    private var eventProbeEnabled: Bool {
        ProcessInfo.processInfo.environment["GOLDENEYE_M3_EVENT_PROBE"] == "1"
    }

    private var pauseProbeEnabled: Bool {
        ProcessInfo.processInfo.environment["GOLDENEYE_M5_PAUSE_PROBE"] == "1"
            || ProcessInfo.processInfo.environment["GOLDENEYE_CADENCE_STRESS"] == "1"
    }

    private var cadenceProbeEnabled: Bool {
        ProcessInfo.processInfo.environment["GOLDENEYE_CADENCE_PROBE"] == "1"
    }

    private var cadenceFullscreenRequested: Bool {
        ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_FULLSCREEN"] == "1"
    }

    private var cadenceWarmupSeconds: TimeInterval {
        guard let raw = ProcessInfo.processInfo.environment["GOLDENEYE_CADENCE_WARMUP"],
              let value = TimeInterval(raw), value.isFinite, value >= 0 else {
            return 30
        }
        return min(value, 3_600)
    }

    private var cadenceMeasurementSeconds: TimeInterval {
        guard let raw = ProcessInfo.processInfo.environment["GOLDENEYE_CADENCE_DURATION"],
              let value = TimeInterval(raw), value.isFinite, value > 0 else {
            return 0
        }
        return min(value, 86_400)
    }

    private var cadenceTransitionGraceSeconds: TimeInterval {
        guard let raw = ProcessInfo.processInfo.environment["GOLDENEYE_CADENCE_TRANSITION_GRACE"],
              let value = TimeInterval(raw), value.isFinite, value >= 0 else {
            return 20
        }
        return min(value, 300)
    }

    private var nativeTitleRuntimeEnabled: Bool {
        if GoldenEyeFidelityBuildFlavor.current == .debug,
           ProcessInfo.processInfo.environment["GOLDENEYE_DIAGNOSTIC_TITLE_FLOW"] == "1" {
            return false
        }
        if ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_TITLE"] == "1" {
            return true
        }
        // A Release product always uses the source frontend authority. Debug
        // probes remain opt-in so the legacy bounded owner cannot be selected
        // accidentally by an empty environment.
        return !_isDebugAssertConfiguration()
    }

    private var stageBackgroundRuntimeEnabled: Bool {
        GoldenEyeFidelityBuildFlavor.current == .debug
            && ProcessInfo.processInfo.environment["GOLDENEYE_M27_STAGE_OVERLAY"] == "1"
    }

    private var captureModeEnabled: Bool {
        ProcessInfo.processInfo.environment["GOLDENEYE_CAPTURE_MODE"] == "1"
    }

    private func recordInputEvidence(_ line: String) {
        guard eventProbeEnabled || pauseProbeEnabled || cadenceProbeEnabled else { return }
        let paths: [String] = [
            eventProbeEnabled ? "/tmp/goldeneye-m3-events.log" : "",
            pauseProbeEnabled ? "/tmp/goldeneye-m5-pause.log" : "",
            cadenceProbeEnabled ? "/tmp/goldeneye-cadence-events.log" : "",
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
                let allowsDiagnosticRenderer = GoldenEyeFidelityBuildFlavor.current == .debug
                let wantsClassicProp = allowsDiagnosticRenderer
                    && ProcessInfo.processInfo.environment["GOLDENEYE_M10_PROP"] == "1"
                let wantsClassicTexturedProp = allowsDiagnosticRenderer
                    && ProcessInfo.processInfo.environment["GOLDENEYE_M11_TEXTURED_PROP"] == "1"
                let wantsClassicCombiner = allowsDiagnosticRenderer
                    && ProcessInfo.processInfo.environment["GOLDENEYE_M12_CLASSIC_COMBINER"] == "1"
                let wantsNativeTitle = nativeTitleRuntimeEnabled
                let wantsDiagnosticTitle = allowsDiagnosticRenderer
                    && ProcessInfo.processInfo.environment["GOLDENEYE_DIAGNOSTIC_TITLE_FLOW"] == "1"
                let wantsStageBackground = stageBackgroundRuntimeEnabled
                let wantsPipeline = allowsDiagnosticRenderer
                    && (ProcessInfo.processInfo.environment["GOLDENEYE_M6_PIPELINE"] == "1"
                        || ProcessInfo.processInfo.environment["GOLDENEYE_M8_TRIANGLE"] == "1"
                        || wantsClassicProp
                        || wantsClassicTexturedProp
                        || wantsClassicCombiner
                        || wantsStageBackground)
                if wantsStageBackground {
                    do {
                        guard let libraryURL = Bundle.main.url(forResource: "GoldenEyeStageBackground", withExtension: "metallib") else {
                            print("GoldenEye stage background metallib is missing")
                            return
                        }
                        let pipeline = try GoldenEyeStageBackgroundPipeline(device: device, libraryURL: libraryURL)
                        baselinePipeline = pipeline
                        let stageRoot = ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_STAGE_ASSET_ROOT"]
                            .map { URL(fileURLWithPath: $0, isDirectory: true) }
                        guard let stageRoot else {
                            print("GoldenEye stage asset root is missing")
                            return
                        }
                        let stageID: UInt32
                        if let rawStageID = ProcessInfo.processInfo.environment["GOLDENEYE_M27_STAGE_ID"] {
                            guard let parsedStageID = UInt32(rawStageID) else {
                                throw GoldenEyeStageBackgroundPipelineError.creationFailed(
                                    "invalid stage ID \(rawStageID)"
                                )
                            }
                            stageID = parsedStageID
                        } else {
                            stageID = 33
                        }
                        frameRenderer = try GoldenEyeMetalStageBackgroundRenderer(
                            state: state,
                            layer: gameView.metalLayer,
                            pipeline: pipeline,
                            assetRoot: stageRoot,
                            stageID: stageID
                        )
                    } catch {
                        print("GoldenEye stage background renderer failed: \(error)")
                        return
                    }
                } else if allowsDiagnosticRenderer,
                          wantsNativeTitle,
                   ProcessInfo.processInfo.environment["GOLDENEYE_CADENCE_RENDERER"] == "clear" {
                    // Measurement-only isolate: this bypasses title asset and
                    // shader work so cadence diagnostics can distinguish a
                    // presentation path fault from title rendering work.
                    frameRenderer = GoldenEyeMetalClearRenderer(state: state, layer: gameView.metalLayer)
                } else if wantsDiagnosticTitle {
                    do {
                        guard let libraryURL = Bundle.main.url(forResource: "GoldenEyeTitle", withExtension: "metallib") else {
                            print("GoldenEye diagnostic title metallib is missing")
                            return
                        }
                        let pipeline = try GoldenEyeTitlePipeline(device: device, libraryURL: libraryURL)
                        baselinePipeline = pipeline
                        let assetRoot = ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_ASSET_ROOT"]
                            .map { URL(fileURLWithPath: $0, isDirectory: true) }
                        frameRenderer = try GoldenEyeMetalTitleRenderer(
                            state: state,
                            layer: gameView.metalLayer,
                            pipeline: pipeline,
                            assetRoot: assetRoot
                        )
                    } catch {
                        print("GoldenEye diagnostic title renderer failed: \(error)")
                        return
                    }
                } else if wantsNativeTitle {
                    do {
                        guard let rawSourceRoot = ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_SOURCE_FRONTEND_ROOT"],
                              !rawSourceRoot.isEmpty else {
                            throw GoldenEyeSourceProductRendererV6Error.missingPreparedRoot
                        }
                        if GoldenEyeFidelityBuildFlavor.current == .release,
                           ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_ASSET_ROOT"] == nil {
                            throw GoldenEyeSourceProductRendererV6Error.missingAudioAssetRoot
                        }
                        guard let libraryURL = Bundle.main.url(
                            forResource: "GoldenEyeSourceSceneV6",
                            withExtension: "metallib"
                        ) else {
                            throw GoldenEyeSourceProductRendererV6Error.missingPipelineLibrary
                        }
                        guard let source2DLibraryURL = Bundle.main.url(
                            forResource: "GoldenEyeSource2DV6",
                            withExtension: "metallib"
                        ) else {
                            throw GoldenEyeSourceProductRendererV6Error.missing2DPipelineLibrary
                        }
                        let sourceRoot = URL(
                            fileURLWithPath: rawSourceRoot,
                            isDirectory: true
                        )
                        // The provider consumes the same guarded GESM values
                        // as the product preparation path.  It owns no ROM or
                        // Metal object and never supplies an identity default.
                        let preparation = try GoldenEyeSourceProductPreparationV6.load(
                            rootURL: sourceRoot
                        )
                        // Gunbarrel's prepared character GESM packets live in
                        // the guarded Cast root and intentionally replace the
                        // older title-side model rows.  Give the matrix
                        // provider the same merged value catalog that the
                        // renderer consumes; otherwise the source frontend
                        // path cannot discover suitbond's typed model handle
                        // and fails before the dynamic Gunbarrel scene.
                        var matrixModels = preparation.models
                        if let rawCastRoot = ProcessInfo.processInfo.environment[
                            "GOLDENEYE_NATIVE_CAST_ASSET_ROOT"
                        ], !rawCastRoot.isEmpty {
                            let castPreparation = try GoldenEyeCastPreparedAssetCatalogV6.load(
                                rootURL: URL(fileURLWithPath: rawCastRoot, isDirectory: true)
                            )
                            for (name, model) in castPreparation.models {
                                matrixModels[name] = model
                            }
                        }
                        let matrixProvider = try GoldenEyeSourceFrontendMatrixProviderV6(
                            models: matrixModels,
                            viewportWidth: 440,
                            viewportHeight: 330
                        )
                        frameRenderer = try GoldenEyeSourceProductRendererV6(
                            state: state,
                            sourceRoot: sourceRoot,
                            libraryURL: libraryURL,
                            source2DLibraryURL: source2DLibraryURL,
                            outputMode: .faithfulHD,
                            frameResourceProvider: matrixProvider
                        )
                    } catch {
                        print("GoldenEye source product renderer failed: \(error)")
                        return
                    }
                } else if wantsPipeline {
                    do {
                        if wantsClassicCombiner {
                            guard let libraryURL = Bundle.main.url(forResource: "GoldenEyeClassicCombinerProp", withExtension: "metallib") else {
                                print("GoldenEye classic combiner prop metallib is missing")
                                return
                            }
                            let pipeline = try GoldenEyeClassicCombinerPropPipeline(device: device, libraryURL: libraryURL)
                            baselinePipeline = pipeline
                            let propBlob = try GoldenEyeClassicPropAsset.loadFromEnvironment()
                            let textureBlobs = try GoldenEyeClassicPropAsset.loadTextureBlobsFromEnvironment()
                            let materials = GoldenEyeClassicPropAsset.textureMaterials()
                            frameRenderer = try GoldenEyeMetalClassicCombinerPropRenderer(
                                state: state,
                                layer: gameView.metalLayer,
                                pipeline: pipeline,
                                propBlob: propBlob,
                                materials: materials,
                                textureBlobs: textureBlobs
                            )
                        } else if wantsClassicTexturedProp {
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
        if (nativeTitleRuntimeEnabled || stageBackgroundRuntimeEnabled), let frameRenderer {
            let controllerAdapter = GoldenEyeGameControllerAdapter(mailbox: nativeInputMailbox)
            gameControllerAdapter = controllerAdapter
            let assetRoot = ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_ASSET_ROOT"]
                .map { URL(fileURLWithPath: $0, isDirectory: true) }
            let audioService = nativeTitleRuntimeEnabled
                ? assetRoot.map { GoldenEyeNativeAudioService(assetRoot: $0) }
                : nil
            nativeAudioService = audioService
            let nativeOwner: GoldenEyeNativeTitleOwner
            do {
                if let sourceRenderer = frameRenderer as? GoldenEyeSourceProductRendererV6 {
                    try sourceRenderer.prewarmSourceTitleScenes()
                }
                nativeOwner = try GoldenEyeNativeTitleOwner(
                    renderer: frameRenderer,
                    layer: gameView.metalLayer,
                    inputMailbox: nativeInputMailbox,
                    audioService: audioService,
                    inputPoller: { [weak controllerAdapter] in
                        controllerAdapter?.poll()
                    }
                )
            } catch {
                // Source authority construction is a Release gate.  Do not
                // start the owner or select the handwritten flow when it
                // fails; preserve the exact error as launch evidence.
                print("GoldenEye source frontend authority failed: \(error)")
                try? "authorityInitializationFailure=\(error)\n".write(
                    toFile: "/tmp/goldeneye-source-frontend-owner.log",
                    atomically: true,
                    encoding: .utf8
                )
                return
            }
            nativeTitleOwner = nativeOwner
            gameView.drawableSizePublisher = { [weak nativeOwner] size in
                nativeOwner?.requestDrawableSize(size)
            }
            nativeOwner.requestDrawableSize(gameView.metalLayer.drawableSize)
            nativeOwner.requestPreferredFrameRateRange(
                CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            )
            nativeOwner.start()
            guard nativeOwner.waitUntilRunning() else {
                print("GoldenEye native title owner failed to start")
                nativeTitleOwner = nil
                return
            }
        } else {
            ownerLoop.start(renderer: frameRenderer)
        }
        scheduleInputProbe()
        schedulePauseProbe()
        if ProcessInfo.processInfo.environment["GOLDENEYE_M9_RESIZE"] == "1"
            || ProcessInfo.processInfo.environment["GOLDENEYE_M12_RESIZE"] == "1"
            || ProcessInfo.processInfo.environment["GOLDENEYE_CADENCE_STRESS"] == "1" {
            scheduleResizeProbe()
        }
        scheduleNativeTitleSmokeInput()
        scheduleCadenceWarmup()
        scheduleCadenceTermination()
        scheduleCadenceKeepAlive()
    }

    override func viewWillDisappear() {
        stopRuntimeForTermination()
        super.viewWillDisappear()
    }

    /// AppKit may deliver application termination without a preceding window
    /// disappearance. Stop the owner/display-link path explicitly so the
    /// renderer can drain its Metal 4 completion fence and publish shutdown
    /// evidence before the process exits.
    func stopRuntimeForTermination() {
        gameControllerAdapter?.stop()
        gameControllerAdapter = nil
        gameView.drawableSizePublisher = nil
        nativeTitleOwner?.stop()
        nativeTitleOwner = nil
        nativeAudioService = nil
        ownerLoop.stop()
    }

    override func keyDown(with event: NSEvent) {
        keyboardState.keyDown(keyCode: event.keyCode, isRepeat: event.isARepeat)
        if nativeTitleRuntimeEnabled {
            nativeInputMailbox.enqueueKeyboard(
                keyCode: event.keyCode,
                isDown: true,
                isRepeat: event.isARepeat
            )
        }
        let snapshot = keyboardState.snapshot()
        recordInputEvidence("event=keyDown keyCode=\(event.keyCode) repeat=\(event.isARepeat ? 1 : 0) sequence=\(snapshot.sequence) held=\(snapshot.held) pressed=\(snapshot.pressed) released=\(snapshot.released)")
        if let nativeTitleOwner { nativeTitleOwner.submit(input: snapshot) }
        else { ownerLoop.submit(input: snapshot) }
    }

    override func keyUp(with event: NSEvent) {
        keyboardState.keyUp(keyCode: event.keyCode)
        if nativeTitleRuntimeEnabled {
            nativeInputMailbox.enqueueKeyboard(keyCode: event.keyCode, isDown: false)
        }
        let snapshot = keyboardState.snapshot()
        recordInputEvidence("event=keyUp keyCode=\(event.keyCode) sequence=\(snapshot.sequence) held=\(snapshot.held) pressed=\(snapshot.pressed) released=\(snapshot.released)")
        if let nativeTitleOwner { nativeTitleOwner.submit(input: snapshot) }
        else { ownerLoop.submit(input: snapshot) }
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
        if let nativeTitleOwner { nativeTitleOwner.submit(input: snapshot) }
        else { ownerLoop.submit(input: snapshot) }
    }

    @objc private func applicationWillResignActive(_ notification: Notification) {
        if captureModeEnabled { return }
        recordInputEvidence("event=focusLost reset=1 paused=1")
        keyboardState.reset()
        if nativeTitleRuntimeEnabled { nativeInputMailbox.enqueueFocusLost() }
        nativeTitleOwner?.resetInput()
        nativeTitleOwner?.setPaused(true)
        ownerLoop.resetInput()
        ownerLoop.setPaused(true)
    }

    @objc private func applicationDidBecomeActive(_ notification: Notification) {
        if captureModeEnabled { return }
        recordInputEvidence("event=focusGained paused=0")
        if nativeTitleRuntimeEnabled { nativeInputMailbox.enqueueFocusGained() }
        nativeTitleOwner?.setPaused(false)
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

    /// Bounded Release measurement runs terminate through AppKit so the
    /// owner-thread display link and renderer shutdown paths produce their
    /// normal telemetry. Production launches never set this variable.
    private func scheduleCadenceTermination() {
        guard cadenceProbeEnabled,
              cadenceMeasurementSeconds > 0 else { return }
        guard !didScheduleCadenceSafetyTermination else { return }
        didScheduleCadenceSafetyTermination = true
        let safetySeconds = cadenceWarmupSeconds
            + cadenceTransitionGraceSeconds
            + cadenceMeasurementSeconds
            + 10
        DispatchQueue.main.asyncAfter(deadline: .now() + safetySeconds) { [weak self] in
            guard let self else { return }
            guard !self.cadenceMeasurementStarted else { return }
            self.recordInputEvidence(
                "event=measurementSafetyTerminate warmup=\(self.cadenceWarmupSeconds) "
                    + "duration=\(self.cadenceMeasurementSeconds)"
            )
            NSApp.terminate(nil)
        }
    }

    /// A direct Release measurement process is launched from a shell, which
    /// can immediately reclaim AppKit foreground status after the window
    /// enters fullscreen. Keep the probe window active for its bounded run so
    /// Core Animation does not intentionally throttle its display link.
    private func scheduleCadenceKeepAlive() {
        guard cadenceProbeEnabled,
              cadenceMeasurementSeconds > 0 else { return }
        let deadline = Date().addingTimeInterval(
            cadenceWarmupSeconds
                + cadenceTransitionGraceSeconds
                + cadenceMeasurementSeconds
                + 10
        )
        func keepAlive() {
            guard Date() < deadline else { return }
            NSApp.activate(ignoringOtherApps: true)
            self.view.window?.makeKeyAndOrderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                keepAlive()
            }
        }
        keepAlive()
    }

    /// Warmup is deliberately outside the measured epoch. It absorbs launch,
    /// shader/resource residency, fullscreen migration, and Core Audio route
    /// startup before the owner resets all timing/hash counters atomically.
    private func scheduleCadenceWarmup() {
        guard cadenceProbeEnabled,
              cadenceMeasurementSeconds > 0,
              !didScheduleCadenceWarmup else { return }
        didScheduleCadenceWarmup = true
        cadenceWarmupReadinessDeadline = Date().addingTimeInterval(
            cadenceWarmupSeconds + cadenceTransitionGraceSeconds
        )
        recordInputEvidence(
            "event=warmupBegin seconds=\(cadenceWarmupSeconds) "
                + "measurementDuration=\(cadenceMeasurementSeconds) "
                + "fullscreenRequested=\(cadenceFullscreenRequested ? 1 : 0)"
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + cadenceWarmupSeconds) { [weak self] in
            self?.attemptCadenceMeasurementStart()
        }
    }

    private func attemptCadenceMeasurementStart() {
        guard cadenceProbeEnabled,
              !cadenceMeasurementStarted else { return }

        let window = view.window
        let isActive = NSApp.isActive
        let isKey = window?.isKeyWindow ?? false
        let isVisible = window?.isVisible == true
            && window?.occlusionState.contains(.visible) == true
        let isFullscreen = window?.styleMask.contains(.fullScreen) == true
        let transitionReady = !cadenceFullscreenRequested || isFullscreen
        guard isActive && isKey && isVisible && transitionReady else {
            if Date() < cadenceWarmupReadinessDeadline {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    self?.attemptCadenceMeasurementStart()
                }
            } else {
                recordInputEvidence(
                    "event=measurementEpochReset=0 reason=readinessTimeout active=\(isActive ? 1 : 0) "
                        + "key=\(isKey ? 1 : 0) visible=\(isVisible ? 1 : 0) "
                        + "fullscreen=\(isFullscreen ? 1 : 0) "
                        + "fullscreenRequested=\(cadenceFullscreenRequested ? 1 : 0)"
                )
            }
            return
        }

        recordInputEvidence(
            "event=activeGateReady=1 active=1 key=1 visible=1 fullscreen=\(isFullscreen ? 1 : 0) "
                + "presentationMode=\(isFullscreen ? "direct-eligible-unverified" : "composited-window") "
                + "hud=\(ProcessInfo.processInfo.environment["GOLDENEYE_CADENCE_HUD_STATE"] ?? "unobserved")"
        )
        guard let nativeTitleOwner,
              nativeTitleOwner.resetMeasurementEpoch(timeout: 5.0) else {
            if Date() < cadenceWarmupReadinessDeadline {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    self?.attemptCadenceMeasurementStart()
                }
            } else {
                recordInputEvidence("event=measurementEpochReset=0 reason=ownerUnavailable")
            }
            return
        }

        cadenceMeasurementStarted = true
        let ownerTelemetry = nativeTitleOwner.telemetry()
        recordInputEvidence(
            "event=measurementEpochReset=1 generation=\(ownerTelemetry.measurementEpochGeneration) "
                + "rawNs=\(ownerTelemetry.measurementEpochNanoseconds) "
                + "warmupSeconds=\(cadenceWarmupSeconds) "
                + "measurementDuration=\(cadenceMeasurementSeconds)"
        )
        let duration = cadenceMeasurementSeconds
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.cadenceMeasurementStarted else { return }
            self.recordInputEvidence(
                "event=measurementTerminate seconds=\(duration) afterEpoch=1"
            )
            NSApp.terminate(nil)
        }
    }

    /// Test-only source-permitted confirms. Production never injects these;
    /// the harness uses them to reach File Select/Mode Select without relying
    /// on external Accessibility permissions or a physical keyboard.
    private func scheduleNativeTitleSmokeInput() {
        guard nativeTitleRuntimeEnabled,
              ProcessInfo.processInfo.environment["GOLDENEYE_TITLE_SMOKE_INPUT"] == "1" else { return }
        let fileSelectOnly = ProcessInfo.processInfo.environment["GOLDENEYE_TITLE_SMOKE_INPUT_MODE"] == "file-select"
        let delays: [TimeInterval] = fileSelectOnly
            ? [5.0, 5.8, 6.6, 7.4]
            : [5.0, 5.8, 6.6, 7.4, 8.2]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.nativeInputMailbox.enqueueKeyboard(keyCode: 0x24, isDown: true)
                self.nativeInputMailbox.enqueueKeyboard(keyCode: 0x24, isDown: false)
            }
        }
    }
}

@MainActor
private final class GoldenEyeAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
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
        window.delegate = self
        window.minSize = NSSize(width: 640, height: 360)
        window.isRestorable = false
        window.setContentSize(NSSize(width: 960, height: 540))
        if ProcessInfo.processInfo.environment["GOLDENEYE_CADENCE_PROBE"] == "1" {
            // Measurement launches originate from a non-AppKit shell. Keep
            // the probe surface visible/ordered so WindowServer and
            // CAMetalDisplayLink do not classify it as an occluded window.
            if ProcessInfo.processInfo.environment["GOLDENEYE_CADENCE_NO_FLOATING"] != "1" {
                window.level = .floating
                window.collectionBehavior = [.fullScreenPrimary, .moveToActiveSpace]
            }
        }
        // Do not trust a restored/off-screen AppKit frame in a multi-display
        // or remote session: keep the validation window inside a real screen
        // so CoreGraphics captures the same pixels the user can see.
        let prefers120Fullscreen = ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_FULLSCREEN"] == "1"
        let requestedDisplay = ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_DISPLAY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedScreen: NSScreen? = requestedDisplay.flatMap { requested in
            guard !requested.isEmpty else { return nil }
            let normalized = requested.lowercased()
            return NSScreen.screens.first {
                let localized = $0.localizedName.lowercased()
                if localized.contains(normalized) { return true }
                // SPDisplaysDataType calls the internal panel "Color LCD",
                // while NSScreen exposes the same 120 Hz panel as
                // "Built-in Retina Display". Keep this alias cadence-only;
                // production launches do not select a display by name.
                return (normalized == "color lcd" && localized.contains("built-in retina"))
                    || (normalized.contains("built-in retina") && localized.contains("color lcd"))
            }
        }
        let preferredScreen = requestedScreen ?? (prefers120Fullscreen
            ? NSScreen.screens.first(where: { $0.minimumRefreshInterval <= (1.0 / 120.0 + 0.0001) })
            : nil)
        if let screen = preferredScreen ?? NSScreen.main ?? NSScreen.screens.first {
            let visible = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: visible.minX + 80, y: visible.minY + 80))
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        recordCadenceWindowState(event: "activeGateObserved")
        if prefers120Fullscreen {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                if ProcessInfo.processInfo.environment["GOLDENEYE_CADENCE_PROBE"] == "1" {
                    try? "event=fullscreenMigrationBegin\n".write(
                        toFile: "/tmp/goldeneye-cadence-events.log",
                        atomically: true,
                        encoding: .utf8
                    )
                }
                self?.window.toggleFullScreen(nil)
            }
        }
        print("GoldenEye AppKit host launched")
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        guard cadenceProbeEnabled else { return }
        recordCadenceWindowState(event: "fullscreenEntryReady")
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        guard cadenceProbeEnabled else { return }
        recordCadenceWindowState(event: "fullscreenExitObserved")
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard cadenceProbeEnabled else { return }
        recordCadenceWindowState(event: "windowKeyObserved")
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard cadenceProbeEnabled else { return }
        recordCadenceWindowState(event: "windowOcclusionChanged")
    }

    private var cadenceProbeEnabled: Bool {
        ProcessInfo.processInfo.environment["GOLDENEYE_CADENCE_PROBE"] == "1"
    }

    private func recordCadenceWindowState(event: String) {
        guard cadenceProbeEnabled else { return }
        let isFullscreen = window?.styleMask.contains(.fullScreen) == true
        let active = NSApp.isActive
        let key = window?.isKeyWindow == true
        let visible = window?.isVisible == true
            && window?.occlusionState.contains(.visible) == true
        let mode = isFullscreen ? "direct-eligible-unverified" : "composited-window"
        let hudState = ProcessInfo.processInfo.environment["GOLDENEYE_CADENCE_HUD_STATE"] ?? "unobserved"
        let line = "event=\(event)=1 value=1 active=\(active ? 1 : 0) key=\(key ? 1 : 0) "
            + "visible=\(visible ? 1 : 0) fullscreen=\(isFullscreen ? 1 : 0) "
            + "presentationMode=\(mode) hud=\(hudState)\n"
        let url = URL(fileURLWithPath: "/tmp/goldeneye-cadence-events.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            try? handle.write(contentsOf: Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url, options: .atomic)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewController?.stopRuntimeForTermination()
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
