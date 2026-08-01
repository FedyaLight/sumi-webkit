import AppKit

extension SumiBookmarksViewController: NSOutlineViewDataSource {
    func outlineView(
        _ outlineView: NSOutlineView,
        numberOfChildrenOfItem item: Any?
    ) -> Int {
        (item as? Node)?.children.count ?? roots.count
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        child index: Int,
        ofItem item: Any?
    ) -> Any {
        (item as? Node)?.children[index] ?? roots[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? Node else { return false }
        return !node.children.isEmpty
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        pasteboardWriterForItem item: Any
    ) -> (any NSPasteboardWriting)? {
        guard viewModel.canDragAndDrop,
              let node = item as? Node,
              !SumiBookmarkConstants.isProtectedFolderID(node.entity.id)
        else { return nil }
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(node.entity.id, forType: .sumiBookmarkIDs)
        return pasteboardItem
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        validateDrop info: any NSDraggingInfo,
        proposedItem item: Any?,
        proposedChildIndex index: Int
    ) -> NSDragOperation {
        guard viewModel.canDragAndDrop,
              droppedBookmarkIDs(from: info.draggingPasteboard).isEmpty == false,
              normalizeDropProposal(item: item, childIndex: index)
        else { return [] }
        return .move
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        acceptDrop info: any NSDraggingInfo,
        item: Any?,
        childIndex index: Int
    ) -> Bool {
        let ids = droppedBookmarkIDs(from: info.draggingPasteboard)
        let destinationIndex = index == NSOutlineViewDropOnItemIndex ? nil : index
        guard let parent = item as? Node else {
            return viewModel.moveEntities(
                ids: ids,
                toParentID: SumiBookmarkConstants.rootFolderID,
                at: destinationIndex.map { max(1, $0) }
            )
        }
        guard parent.entity.isFolder else { return false }
        return viewModel.moveEntities(
            ids: ids,
            toParentID: parent.entity.id,
            at: destinationIndex
        )
    }

    private func normalizeDropProposal(item: Any?, childIndex index: Int) -> Bool {
        guard let node = item as? Node else {
            outlineView.setDropItem(nil, dropChildIndex: max(1, index))
            return true
        }

        if node.entity.isFolder { return true }
        guard let parent = outlineView.parent(forItem: node) as? Node,
              let siblingIndex = parent.children.firstIndex(where: { $0 === node })
        else { return false }
        let insertionIndex = index == NSOutlineViewDropOnItemIndex
            ? siblingIndex
            : max(0, index)
        outlineView.setDropItem(parent, dropChildIndex: insertionIndex)
        return true
    }

    private func droppedBookmarkIDs(from pasteboard: NSPasteboard) -> [String] {
        pasteboard.pasteboardItems?
            .compactMap { $0.string(forType: .sumiBookmarkIDs) }
            .uniquedPreservingOrder()
            ?? []
    }
}

extension SumiBookmarksViewController: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        let row = SumiOutlineRowView()
        let level = outlineView.level(forItem: item)
        row.separatorLeadingInset = level > 0
            ? CGFloat(level) * outlineView.indentationPerLevel + 20
            : 0
        return row
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]
    ) {
        applySortDescriptorsFromOutlineView()
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        viewFor tableColumn: NSTableColumn?,
        item: Any
    ) -> NSView? {
        guard let node = item as? Node else { return nil }
        if tableColumn?.identifier == .bookmarkAddress {
            let cell = reusableAddressCell(in: outlineView)
            let entity = node.entity
            let displayText: String
            if entity.isFolder, viewModel.searchText.isEmpty {
                displayText = String(localized: "\(entity.childBookmarkCount) bookmarks")
            } else if entity.isFolder {
                displayText = entity.parentTitle ?? String(localized: "Folder")
            } else {
                displayText = entity.displayURL
            }
            cell.configure(entity: entity, displayText: displayText) { [weak self] value in
                guard let self else { return }
                if !viewModel.updateAddress(entity, urlString: value) {
                    showMutationError()
                    viewModel.appear()
                }
            }
            return cell
        }

        let cell = reusableNameCell(in: outlineView)
        cell.configure(
            entity: node.entity,
            partition: viewModel.faviconPartition,
            imageReader: viewModel.faviconImageReader
        ) { [weak self] value in
            guard let self else { return }
            if !viewModel.rename(node.entity, title: value) {
                showMutationError()
                viewModel.appear()
            }
        }
        return cell
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        typeSelectStringFor tableColumn: NSTableColumn?,
        item: Any
    ) -> String? {
        (item as? Node)?.entity.title
    }

    private func reusableAddressCell(in outlineView: NSOutlineView) -> SumiBookmarkAddressCellView {
        if let cell = outlineView.makeView(
            withIdentifier: .bookmarkAddressCell,
            owner: self
        ) as? SumiBookmarkAddressCellView {
            return cell
        }
        let cell = SumiBookmarkAddressCellView()
        cell.identifier = .bookmarkAddressCell
        return cell
    }

    private func reusableNameCell(in outlineView: NSOutlineView) -> SumiBookmarkNameCellView {
        if let cell = outlineView.makeView(
            withIdentifier: .bookmarkNameCell,
            owner: self
        ) as? SumiBookmarkNameCellView {
            return cell
        }
        let cell = SumiBookmarkNameCellView()
        cell.identifier = .bookmarkNameCell
        return cell
    }
}

