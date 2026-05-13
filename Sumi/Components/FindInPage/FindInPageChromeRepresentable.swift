//
//  FindInPageChromeRepresentable.swift
//  Sumi
//

import AppKit
import SwiftUI

/// Shared layout for find-in-page chrome and its transient panel strip.
enum FindInPageChromeLayout {
    /// Top padding + representable height plus bottom inset so SwiftUI `.shadow` is not clipped by the panel.
    static let stripHeight: CGFloat = 80
    static let panelWidth: CGFloat = 340
    static let panelHeight: CGFloat = 44
    static let topInset: CGFloat = 24
    static let trailingInset: CGFloat = 14
}

private enum FindInPageChromeAnimation {
    static let duration: TimeInterval = 0.18
    static let presentation = Animation.easeOut(duration: 0.18)
}

struct FindChromePaintSignature: Equatable {
    var theme: ResolvedThemeContext
    var settingsBits: Int
}

@MainActor
private final class FindInPageChromeContainerView: NSView {
    private var hoverShieldTrackingArea: NSTrackingArea?
    private var isHoverShieldEnabled = false
    private var isShieldingWebContentHover = false

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            setShieldingWebContentHover(false)
            WebContentMouseTrackingShield.unregister(self)
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateShielding(refreshIfAlreadyShielding: true)
    }

    override func layout() {
        super.layout()
        updateShielding(refreshIfAlreadyShielding: true)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        clearHoverShieldTrackingArea()

        guard isHoverShieldEnabled else { return }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        hoverShieldTrackingArea = trackingArea
        addTrackingArea(trackingArea)
        updateShielding(refreshIfAlreadyShielding: true)
    }

    override func mouseEntered(with event: NSEvent) {
        updateShielding(refreshIfAlreadyShielding: false)
    }

    override func mouseMoved(with event: NSEvent) {
        updateShielding(refreshIfAlreadyShielding: false)
    }

    override func mouseExited(with event: NSEvent) {
        setShieldingWebContentHover(false)
    }

    func setHoverShieldEnabled(_ isEnabled: Bool) {
        guard isHoverShieldEnabled != isEnabled else {
            updateShielding(refreshIfAlreadyShielding: true)
            return
        }

        isHoverShieldEnabled = isEnabled
        if isEnabled {
            updateTrackingAreas()
        } else {
            clearHoverShieldTrackingArea()
            setShieldingWebContentHover(false)
            WebContentMouseTrackingShield.unregister(self)
        }
    }

    private func clearHoverShieldTrackingArea() {
        if let hoverShieldTrackingArea {
            removeTrackingArea(hoverShieldTrackingArea)
            self.hoverShieldTrackingArea = nil
        }
    }

    private func updateShielding(refreshIfAlreadyShielding: Bool) {
        guard isHoverShieldEnabled,
              let window
        else {
            setShieldingWebContentHover(false)
            return
        }

        let location = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setShieldingWebContentHover(bounds.contains(location), refreshIfUnchanged: refreshIfAlreadyShielding)
    }

    private func setShieldingWebContentHover(
        _ isShielding: Bool,
        refreshIfUnchanged: Bool = false
    ) {
        guard isShieldingWebContentHover != isShielding else {
            if isShielding, refreshIfUnchanged {
                WebContentMouseTrackingShield.refresh(for: self)
            }
            return
        }

        isShieldingWebContentHover = isShielding
        WebContentMouseTrackingShield.setActive(isShielding, for: self)
    }
}

/// Mounts find chrome only while the active window needs it or while the transient panel is dismissing.
/// During dismissal the AppKit host stays alive for animation, while hit testing/focus are disabled.
struct FindInPageChromeHitTestingWrapper: View {
    @ObservedObject var findManager: FindManager
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(\.colorScheme) private var colorScheme
    @State private var keepsChromeMountedForDismissal = false
    @State private var dismissalGeneration: UInt = 0
    let windowStateID: UUID
    let themeContext: ResolvedThemeContext
    let keepsChromeMounted: Bool
    let isInteractive: Bool

