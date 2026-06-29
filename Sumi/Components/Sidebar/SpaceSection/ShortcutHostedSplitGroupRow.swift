import SwiftUI

struct ShortcutHostedSplitGroupRow: View {
    let group: SplitGroup
    let items: [SplitGroupSidebarItem]
    let spaceId: UUID
    let isAppKitInteractionEnabled: Bool
    let accessibilityID: String
    let onPrepareShortcutRestoreGap: (SplitGroupSidebarItem, SplitGroup) -> Void
    let onPerformShortcutRestoreWithPreparedGap: (SplitGroupSidebarItem, SplitGroup, @escaping () -> Void) -> Void

    @EnvironmentObject private var browserManager: BrowserManager
    @EnvironmentObject private var splitManager: SplitViewManager
    @Environment(BrowserWindowState.self) private var windowState

    var body: some View {
        SplitGroupSidebarRow(
            group: group,
            items: items,
            spaceId: spaceId,
            currentTabId: windowState.currentTabId,
            isAppKitInteractionEnabled: isAppKitInteractionEnabled,
            segmentAction: { item in
                SplitGroupSidebarModel.segmentAction(for: item, in: group)
            },
            dragSource: { item in
                shortcutHostedSplitSegmentDragSource(for: item)
            },
            contextMenuEntries: { _ in [] },
            onActivate: { tab in
                browserManager.requestUserTabActivation(tab, in: windowState)
            },
            onActivateGroup: {
                browserManager.focusSplitGroup(group, in: windowState)
            },
            onSegmentActionAnimationStart: { item in
                if SplitGroupSidebarModel.segmentAction(for: item, in: group) == .restore {
                    onPrepareShortcutRestoreGap(item, group)
                }
            },
            onSegmentAction: { item in
                performShortcutHostedSegmentAction(for: item)
            }
        )
        .environmentObject(browserManager)
        .environmentObject(splitManager)
        .accessibilityIdentifier(accessibilityID)
    }

    private func performShortcutHostedSegmentAction(for item: SplitGroupSidebarItem) {
        if SplitGroupSidebarModel.segmentAction(for: item, in: group) == .restore {
            onPerformShortcutRestoreWithPreparedGap(item, group) {
                SidebarMotionTransaction.withoutAnimation {
                    browserManager.restoreShortcutSplitMember(item.id, from: group, in: windowState)
                }
            }
            return
        }

        guard let tab = item.tab else { return }
        SidebarMotionTransaction.withoutAnimation {
            browserManager.closeTab(tab, in: windowState)
        }
    }

    private func shortcutHostedSplitSegmentDragSource(
        for item: SplitGroupSidebarItem
    ) -> SidebarDragSourceConfiguration? {
        let member = SplitGroupSidebarModel.member(for: item, in: group)
        if let pin = SplitGroupSidebarModel.shortcutPin(
            for: item,
            member: member,
            tabManager: browserManager.tabManager
        ) {
            let dragItemId = item.tab?.id ?? pin.id
            return SidebarDragSourceConfiguration(
                item: SumiDragItem(
                    tabId: dragItemId,
                    title: item.title,
                    urlString: item.tab?.url.absoluteString ?? pin.launchURL.absoluteString
                ),
                sourceZone: SplitGroupSidebarModel.sourceZone(for: pin, fallbackSpaceId: spaceId),
                previewKind: .row,
                previewIcon: item.tab?.favicon ?? pin.storedFavicon,
                exclusionZones: [.trailingStrip(32)],
                onActivate: {
                    browserManager.focusSplitGroup(group, in: windowState)
                },
                isEnabled: isAppKitInteractionEnabled
            )
        }

        guard let tab = item.tab else { return nil }
        return SidebarDragSourceConfiguration(
            item: SumiDragItem(
                tabId: tab.id,
                title: tab.name,
                urlString: tab.url.absoluteString
            ),
            sourceZone: .spaceRegular(spaceId),
            previewKind: .row,
            previewIcon: tab.favicon,
            exclusionZones: [.trailingStrip(32)],
            onActivate: {
                browserManager.requestUserTabActivation(tab, in: windowState)
            },
            isEnabled: isAppKitInteractionEnabled
        )
    }
}
