import Foundation

@available(macOS 15.5, *)
@MainActor
struct ExtensionToolbarRuntime {
    let ordering: ExtensionToolbarOrderingRuntime
    let siteAccess: ExtensionToolbarSiteAccessRuntime
    let options: ExtensionToolbarOptionsRuntime
    let popup: ExtensionToolbarPopupRuntime
    let actionPresentation: ExtensionActionPresentationQuery
}
