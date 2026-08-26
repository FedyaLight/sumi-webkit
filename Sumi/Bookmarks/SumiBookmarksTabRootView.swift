import AppKit
import Combine
import SwiftUI

/// SwiftUI reserves the browser-surface slot; AppKit owns every visible
/// bookmark control and interaction inside it.
struct SumiBookmarksTabRootView: NSViewControllerRepresentable {
    @Environment(\.resolvedThemeContext) private var themeContext

    let browserContext: BookmarksPageBrowserContext
    let windowState: BrowserWindowState?

    func makeNSViewController(context _: Context) -> SumiBookmarksViewController {
        let controller = SumiBookmarksViewController(
            viewModel: SumiBookmarksPageViewModel(
                browserContext: browserContext,
                windowState: windowState
            )
        )
        controller.applyAppearance(themeContext.nativeSurfaceThemeContext)
        return controller
    }

    func updateNSViewController(
        _ controller: SumiBookmarksViewController,
        context _: Context
    ) {
        controller.applyAppearance(themeContext.nativeSurfaceThemeContext)
    }
}

@MainActor
final class SumiBookmarksViewController: NSViewController {
    final class Node: NSObject {
        let entity: SumiBookmarkEntity
        let children: [Node]

        init(entity: SumiBookmarkEntity) {
            self.entity = entity
            children = entity.children.map(Node.init(entity:))
        }
    }

    private enum Layout {
        static let headerHeight: CGFloat = 45
        static let horizontalInset: CGFloat = 8
        static let tableHorizontalInset: CGFloat = 12
        static let searchWidth: CGFloat = 110
        static let firstColumnFraction: CGFloat = 0.31
        static let rowHeight: CGFloat = 20
    }

    let viewModel: SumiBookmarksPageViewModel
    let outlineView = SumiBookmarksOutlineView()
    var roots: [Node] = []

    private let scrollView = NSScrollView()
    private let searchField = NSSearchField()
    private let emptyLabel = NSTextField(labelWithString: String(localized: "No Bookmarks"))
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?
    private var pendingSelectionID: String?
    private var pendingRenameID: String?
    private var didApplyInitialSelection = false
    private var didApplyInitialExpansion = false
    var isApplyingSortDescriptors = false

    init(viewModel: SumiBookmarksPageViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        searchTask?.cancel()
    }

    override func loadView() {
        view = NSView()
        configureHeader()
        configureOutlineView()
        configureEmptyState()
        installLayout()
        bindViewModel()
        viewModel.appear()
    }

    func applyAppearance(_ themeContext: ResolvedThemeContext) {
        view.sumiApplyNativeSurfaceAppearance(themeContext: themeContext)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let availableWidth = outlineView.bounds.width
        guard availableWidth > 0,
              let firstColumn = outlineView.tableColumns.first,
              let addressColumn = outlineView.tableColumns.last,
              firstColumn !== addressColumn
        else { return }
        let firstWidth = max(
            firstColumn.minWidth,
            floor(availableWidth * Layout.firstColumnFraction)
        )
        let addressWidth = max(addressColumn.minWidth, availableWidth - firstWidth)
        if abs(firstColumn.width - firstWidth) > 0.5 {
            firstColumn.width = firstWidth
        }
        if abs(addressColumn.width - addressWidth) > 0.5 {
            addressColumn.width = addressWidth
        }
    }

