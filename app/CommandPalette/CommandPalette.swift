//
//  CommandPalette.swift
//  Sumi
//
//  Per-window command palette state and actions
//

import Foundation
import SwiftUI

enum CommandPaletteStateChangeKind {
    case draft
    case session
}

@MainActor
@Observable
class CommandPalette {
    /// Whether the command palette is visible
    var isVisible: Bool = false

    /// Text to prefill in the command palette
    var prefilledText: String = ""

    /// Whether pressing Return should navigate the current tab (vs creating new tab)
    var shouldNavigateCurrentTab: Bool = false

    /// Callback used by the window/session layer to persist palette state.
    var onStateChange: ((CommandPaletteStateChangeKind) -> Void)?

    // MARK: - Actions

    /// Open the command palette with optional prefill text
    func open(prefill: String = "", navigateCurrentTab: Bool = false) {
        let shouldOverrideDraft = !prefill.isEmpty || prefilledText.isEmpty || navigateCurrentTab
        if shouldOverrideDraft {
            prefilledText = prefill
            shouldNavigateCurrentTab = navigateCurrentTab
        }
        DispatchQueue.main.async {
            self.isVisible = true
            self.notifyStateChanged(.session)
        }
    }

    /// Open the command palette with the current tab's URL
    func openWithCurrentURL(_ url: URL) {
        open(prefill: url.absoluteString, navigateCurrentTab: true)
    }

    /// Close the command palette
    func close(preserveDraft: Bool = true) {
        isVisible = false
        if !preserveDraft {
            clearDraft(notify: false)
        }
        notifyStateChanged(.session)
    }

    func updateDraft(text: String) {
        guard prefilledText != text else { return }
        prefilledText = text
        notifyStateChanged(.draft)
    }

    func restore(draftText: String, navigateCurrentTab: Bool) {
        prefilledText = draftText
        shouldNavigateCurrentTab = navigateCurrentTab
        notifyStateChanged(.session)
    }

    func clearDraft() {
        clearDraft(notify: true)
    }

    private func clearDraft(notify: Bool) {
        shouldNavigateCurrentTab = false
        prefilledText = ""
        if notify {
            notifyStateChanged(.session)
        }
    }

    /// Toggle the command palette visibility
    func toggle() {
        if isVisible {
            close()
        } else {
            open()
        }
    }

    private func notifyStateChanged(_ kind: CommandPaletteStateChangeKind) {
        onStateChange?(kind)
    }
}
