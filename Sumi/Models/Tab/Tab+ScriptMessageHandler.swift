import AppKit
import Foundation

extension Tab {
    func normalTabCoreUserScripts() -> [SumiPageScript] {
        makeNormalTabCoreUserScripts(for: self)
    }

    func isGlanceTriggerActive(_ flags: NSEvent.ModifierFlags) -> Bool {
        guard sumiSettings?.glanceEnabled ?? true else { return false }
        return flags.intersection([.command, .option, .control, .shift]) == [.option]
    }

    func shouldOpenDynamicallyInGlance(
        url: URL,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        guard sumiSettings?.glanceEnabled ?? true else { return false }
        guard modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]) else {
            return false
        }
        guard isPinned || shortcutPinRole == .essential else { return false }
        guard url.sumiIsGlancePreviewableLink else { return false }

        if url.sumiNavigationalScheme == .file {
            return self.url != url
        }

        guard let currentHost = self.url.host,
              let newHost = url.host else { return false }
        return currentHost != newHost
    }
}
