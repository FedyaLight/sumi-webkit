import AppKit
import SwiftUI

@MainActor
final class NativeSurfaceScrollHoverCoordinator: ObservableObject {
    @Published private(set) var hoverUpdatesEnabled = true

    private static let defaultHoverRestoreDelayNanoseconds: UInt64 = 250_000_000

    private let hoverRestoreDelayNanoseconds: UInt64
    private let sleepForNanoseconds: @Sendable (UInt64) async throws -> Void
    private var phaseScrollingRegions: Set<String> = []
    private var activeTokensByRegion: [String: UUID] = [:]
    private var restoreTask: Task<Void, Never>?

    init(
        hoverRestoreDelayNanoseconds: UInt64 = NativeSurfaceScrollHoverCoordinator.defaultHoverRestoreDelayNanoseconds,
        sleepForNanoseconds: @escaping @Sendable (UInt64) async throws -> Void = { nanoseconds in
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.hoverRestoreDelayNanoseconds = hoverRestoreDelayNanoseconds
        self.sleepForNanoseconds = sleepForNanoseconds
    }

    func registerRegion(_ region: String) -> UUID {
        let token = UUID()
        activeTokensByRegion[region] = token
        return token
    }

    func unregisterRegion(_ region: String, token: UUID) {
        guard activeTokensByRegion[region] == token else { return }

        activeTokensByRegion.removeValue(forKey: region)
        phaseScrollingRegions.remove(region)
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

    func reset() {
        restoreTask?.cancel()
        restoreTask = nil
        phaseScrollingRegions.removeAll()
        activeTokensByRegion.removeAll()
        setHoverUpdatesEnabled(true)
    }

    private func setHoverUpdatesEnabled(_ enabled: Bool) {
        guard hoverUpdatesEnabled != enabled else { return }
        hoverUpdatesEnabled = enabled
    }

    private func scheduleHoverRestoreIfIdle() {
        restoreTask?.cancel()
        let delay = hoverRestoreDelayNanoseconds
        let sleepForNanoseconds = sleepForNanoseconds
        restoreTask = Task { @MainActor [weak self, sleepForNanoseconds] in
            do {
                try await sleepForNanoseconds(delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.restoreHoverIfIdle()
            self?.restoreTask = nil
        }
    }

    private func restoreHoverIfIdle() {
        guard phaseScrollingRegions.isEmpty else { return }

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
    typealias Coordinator = SidebarHoverBindingCoordinator

    @Binding var isHovered: Bool
    let session: SidebarHoverSession
    let isEnabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> SidebarHoverTrackingView {
        let view = SidebarHoverTrackingView(frame: .zero)
        update(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: SidebarHoverTrackingView, context: Context) {
        update(nsView, coordinator: context.coordinator)
    }

    static func dismantleNSView(
        _ nsView: SidebarHoverTrackingView,
        coordinator: Coordinator
    ) {
        coordinator.detach()
    }

    private func update(
        _ view: SidebarHoverTrackingView,
        coordinator: Coordinator
    ) {
        coordinator.update(
            view: view,
            session: session,
            isHovered: $isHovered,
            isEnabled: isEnabled
        )
    }
}

private struct NativeSurfaceHoverModifier: ViewModifier {
    @Binding var isHovered: Bool
    let isEnabled: Bool

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.nativeSurfaceHoverUpdatesEnabled) private var hoverUpdatesEnabled

    private var effectiveIsEnabled: Bool {
        isEnabled && hoverUpdatesEnabled
    }

    func body(content: Content) -> some View {
        content.overlay {
            NativeSurfaceHoverBridge(
                isHovered: $isHovered,
                session: windowState.sidebarInteractionState.hoverSession,
                isEnabled: effectiveIsEnabled
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
