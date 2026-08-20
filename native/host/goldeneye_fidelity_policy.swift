import Foundation

/// The presentation modes that are allowed by the source-faithful renderer.
///
/// The mode is deliberately selected by the caller.  In particular, the
/// policy never promotes a diagnostic renderer, an incomplete packet, or an
/// environment variable into an effective output mode.
public enum GoldenEyeFidelityOutputMode: UInt8, CaseIterable, Sendable, Equatable {
    /// Native-resolution rendering with the complete 440x330 source canvas
    /// uniformly fitted into the drawable.  The 4:3 composition is centered
    /// and never stretched.
    case faithfulHD = 0

    /// A compositor-independent 320x240 target using the exact source
    /// 440x330-to-320x240 scale.  The target dimensions do not depend on the
    /// window or display size supplied to the layout initializer.
    case reference320x240 = 1

    /// Widescreen presentation with the source 440-unit UI core preserved.
    /// Only the declared neutral/3D viewport may consume the side expansion.
    case adaptiveWidescreen = 2
}

public extension GoldenEyeFidelityOutputMode {
    var allowsWidescreenExpansion: Bool {
        self == .adaptiveWidescreen
    }
}

/// Build flavor is explicit so release gates can be exercised without
/// depending on the configuration of the test process.
public enum GoldenEyeFidelityBuildFlavor: UInt8, Sendable, Equatable {
    case debug = 0
    case release = 1

    public static var current: Self {
#if DEBUG
        return .debug
#else
        return .release
#endif
    }
}

/// Environment switches which historically enabled partial or diagnostic
/// rendering.  They are identifiers only; this policy never reads them to
/// select a renderer or a fallback.
public enum GoldenEyeFidelityDiagnosticPath: String, CaseIterable, Sendable, Equatable {
    case partialGeometry = "GOLDENEYE_TITLE_PARTIAL_GEOMETRY"
    case getuDraw = "GOLDENEYE_TITLE_GETU_DRAW"
    case diagnosticTitle = "GOLDENEYE_DIAGNOSTIC_TITLE_FLOW"
    case baselinePipeline = "GOLDENEYE_M6_PIPELINE"
    case triangleProbe = "GOLDENEYE_M8_TRIANGLE"
    case classicProp = "GOLDENEYE_M10_PROP"
    case classicTexturedProp = "GOLDENEYE_M11_TEXTURED_PROP"
    case classicCombiner = "GOLDENEYE_M12_CLASSIC_COMBINER"
    case stageOverlay = "GOLDENEYE_M27_STAGE_OVERLAY"
    case cadenceClearRenderer = "GOLDENEYE_CADENCE_RENDERER"

    fileprivate func isRequested(by value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if self == .cadenceClearRenderer {
            return normalized == "clear"
        }
        switch normalized {
        case "1", "true", "yes", "on": return true
        default: return false
        }
    }
}

public enum GoldenEyeFidelityViolation: Sendable, Equatable, CustomStringConvertible {
    case diagnosticPathEnabled(GoldenEyeFidelityDiagnosticPath)
    case missingEvidence
    case sourceManifestMissing
    case sourceManifestMismatch(expected: UInt64, rendered: UInt64)
    case visibleCommandCountMismatch(expected: UInt32, emitted: UInt32)
    case unsupportedVisibleCommands(UInt32)
    case resourceCountMismatch(expected: UInt32, resident: UInt32)
    case missingResources(UInt32)
    case invalidResourceEvidence

    public var description: String {
        switch self {
        case let .diagnosticPathEnabled(path):
            return "diagnostic path enabled: \(path.rawValue)"
        case .missingEvidence:
            return "visible-command/resource evidence is missing"
        case .sourceManifestMissing:
            return "source and rendered manifests must be non-zero"
        case let .sourceManifestMismatch(expected, rendered):
            return "source manifest mismatch expected=\(expected) rendered=\(rendered)"
        case let .visibleCommandCountMismatch(expected, emitted):
            return "visible command count mismatch expected=\(expected) emitted=\(emitted)"
        case let .unsupportedVisibleCommands(count):
            return "unsupported visible commands: \(count)"
        case let .resourceCountMismatch(expected, resident):
            return "resident resource count mismatch expected=\(expected) resident=\(resident)"
        case let .missingResources(count):
            return "missing resources: \(count)"
        case .invalidResourceEvidence:
            return "resource evidence contains an invalid count"
        }
    }
}

/// Evidence emitted by the source-frame producer for one immutable frame.
///
/// Counts are intentionally copied values.  A source frame is complete only
/// when every visible command and required resource has a corresponding
/// native record and both sides agree on the source manifest hash.
public struct GoldenEyeFidelityEvidence: Sendable, Equatable {
    public let sourceManifestHash: UInt64
    public let renderedManifestHash: UInt64
    public let expectedVisibleCommandCount: UInt32
    public let emittedVisibleCommandCount: UInt32
    public let unsupportedVisibleCommandCount: UInt32
    public let expectedResourceCount: UInt32
    public let residentResourceCount: UInt32
    public let missingResourceCount: UInt32

