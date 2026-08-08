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
private final class FindInPageChromeContainerView: WebContentHoverShieldingNSView {}

/// Mounts find chrome only while the active window needs it or while the transient panel is dismissing.
/// During dismissal the AppKit host stays alive for animation, while hit testing/focus are disabled.
struct FindInPageChromeHitTestingWrapper: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var keepsChromeMountedForDismissal = false
    @State private var dismissalGeneration: UInt = 0
    let findManager: FindManager
    let model: FindInPageModel?
    let focusGeneration: UInt
    let themeContext: ResolvedThemeContext
    let isPresented: Bool

    private var shouldMountFindChrome: Bool {
        isPresented || keepsChromeMountedForDismissal
    }

    var body: some View {
        Group {
            if shouldMountFindChrome {
                ZStack(alignment: .top) {
                    FindInPageChromeRepresentable(
                        findManager: findManager,
                        model: model,
                        focusGeneration: focusGeneration,
                        themeContext: themeContext,
                        isVisible: isPresented
                    )
                    .frame(width: FindInPageChromeLayout.panelWidth, height: FindInPageChromeLayout.panelHeight)
                    .shadow(
                        color: .black.opacity(colorScheme == .dark ? 0.42 : 0.18),
                        radius: 12,
                        x: 0,
                        y: 4
                    )
                    .opacity(isPresented ? 1 : 0)
                    .offset(y: isPresented ? 0 : -FindInPageChromeLayout.panelHeight)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, FindInPageChromeLayout.topInset)
                    .padding(.trailing, FindInPageChromeLayout.trailingInset)
                }
                .frame(height: FindInPageChromeLayout.stripHeight, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .top)
            } else {
                Color.clear
                    .frame(width: 0, height: 0)
            }
        }
        .animation(FindInPageChromeAnimation.presentation, value: isPresented)
        .onChange(of: isPresented) { wasPresented, isPresented in
            if isPresented {
                dismissalGeneration &+= 1
                keepsChromeMountedForDismissal = false
            } else if wasPresented {
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
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.chromeThemeTokens) private var scopedChromeTokens
    let findManager: FindManager
    let model: FindInPageModel?
    let focusGeneration: UInt
    let themeContext: ResolvedThemeContext
    let isVisible: Bool

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
        coordinator.findViewController?.cancelPendingTextFocus()

        coordinator.restoreFocusIfOwned(
            by: nsViewController.view,
            in: nsViewController.view.window
        )
    }

    func updateNSViewController(_ container: NSViewController, context: Context) {
        guard let findVC = context.coordinator.findViewController else { return }
        findVC.delegate = context.coordinator

        if isVisible {
            context.coordinator.lastVisibleModel = model
            context.coordinator.captureFocusReturnTargetIfNeeded(
                excluding: container.view,
                in: container.view.window
            )
        }
        let displayModel = isVisible ? model : context.coordinator.lastVisibleModel
        let shouldRender = isVisible || displayModel != nil

        if !isVisible {
            context.coordinator.restoreFocusIfOwned(
                by: container.view,
                in: container.view.window
            )
        }
        if !isVisible {
            findVC.cancelPendingTextFocus()
        }

        container.view.isHidden = !shouldRender
        (container.view as? FindInPageChromeContainerView)?.setHoverShieldEnabled(isVisible)

        let signature = FindChromePaintSignature(
            theme: themeContext,
            settingsBits: sumiSettings.chromeTokenRecipeFingerprint
        )
        if context.coordinator.lastChromePaintSignature != signature {
            context.coordinator.lastChromePaintSignature = signature
            let paint = FindInPageChromePaint.resolve(
                tokens: scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings)
            )
            findVC.applyChromeColors(paint)
        }

        if shouldRender {
            if findVC.model !== displayModel {
                findVC.model = displayModel
            }
            if isVisible {
                findVC.requestTextFocus(
                    generation: focusGeneration
                )
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
        var lastChromePaintSignature: FindChromePaintSignature?
        weak var focusReturnTarget: NSResponder?

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

        func captureFocusReturnTargetIfNeeded(
            excluding findView: NSView,
            in window: NSWindow?
        ) {
            guard focusReturnTarget == nil,
                  let responder = window?.firstResponder else {
                return
            }
            if let responderView = responder as? NSView,
               responderView.isDescendant(of: findView) {
                return
            }
            focusReturnTarget = responder
        }

        func restoreFocusIfOwned(
            by findView: NSView,
            in window: NSWindow?
        ) {
            guard let window,
                  let responderView = window.firstResponder as? NSView,
                  responderView.isDescendant(of: findView) else {
                focusReturnTarget = nil
                return
            }
            if let focusReturnTarget {
                _ = window.makeFirstResponder(focusReturnTarget)
            }
            self.focusReturnTarget = nil
        }
    }
}
