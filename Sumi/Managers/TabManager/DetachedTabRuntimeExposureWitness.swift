import Foundation

@MainActor
struct DetachedTabRuntimeExposureWitness {
    let tab: Tab
    private let attachment: TabRuntimeAttachmentWitness
    private let windows: ShortcutTabWindowQuery

    init?(
        tab: Tab,
        attachment: TabRuntimeAttachmentWitness,
        windows: ShortcutTabWindowQuery
    ) {
        self.tab = tab
        self.attachment = attachment
        self.windows = windows
        guard isCurrent() else { return nil }
    }

    func isCurrent() -> Bool {
        guard attachment.isCurrent() else { return false }
        guard let runtime else { return tab.hasBrowserRuntime == false }
        return windows.windowIdsDisplaying(
            tabId: tab.id,
            preferredWindowId: nil,
            using: runtime
        ).isEmpty
    }

    var runtime: RuntimePortRegistry? { attachment.lease.registry }
    var runtimeAttachment: TabRuntimeAttachmentWitness { attachment }
}
