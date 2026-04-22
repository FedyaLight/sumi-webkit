//
//  FindInPageChromeRepresentable.swift
//  Sumi
//

import AppKit
import SwiftUI

struct FindChromePaintSignature: Equatable {
    var theme: ResolvedThemeContext
    var settingsBits: Int

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.theme == rhs.theme && lhs.settingsBits == rhs.settingsBits
    }
}

/// Wraps find chrome so `FindManager` / `WindowRegistry` drive visibility.
/// When find is closed we **remove** the AppKit host from the hierarchy so it cannot keep capturing mouse/hover
/// after Cmd+F (SwiftUI `allowsHitTesting(false)` alone is not always reliable for `NSViewControllerRepresentable`).
struct FindInPageChromeHitTestingWrapper: View {
    @ObservedObject var findManager: FindManager
    @Environment(WindowRegistry.self) private var windowRegistry
    let windowStateID: UUID
    let themeContext: ResolvedThemeContext

    private var shouldMountFindChrome: Bool {
        windowRegistry.activeWindow?.id == windowStateID && findManager.isFindBarVisible
    }

    var body: some View {
        if shouldMountFindChrome {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                FindInPageChromeRepresentable(
                    findManager: findManager,
                    windowStateID: windowStateID,
                    themeContext: themeContext
                )
                .frame(width: 400, height: 48)
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .top)
        } else {
            Color.clear
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
    }
}

/// Hosts DuckDuckGo-style `FindInPageViewController` in the top browser chrome (400×40, centered).
struct FindInPageChromeRepresentable: NSViewControllerRepresentable {
    @ObservedObject var findManager: FindManager
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(\.sumiSettings) private var sumiSettings
    let windowStateID: UUID
    let themeContext: ResolvedThemeContext

    func makeCoordinator() -> Coordinator {
        Coordinator(findManager: findManager)
    }

    func makeNSViewController(context: Context) -> NSViewController {
        let container = NSViewController()
        let findVC = FindInPageViewController.create()
        findVC.delegate = context.coordinator
        context.coordinator.findViewController = findVC

        container.addChild(findVC)
        container.view.addSubview(findVC.view)
        findVC.view.translatesAutoresizingMaskIntoConstraints = false

        container.view.setContentHuggingPriority(.required, for: .vertical)
        container.view.setContentCompressionResistancePriority(.required, for: .vertical)

        NSLayoutConstraint.activate([
            findVC.view.widthAnchor.constraint(equalToConstant: 400),
            findVC.view.heightAnchor.constraint(equalToConstant: 40),
            findVC.view.centerXAnchor.constraint(equalTo: container.view.centerXAnchor),
            findVC.view.topAnchor.constraint(equalTo: container.view.topAnchor, constant: 8),
            container.view.bottomAnchor.constraint(equalTo: findVC.view.bottomAnchor),
        ])

        return container
    }

    static func dismantleNSViewController(_ nsViewController: NSViewController, coordinator: Coordinator) {
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

        if !visible, let window = container.view.window,
           let responder = window.firstResponder as? NSView,
           responder.isDescendant(of: container.view) {
            window.makeFirstResponder(nil)
        }

        findVC.view.isHidden = !visible
        container.view.isHidden = !visible

        let signature = FindChromePaintSignature(
            theme: themeContext,
            settingsBits: sumiSettings.chromeTokenRecipeFingerprint
        )
        if context.coordinator.lastChromePaintSignature != signature {
            context.coordinator.lastChromePaintSignature = signature
            let paint = FindInPageChromePaint.resolve(tokens: themeContext.tokens(settings: sumiSettings))
            findVC.applyChromeColors(paint)
        }

        if visible {
            if findVC.model !== model {
                findVC.model = model
            }
            let generation = findManager.findFieldFocusGeneration
            if generation != context.coordinator.lastAppliedFocusGeneration {
                context.coordinator.lastAppliedFocusGeneration = generation
                findVC.makeMeFirstResponder()
                // One deferred retry: representable can update before the NSView is in a window or first responder commits.
                if container.view.window == nil || !findVC.textField.sumi_findIsFirstResponder {
                    DispatchQueue.main.async {
                        findVC.makeMeFirstResponder()
                    }
                }
            }
        } else if findVC.model != nil {
            findVC.model = nil
        }
    }

    @MainActor
    final class Coordinator: NSObject, FindInPageDelegate {
        weak var findManager: FindManager?
        weak var findViewController: FindInPageViewController?
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
