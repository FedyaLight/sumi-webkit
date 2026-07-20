import SumiDomain

struct SplitGroupContextMenuMember {
    let id: SplitMemberID
    let title: String
    let url: URL
    var additionalEntries: [SidebarContextMenuEntry] = []
}

struct SplitGroupContextMenuActions {
    typealias Action = @MainActor @Sendable () -> Void

    var edit: Action? = nil
    var duplicate: Action? = nil
    var addTab: Action? = nil
    var moveTo: [SidebarContextMenuEntry] = []
    var unload: Action? = nil
    var delete: Action? = nil
    var close: Action? = nil

    static var empty: Self { Self() }
}

@MainActor
enum SplitGroupContextMenuFactory {
    static func entries(
        for group: SplitGroup,
        members: [SplitGroupContextMenuMember],
        splitLayout: SplitLayoutService,
        emptySplitCreation: EmptySplitCreationWorkflow?,
        windowState: BrowserWindowState,
        actions: SplitGroupContextMenuActions = .empty
    ) -> [SidebarContextMenuEntry] {
        var metadata: [SidebarContextMenuEntry] = []
        if let edit = actions.edit {
            metadata.append(.action(.init(
                title: "Edit…",
                systemImage: "pencil",
                classification: .structuralMutation,
                action: edit
            )))
        }
        if let duplicate = actions.duplicate {
            metadata.append(.action(.init(
                title: "Duplicate",
                systemImage: "doc.on.doc",
                classification: .structuralMutation,
                action: duplicate
            )))
        }
        if !actions.moveTo.isEmpty {
            metadata.append(.submenu(
                title: "Move to",
                systemImage: "arrow.right",
                children: actions.moveTo
            ))
        }
        var splitCommands: [SidebarContextMenuEntry] = [
            .action(.init(
                title: "Separate All Tabs",
                systemImage: "rectangle.split.1x2",
                classification: .structuralMutation,
                action: { splitLayout.unsplit(groupID: group.id) }
            )),
        ]
        if let addTab = actions.addTab {
            splitCommands.append(.action(.init(
                title: "Add Tab…",
                systemImage: "plus",
                isEnabled: group.memberIDs.count < SplitGroup.maximumMembers,
                classification: .structuralMutation,
                action: addTab
            )))
        } else if let emptySplitCreation {
            splitCommands.append(.action(.init(
                title: "Add Tab…",
                systemImage: "plus",
                isEnabled: group.memberIDs.count < SplitGroup.maximumMembers,
                classification: .structuralMutation,
                action: {
                    emptySplitCreation.create(
                        side: .right,
                        in: windowState,
                        reason: .splitTabPicker
                    )
                }
            )))
        }
        var sections = [metadata, splitCommands]
        let layoutEntries: [SidebarContextMenuEntry] =
            SplitLayoutKind.allCases.compactMap { kind in
            guard kind != group.layoutKind else { return nil }
            return .action(.init(
                title: conversionTitle(for: kind),
                systemImage: systemImage(for: kind),
                classification: .structuralMutation,
                action: {
                    splitLayout.setLayoutKind(
                        kind,
                        groupID: group.id,
                        in: windowState.id
                    )
                }
            ))
        }
        sections.append(layoutEntries)
        if !members.isEmpty {
            sections.append([
                .action(.init(
                    title: "Tab Options",
                    isEnabled: false,
                    onAction: {}
                )),
            ] + members.map { member in
                .submenu(
                    title: member.title,
                    children: memberEntries(
                        member,
                        groupID: group.id,
                        splitLayout: splitLayout,
                        windowState: windowState
                    )
                )
            })
        }
        var lifecycle: [SidebarContextMenuEntry] = []
        if let unload = actions.unload {
            lifecycle.append(.action(.init(
                title: "Unload Split View",
                systemImage: "arrow.down.circle",
                classification: .structuralMutation,
                action: unload
            )))
        }
        if let close = actions.close {
            lifecycle.append(.action(.init(
                title: "Close Split View",
                systemImage: "xmark",
                classification: .structuralMutation,
                action: close
            )))
        }
        if let delete = actions.delete {
            lifecycle.append(.action(.init(
                title: "Delete Split View…",
                systemImage: "trash",
                role: .destructive,
                classification: .structuralMutation,
                action: delete
            )))
        }
        sections.append(lifecycle)
        return joinSidebarMenuSections(sections)
    }

    private static func memberEntries(
        _ member: SplitGroupContextMenuMember,
        groupID: UUID,
        splitLayout: SplitLayoutService,
        windowState: BrowserWindowState
    ) -> [SidebarContextMenuEntry] {
        var entries: [SidebarContextMenuEntry] = [
            .action(.init(
                title: "Separate from Split View",
                systemImage: "rectangle.portrait.and.arrow.right",
                classification: .structuralMutation,
                action: {
                    splitLayout.separate(
                        member.id,
                        from: groupID,
                        in: windowState
                    )
                }
            )),
            .separator,
            .action(.init(
                title: "Copy Link",
                systemImage: "link",
                action: { SidebarLinkActions.copyLink(member.url) }
            )),
            .action(.init(
                title: "Copy Link as Markdown",
                systemImage: "text.badge.checkmark",
                action: {
                    SidebarLinkActions.copyLinkAsMarkdown(
                        title: member.title,
                        url: member.url
                    )
                }
            )),
        ]
        if !member.additionalEntries.isEmpty {
            entries.append(.separator)
            entries.append(contentsOf: member.additionalEntries)
        }
        return entries
    }

    private static func conversionTitle(
        for kind: SplitLayoutKind
    ) -> String {
        switch kind {
        case .grid: "Convert to Grid Split View"
        case .vertical: "Convert to Vertical Split View"
        case .horizontal: "Convert to Horizontal Split View"
        }
    }

    private static func systemImage(
        for kind: SplitLayoutKind
    ) -> String {
        switch kind {
        case .grid: "square.grid.2x2"
        case .vertical: "rectangle.split.2x1"
        case .horizontal: "rectangle.split.1x2"
        }
    }
}
