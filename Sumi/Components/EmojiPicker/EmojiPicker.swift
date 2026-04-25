//
//  EmojiPicker.swift
//  Sumi
//
//  Created by Maciek Bagiński on 02/10/2025.
//

import AppKit
import SwiftUI

/// Shared layout, timing, and motion constants for the emoji popover and its SwiftUI panel.
enum SumiEmojiPickerMetrics {
    static let popoverWidth: CGFloat = 320
    static let popoverHeight: CGFloat = 300
    static let searchDebounce: Duration = .milliseconds(150)
    static let appearSpringResponse: Double = 0.42
    static let appearSpringDamping: Double = 0.78
    static let disappearEaseDuration: Double = 0.16
    static let appearScale: CGFloat = 0.94
    static let appearOffsetY: CGFloat = -10
}

@MainActor
class EmojiPickerManager: NSObject, ObservableObject {
    var popover: NSPopover?
    weak var anchorView: NSView?
    var sidebarRecoveryCoordinator: SidebarHostRecoveryHandling = SidebarHostRecoveryCoordinator.shared
    @Published var selectedEmoji: String = ""
    @Published var committedEmoji: String = ""

    private let pickerViewModel = EmojiPickerViewModel()
    private var emojiHostingController: NSHostingController<AnyView>?
    private var activePresentationSource: SidebarTransientPresentationSource?
    private var transientSessionToken: SidebarTransientSessionToken?
    private var activeCommitHandler: ((String) -> Void)?
    private var activeSettings: SumiSettingsService?
    private var activeThemeContext: ResolvedThemeContext?

    func toggle(
        source: SidebarTransientPresentationSource? = nil,
        settings: SumiSettingsService? = nil,
        themeContext: ResolvedThemeContext? = nil,
        onCommit: ((String) -> Void)? = nil
    ) {
        guard let anchorView = anchorView else { return }

        if popover?.isShown == true {
            popover?.close()
            return
        }

        committedEmoji = ""
        activePresentationSource = source
        activeCommitHandler = onCommit
        activeSettings = settings
        activeThemeContext = themeContext
        transientSessionToken = source.flatMap {
            $0.coordinator?.beginSession(
                kind: .emojiPopover,
                source: $0,
                path: "EmojiPickerManager.toggle"
            )
        }
        ensureHostingController()
        pickerViewModel.resetForOpen(currentGlyph: selectedEmoji)

        if popover == nil {
            let pop = NSPopover()
            pop.contentViewController = emojiHostingController
            pop.behavior = .semitransient
            pop.delegate = self
            pop.contentSize = NSSize(
                width: SumiEmojiPickerMetrics.popoverWidth,
                height: SumiEmojiPickerMetrics.popoverHeight
            )
            pop.animates = true
            popover = pop
        }

        popover?.contentSize = NSSize(
            width: SumiEmojiPickerMetrics.popoverWidth,
            height: SumiEmojiPickerMetrics.popoverHeight
        )
        popover?.appearance = anchorView.window?.effectiveAppearance

        guard let window = anchorView.window,
            let screen = window.screen
        else {
            popover?.show(
                relativeTo: anchorView.bounds,
                of: anchorView,
                preferredEdge: .minY
            )
            return
        }

        let anchorFrameInWindow = anchorView.convert(anchorView.bounds, to: nil)
        let anchorFrameInScreen = window.convertToScreen(anchorFrameInWindow)

        let popoverWidth = SumiEmojiPickerMetrics.popoverWidth
        let screenFrame = screen.visibleFrame

        var positioningRect = anchorView.bounds

        let rightEdge = anchorFrameInScreen.maxX
        let leftEdge = anchorFrameInScreen.minX

        if rightEdge + popoverWidth > screenFrame.maxX {
            let overflow = (rightEdge + popoverWidth) - screenFrame.maxX
            positioningRect.origin.x -= overflow
        } else if leftEdge < screenFrame.minX {
            let overflow = screenFrame.minX - leftEdge
            positioningRect.origin.x += overflow
        }

        popover?.show(
            relativeTo: positioningRect,
            of: anchorView,
            preferredEdge: .maxY
        )
    }

    private func ensureHostingController() {
        let panel = makePanel()
        if let emojiHostingController {
            emojiHostingController.rootView = panel
            return
        }

        let hosting = NSHostingController(rootView: panel)
        hosting.view.frame = NSRect(
            x: 0,
            y: 0,
            width: SumiEmojiPickerMetrics.popoverWidth,
            height: SumiEmojiPickerMetrics.popoverHeight
        )
        emojiHostingController = hosting
    }

    private func makePanel() -> AnyView {
        let panel = SumiEmojiPickerPanel(
            model: pickerViewModel,
            onEmojiSelected: { [weak self] emoji in
                DispatchQueue.main.async { [weak self] in
                    self?.selectedEmoji = emoji
                }
            }
        )

        if let activeSettings, let activeThemeContext {
            return AnyView(
                panel
                    .environment(\.sumiSettings, activeSettings)
                    .environment(\.resolvedThemeContext, activeThemeContext)
            )
        }

        if let activeSettings {
            return AnyView(panel.environment(\.sumiSettings, activeSettings))
        }

        return AnyView(panel)
    }
}

extension EmojiPickerManager: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        let selectedEmojiForCommit = selectedEmoji
        let commitPickedEmoji = { [weak self] in
            guard let self, !selectedEmojiForCommit.isEmpty else { return }
            if let activeCommitHandler = self.activeCommitHandler {
                activeCommitHandler(selectedEmojiForCommit)
            } else {
                self.committedEmoji = selectedEmojiForCommit
            }
        }

        if let coordinator = activePresentationSource?.coordinator,
           let transientSessionToken
        {
            coordinator.finishSession(
                transientSessionToken,
                reason: "EmojiPickerManager.popoverDidClose",
                teardown: commitPickedEmoji
            )
        } else {
            commitPickedEmoji()
            let window = anchorView?.window
            // Window-level recovery invalidates all registered anchors (including the sidebar
            // NSHostingView). Leaf-only recover(anchor:) was insufficient after popover dismiss.
            sidebarRecoveryCoordinator.recover(in: window)
            sidebarRecoveryCoordinator.recover(anchor: anchorView)
        }
        transientSessionToken = nil
        activePresentationSource = nil
        activeCommitHandler = nil
    }
}

struct EmojiPickerAnchor: NSViewRepresentable {
    let manager: EmojiPickerManager

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        manager.anchorView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
