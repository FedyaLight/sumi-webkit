import Foundation

@MainActor
func makeNormalTabCoreUserScripts(for tab: Tab) -> [SumiUserScript] {
    var scripts: [SumiUserScript] = [
        SumiLinkInteractionUserScript(contextID: tab.id),
        SumiWebPageContextMenuUserScript(contextID: tab.id),
        SumiDocumentSuspensionSensorUserScript(
            tabID: tab.id,
            committedDocumentRuntime: tab.committedDocumentRuntime
        ),
        SumiTabSuspensionUserScript(tabID: tab.id),
        SumiSubframePictureInPictureUserScript(
            tabID: tab.id,
            committedDocumentRuntime: tab.committedDocumentRuntime
        ),
        SumiWebNotificationUserScript(tab: tab),
        SumiNativeScrollbarHideUserScript(),
    ]
    if tab.sumiSettings?.isGPCEnabled ?? true {
        scripts.append(SumiGPCUserScript())
    }
    return scripts
}