    public init(
        sourceManifestHash: UInt64,
        renderedManifestHash: UInt64,
        expectedVisibleCommandCount: UInt32,
        emittedVisibleCommandCount: UInt32,
        unsupportedVisibleCommandCount: UInt32,
        expectedResourceCount: UInt32,
        residentResourceCount: UInt32,
        missingResourceCount: UInt32
    ) {
        self.sourceManifestHash = sourceManifestHash
        self.renderedManifestHash = renderedManifestHash
        self.expectedVisibleCommandCount = expectedVisibleCommandCount
        self.emittedVisibleCommandCount = emittedVisibleCommandCount
        self.unsupportedVisibleCommandCount = unsupportedVisibleCommandCount
        self.expectedResourceCount = expectedResourceCount
        self.residentResourceCount = residentResourceCount
        self.missingResourceCount = missingResourceCount
    }

    public func violations() -> [GoldenEyeFidelityViolation] {
        var result: [GoldenEyeFidelityViolation] = []
        if sourceManifestHash == 0 || renderedManifestHash == 0 {
            result.append(.sourceManifestMissing)
        } else if sourceManifestHash != renderedManifestHash {
            result.append(.sourceManifestMismatch(
                expected: sourceManifestHash,
                rendered: renderedManifestHash
            ))
        }
        if expectedVisibleCommandCount != emittedVisibleCommandCount {
            result.append(.visibleCommandCountMismatch(
                expected: expectedVisibleCommandCount,
                emitted: emittedVisibleCommandCount
            ))
        }
        if unsupportedVisibleCommandCount != 0 {
            result.append(.unsupportedVisibleCommands(unsupportedVisibleCommandCount))
        }
        if residentResourceCount > expectedResourceCount {
            result.append(.invalidResourceEvidence)
        } else if residentResourceCount != expectedResourceCount {
            result.append(.resourceCountMismatch(
                expected: expectedResourceCount,
                resident: residentResourceCount
            ))
        }
        if missingResourceCount != 0 {
            result.append(.missingResources(missingResourceCount))
        }
        return result
    }

    public var isComplete: Bool {
        violations().isEmpty
    }
}

/// A source-to-output transform for the frontend's canonical 440x330 space.
/// Coordinates are top-left origin, matching the source UI and AppKit view.
public struct GoldenEyeFidelityLayout: Sendable, Equatable {
    public struct Point: Sendable, Equatable {
        public let x: Double
        public let y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    public struct Rect: Sendable, Equatable {
        public let minX: Double
        public let minY: Double
        public let maxX: Double
        public let maxY: Double

        public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
            self.minX = minX
            self.minY = minY
            self.maxX = maxX
            self.maxY = maxY
        }

        public var width: Double { maxX - minX }
        public var height: Double { maxY - minY }

        public func contains(_ point: Point) -> Bool {
            point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
        }
    }

    public static let sourceWidth = 440.0
    public static let sourceHeight = 330.0
    public static let referenceWidth = 320.0
    public static let referenceHeight = 240.0

    public let mode: GoldenEyeFidelityOutputMode
    public let drawableWidth: Double
    public let drawableHeight: Double
    public let outputWidth: Double
    public let outputHeight: Double
    public let scale: Double
    public let originX: Double
    public let originY: Double
    /// Source-space side expansion for adaptive widescreen.  It is zero for
    /// Faithful HD and for the fixed reference target.
    public let sideGutter: Double
    public let sourceRectInOutput: Rect

    public init(
        mode: GoldenEyeFidelityOutputMode,
        drawableWidth: Double,
        drawableHeight: Double
    ) {
        precondition(drawableWidth > 0 && drawableHeight > 0)
        self.mode = mode
        self.drawableWidth = drawableWidth
        self.drawableHeight = drawableHeight

        switch mode {
        case .reference320x240:
            outputWidth = Self.referenceWidth
            outputHeight = Self.referenceHeight
            scale = Self.referenceWidth / Self.sourceWidth
            originX = 0
            originY = 0
            sideGutter = 0
            sourceRectInOutput = Rect(
                minX: 0,
                minY: 0,
                maxX: Self.referenceWidth,
                maxY: Self.referenceHeight
            )

        case .faithfulHD:
            outputWidth = drawableWidth
            outputHeight = drawableHeight
            scale = min(drawableWidth / Self.sourceWidth, drawableHeight / Self.sourceHeight)
            let contentWidth = Self.sourceWidth * scale
            let contentHeight = Self.sourceHeight * scale
            originX = (drawableWidth - contentWidth) * 0.5
            originY = (drawableHeight - contentHeight) * 0.5
            sideGutter = 0
            sourceRectInOutput = Rect(
                minX: originX,
                minY: originY,
                maxX: originX + contentWidth,
                maxY: originY + contentHeight
            )

        case .adaptiveWidescreen:
            outputWidth = drawableWidth
            outputHeight = drawableHeight
            scale = min(drawableWidth / Self.sourceWidth, drawableHeight / Self.sourceHeight)
            let contentWidth = Self.sourceWidth * scale
            let contentHeight = Self.sourceHeight * scale
            originX = 0
            originY = (drawableHeight - contentHeight) * 0.5
            sideGutter = max(0, (drawableWidth / scale - Self.sourceWidth) * 0.5)
            sourceRectInOutput = Rect(
                minX: sideGutter * scale,
                minY: originY,
                maxX: sideGutter * scale + contentWidth,
                maxY: originY + contentHeight
            )
        }
    }

