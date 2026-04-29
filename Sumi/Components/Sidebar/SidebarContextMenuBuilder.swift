//
//  SidebarContextMenuBuilder.swift
//  Sumi
//

import AppKit

final class SidebarContextMenuBuilder: NSObject, NSMenuDelegate {
    private let entries: [SidebarContextMenuEntry]
    private let onMenuWillOpen: () -> Void
    private let onMenuDidClose: () -> Void
    private let onActionWillDispatch: (String, SidebarContextMenuActionClassification) -> Void
    private let onActionDidDrain: (String, SidebarContextMenuActionClassification) -> Void
    private var actionTargets: [SidebarContextMenuActionTarget] = []
    private var didOpenMenu = false
    private var didCloseMenu = false

    init(
        entries: [SidebarContextMenuEntry],
        onMenuWillOpen: @escaping () -> Void = {},
        onMenuDidClose: @escaping () -> Void = {},
        onActionWillDispatch: @escaping (String, SidebarContextMenuActionClassification) -> Void = { _, _ in },
        onActionDidDrain: @escaping (String, SidebarContextMenuActionClassification) -> Void = { _, _ in }
    ) {
        self.entries = entries
        self.onMenuWillOpen = onMenuWillOpen
        self.onMenuDidClose = onMenuDidClose
        self.onActionWillDispatch = onActionWillDispatch
        self.onActionDidDrain = onActionDidDrain
    }

    func buildMenu() -> NSMenu {
        actionTargets.removeAll()
        didOpenMenu = false
        didCloseMenu = false

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        append(entries, to: menu)

        while menu.items.last?.isSeparatorItem == true {
            menu.removeItem(at: menu.items.count - 1)
        }

        return menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard !didOpenMenu else { return }
        didOpenMenu = true
        onMenuWillOpen()
    }

    func menuDidClose(_ menu: NSMenu) {
        forceCloseLifecycleIfNeeded()
    }

    func forceCloseLifecycleIfNeeded() {
        guard didOpenMenu, !didCloseMenu else { return }
        didCloseMenu = true
        onMenuDidClose()
    }

    private func append(_ entries: [SidebarContextMenuEntry], to menu: NSMenu) {
        for entry in entries {
            switch entry {
            case .separator:
                guard !menu.items.isEmpty, menu.items.last?.isSeparatorItem == false else { continue }
                menu.addItem(.separator())

            case .submenu(let title, let systemImage, let children):
                let submenu = NSMenu(title: title)
                submenu.autoenablesItems = false
                append(children, to: submenu)
                while submenu.items.last?.isSeparatorItem == true {
                    submenu.removeItem(at: submenu.items.count - 1)
                }
                guard !submenu.items.isEmpty else { continue }

                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.submenu = submenu
                if let systemImage {
                    item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
                }
                menu.addItem(item)

            case .action(let action):
                let target = SidebarContextMenuActionTarget(
                    title: action.title,
                    classification: action.classification,
                    action: action.action,
                    onActionWillDispatch: onActionWillDispatch,
                    onActionDidDrain: onActionDidDrain
                )
                actionTargets.append(target)

                let item = NSMenuItem(
                    title: action.title,
                    action: #selector(SidebarContextMenuActionTarget.performAction),
                    keyEquivalent: ""
                )
                item.target = target
                item.isEnabled = action.isEnabled
                item.state = action.state
                if let systemImage = action.systemImage {
                    item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: action.title)
                }
                if action.role == .destructive {
                    item.attributedTitle = NSAttributedString(
                        string: action.title,
                        attributes: [.foregroundColor: NSColor.systemRed]
                    )
                }
                menu.addItem(item)
            }
        }
    }
}

private final class SidebarContextMenuActionTarget: NSObject {
    private let title: String
    private let classification: SidebarContextMenuActionClassification
    private let action: () -> Void
    private let onActionWillDispatch: (String, SidebarContextMenuActionClassification) -> Void
    private let onActionDidDrain: (String, SidebarContextMenuActionClassification) -> Void

    init(
        title: String,
        classification: SidebarContextMenuActionClassification,
        action: @escaping () -> Void,
        onActionWillDispatch: @escaping (String, SidebarContextMenuActionClassification) -> Void,
        onActionDidDrain: @escaping (String, SidebarContextMenuActionClassification) -> Void
    ) {
        self.title = title
        self.classification = classification
        self.action = action
        self.onActionWillDispatch = onActionWillDispatch
        self.onActionDidDrain = onActionDidDrain
    }

    @objc func performAction() {
        onActionWillDispatch(title, classification)
        DispatchQueue.main.async { [classification, title, action, onActionDidDrain] in
            action()
            DispatchQueue.main.async {
                onActionDidDrain(title, classification)
            }
        }
    }
}
