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

    var pairingPreviewColor: NSColor = .controlBackgroundColor {
        didSet {
            guard pairingPreviewColor != oldValue else { return }
            applyColors()
        }
    }

    var prefersReducedMotion = false

    private weak var hostLayer: CALayer?
    private var lineLayer: CALayer?
    private var ringLayer: CALayer?
    private var pairingLayer: CALayer?
    private var lastSlotKey: DropZoneSlot?
    private var lastLineRect: CGRect?
    private var lastPairingTarget: SidebarSplitPairingTarget?

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
        lastPairingTarget = nil

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
        pairingLayer?.isHidden = true
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

    func updatePairingTarget(
        rect: CGRect,
        target: SidebarSplitPairingTarget
    ) {
        let layer = materializedPairingLayer()
        let wasHidden = layer.isHidden
        let targetChanged = target != lastPairingTarget
        guard wasHidden
                || targetChanged
                || layer.frame != rect
        else { return }

        lastSlotKey = nil
        lastLineRect = nil
        lastPairingTarget = target

        CATransaction.begin()
        if !wasHidden, !prefersReducedMotion {
            CATransaction.setAnimationDuration(Metrics.slideDuration)
            CATransaction.setAnimationTimingFunction(
                CAMediaTimingFunction(name: .easeOut)
            )
        } else {
            CATransaction.setDisableActions(true)
        }
        lineLayer?.isHidden = true
        ringLayer?.isHidden = true
        layer.isHidden = false
        layer.frame = rect
        applyPairingStyle()
        CATransaction.commit()

        if targetChanged, !wasHidden {
            NSHapticFeedbackManager.defaultPerformer.perform(
                .alignment,
                performanceTime: .default
            )
        }
    }

    func hide() {
        lastSlotKey = nil
        lastLineRect = nil
        lastPairingTarget = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lineLayer?.isHidden = true
        ringLayer?.isHidden = true
        pairingLayer?.isHidden = true
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

    private func materializedPairingLayer() -> CALayer {
        if let pairingLayer {
            return pairingLayer
        }

        let layer = CALayer()
        layer.cornerRadius =
            SplitGroupSidebarVisualLayout.segmentCornerRadius
        layer.isHidden = true
        hostLayer?.addSublayer(layer)
        pairingLayer = layer
        applyColors()
        return layer
    }

    private func applyColors() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lineLayer?.backgroundColor = accentColor.cgColor
        ringLayer?.borderColor = accentColor.cgColor
        if lastPairingTarget != nil {
            applyPairingStyle()
        }
        CATransaction.commit()
    }

    private func applyPairingStyle() {
        pairingLayer?.cornerRadius =
            SplitGroupSidebarVisualLayout.segmentCornerRadius
        pairingLayer?.borderWidth = 0
        pairingLayer?.backgroundColor = pairingPreviewColor.cgColor
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
