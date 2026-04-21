import AppKit
import SwiftUI

// MARK: - Phase 1: AppKit-owned sidebar column

private final class SidebarColumnContainerView: NSView {
    var onWindowChanged: ((NSWindow?) -> Void)?
    weak var hostedSidebarView: NSView?
    weak var contextMenuController: SidebarContextMenuController?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return SidebarColumnHitTestRouting.routedHit(
            point: point,
            in: self,
            originalHit: hit,
            hostedSidebarView: hostedSidebarView,
            contextMenuController: contextMenuController,
            eventType: window?.currentEvent?.type
        )
    }

    override func rightMouseDown(with event: NSEvent) {
        guard contextMenuController?.presentBackgroundMenu(
            trigger: .rightMouseDown,
            event: event,
            in: self
        ) == true else {
            super.rightMouseDown(with: event)
            return
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChanged?(window)
    }
}

@MainActor
enum SidebarColumnHitTestRouting {
    static func routedHit(
        point: NSPoint,
        in containerView: NSView,
        originalHit: NSView?,
        hostedSidebarView: NSView?,
        contextMenuController: SidebarContextMenuController?,
        eventType: NSEvent.EventType?
    ) -> NSView? {
        if eventType == .leftMouseDragged || eventType == .leftMouseUp,
           let owner = contextMenuController?.primaryMouseTrackingOwner(in: containerView.window)
        {
            logRoute(
                eventType: eventType,
                originalHit: originalHit,
                originalOwner: owner,
                owner: owner,
                hostedSidebarView: hostedSidebarView,
                decision: "primary-tracking-owner",
                usedBackgroundMenu: false
            )
            return owner
        }

        guard containerView.bounds.contains(point),
              eventType == .leftMouseDown || eventType == .rightMouseDown
        else {
            return originalHit
        }

        let windowPoint = containerView.convert(point, to: nil)
        let originalOwner = originalHit?.nearestAncestor(of: SidebarInteractiveItemView.self)
        var originalOwnerPriority: Int?
        if let originalOwner,
           contextMenuController?.prefersOriginalHitOwner(
               originalOwner,
               at: windowPoint,
               in: containerView.window,
               eventType: eventType,
               hostedSidebarView: hostedSidebarView
           ) == true
        {
            let originalPoint = originalOwner.convert(windowPoint, from: nil)
            originalOwnerPriority = originalOwner.routingPriority(
                at: originalPoint,
                eventType: eventType
            )
        }

        if let owner = contextMenuController?.interactiveOwner(
            at: windowPoint,
            in: containerView.window,
            eventType: eventType,
            hostedSidebarView: hostedSidebarView
        ) {
            if let originalOwner,
               originalOwner !== owner,
               let originalOwnerPriority
            {
                let ownerPoint = owner.convert(windowPoint, from: nil)
                let ownerPriority = owner.routingPriority(
                    at: ownerPoint,
                    eventType: eventType
                )
                if originalOwnerPriority >= ownerPriority {
                    logRoute(
                        eventType: eventType,
                        originalHit: originalHit,
                        originalOwner: originalOwner,
                        owner: originalOwner,
                        hostedSidebarView: hostedSidebarView,
                        decision: "original-hit-owner",
                        usedBackgroundMenu: false
                    )
                    return originalOwner
                }
            }

            logRoute(
                eventType: eventType,
                originalHit: originalHit,
                originalOwner: originalOwner,
                owner: owner,
                hostedSidebarView: hostedSidebarView,
                decision: originalOwner === owner ? "original-hit-owner" : "registry-owner",
                usedBackgroundMenu: false
            )
            return owner
        }

        if let originalOwner,
           originalOwnerPriority != nil
        {
            logRoute(
                eventType: eventType,
                originalHit: originalHit,
                originalOwner: originalOwner,
                owner: originalOwner,
                hostedSidebarView: hostedSidebarView,
                decision: "original-hit-owner",
                usedBackgroundMenu: false
            )
            return originalOwner
        }

        guard eventType == .rightMouseDown,
              let hostedSidebarView
        else {
            return originalHit
        }

        if let originalOwner {
            let ownerPoint = originalOwner.convert(windowPoint, from: nil)
            if originalOwner.shouldCaptureInteraction(at: ownerPoint, eventType: eventType) {
                logRoute(
                    eventType: eventType,
                    originalHit: originalHit,
                    originalOwner: originalOwner,
                    owner: originalOwner,
                    hostedSidebarView: hostedSidebarView,
                    decision: "background-fallback-owner",
                    usedBackgroundMenu: false
                )
                return originalOwner
            }
        }

        if originalHit?.nearestAncestor(of: SidebarInteractiveItemView.self) != nil,
           originalHit?.isDescendant(of: hostedSidebarView) != true
        {
            return originalHit
        }

        if let originalHit,
           originalHit === hostedSidebarView || originalHit.isDescendant(of: hostedSidebarView)
        {
            logRoute(
                eventType: eventType,
                originalHit: originalHit,
                originalOwner: originalOwner,
                owner: nil,
                hostedSidebarView: hostedSidebarView,
                decision: "background-menu",
                usedBackgroundMenu: true
            )
            return containerView
        }

        return originalHit
    }