    private func configureHeader() {
        let title = NSTextField(labelWithString: String(localized: "Bookmarks"))
        title.font = .systemFont(ofSize: 22, weight: .bold)
        title.setContentHuggingPriority(.required, for: .horizontal)

        let newFolderButton = NSButton(
            title: String(localized: "New Folder"),
            target: self,
            action: #selector(createFolder)
        )
        newFolderButton.bezelStyle = .rounded
        newFolderButton.controlSize = .small

        searchField.placeholderString = String(localized: "Search")
        searchField.controlSize = .small
        searchField.sendsSearchStringImmediately = true
        searchField.delegate = self
        searchField.widthAnchor.constraint(equalToConstant: Layout.searchWidth).isActive = true

        let spacer = NSView()
        let header = NSStackView(views: [title, spacer, newFolderButton, searchField])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        header.edgeInsets = NSEdgeInsets(
            top: 0,
            left: Layout.horizontalInset,
            bottom: 0,
            right: Layout.horizontalInset
        )
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: Layout.headerHeight),
        ])
    }

    private func configureOutlineView() {
        let nameColumn = NSTableColumn(identifier: .bookmarkName)
        nameColumn.title = String(localized: "Site")
        nameColumn.minWidth = 240
        nameColumn.width = 390
        nameColumn.sortDescriptorPrototype = NSSortDescriptor(
            key: "name",
            ascending: true,
            selector: #selector(NSString.localizedCaseInsensitiveCompare(_:))
        )

        let addressColumn = NSTableColumn(identifier: .bookmarkAddress)
        addressColumn.title = String(localized: "Address")
        addressColumn.minWidth = 240
        addressColumn.resizingMask = .autoresizingMask
        addressColumn.sortDescriptorPrototype = NSSortDescriptor(
            key: "address",
            ascending: true,
            selector: #selector(NSString.localizedCaseInsensitiveCompare(_:))
        )

        outlineView.addTableColumn(nameColumn)
        outlineView.addTableColumn(addressColumn)
        outlineView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outlineView.outlineTableColumn = nameColumn
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.headerView = NSTableHeaderView()
        outlineView.rowHeight = Layout.rowHeight
        outlineView.rowSizeStyle = .small
        outlineView.intercellSpacing = .zero
        outlineView.indentationPerLevel = 14
        outlineView.gridStyleMask = .solidVerticalGridLineMask
        outlineView.gridColor = .separatorColor
        outlineView.allowsMultipleSelection = true
        outlineView.allowsEmptySelection = true
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.backgroundColor = .clear
        outlineView.style = .plain
        outlineView.target = self
        outlineView.doubleAction = #selector(openDoubleClickedItem)
        outlineView.onDelete = { [weak self] in self?.deleteSelectedItems() }
        outlineView.onReturn = { [weak self] in self?.openSelectedItems() }
        outlineView.registerForDraggedTypes([.sumiBookmarkIDs])
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)

        let menu = NSMenu()
        menu.delegate = self
        outlineView.menu = menu

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
    }

    private func configureEmptyState() {
        emptyLabel.font = .systemFont(ofSize: 15, weight: .medium)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true
        view.addSubview(emptyLabel)
    }

    private func installLayout() {
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: Layout.headerHeight),
            scrollView.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: Layout.tableHorizontalInset
            ),
            scrollView.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -Layout.tableHorizontalInset
            ),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
        ])
    }

    private func bindViewModel() {
        viewModel.$outlineRoots
            .sink { [weak self] entities in
                self?.apply(entities)
            }
            .store(in: &cancellables)

        viewModel.$sortMode
            .removeDuplicates()
            .sink { [weak self] mode in
                self?.applySortDescriptor(for: mode)
            }
            .store(in: &cancellables)
    }

    private func apply(_ entities: [SumiBookmarkEntity]) {
        let selectedIDs = pendingSelectionID.map { [$0] } ?? selectedEntities.map(\.id)
        let expandedIDs = expandedEntityIDs()
        roots = entities.map(Node.init(entity:))
        outlineView.reloadData()

        if viewModel.searchText.isEmpty {
            if didApplyInitialExpansion {
                restoreExpansion(ids: expandedIDs)
            } else if let firstRoot = roots.first {
                outlineView.expandItem(firstRoot)
                didApplyInitialExpansion = true
            }
        }

        if !didApplyInitialSelection, let initial = viewModel.initiallySelectedFolderID {
            didApplyInitialSelection = true
            expandAncestorsAndSelect(id: initial)
        } else {
            restoreSelection(ids: selectedIDs)
        }
        let renameID = pendingRenameID
        pendingSelectionID = nil
        pendingRenameID = nil
        emptyLabel.stringValue = viewModel.searchText.isEmpty
            ? String(localized: "No Bookmarks")
            : String(localized: "No Matching Bookmarks")
        emptyLabel.isHidden = !entities.isEmpty
        if let renameID {
            DispatchQueue.main.async { [weak self] in
                self?.beginRenaming(entityID: renameID)
            }
        }
    }

    private func applySortDescriptor(for mode: SumiBookmarkSortMode) {
        let descriptor: NSSortDescriptor?
        switch mode {
        case .manual:
            descriptor = nil
        case .nameAscending:
            descriptor = NSSortDescriptor(key: "name", ascending: true)
        case .nameDescending:
            descriptor = NSSortDescriptor(key: "name", ascending: false)
        case .addressAscending:
            descriptor = NSSortDescriptor(key: "address", ascending: true)
        case .addressDescending:
            descriptor = NSSortDescriptor(key: "address", ascending: false)
        }
        isApplyingSortDescriptors = true
        outlineView.sortDescriptors = descriptor.map { [$0] } ?? []
        isApplyingSortDescriptors = false
    }

    func applySortDescriptorsFromOutlineView() {
        guard !isApplyingSortDescriptors,
              let descriptor = outlineView.sortDescriptors.first,
              let key = descriptor.key
        else { return }
        switch (key, descriptor.ascending) {
        case ("name", true):
            viewModel.sortMode = .nameAscending
        case ("name", false):
            viewModel.sortMode = .nameDescending
        case ("address", true):
            viewModel.sortMode = .addressAscending
        case ("address", false):
            viewModel.sortMode = .addressDescending
        default:
            break
        }
    }

    private func expandedEntityIDs() -> Set<String> {
        Set((0..<outlineView.numberOfRows).compactMap { row in
            guard let node = outlineView.item(atRow: row) as? Node,
                  outlineView.isItemExpanded(node)
            else { return nil }
            return node.entity.id
        })
    }

    private func restoreExpansion(ids: Set<String>) {
        func visit(_ node: Node) {
            if ids.contains(node.entity.id) { outlineView.expandItem(node) }
            node.children.forEach(visit)
        }
        roots.forEach(visit)
    }

    private func restoreSelection(ids: [String]) {
        let idSet = Set(ids)
        guard !idSet.isEmpty else { return }
        let rows = IndexSet((0..<outlineView.numberOfRows).filter { row in
            guard let node = outlineView.item(atRow: row) as? Node else { return false }
            return idSet.contains(node.entity.id)
        })
        outlineView.selectRowIndexes(rows, byExtendingSelection: false)
        if let row = rows.first { outlineView.scrollRowToVisible(row) }
    }

    private func expandAncestorsAndSelect(id: String) {
        guard let path = nodePath(to: id, in: roots) else { return }
        path.dropLast().forEach { outlineView.expandItem($0) }
        restoreSelection(ids: [id])
    }

    private func nodePath(to id: String, in nodes: [Node]) -> [Node]? {
        for node in nodes {
            if node.entity.id == id { return [node] }
            if let path = nodePath(to: id, in: node.children) { return [node] + path }
        }
        return nil
    }

    var selectedEntities: [SumiBookmarkEntity] {
        outlineView.selectedRowIndexes.compactMap { row in
            (outlineView.item(atRow: row) as? Node)?.entity
        }
    }

    func contextEntity() -> SumiBookmarkEntity? {
        let row = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
        return row >= 0 ? (outlineView.item(atRow: row) as? Node)?.entity : nil
    }

    @objc func createFolder() {
        createFolderAndBeginRenaming(parentID: SumiBookmarkConstants.rootFolderID)
    }

    @objc func createContextFolder() {
        guard let entity = contextEntity() else { return }
        createFolderAndBeginRenaming(
            parentID: entity.isFolder
                ? entity.id
                : entity.parentID ?? SumiBookmarkConstants.rootFolderID
        )
    }

    private func createFolderAndBeginRenaming(parentID: String) {
        guard let folder = viewModel.createFolder(
            title: String(localized: "Untitled Folder"),
            parentID: parentID
        ) else {
            showMutationError()
            return
        }
        pendingSelectionID = folder.id
        pendingRenameID = folder.id
        viewModel.appear()
    }

    @objc func renameContextItem() {
        guard let entity = contextEntity() else { return }
        beginRenaming(entityID: entity.id)
    }

    @objc func editContextItemAddress() {
        guard let entity = contextEntity(), entity.isBookmark else { return }
        beginEditingAddress(entityID: entity.id)
    }

    @objc func openContextItemInNewTab() {
        contextEntity().map { viewModel.open($0, mode: .newTab) }
    }

    @objc func openContextItemInNewWindow() {
        contextEntity().map { viewModel.open($0, mode: .newWindow) }
    }

    @objc func copyContextItemLink() {
        contextEntity().map(viewModel.copyLink)
    }

    @objc func deleteContextItem() {
        guard let entity = contextEntity() else { return }
        let selection = selectedEntities
        viewModel.delete(selection.contains(where: { $0.id == entity.id }) ? selection : [entity])
    }

    @objc func sortByName() {
        viewModel.sortMode = .nameAscending
    }

    @objc func sortByAddress() {
        viewModel.sortMode = .addressAscending
    }

    private func beginRenaming(entityID: String) {
        guard let row = row(for: entityID),
              let cell = outlineView.view(
                  atColumn: outlineView.column(withIdentifier: .bookmarkName),
                  row: row,
                  makeIfNecessary: true
              ) as? SumiBookmarkNameCellView
        else { return }
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        cell.beginEditing()
    }

    private func beginEditingAddress(entityID: String) {
        guard let row = row(for: entityID),
              let cell = outlineView.view(
                  atColumn: outlineView.column(withIdentifier: .bookmarkAddress),
                  row: row,
                  makeIfNecessary: true
              ) as? SumiBookmarkAddressCellView
        else { return }
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        cell.beginEditing()
    }

    private func row(for entityID: String) -> Int? {
        (0..<outlineView.numberOfRows).first { row in
            (outlineView.item(atRow: row) as? Node)?.entity.id == entityID
        }
    }

    @objc private func openDoubleClickedItem() {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? Node else { return }
        if node.entity.isFolder {
            outlineView.isItemExpanded(node)
                ? outlineView.collapseItem(node)
                : outlineView.expandItem(node)
        } else {
            viewModel.openFromRow(
                node.entity,
                modifiers: NSApp.currentEvent?.modifierFlags ?? []
            )
        }
    }

    private func openSelectedItems() {
        let entities = selectedEntities
        guard !entities.isEmpty else { return }
        if entities.count == 1, let entity = entities.first {
            viewModel.openFromRow(entity)
        } else {
            viewModel.open(entities)
        }
    }

    private func deleteSelectedItems() {
        viewModel.delete(selectedEntities)
    }

    func showMutationError() {
        guard let message = viewModel.statusMessage else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Bookmarks Could Not Be Updated")
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.window.appearance = view.effectiveAppearance
        alert.runModal()
    }
}

extension SumiBookmarksViewController: NSSearchFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSSearchField === searchField else { return }
        let query = searchField.stringValue
        searchTask?.cancel()
        searchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.viewModel.searchText = query
        }
    }
}

@MainActor
final class SumiBookmarksOutlineView: NSOutlineView {
    var onDelete: (() -> Void)?
    var onReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            onReturn?()
        case 51, 117:
            onDelete?()
        default:
            super.keyDown(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        if row >= 0, !selectedRowIndexes.contains(row) {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        return super.menu(for: event)
    }
}

extension NSPasteboard.PasteboardType {
    static let sumiBookmarkIDs = Self("com.sumi.browser.bookmark-identifiers")
}

extension NSUserInterfaceItemIdentifier {
    static let bookmarkName = Self("BookmarkName")
    static let bookmarkAddress = Self("BookmarkAddress")
    static let bookmarkNameCell = Self("BookmarkNameCell")
    static let bookmarkAddressCell = Self("BookmarkAddressCell")
}
