import Foundation

@MainActor
func makeNormalTabCoreUserScripts(for tab: Tab) -> [SumiPageScript] {
    var scripts: [SumiPageScript] = [
        SumiLinkInteractionUserScript(contextID: tab.id),
        SumiWebPageContextMenuUserScript(contextID: tab.id),
        SumiDocumentSuspensionSensorUserScript(
            tabID: tab.id,
            committedDocumentRuntime: tab.committedDocumentRuntime
        ),
        SumiTabSuspensionUserScript(tabID: tab.id),
        SumiWebNotificationUserScript(tab: tab),
        SumiNativeScrollbarHideUserScript(),
    ]
    if tab.sumiSettings?.isGPCEnabled ?? false {
        scripts.append(SumiGPCUserScript())
    }
    return scripts
}