    private static func logRoute(
        eventType: NSEvent.EventType?,
        originalHit: NSView?,
        originalOwner: SidebarInteractiveItemView?,
        owner: SidebarInteractiveItemView?,
        hostedSidebarView: NSView?,
        decision: String,
        usedBackgroundMenu: Bool
    ) {
        let ownerSource = owner?.sourceID ?? "nil"
        let originalOwnerSource = originalOwner?.sourceID ?? "nil"
        let hostedRootDescription = sidebarViewDebugDescription(hostedSidebarView)
        let ownerRootDescription = sidebarViewDebugDescription(sidebarHostedSidebarRoot(from: owner))
        let originalOwnerRootDescription = sidebarViewDebugDescription(
            sidebarHostedSidebarRoot(from: originalOwner)
        )
        let ownerInHostedRoot = hostedSidebarView.map { owner?.isDescendant(of: $0) == true } ?? false
        let originalOwnerInHostedRoot = hostedSidebarView.map {
            originalOwner?.isDescendant(of: $0) == true
        } ?? false
        RuntimeDiagnostics.emit {
            "🧭 Sidebar column hit-test event=\(eventType.map(String.init(describing:)) ?? "nil") decision=\(decision) hit=\(originalHit.map { String(describing: type(of: $0)) } ?? "nil") originalOwner=\(originalOwner?.recoveryDebugDescription ?? "nil") owner=\(owner?.recoveryDebugDescription ?? "nil") hostedRoot=\(hostedRootDescription) originalOwnerRoot=\(originalOwnerRootDescription) ownerRoot=\(ownerRootDescription) originalOwnerInHostedRoot=\(originalOwnerInHostedRoot) ownerInHostedRoot=\(ownerInHostedRoot) background=\(usedBackgroundMenu)"
        }
        SidebarUITestDragMarker.recordEvent(
            "route",
            dragItemID: owner?.recoveryMetadata.dragItemID ?? originalOwner?.recoveryMetadata.dragItemID,
            ownerDescription: owner?.recoveryDebugDescription ?? originalOwner?.recoveryDebugDescription ?? "nil",
            sourceID: owner?.sourceID ?? originalOwner?.sourceID,
            viewDescription: owner?.debugViewDescription ?? originalOwner?.debugViewDescription,
            details: "event=\(eventType.map(String.init(describing:)) ?? "nil") decision=\(decision) originalHit=\(originalHit.map { String(describing: type(of: $0)) } ?? "nil") originalOwner=\(originalOwner?.recoveryDebugDescription ?? "nil") owner=\(owner?.recoveryDebugDescription ?? "nil") originalOwnerSource=\(originalOwnerSource) ownerSource=\(ownerSource) originalOwnerView=\(originalOwner?.debugViewDescription ?? "nil") ownerView=\(owner?.debugViewDescription ?? "nil") hostedRoot=\(hostedRootDescription) originalOwnerRoot=\(originalOwnerRootDescription) ownerRoot=\(ownerRootDescription) originalOwnerInHostedRoot=\(originalOwnerInHostedRoot) ownerInHostedRoot=\(ownerInHostedRoot) background=\(usedBackgroundMenu)"
        )
    }
}

private extension NSView {
    func nearestAncestor<T: NSView>(of type: T.Type) -> T? {
        var current: NSView? = self
        while let view = current {
            if let match = view as? T {
                return match
            }
            current = view.superview
        }
        return nil
    }
}

@MainActor
struct SidebarHostEnvironmentContext {
    let browserManager: BrowserManager
    let windowState: BrowserWindowState
    let windowRegistry: WindowRegistry
    let commandPalette: CommandPalette
    let sumiSettings: SumiSettingsService
    let resolvedThemeContext: ResolvedThemeContext
}

enum SidebarPresentationMode: Equatable {
    case docked
    case collapsedHidden
    case collapsedVisible
}

struct SidebarPresentationContext: Equatable {
    let mode: SidebarPresentationMode
    let sidebarWidth: CGFloat

    var contentWidth: CGFloat {
        BrowserWindowState.sidebarContentWidth(for: sidebarWidth)
    }