    /// Maps canonical source coordinates into the output surface.  For the
    /// fixed reference mode the output surface is always 320x240, regardless
    /// of the display drawable passed to the initializer.
    public func sourceToOutput(_ point: Point) -> Point {
        switch mode {
        case .reference320x240:
            return Point(x: point.x * scale, y: point.y * scale)
        case .faithfulHD:
            return Point(x: originX + point.x * scale, y: originY + point.y * scale)
        case .adaptiveWidescreen:
            return Point(
                x: (point.x + sideGutter) * scale,
                y: originY + point.y * scale
            )
        }
    }

    /// Inverse of ``sourceToOutput`` for hit testing.  It intentionally does
    /// not clamp: callers can distinguish side gutters or letterbox regions
    /// from a source hit by checking the returned point against 440x330.
    public func outputToSource(_ point: Point) -> Point {
        switch mode {
        case .reference320x240:
            return Point(x: point.x / scale, y: point.y / scale)
        case .faithfulHD:
            return Point(
                x: (point.x - originX) / scale,
                y: (point.y - originY) / scale
            )
        case .adaptiveWidescreen:
            return Point(
                x: point.x / scale - sideGutter,
                y: (point.y - originY) / scale
            )
        }
    }

    public func sourceToOutputRect(_ rect: Rect) -> Rect {
        let lower = sourceToOutput(Point(x: rect.minX, y: rect.minY))
        let upper = sourceToOutput(Point(x: rect.maxX, y: rect.maxY))
        return Rect(minX: lower.x, minY: lower.y, maxX: upper.x, maxY: upper.y)
    }

    public func outputToSourceRect(_ rect: Rect) -> Rect {
        let lower = outputToSource(Point(x: rect.minX, y: rect.minY))
        let upper = outputToSource(Point(x: rect.maxX, y: rect.maxY))
        return Rect(minX: lower.x, minY: lower.y, maxX: upper.x, maxY: upper.y)
    }
}

public struct GoldenEyeFidelityResolution: Sendable, Equatable {
    public let requestedMode: GoldenEyeFidelityOutputMode
    public let effectiveMode: GoldenEyeFidelityOutputMode
    public let layout: GoldenEyeFidelityLayout
    public let buildFlavor: GoldenEyeFidelityBuildFlavor
    public let diagnostics: [GoldenEyeFidelityDiagnosticPath]
    public let blockingViolations: [GoldenEyeFidelityViolation]

    /// This is always false.  A policy result may identify a diagnostic path,
    /// but it cannot silently turn that path into the effective renderer.
    public let fallbackEnabled: Bool = false

    public var isAccepted: Bool { blockingViolations.isEmpty }

    public var requiresExplicitDiagnosticHandling: Bool {
        !diagnostics.isEmpty
    }
}

public enum GoldenEyeFidelityPolicy {
    public static let defaultMode: GoldenEyeFidelityOutputMode = .faithfulHD

    public static func resolve(
        mode: GoldenEyeFidelityOutputMode = defaultMode,
        drawableWidth: Double,
        drawableHeight: Double,
        buildFlavor: GoldenEyeFidelityBuildFlavor = .current,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        evidence: GoldenEyeFidelityEvidence? = nil
    ) -> GoldenEyeFidelityResolution {
        let layout = GoldenEyeFidelityLayout(
            mode: mode,
            drawableWidth: drawableWidth,
            drawableHeight: drawableHeight
        )
        let diagnostics = GoldenEyeFidelityDiagnosticPath.allCases.filter {
            guard let value = environment[$0.rawValue] else { return false }
            return $0.isRequested(by: value)
        }

        var violations = evidence?.violations() ?? [.missingEvidence]
        if buildFlavor == .release {
            violations.append(contentsOf: diagnostics.map { .diagnosticPathEnabled($0) })
        }

        return GoldenEyeFidelityResolution(
            requestedMode: mode,
            effectiveMode: mode,
            layout: layout,
            buildFlavor: buildFlavor,
            diagnostics: diagnostics,
            blockingViolations: violations
        )
    }

}
