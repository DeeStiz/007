import Foundation

@main
struct GoldenEyeFidelityPolicySmoke {
    private static let epsilon = 0.000_000_1

    private static func approximately(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) <= epsilon
    }

    private static func requireRoundTrip(
        _ layout: GoldenEyeFidelityLayout,
        _ point: GoldenEyeFidelityLayout.Point
    ) {
        let output = layout.sourceToOutput(point)
        let roundTrip = layout.outputToSource(output)
        precondition(approximately(roundTrip.x, point.x))
        precondition(approximately(roundTrip.y, point.y))
    }

    private static func completeEvidence() -> GoldenEyeFidelityEvidence {
        GoldenEyeFidelityEvidence(
            sourceManifestHash: 0xA11CE,
            renderedManifestHash: 0xA11CE,
            expectedVisibleCommandCount: 100,
            emittedVisibleCommandCount: 100,
            unsupportedVisibleCommandCount: 0,
            expectedResourceCount: 24,
            residentResourceCount: 24,
            missingResourceCount: 0
        )
    }

    static func main() {
        // The fixed reference target always uses the exact 440x330 -> 320x240
        // transform, even when the host drawable is a larger display.
        let reference = GoldenEyeFidelityLayout(
            mode: .reference320x240,
            drawableWidth: 1920,
            drawableHeight: 1080
        )
        precondition(reference.outputWidth == 320)
        precondition(reference.outputHeight == 240)
        precondition(approximately(reference.scale, 8.0 / 11.0))
        precondition(reference.sourceToOutput(.init(x: 440, y: 330)) == .init(x: 320, y: 240))
        requireRoundTrip(reference, .init(x: 335, y: 285))

        // Faithful HD is uniformly fitted to a centered 4:3 rectangle.  A
        // 4:3 drawable has no gutters and preserves source coordinates.
        let fourByThree = GoldenEyeFidelityLayout(
            mode: .faithfulHD,
            drawableWidth: 640,
            drawableHeight: 480
        )
        precondition(approximately(fourByThree.scale, 16.0 / 11.0))
        precondition(approximately(fourByThree.originX, 0))
        precondition(approximately(fourByThree.originY, 0))
        precondition(fourByThree.sourceRectInOutput == .init(minX: 0, minY: 0, maxX: 640, maxY: 480))
        requireRoundTrip(fourByThree, .init(x: 76, y: 112))

        let wide = GoldenEyeFidelityLayout(
            mode: .faithfulHD,
            drawableWidth: 1920,
            drawableHeight: 1080
        )
        precondition(approximately(wide.scale, 1080.0 / 330.0))
        precondition(approximately(wide.originX, 240))
        precondition(approximately(wide.originY, 0))
        precondition(wide.sourceRectInOutput == .init(minX: 240, minY: 0, maxX: 1680, maxY: 1080))
        requireRoundTrip(wide, .init(x: 335, y: 285))

        // Adaptive widescreen has the same authored source rectangle, but
        // exposes the neutral side expansion to the caller instead of
        // pillarboxing it.  Source art still maps to the same centered core.
        let adaptiveWide = GoldenEyeFidelityLayout(
            mode: .adaptiveWidescreen,
            drawableWidth: 1920,
            drawableHeight: 1080
        )
        precondition(adaptiveWide.mode.allowsWidescreenExpansion)
        precondition(approximately(adaptiveWide.sideGutter, 73.3333333333))
        precondition(approximately(adaptiveWide.sourceRectInOutput.minX, 240))
        precondition(approximately(adaptiveWide.sourceRectInOutput.minY, 0))
        precondition(approximately(adaptiveWide.sourceRectInOutput.maxX, 1680))
        precondition(approximately(adaptiveWide.sourceRectInOutput.maxY, 1080))
        let adaptiveTopLeft = adaptiveWide.sourceToOutput(.init(x: 0, y: 0))
        let adaptiveBottomRight = adaptiveWide.sourceToOutput(.init(x: 440, y: 330))
        precondition(approximately(adaptiveTopLeft.x, 240))
        precondition(approximately(adaptiveTopLeft.y, 0))
        precondition(approximately(adaptiveBottomRight.x, 1680))
        precondition(approximately(adaptiveBottomRight.y, 1080))
        precondition(adaptiveWide.outputToSource(.init(x: 0, y: 540)).x < 0)
        requireRoundTrip(adaptiveWide, .init(x: 268, y: 165))

        let ultrawide = GoldenEyeFidelityLayout(
            mode: .adaptiveWidescreen,
            drawableWidth: 3440,
            drawableHeight: 1440
        )
        precondition(approximately(ultrawide.scale, 1440.0 / 330.0))
        precondition(ultrawide.sideGutter > adaptiveWide.sideGutter)
        precondition(approximately(ultrawide.sourceRectInOutput.minX, 760))
        precondition(approximately(ultrawide.sourceRectInOutput.maxX, 2680))
        requireRoundTrip(ultrawide, .init(x: 110, y: 220))

        let evidence = completeEvidence()
        let cleanRelease = GoldenEyeFidelityPolicy.resolve(
            drawableWidth: 1920,
            drawableHeight: 1080,
            buildFlavor: .release,
            environment: [:],
            evidence: evidence
        )
        precondition(cleanRelease.isAccepted)
        precondition(cleanRelease.requestedMode == .faithfulHD)
        precondition(cleanRelease.effectiveMode == .faithfulHD)
        precondition(!cleanRelease.fallbackEnabled)

        for diagnostic in GoldenEyeFidelityDiagnosticPath.allCases {
            let requestedValue = diagnostic == .cadenceClearRenderer ? "clear" : "1"
            let rejection = GoldenEyeFidelityPolicy.resolve(
                drawableWidth: 640,
                drawableHeight: 480,
                buildFlavor: .release,
                environment: [diagnostic.rawValue: requestedValue],
                evidence: evidence
            )
            precondition(!rejection.isAccepted)
            precondition(rejection.diagnostics == [diagnostic])
            precondition(rejection.blockingViolations.contains(.diagnosticPathEnabled(diagnostic)))
            precondition(rejection.effectiveMode == .faithfulHD)
            precondition(!rejection.fallbackEnabled)
        }

        // A disabled switch is not a diagnostic path request.
        let disabledSwitch = GoldenEyeFidelityPolicy.resolve(
            drawableWidth: 640,
            drawableHeight: 480,
            buildFlavor: .release,
            environment: [GoldenEyeFidelityDiagnosticPath.getuDraw.rawValue: "0"],
            evidence: evidence
        )
        precondition(disabledSwitch.isAccepted)
        precondition(disabledSwitch.diagnostics.isEmpty)

        let incomplete = GoldenEyeFidelityEvidence(
            sourceManifestHash: 1,
            renderedManifestHash: 2,
            expectedVisibleCommandCount: 4,
            emittedVisibleCommandCount: 3,
            unsupportedVisibleCommandCount: 1,
            expectedResourceCount: 2,
            residentResourceCount: 1,
            missingResourceCount: 1
        )
        let incompleteRelease = GoldenEyeFidelityPolicy.resolve(
            drawableWidth: 640,
            drawableHeight: 480,
            buildFlavor: .release,
            environment: [:],
            evidence: incomplete
        )
        precondition(!incompleteRelease.isAccepted)
        precondition(incompleteRelease.blockingViolations.contains(.unsupportedVisibleCommands(1)))
        precondition(incompleteRelease.blockingViolations.contains(.missingResources(1)))

        // Debug can identify an explicitly requested diagnostic path, but it
        // cannot change the selected mode or enable a fallback.  Incomplete
        // source evidence remains blocking in every flavor.
        let debugDiagnostic = GoldenEyeFidelityPolicy.resolve(
            drawableWidth: 640,
            drawableHeight: 480,
            buildFlavor: .debug,
            environment: [GoldenEyeFidelityDiagnosticPath.partialGeometry.rawValue: "true"],
            evidence: evidence
        )
        precondition(debugDiagnostic.isAccepted)
        precondition(debugDiagnostic.requiresExplicitDiagnosticHandling)
        precondition(debugDiagnostic.effectiveMode == .faithfulHD)
        precondition(!debugDiagnostic.fallbackEnabled)

        let debugIncomplete = GoldenEyeFidelityPolicy.resolve(
            mode: .adaptiveWidescreen,
            drawableWidth: 2560,
            drawableHeight: 1080,
            buildFlavor: .debug,
            environment: [:],
            evidence: incomplete
        )
        precondition(!debugIncomplete.isAccepted)
        precondition(debugIncomplete.effectiveMode == .adaptiveWidescreen)
        precondition(!debugIncomplete.fallbackEnabled)

        let diagnosticGateCount = GoldenEyeFidelityDiagnosticPath.allCases.count
        precondition(diagnosticGateCount == 10)
        let cadenceRejection = GoldenEyeFidelityPolicy.resolve(
            drawableWidth: 640,
            drawableHeight: 480,
            buildFlavor: .release,
            environment: [GoldenEyeFidelityDiagnosticPath.cadenceClearRenderer.rawValue: "clear"],
            evidence: evidence
        )
        precondition(!cadenceRejection.isAccepted)
        precondition(cadenceRejection.diagnostics == [.cadenceClearRenderer])
        print("goldeneye_fidelity_policy_smoke: PASS reference=320x240 faithful=4:3/letterbox adaptive=16:9/ultrawide release-gates=\(diagnosticGateCount)")
    }
}