extension SumiBookmarksViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let entity = contextEntity() else { return }

        menu.addItem(
            withTitle: entity.isFolder
                ? String(localized: "Open in New Tabs")
                : String(localized: "Open in New Tab"),
            action: #selector(openContextItemInNewTab),
            keyEquivalent: ""
        )
        if entity.isBookmark {
            menu.addItem(
                withTitle: String(localized: "Open in New Window"),
                action: #selector(openContextItemInNewWindow),
                keyEquivalent: ""
            )
        }

        if !SumiBookmarkConstants.isProtectedFolderID(entity.id) {
            menu.addItem(
                withTitle: String(localized: "Rename"),
                action: #selector(renameContextItem),
                keyEquivalent: ""
            )
        }
        if entity.isBookmark {
            menu.addItem(
                withTitle: String(localized: "Edit Address…"),
                action: #selector(editContextItemAddress),
                keyEquivalent: ""
            )
            menu.addItem(
                withTitle: String(localized: "Copy"),
                action: #selector(copyContextItemLink),
                keyEquivalent: ""
            )
        }
        if entity.isFolder {
            menu.addItem(
                withTitle: String(localized: "New Folder"),
                action: #selector(createContextFolder),
                keyEquivalent: ""
            )
            let sortItem = NSMenuItem(
                title: String(localized: "Sort By"),
                action: nil,
                keyEquivalent: ""
            )
            let sortMenu = NSMenu()
            sortMenu.addItem(
                withTitle: String(localized: "Name"),
                action: #selector(sortByName),
                keyEquivalent: ""
            )
            sortMenu.addItem(
                withTitle: String(localized: "Address"),
                action: #selector(sortByAddress),
                keyEquivalent: ""
            )
            sortItem.submenu = sortMenu
            menu.addItem(sortItem)
        }
        if !SumiBookmarkConstants.isProtectedFolderID(entity.id) {
            menu.addItem(
                withTitle: String(localized: "Delete"),
                action: #selector(deleteContextItem),
                keyEquivalent: ""
            )
        }
        if entity.isBookmark {
            menu.addItem(
                withTitle: String(localized: "New Folder"),
                action: #selector(createContextFolder),
                keyEquivalent: ""
            )
        }
        menu.items.forEach { $0.target = self }
        menu.items.compactMap(\.submenu).flatMap(\.items).forEach { $0.target = self }
    }
}