    var isCollapsedOverlay: Bool {
        mode != .docked
    }

    var showsResizeHandle: Bool {
        mode == .docked
    }

    static func collapsedSidebarWidth(
        sidebarWidth: CGFloat,
        savedSidebarWidth: CGFloat
    ) -> CGFloat {
        BrowserWindowState.clampedSidebarWidth(
            max(sidebarWidth, savedSidebarWidth)
        )
    }

    static func docked(sidebarWidth: CGFloat) -> SidebarPresentationContext {
        let clampedWidth = BrowserWindowState.clampedSidebarWidth(sidebarWidth)
        return SidebarPresentationContext(
            mode: .docked,
            sidebarWidth: clampedWidth
        )
    }

    static func collapsedHidden(
        sidebarWidth: CGFloat
    ) -> SidebarPresentationContext {
        let clampedWidth = BrowserWindowState.clampedSidebarWidth(sidebarWidth)
        return SidebarPresentationContext(
            mode: .collapsedHidden,
            sidebarWidth: clampedWidth
        )
    }

    static func collapsedVisible(
        sidebarWidth: CGFloat
    ) -> SidebarPresentationContext {
        let clampedWidth = BrowserWindowState.clampedSidebarWidth(sidebarWidth)
        return SidebarPresentationContext(
            mode: .collapsedVisible,
            sidebarWidth: clampedWidth
        )
    }
}

private struct SidebarPresentationContextKey: EnvironmentKey {
    static let defaultValue = SidebarPresentationContext.docked(
        sidebarWidth: BrowserWindowState.sidebarDefaultWidth
    )
}

extension EnvironmentValues {
    var sidebarPresentationContext: SidebarPresentationContext {
        get { self[SidebarPresentationContextKey.self] }
        set { self[SidebarPresentationContextKey.self] = newValue }
    }
}

@MainActor
extension View {
    func sidebarHostEnvironment(_ context: SidebarHostEnvironmentContext) -> some View {
        self
            .environmentObject(context.browserManager)
            .environmentObject(context.browserManager.extensionSurfaceStore)
            .environment(context.windowState)
            .environment(context.windowRegistry)
            .environment(context.commandPalette)
            .environment(\.sumiSettings, context.sumiSettings)
            .environment(\.resolvedThemeContext, context.resolvedThemeContext)
    }
}

/// Owns a single `NSHostingController` for the SwiftUI sidebar so the column is not re-hosted by incidental
/// `WindowView` body recomputations (see APPLE_BRIDGING: stable owner at the framework boundary).
@MainActor
final class SidebarColumnViewController: NSViewController {
    var sidebarRecoveryCoordinator: SidebarHostRecoveryHandling = SidebarHostRecoveryCoordinator.shared

    private var hostingController: NSViewController?
    private var widthConstraint: NSLayoutConstraint?
    private weak var registeredRecoveryAnchor: NSView?

    override func loadView() {
        let containerView = SidebarColumnContainerView()
        containerView.onWindowChanged = { [weak self] window in
            Task { @MainActor [weak self] in
                self?.syncRecoveryAnchor(window: window)
            }
        }
        view = containerView
        view.translatesAutoresizingMaskIntoConstraints = true
    }

    func updateHostedSidebar<Content: View>(
        root: Content,
        width: CGFloat,
        contextMenuController: SidebarContextMenuController? = nil
    ) {
        let previousHostedSidebarView = hostingController?.view
        (view as? SidebarColumnContainerView)?.contextMenuController = contextMenuController

        if let hostingController = hostingController as? NSHostingController<Content> {
            hostingController.rootView = root
            widthConstraint?.constant = width
        } else {
            removeHostingControllerIfNeeded()

            let nextHostingController = NSHostingController(rootView: root)
            hostingController = nextHostingController
            addChild(nextHostingController)
            view.addSubview(nextHostingController.view)
            nextHostingController.view.translatesAutoresizingMaskIntoConstraints = false
            let wc = nextHostingController.view.widthAnchor.constraint(equalToConstant: width)
            wc.priority = .defaultHigh
            NSLayoutConstraint.activate([
                nextHostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                nextHostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                nextHostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
                nextHostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                wc,
            ])
            widthConstraint = wc
            nextHostingController.view.layoutSubtreeIfNeeded()
        }

        (view as? SidebarColumnContainerView)?.hostedSidebarView = hostingController?.view
        SidebarUITestDragMarker.recordEvent(
            "hostedSidebarUpdate",
            dragItemID: nil,
            ownerDescription: "nil",
            viewDescription: sidebarViewDebugDescription(hostingController?.view),
            details: "reusedHostedRoot=\(previousHostedSidebarView === hostingController?.view) previousHostedRoot=\(sidebarViewDebugDescription(previousHostedSidebarView)) hostedRoot=\(sidebarViewDebugDescription(hostingController?.view)) controller=\(sidebarObjectDebugDescription(hostingController)) width=\(Int(width))"
        )

        syncRecoveryAnchor(window: view.window)
    }