    private var shouldMountFindChrome: Bool {
        windowRegistry.activeWindow?.id == windowStateID
            && (findManager.isFindBarVisible || keepsChromeMounted || keepsChromeMountedForDismissal)
    }

    private var shouldKeepRepresentableRendered: Bool {
        keepsChromeMounted || keepsChromeMountedForDismissal
    }

    private var isRepresentableInteractive: Bool {
        isInteractive && findManager.isFindBarVisible
    }

    private var isChromePresented: Bool {
        windowRegistry.activeWindow?.id == windowStateID && findManager.isFindBarVisible
    }

    var body: some View {
        Group {
            if shouldMountFindChrome {
                ZStack(alignment: .top) {
                    FindInPageChromeRepresentable(
                        findManager: findManager,
                        windowStateID: windowStateID,
                        themeContext: themeContext,
                        keepsChromeMounted: shouldKeepRepresentableRendered,
                        isInteractive: isRepresentableInteractive
                    )
                    .frame(width: FindInPageChromeLayout.panelWidth, height: FindInPageChromeLayout.panelHeight)
                    .shadow(
                        color: .black.opacity(colorScheme == .dark ? 0.42 : 0.18),
                        radius: 12,
                        x: 0,
                        y: 4
                    )
                    .opacity(isChromePresented ? 1 : 0)
                    .offset(y: isChromePresented ? 0 : -FindInPageChromeLayout.panelHeight)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, FindInPageChromeLayout.topInset)
                    .padding(.trailing, FindInPageChromeLayout.trailingInset)
                }
                .frame(height: FindInPageChromeLayout.stripHeight, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .top)
                .allowsHitTesting(isRepresentableInteractive)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
            } else {
                Color.clear
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
            }
        }
        .animation(FindInPageChromeAnimation.presentation, value: shouldMountFindChrome)
        .animation(FindInPageChromeAnimation.presentation, value: isChromePresented)
        .onChange(of: findManager.isFindBarVisible) { wasVisible, isVisible in
            if isVisible {
                dismissalGeneration &+= 1
                keepsChromeMountedForDismissal = false
            } else if wasVisible && windowRegistry.activeWindow?.id == windowStateID {
                dismissalGeneration &+= 1
                let generation = dismissalGeneration
                keepsChromeMountedForDismissal = true
                DispatchQueue.main.asyncAfter(deadline: .now() + FindInPageChromeAnimation.duration) {
                    guard dismissalGeneration == generation else { return }
                    keepsChromeMountedForDismissal = false
                }
            }
        }
    }
}