@MainActor
final class SumiBookmarkNameCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private var loadTask: Task<Void, Never>?
    private var representedEntityID: String?
    private var onCommit: ((String) -> Void)?
    private var originalTitle = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.symbolConfiguration = .init(pointSize: 11, weight: .regular)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.delegate = self

        let row = NSStackView(views: [iconView, titleField])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        loadTask?.cancel()
    }

    func configure(
        entity: SumiBookmarkEntity,
        partition: SumiFaviconPartition,
        imageReader: any BrowserFaviconImageReading,
        onCommit: @escaping (String) -> Void
    ) {
        representedEntityID = entity.id
        let displayTitle = entity.id == SumiBookmarkConstants.favoritesFolderID
            ? String(localized: "Favorites")
            : entity.title
        originalTitle = displayTitle
        titleField.stringValue = displayTitle
        titleField.isEditable = false
        titleField.isSelectable = false
        self.onCommit = onCommit
        toolTip = displayTitle
        loadTask?.cancel()

        if entity.isFolder {
            iconView.image = NSImage(
                systemSymbolName: entity.id == SumiBookmarkConstants.favoritesFolderID
                    ? "star"
                    : "folder",
                accessibilityDescription: nil
            )
            iconView.contentTintColor = .secondaryLabelColor
            return
        }

        iconView.contentTintColor = nil
        guard let url = entity.url else {
            iconView.image = nil
            return
        }
        let fallback = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        let cached = TabFaviconStore.getCachedImage(
            forDocumentURL: url,
            partition: partition,
            context: .historyBookmarkRow,
            imageReader: imageReader
        )
        iconView.image = cached ?? fallback
        loadTask = Task { @MainActor [weak self] in
            let image = await TabFaviconStore.loadCachedDisplayImage(
                forDocumentURL: url,
                partition: partition,
                context: .historyBookmarkRow,
                priority: .historyBookmarkVisibleRow,
                imageReader: imageReader
            )
            guard !Task.isCancelled, self?.representedEntityID == entity.id else { return }
            self?.iconView.image = image ?? cached ?? fallback
        }
    }

    func beginEditing() {
        titleField.isEditable = true
        titleField.isSelectable = true
        window?.makeFirstResponder(titleField)
        titleField.selectText(nil)
    }
}

extension SumiBookmarkNameCellView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ notification: Notification) {
        titleField.isEditable = false
        titleField.isSelectable = false
        let value = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != originalTitle else {
            titleField.stringValue = originalTitle
            return
        }
        onCommit?(value)
    }
}

@MainActor
final class SumiBookmarkAddressCellView: NSTableCellView, NSTextFieldDelegate {
    private let addressField = NSTextField(labelWithString: "")
    private var representedEntityID: String?
    private var isBookmark = false
    private var originalAddress = ""
    private var onCommit: ((String) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addressField.lineBreakMode = .byTruncatingMiddle
        addressField.delegate = self
        addressField.translatesAutoresizingMaskIntoConstraints = false
        textField = addressField
        addSubview(addressField)
        NSLayoutConstraint.activate([
            addressField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            addressField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            addressField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        entity: SumiBookmarkEntity,
        displayText: String,
        onCommit: @escaping (String) -> Void
    ) {
        representedEntityID = entity.id
        isBookmark = entity.isBookmark
        originalAddress = displayText
        addressField.stringValue = displayText
        addressField.isEditable = false
        addressField.isSelectable = false
        self.onCommit = onCommit
        toolTip = displayText
    }

    func beginEditing() {
        guard isBookmark else { return }
        addressField.isEditable = true
        addressField.isSelectable = true
        window?.makeFirstResponder(addressField)
        addressField.selectText(nil)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        addressField.isEditable = false
        addressField.isSelectable = false
        let value = addressField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != originalAddress else {
            addressField.stringValue = originalAddress
            return
        }
        onCommit?(value)
    }
}

private extension Array where Element: Hashable {
    func uniquedPreservingOrder() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
