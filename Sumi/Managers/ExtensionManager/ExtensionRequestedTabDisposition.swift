import Foundation

/// Applies the active/pinned disposition an extension asked for to a tab that
/// has already been created, placed and admitted. Every observable step
/// revalidates the invocation so a superseded callback cannot select or pin.
@available(macOS 15.5, *)
@MainActor
enum ExtensionRequestedTabDisposition {
    static func apply(
        to tab: Tab,
        shouldBeActive: Bool,
        shouldBePinned: Bool,
        committedResidence: BrowserWindowState?,
        targetSpace: Space?,
        invocation: ExtensionRequestedTabInvocationAuthority,
        browserContext: any ExtensionTabCreation
    ) throws {
        if shouldBeActive {
            guard let committedResidence else {
                throw ExtensionManagerCallbackError
                    .requestedTabUnavailable.nsError()
            }
            guard invocation.isCurrent else { throw CancellationError() }
            browserContext.selectExtensionTab(tab, in: committedResidence)
        }
        if shouldBePinned {
            // Display active Tabs before regular-to-shortcut conversion.
            guard invocation.isCurrent else { throw CancellationError() }
            guard browserContext.pinExtensionTab(
                tab,
                targetWindow: committedResidence,
                targetSpace: targetSpace
            ) else {
                throw ExtensionManagerCallbackError
                    .requestedTabUnavailable.nsError()
            }
        }
    }
}
