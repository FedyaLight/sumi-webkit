import AppKit

/// Owns the drop-indicator CALayers (2pt rounded bar + leading ring) inside the
/// sidebar drag overlay. Zen parity: the line slides between slots with a short
/// ease-out and plays haptic feedback when it lands on a new slot. Pure AppKit —
/// callers hand it an already-converted rect and the resolved slot key.
@MainActor
final class SidebarDropIndicatorPresenter {
    private typealias Metrics = SidebarDropIndicatorGeometry.Metrics

    var accentColor: NSColor = .controlAccentColor {
        didSet {
            guard accentColor != oldValue else { return }
            applyColors()
        }
    }

    var prefersReducedMotion = false

    private weak var hostLayer: CALayer?
    private var lineLayer: CALayer?
    private var ringLayer: CALayer?
    private var lastSlotKey: DropZoneSlot?
    private var lastLineRect: CGRect?

    func attach(to hostLayer: CALayer) {
        self.hostLayer = hostLayer
    }

    func update(lineRect: CGRect?, slotKey: DropZoneSlot?) {
        guard let lineRect else {
            hide()
            return
        }

        let (line, ring) = materializedLayers()
        let wasHidden = line.isHidden
        let slotChanged = slotKey != lastSlotKey
        if !wasHidden, !slotChanged, lineRect == lastLineRect {
            return
        }
        lastSlotKey = slotKey
        lastLineRect = lineRect

        let animatesSlide = !wasHidden && !prefersReducedMotion

        CATransaction.begin()
        if animatesSlide {
            CATransaction.setAnimationDuration(Metrics.slideDuration)
            CATransaction.setAnimationTimingFunction(
                CAMediaTimingFunction(name: .easeOut)
            )
        } else {
            CATransaction.setDisableActions(true)
        }
        line.isHidden = false
        ring.isHidden = false
        line.frame = barFrame(for: lineRect)
        ring.frame = ringFrame(for: lineRect)
        CATransaction.commit()

        if slotChanged, !wasHidden {
            NSHapticFeedbackManager.defaultPerformer.perform(
                .alignment,
                performanceTime: .default
            )
        }
    }

    func hide() {
        lastSlotKey = nil
        lastLineRect = nil
        guard let lineLayer, !lineLayer.isHidden else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lineLayer.isHidden = true
        ringLayer?.isHidden = true
        CATransaction.commit()
    }

    // MARK: - Layers

    private func materializedLayers() -> (line: CALayer, ring: CALayer) {
        if let lineLayer, let ringLayer {
            return (lineLayer, ringLayer)
        }

        let line = CALayer()
        line.cornerRadius = Metrics.cornerRadius
        line.isHidden = true

        let ring = CALayer()
        ring.borderWidth = Metrics.ringBorderWidth
        ring.cornerRadius = Metrics.ringDiameter / 2
        ring.backgroundColor = NSColor.clear.cgColor
        ring.isHidden = true

        hostLayer?.addSublayer(line)
        hostLayer?.addSublayer(ring)
        lineLayer = line
        ringLayer = ring
        applyColors()
        return (line, ring)
    }

    private func applyColors() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lineLayer?.backgroundColor = accentColor.cgColor
        ringLayer?.borderColor = accentColor.cgColor
        CATransaction.commit()
    }

    // MARK: - Frames (host-view coordinates, bottom-left origin)

    /// The bar starts after the leading ring, mirroring Zen's indicator.
    private func barFrame(for lineRect: CGRect) -> CGRect {
        let leadingGap = Metrics.ringDiameter + 2
        return CGRect(
            x: lineRect.minX + leadingGap,
            y: lineRect.minY,
            width: max(0, lineRect.width - leadingGap),
            height: lineRect.height
        )
    }

    private func ringFrame(for lineRect: CGRect) -> CGRect {
        CGRect(
            x: lineRect.minX,
            y: lineRect.midY - Metrics.ringDiameter / 2,
            width: Metrics.ringDiameter,
            height: Metrics.ringDiameter
        )
    }
}
