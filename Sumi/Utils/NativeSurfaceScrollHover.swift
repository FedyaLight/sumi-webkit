import AppKit
import SwiftUI

@MainActor
final class NativeSurfaceScrollHoverCoordinator: ObservableObject {
    @Published private(set) var hoverUpdatesEnabled = true

    private static let hoverRestoreDelayNanoseconds: UInt64 = 250_000_000

    private var phaseScrollingRegions: Set<String> = []
    private var activityRegions: Set<String> = []
    private var activeTokensByRegion: [String: UUID] = [:]
    private var restoreTask: Task<Void, Never>?

    func registerRegion(_ region: String) -> UUID {
        let token = UUID()
        activeTokensByRegion[region] = token
        return token
    }

    func unregisterRegion(_ region: String, token: UUID) {
        guard activeTokensByRegion[region] == token else { return }

        activeTokensByRegion.removeValue(forKey: region)
        phaseScrollingRegions.remove(region)
        activityRegions.remove(region)
        scheduleHoverRestoreIfIdle()
    }

    func setScrolling(_ isScrolling: Bool, region: String) {
        if isScrolling {
            phaseScrollingRegions.insert(region)
            setHoverUpdatesEnabled(false)
            return
        }

        phaseScrollingRegions.remove(region)
        scheduleHoverRestoreIfIdle()
    }

    func notifyScrollActivity(region: String) {
        activityRegions.insert(region)
        setHoverUpdatesEnabled(false)
        scheduleHoverRestoreIfIdle()
    }

    func reset() {
        restoreTask?.cancel()
        restoreTask = nil
        phaseScrollingRegions.removeAll()
        activityRegions.removeAll()
        activeTokensByRegion.removeAll()
        setHoverUpdatesEnabled(true)
    }

    private func setHoverUpdatesEnabled(_ enabled: Bool) {
        guard hoverUpdatesEnabled != enabled else { return }
        hoverUpdatesEnabled = enabled
    }

    private func scheduleHoverRestoreIfIdle() {
        restoreTask?.cancel()
        let delay = Self.hoverRestoreDelayNanoseconds
        restoreTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            self?.activityRegions.removeAll()
            self?.restoreHoverIfIdle()
            self?.restoreTask = nil
        }
    }

    private func restoreHoverIfIdle() {
        guard phaseScrollingRegions.isEmpty,
              activityRegions.isEmpty
        else { return }

        setHoverUpdatesEnabled(true)
    }
}

private struct NativeSurfaceHoverUpdatesEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var nativeSurfaceHoverUpdatesEnabled: Bool {
        get { self[NativeSurfaceHoverUpdatesEnabledKey.self] }
        set { self[NativeSurfaceHoverUpdatesEnabledKey.self] = newValue }
    }
}

