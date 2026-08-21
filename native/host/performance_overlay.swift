import AppKit
import Foundation

/// A value-only snapshot used by the AppKit HUD and Dock badge. The
/// presentation telemetry is intentionally kept separate from the renderer's
/// Metal objects so polling the overlay cannot retain or mutate GPU state.
struct GoldenEyePerformanceSnapshot: Sendable, Equatable {
    let presentedFPS: Double?
    let logicHz: Double?
    let rendererP95Milliseconds: Double?
    let presentedSamples: UInt64
    let tickCount: UInt64

    var badgeLabel: String {
        // WindowServer may not publish presented-time samples in a headless or
        // occluded session. Keep the Dock badge useful by falling back to the
        // authoritative owner rate without relabeling the HUD's FPS field.
        guard let rate = presentedFPS ?? logicHz,
              rate.isFinite,
              rate >= 0 else {
            return "—"
        }
        return String(Int(rate.rounded()))
    }

    var text: String {
        let fps = presentedFPS.map { String(format: "%.0f", $0) } ?? "—"
        let logic = logicHz.map { String(format: "%.0f", $0) } ?? "—"
        let callback = rendererP95Milliseconds.map { String(format: "%.2f", $0) } ?? "—"
        return "FPS  \(fps)\nLogic \(logic) Hz   CPU p95 \(callback) ms"
    }
}

/// Small native AppKit HUD placed above the Metal view. It is opt-in from the
/// View menu and deliberately uses a single label so it has no per-frame
/// drawing or layout work beyond the low-frequency text update.
final class GoldenEyePerformanceOverlay: NSView {
    private let label = NSTextField(labelWithString: "FPS  —\nLogic — Hz   CPU p95 — ms")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.78).cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        layer?.borderWidth = 1

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .left
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byClipping
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 204, height: 48)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // The HUD is presentation-only; it must never steal future mouse or
        // controller-pointer events from the Metal game surface beneath it.
        nil
    }

    func update(snapshot: GoldenEyePerformanceSnapshot) {
        label.stringValue = snapshot.text
        let fps = snapshot.presentedFPS.map { String(format: "%.0f", $0) } ?? "—"
        let logic = snapshot.logicHz.map { String(format: "%.0f", $0) } ?? "—"
        toolTip = "Presented FPS: \(fps)   Logic: \(logic) Hz   Ticks: \(snapshot.tickCount)"
    }
}
