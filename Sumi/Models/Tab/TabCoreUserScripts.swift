import Foundation

@MainActor
func makeNormalTabCoreUserScripts(for tab: Tab) -> [SumiPageScript] {
    var scripts: [SumiPageScript] = [
        SumiLinkInteractionUserScript(contextID: tab.id),
        SumiWebPageContextMenuUserScript(contextID: tab.id),
        SumiWebNotificationUserScript(tab: tab),
        SumiPageScrollbarOverlayUserScript(),
    ]
    if (tab.sumiSettings?.memoryMode ?? .off) != .off {
        scripts.append(
            SumiDocumentSuspensionSensorUserScript(
                tabID: tab.id,
                committedDocumentRuntime: tab.committedDocumentRuntime
            )
        )
        scripts.append(SumiTabSuspensionUserScript(tabID: tab.id))
    }
    if tab.sumiSettings?.isGPCEnabled ?? false {
        scripts.append(SumiGPCUserScript())
    }
    return scripts
}
