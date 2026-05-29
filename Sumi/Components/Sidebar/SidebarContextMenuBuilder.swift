//
//  SidebarContextMenuBuilder.swift
//  Sumi
//

import AppKit

@MainActor
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
                    item.image = SidebarContextMenuImageStore.image(for: .systemImage(systemImage))
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
                if let icon = action.icon {
                    item.image = SidebarContextMenuImageStore.image(for: icon)
                } else if let systemImage = action.systemImage {
                    item.image = SidebarContextMenuImageStore.image(for: .systemImage(systemImage))
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

@MainActor
enum SidebarContextMenuImageStore {
    private static let imageSize = NSSize(width: 16, height: 16)
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 160
        return cache
    }()

    static func image(for icon: SidebarContextMenuIcon) -> NSImage? {
        let key = cacheKey(for: icon) as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let image = makeImage(for: icon) else {
            return nil
        }
        cache.setObject(image, forKey: key)
        return image
    }

    private static func makeImage(for icon: SidebarContextMenuIcon) -> NSImage? {
        switch icon {
        case .systemImage(let name):
            return sizedCopy(NSImage(systemSymbolName: name, accessibilityDescription: nil))
        case .emoji(let glyph):
            return emojiImage(glyph)
        case .folderIcon(let value):
            return folderImage(value)
        }
    }

    private static func emojiImage(_ glyph: String) -> NSImage {
        let image = NSImage(size: imageSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
        ]
        let textSize = glyph.size(withAttributes: attributes)
        let rect = NSRect(
            x: (imageSize.width - textSize.width) / 2,
            y: (imageSize.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        glyph.draw(in: rect, withAttributes: attributes)
        return image
    }

    private static func folderImage(_ value: String) -> NSImage? {
        switch SumiZenFolderIconCatalog.resolveFolderIcon(value) {
        case .bundled(let name):
            guard let source = SumiZenFolderIconCatalog.bundledFolderImage(named: name) else {
                return nil
            }
            return rasterizedCopy(source, isTemplate: true)
        case .none:
            return sizedCopy(NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil))
        }
    }

    private static func sizedCopy(_ source: NSImage?) -> NSImage? {
        guard let prepared = source?.copy() as? NSImage else {
            return source
        }
        prepared.size = imageSize
        return prepared
    }

    private static func rasterizedCopy(_ source: NSImage, isTemplate: Bool) -> NSImage {
        let image = NSImage(size: imageSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        source.draw(
            in: NSRect(origin: .zero, size: imageSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        image.isTemplate = isTemplate
        return image
    }

    private static func cacheKey(for icon: SidebarContextMenuIcon) -> String {
        switch icon {
        case .systemImage(let name):
            return "system:\(name)"
        case .emoji(let glyph):
            return "emoji:\(glyph)"
        case .folderIcon(let value):
            return "folder:\(value)"
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
        scheduleOnMainRunLoop { [self] in
            performDeferredAction()
        }
    }

    private func performDeferredAction() {
        action()
        scheduleOnMainRunLoop { [self] in
            finishDeferredAction()
        }
    }

    private func finishDeferredAction() {
        onActionDidDrain(title, classification)
    }

    private func scheduleOnMainRunLoop(_ work: @escaping () -> Void) {
        let runLoop = CFRunLoopGetMain()
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, work)
        CFRunLoopWakeUp(runLoop)
    }
}