private struct NativeSurfaceHoverBridge: NSViewRepresentable {
    @Binding var isHovered: Bool
    let isEnabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NativeSurfaceHoverTrackingView {
        let view = NativeSurfaceHoverTrackingView(frame: .zero)
        update(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NativeSurfaceHoverTrackingView, context: Context) {
        update(nsView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ nsView: NativeSurfaceHoverTrackingView, coordinator: Coordinator) {
        coordinator.detach(from: nsView)
        nsView.onHoverChanged = nil
        nsView.setHoverTrackingEnabled(false)
    }

    private func update(_ view: NativeSurfaceHoverTrackingView, coordinator: Coordinator) {
        coordinator.updateBinding($isHovered)
        coordinator.attach(view)
        view.setHoverTrackingEnabled(isEnabled)
    }

    @MainActor
    final class Coordinator {
        private var isHovered: Binding<Bool>?
        private weak var view: NativeSurfaceHoverTrackingView?

        func updateBinding(_ isHovered: Binding<Bool>) {
            self.isHovered = isHovered
        }

        func attach(_ view: NativeSurfaceHoverTrackingView) {
            guard self.view !== view else { return }

            self.view = view
            view.onHoverChanged = { [weak self] hovering in
                self?.setBindingIfNeeded(hovering)
            }
        }

        func detach(from view: NativeSurfaceHoverTrackingView) {
            guard self.view === view else { return }
            self.view = nil
            isHovered = nil
        }

        private func setBindingIfNeeded(_ hovering: Bool) {
            guard let isHovered, isHovered.wrappedValue != hovering else { return }
            isHovered.wrappedValue = hovering
        }
    }
}

@MainActor
private final class NativeSurfaceHoverTrackingView: NSView {
    var onHoverChanged: ((Bool) -> Void)?

    private var trackingArea: NSTrackingArea?
    private var hoverTrackingEnabled = true
    private var reportedHover = false

    override var isOpaque: Bool {
        false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            setReportedHover(false, publish: false)
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        removeHoverTrackingArea()

        guard hoverTrackingEnabled else { return }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [
                .mouseEnteredAndExited,
                .mouseMoved,
                .activeInActiveApp,
                .inVisibleRect,
            ],
            owner: self,
            userInfo: nil
        )
        self.trackingArea = trackingArea
        addTrackingArea(trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        guard hoverTrackingEnabled else { return }
        setReportedHover(true)
    }

    override func mouseMoved(with event: NSEvent) {
        guard hoverTrackingEnabled else { return }
        setReportedHover(true)
    }

    override func mouseExited(with event: NSEvent) {
        setReportedHover(false)
    }

    func setHoverTrackingEnabled(_ enabled: Bool) {
        guard hoverTrackingEnabled != enabled else { return }

        hoverTrackingEnabled = enabled
        if enabled {
            updateTrackingAreas()
        } else {
            removeHoverTrackingArea()
            setReportedHover(false, publish: false)
        }
    }

    private func setReportedHover(_ hovering: Bool, publish: Bool = true) {
        guard reportedHover != hovering else { return }

        reportedHover = hovering
        if publish {
            onHoverChanged?(hovering)
        }
    }

    private func removeHoverTrackingArea() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
            self.trackingArea = nil
        }
    }
}

private struct NativeSurfaceHoverModifier: ViewModifier {
    @Binding var isHovered: Bool
    let isEnabled: Bool

    @Environment(\.nativeSurfaceHoverUpdatesEnabled) private var hoverUpdatesEnabled

    private var effectiveIsEnabled: Bool {
        isEnabled && hoverUpdatesEnabled
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                NativeSurfaceHoverBridge(
                    isHovered: $isHovered,
                    isEnabled: effectiveIsEnabled
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .onChange(of: effectiveIsEnabled) { _, enabled in
                if !enabled {
                    isHovered = false
                }
            }
            .onDisappear {
                isHovered = false
            }
    }
}

private struct NativeScrollHoverSuppressionModifier: ViewModifier {
    let coordinator: NativeSurfaceScrollHoverCoordinator
    let region: String

    @State private var regionToken: UUID?

    func body(content: Content) -> some View {
        content
            .onAppear {
                registerRegionIfNeeded()
            }
            .onScrollPhaseChange { _, newPhase in
                registerRegionIfNeeded()
                coordinator.setScrolling(newPhase.isScrolling, region: region)
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, _ in
                registerRegionIfNeeded()
                coordinator.notifyScrollActivity(region: region)
            }
            .onDisappear {
                guard let token = regionToken else { return }
                regionToken = nil
                coordinator.unregisterRegion(region, token: token)
            }
    }

    private func registerRegionIfNeeded() {
        guard regionToken == nil else { return }
        regionToken = coordinator.registerRegion(region)
    }
}

extension View {
    func nativeSurfaceHover(
        _ isHovered: Binding<Bool>,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            NativeSurfaceHoverModifier(
                isHovered: isHovered,
                isEnabled: isEnabled
            )
        )
    }

    func suppressesNativeSurfaceHoverWhileScrolling(
        _ coordinator: NativeSurfaceScrollHoverCoordinator,
        region: String
    ) -> some View {
        modifier(
            NativeScrollHoverSuppressionModifier(
                coordinator: coordinator,
                region: region
            )
        )
    }
}