    func teardownSidebarHosting() {
        unregisterRecoveryAnchor()
        (view as? SidebarColumnContainerView)?.hostedSidebarView = nil
        (view as? SidebarColumnContainerView)?.contextMenuController = nil
        widthConstraint?.isActive = false
        widthConstraint = nil
        removeHostingControllerIfNeeded()
    }

    private func syncRecoveryAnchor(window: NSWindow?) {
        guard let anchor = hostingController?.view else {
            unregisterRecoveryAnchor()
            return
        }

        if let registeredRecoveryAnchor,
           registeredRecoveryAnchor !== anchor
        {
            sidebarRecoveryCoordinator.unregister(anchor: registeredRecoveryAnchor)
        }

        registeredRecoveryAnchor = anchor
        sidebarRecoveryCoordinator.sync(anchor: anchor, window: window ?? anchor.window)
    }

    private func unregisterRecoveryAnchor() {
        guard let registeredRecoveryAnchor else { return }
        sidebarRecoveryCoordinator.unregister(anchor: registeredRecoveryAnchor)
        self.registeredRecoveryAnchor = nil
    }

    private func removeHostingControllerIfNeeded() {
        guard let hostingController else { return }
        hostingController.view.removeFromSuperview()
        hostingController.removeFromParent()
        self.hostingController = nil
    }
}

struct SidebarColumnHostedRootView: View {
    let environmentContext: SidebarHostEnvironmentContext
    let presentationContext: SidebarPresentationContext

    var body: some View {
        SpacesSideBarView()
            .frame(width: presentationContext.sidebarWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .trailing) {
                if presentationContext.showsResizeHandle {
                    SidebarResizeView()
                        .frame(maxHeight: .infinity)
                        .zIndex(2000)
                }
            }
            .sidebarHostEnvironment(environmentContext)
            .environment(\.sidebarPresentationContext, presentationContext)
            // `NSHostingController` roots do not inherit `ContentView`’s `.ignoresSafeArea`; without this,
            // macOS reserves a title-bar safe area above the sidebar chrome when using `fullSizeContentView`.
            .ignoresSafeArea(.container, edges: .top)
    }
}

enum SidebarColumnHostedRoot {
    @MainActor
    static func view(
        browserManager: BrowserManager,
        windowState: BrowserWindowState,
        windowRegistry: WindowRegistry,
        commandPalette: CommandPalette,
        sumiSettings: SumiSettingsService,
        resolvedThemeContext: ResolvedThemeContext,
        presentationContext: SidebarPresentationContext
    ) -> SidebarColumnHostedRootView {
        SidebarColumnHostedRootView(
            environmentContext: SidebarHostEnvironmentContext(
                browserManager: browserManager,
                windowState: windowState,
                windowRegistry: windowRegistry,
                commandPalette: commandPalette,
                sumiSettings: sumiSettings,
                resolvedThemeContext: resolvedThemeContext
            ),
            presentationContext: presentationContext
        )
    }
}

struct SidebarColumnRepresentable: NSViewControllerRepresentable {
    @ObservedObject var browserManager: BrowserManager
    var windowState: BrowserWindowState
    var windowRegistry: WindowRegistry
    var commandPalette: CommandPalette
    var sumiSettings: SumiSettingsService
    var resolvedThemeContext: ResolvedThemeContext
    var presentationContext: SidebarPresentationContext

    func makeNSViewController(context: Context) -> SidebarColumnViewController {
        SidebarColumnViewController()
    }

    func updateNSViewController(_ controller: SidebarColumnViewController, context: Context) {
        let root = SidebarColumnHostedRoot.view(
            browserManager: browserManager,
            windowState: windowState,
            windowRegistry: windowRegistry,
            commandPalette: commandPalette,
            sumiSettings: sumiSettings,
            resolvedThemeContext: resolvedThemeContext,
            presentationContext: presentationContext
        )
        controller.updateHostedSidebar(
            root: root,
            width: presentationContext.sidebarWidth,
            contextMenuController: windowState.sidebarContextMenuController
        )
    }

    static func dismantleNSViewController(_ nsViewController: SidebarColumnViewController, coordinator: ()) {
        nsViewController.teardownSidebarHosting()
    }
}