/// Hosts `FindInPageViewController` in the top-right browser chrome.
struct FindInPageChromeRepresentable: NSViewControllerRepresentable {
    @ObservedObject var findManager: FindManager
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(\.sumiSettings) private var sumiSettings
    let windowStateID: UUID
    let themeContext: ResolvedThemeContext
    let keepsChromeMounted: Bool
    let isInteractive: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(findManager: findManager)
    }

    func makeNSViewController(context: Context) -> NSViewController {
        let container = NSViewController()
        container.view = FindInPageChromeContainerView(frame: NSRect(
            x: 0,
            y: 0,
            width: FindInPageChromeLayout.panelWidth,
            height: FindInPageChromeLayout.panelHeight
        ))
        let findVC = FindInPageViewController.create()
        findVC.delegate = context.coordinator
        context.coordinator.findViewController = findVC

        container.addChild(findVC)
        container.view.addSubview(findVC.view)
        findVC.view.translatesAutoresizingMaskIntoConstraints = false

        container.view.setContentHuggingPriority(.required, for: .vertical)
        container.view.setContentCompressionResistancePriority(.required, for: .vertical)

        NSLayoutConstraint.activate([
            findVC.view.widthAnchor.constraint(equalToConstant: FindInPageChromeLayout.panelWidth),
            findVC.view.heightAnchor.constraint(equalToConstant: FindInPageChromeLayout.panelHeight),
            findVC.view.centerXAnchor.constraint(equalTo: container.view.centerXAnchor),
            findVC.view.topAnchor.constraint(equalTo: container.view.topAnchor),
            container.view.bottomAnchor.constraint(equalTo: findVC.view.bottomAnchor),
        ])

        return container
    }

    static func dismantleNSViewController(_ nsViewController: NSViewController, coordinator: Coordinator) {
        (nsViewController.view as? FindInPageChromeContainerView)?.setHoverShieldEnabled(false)

        guard let window = nsViewController.view.window,
              let responder = window.firstResponder as? NSView,
              responder.isDescendant(of: nsViewController.view) else { return }
        window.makeFirstResponder(nil)
    }

    func updateNSViewController(_ container: NSViewController, context: Context) {
        guard let findVC = context.coordinator.findViewController else { return }
        findVC.delegate = context.coordinator

        let isActiveWindow = windowRegistry.activeWindow?.id == windowStateID
        let model = findManager.currentModel
        let visible = (model?.isVisible == true) && isActiveWindow
        if visible {
            context.coordinator.lastVisibleModel = model
        }
        let displayModel = visible ? model : context.coordinator.lastVisibleModel
        let shouldRender = visible || (keepsChromeMounted && displayModel != nil)

        if (!visible || !isInteractive), let window = container.view.window,
           let responder = window.firstResponder as? NSView,
           responder.isDescendant(of: container.view) {
            window.makeFirstResponder(nil)
        }

        findVC.view.isHidden = !shouldRender
        container.view.isHidden = !shouldRender
        (container.view as? FindInPageChromeContainerView)?.setHoverShieldEnabled(visible && isInteractive)

        let signature = FindChromePaintSignature(
            theme: themeContext,
            settingsBits: sumiSettings.chromeTokenRecipeFingerprint
        )
        if context.coordinator.lastChromePaintSignature != signature {
            context.coordinator.lastChromePaintSignature = signature
            let paint = FindInPageChromePaint.resolve(tokens: themeContext.tokens(settings: sumiSettings))
            findVC.applyChromeColors(paint)
        }

        if shouldRender {
            if findVC.model !== displayModel {
                findVC.model = displayModel
            }
            let generation = findManager.findFieldFocusGeneration
            if visible && isInteractive && generation != context.coordinator.lastAppliedFocusGeneration {
                context.coordinator.lastAppliedFocusGeneration = generation
                findVC.makeMeFirstResponder()
                // One deferred retry: representable can update before the NSView is in a window or first responder commits.
                if container.view.window == nil || !findVC.textField.sumi_findIsFirstResponder {
                    let containerView = container.view
                    DispatchQueue.main.async { [weak findVC, weak containerView] in
                        guard let findVC, containerView?.window != nil else { return }
                        findVC.makeMeFirstResponder()
                    }
                }
            }
        } else if findVC.model != nil {
            findVC.model = nil
            context.coordinator.lastVisibleModel = nil
        }
    }

    @MainActor
    final class Coordinator: NSObject, FindInPageDelegate {
        weak var findManager: FindManager?
        weak var findViewController: FindInPageViewController?
        var lastVisibleModel: FindInPageModel?
        var lastAppliedFocusGeneration: UInt = 0
        var lastChromePaintSignature: FindChromePaintSignature?

        init(findManager: FindManager) {
            self.findManager = findManager
        }

        func findInPageNext(_ sender: Any) {
            findManager?.findNext()
        }

        func findInPagePrevious(_ sender: Any) {
            findManager?.findPrevious()
        }

        func findInPageDone(_ sender: Any) {
            findManager?.hideFindBar()
        }
    }
}
