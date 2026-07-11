import SumiDomain
import SwiftUI

struct ShortcutHostedSplitGroupRow: View {
    let group: SplitGroup
    let items: [SplitGroupSidebarItem]
    let spaceId: UUID
    let tabManager: TabManager
    let splitLayout: SplitLayoutService
    let emptySplitCreation: EmptySplitCreationWorkflow
    let isAppKitInteractionEnabled: Bool
    let accessibilityID: String
    let onActivateMember: (SplitMemberID) -> Void
    let onRestoreShortcutMember: (SplitMemberID) -> Void
    let onCloseMember: (SplitMemberID) -> Void
    let onPrepareShortcutRestoreGap: (SplitMemberID) -> Void
    let onPerformShortcutRestoreWithPreparedGap: (
        SplitMemberID,
        @escaping () -> Void
    ) -> Void

    @Environment(BrowserWindowState.self) private var windowState

    init(
        group: SplitGroup,
        items: [SplitGroupSidebarItem],
        spaceId: UUID,
        tabManager: TabManager,
        splitLayout: SplitLayoutService,
        emptySplitCreation: EmptySplitCreationWorkflow,
        isAppKitInteractionEnabled: Bool,
        accessibilityID: String,
        onActivateMember: @escaping (SplitMemberID) -> Void,
        onRestoreShortcutMember: @escaping (SplitMemberID) -> Void,
        onCloseMember: @escaping (SplitMemberID) -> Void,
        onPrepareShortcutRestoreGap: @escaping (SplitMemberID) -> Void,
        onPerformShortcutRestoreWithPreparedGap: @escaping (
            SplitMemberID,
            @escaping () -> Void
        ) -> Void
    ) {
        self.group = group
        self.items = items
        self.spaceId = spaceId
        self.tabManager = tabManager
        self.splitLayout = splitLayout
        self.emptySplitCreation = emptySplitCreation
        self.isAppKitInteractionEnabled = isAppKitInteractionEnabled
        self.accessibilityID = accessibilityID
        self.onActivateMember = onActivateMember
        self.onRestoreShortcutMember = onRestoreShortcutMember
        self.onCloseMember = onCloseMember
        self.onPrepareShortcutRestoreGap = onPrepareShortcutRestoreGap
        self.onPerformShortcutRestoreWithPreparedGap =
            onPerformShortcutRestoreWithPreparedGap
    }

    var body: some View {
        SplitGroupSidebarRow(
            group: group,
            items: items,
            spaceId: spaceId,
            currentTabId: windowState.currentTabId,
            isAppKitInteractionEnabled: isAppKitInteractionEnabled,
            splitLayout: splitLayout,
            emptySplitCreation: emptySplitCreation,
            segmentAction: { item in
                SplitGroupSidebarModel.segmentAction(for: item, in: group)
            },
            dragSource: shortcutHostedSplitSegmentDragSource,
            contextMenuEntries: { _ in [] },
            onActivateMember: onActivateMember,
            onSegmentActionAnimationStart: { memberID in
                if isShortcut(memberID) {
                    onPrepareShortcutRestoreGap(memberID)
                }
            },
            onSegmentAction: performShortcutHostedSegmentAction,
            onSegmentMiddleClick: onCloseMember
        )
        .accessibilityIdentifier(accessibilityID)
    }

    private func performShortcutHostedSegmentAction(
        for memberID: SplitMemberID
    ) {
        if isShortcut(memberID) {
            onPerformShortcutRestoreWithPreparedGap(memberID) {
                SidebarMotionTransaction.withoutAnimation {
                    onRestoreShortcutMember(memberID)
                }
            }
            return
        }
        SidebarMotionTransaction.withoutAnimation {
            onCloseMember(memberID)
        }
    }

    private func isShortcut(_ memberID: SplitMemberID) -> Bool {
        if case .shortcutPin = memberID { return true }
        return false
    }

    private func shortcutHostedSplitSegmentDragSource(
        for item: SplitGroupSidebarItem
    ) -> SidebarDragSourceConfiguration? {
        if let pin = item.pin {
            return SidebarDragSourceConfiguration(
                item: SumiDragItem.splitMember(
                    item.id,
                    groupID: group.id,
                    title: item.title,
                    urlString: item.tab?.url.absoluteString
                        ?? pin.launchURL.absoluteString
                ),
                sourceZone: SplitGroupSidebarModel.sourceZone(
                    for: pin,
                    fallbackSpaceId: spaceId
                ),
                previewKind: .row,
                previewIcon: item.tab?.favicon ?? pin.storedFavicon,
                exclusionZones: [.trailingStrip(32)],
                onActivate: { onActivateMember(item.id) },
                isEnabled: isAppKitInteractionEnabled
            )
        }

        guard let tab = item.tab else { return nil }
        return SidebarDragSourceConfiguration(
            item: SumiDragItem.splitMember(
                item.id,
                groupID: group.id,
                title: tab.name,
                urlString: tab.url.absoluteString
            ),
            sourceZone: .spaceRegular(spaceId),
            previewKind: .row,
            previewIcon: tab.favicon,
            exclusionZones: [.trailingStrip(32)],
            onActivate: { onActivateMember(item.id) },
            isEnabled: isAppKitInteractionEnabled
        )
    }
}
