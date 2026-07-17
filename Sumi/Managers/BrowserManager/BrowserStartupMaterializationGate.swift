import Foundation
import SumiDomain

@MainActor
final class BrowserStartupMaterializationGate {
    private let restoration: BrowserStartupProtectionLevelRestoration
    private(set) var hasFinishedProtectionRestore = false

    init(restoration: BrowserStartupProtectionLevelRestoration) {
        self.restoration = restoration
    }

    var shouldDeferNormalTabMaterialization: Bool {
        StartupNormalTabMaterializationPolicy.shouldDefer(
            appliedProtectionLevel: restoration.appliedProtectionLevel,
            hasFinishedStartupProtectionRestore: hasFinishedProtectionRestore
        )
    }

    func canMaterialize(_ tab: Tab) -> Bool {
        if ExtensionURLIdentity.isOwned(tab.url)
            || tab.webExtensionContextOverride != nil {
            return true
        }
        return !tab.requiresPrimaryWebView
            || !shouldDeferNormalTabMaterialization
    }

    func finishProtectionRestore() -> Bool {
        guard !hasFinishedProtectionRestore else { return false }
        hasFinishedProtectionRestore = true
        return true
    }

    func restoreAppliedProtectionLevelForStartup() async throws {
        try await restoration.restoreAppliedProtectionLevelForStartup()
    }
}
