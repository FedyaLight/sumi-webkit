import AppKit
import Foundation

extension Tab {
    func normalTabCoreUserScripts() -> [SumiPageScript] {
        let isGPCEnabled = sumiSettings?.isGPCEnabled ?? false
        let memoryMode = sumiSettings?.memoryMode ?? .off
        if let cachedNormalTabCoreUserScripts,
           cachedNormalTabCoreUserScriptsGPCEnabled == isGPCEnabled,
           cachedNormalTabCoreUserScriptsMemoryMode == memoryMode {
            return cachedNormalTabCoreUserScripts
        }
        let scripts = makeNormalTabCoreUserScripts(for: self)
        cachedNormalTabCoreUserScripts = scripts
        cachedNormalTabCoreUserScriptsGPCEnabled = isGPCEnabled
        cachedNormalTabCoreUserScriptsMemoryMode = memoryMode
        return scripts
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
        guard usesPinnedLinkPolicy else { return false }
        guard url.sumiIsGlancePreviewableLink else { return false }

        if url.sumiNavigationalScheme == .file {
            return self.url != url
        }

        guard let newHost = url.host else { return false }
        return self.url.host != newHost
    }

    var usesPinnedLinkPolicy: Bool {
        isPinned || isSpacePinned || shortcutPinRole != nil
    }
}
