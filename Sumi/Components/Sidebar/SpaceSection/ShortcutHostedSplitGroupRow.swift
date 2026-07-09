import SwiftUI

struct ShortcutHostedSplitGroupRow: View {
    let group: SplitGroup
    let items: [SplitGroupSidebarItem]
    let spaceId: UUID
    let tabManager: TabManager
    let isAppKitInteractionEnabled: Bool
    let accessibilityID: String
    let onActivateTab: (Tab) -> Void
    let onActivateGroup: (SplitGroup) -> Void
    let onRestoreShortcutSplitMember: (SplitGroupSidebarItem, SplitGroup) -> Void
    let onCloseTab: (Tab) -> Void
    let onPrepareShortcutRestoreGap: (SplitGroupSidebarItem, SplitGroup) -> Void
    let onPerformShortcutRestoreWithPreparedGap: (SplitGroupSidebarItem, SplitGroup, @escaping () -> Void) -> Void

    @EnvironmentObject private var splitManager: SplitViewManager
    @Environment(BrowserWindowState.self) private var windowState

    init(
        group: SplitGroup,
        items: [SplitGroupSidebarItem],
        spaceId: UUID,
        browserContext: SidebarBrowserContext,
        isAppKitInteractionEnabled: Bool,
        accessibilityID: String,
        onActivateTab: @escaping (Tab) -> Void,
        onActivateGroup: @escaping (SplitGroup) -> Void,
        onRestoreShortcutSplitMember: @escaping (SplitGroupSidebarItem, SplitGroup) -> Void,
        onCloseTab: @escaping (Tab) -> Void,
        onPrepareShortcutRestoreGap: @escaping (SplitGroupSidebarItem, SplitGroup) -> Void,
        onPerformShortcutRestoreWithPreparedGap: @escaping (SplitGroupSidebarItem, SplitGroup, @escaping () -> Void) -> Void
    ) {
        self.group = group
        self.items = items
        self.spaceId = spaceId
        self.tabManager = browserContext.tabManager
        self.isAppKitInteractionEnabled = isAppKitInteractionEnabled
        self.accessibilityID = accessibilityID
        self.onActivateTab = onActivateTab
        self.onActivateGroup = onActivateGroup
        self.onRestoreShortcutSplitMember = onRestoreShortcutSplitMember
        self.onCloseTab = onCloseTab
        self.onPrepareShortcutRestoreGap = onPrepareShortcutRestoreGap
        self.onPerformShortcutRestoreWithPreparedGap = onPerformShortcutRestoreWithPreparedGap
    }

    init(
        group: SplitGroup,
        items: [SplitGroupSidebarItem],
        spaceId: UUID,
        tabManager: TabManager,
        isAppKitInteractionEnabled: Bool,
        accessibilityID: String,
        onActivateTab: @escaping (Tab) -> Void,
        onActivateGroup: @escaping (SplitGroup) -> Void,
        onRestoreShortcutSplitMember: @escaping (SplitGroupSidebarItem, SplitGroup) -> Void,
        onCloseTab: @escaping (Tab) -> Void,
        onPrepareShortcutRestoreGap: @escaping (SplitGroupSidebarItem, SplitGroup) -> Void,
        onPerformShortcutRestoreWithPreparedGap: @escaping (SplitGroupSidebarItem, SplitGroup, @escaping () -> Void) -> Void
    ) {
        self.group = group
        self.items = items
        self.spaceId = spaceId
        self.tabManager = tabManager
        self.isAppKitInteractionEnabled = isAppKitInteractionEnabled
        self.accessibilityID = accessibilityID
        self.onActivateTab = onActivateTab
        self.onActivateGroup = onActivateGroup
        self.onRestoreShortcutSplitMember = onRestoreShortcutSplitMember
        self.onCloseTab = onCloseTab
        self.onPrepareShortcutRestoreGap = onPrepareShortcutRestoreGap
        self.onPerformShortcutRestoreWithPreparedGap = onPerformShortcutRestoreWithPreparedGap
    }

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
                onActivateTab(tab)
            },
            onActivateGroup: {
                onActivateGroup(group)
            },
            onSegmentActionAnimationStart: { item in
                if SplitGroupSidebarModel.segmentAction(for: item, in: group) == .restore {
                    onPrepareShortcutRestoreGap(item, group)
                }
            },
            onSegmentAction: { item in
                performShortcutHostedSegmentAction(for: item)
            },
            onSegmentMiddleClick: { item in
                performShortcutHostedSegmentMiddleClick(for: item)
            }
        )
        .environmentObject(splitManager)
        .accessibilityIdentifier(accessibilityID)
    }

    private func performShortcutHostedSegmentAction(for item: SplitGroupSidebarItem) {
        if SplitGroupSidebarModel.segmentAction(for: item, in: group) == .restore {
            onPerformShortcutRestoreWithPreparedGap(item, group) {
                SidebarMotionTransaction.withoutAnimation {
                    onRestoreShortcutSplitMember(item, group)
                }
            }
            return
        }

        guard let tab = item.tab else { return }
        SidebarMotionTransaction.withoutAnimation {
            onCloseTab(tab)
        }
    }

    private func performShortcutHostedSegmentMiddleClick(for item: SplitGroupSidebarItem) {
        guard let tab = item.tab else { return }
        SidebarMotionTransaction.withoutAnimation {
            onCloseTab(tab)
        }
    }

    private func shortcutHostedSplitSegmentDragSource(
        for item: SplitGroupSidebarItem
    ) -> SidebarDragSourceConfiguration? {
        let member = SplitGroupSidebarModel.member(for: item, in: group)
        if let pin = SplitGroupSidebarModel.shortcutPin(
            for: item,
            member: member,
            tabManager: tabManager
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
                    onActivateGroup(group)
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
                onActivateTab(tab)
            },
            isEnabled: isAppKitInteractionEnabled
        )
    }
}
