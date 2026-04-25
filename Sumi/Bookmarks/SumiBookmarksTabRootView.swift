import SwiftUI
import UniformTypeIdentifiers

struct SumiBookmarksTabRootView: View {
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @ObservedObject var browserManager: BrowserManager
    @StateObject private var viewModel: SumiBookmarksPageViewModel
    @State private var bookmarkDraft: SumiBookmarkFormDraft?
    @State private var folderDraft: SumiFolderFormDraft?
    @FocusState private var searchFocused: Bool

    private enum Layout {
        static let sidebarWidth: CGFloat = 260
        static let contentMaxWidth: CGFloat = 1100
        static let rowCornerRadius: CGFloat = 8
    }

    init(browserManager: BrowserManager, windowState: BrowserWindowState?) {
        self.browserManager = browserManager
        _viewModel = StateObject(
            wrappedValue: SumiBookmarksPageViewModel(
                browserManager: browserManager,
                windowState: windowState
            )
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(tokens.windowBackground)
        .environment(\.resolvedThemeContext, surfaceThemeContext)
        .environment(\.colorScheme, surfaceThemeContext.chromeColorScheme)
        .overlay(alignment: .topLeading) {
            Button {
                searchFocused = true
            } label: {
                EmptyView()
            }
            .keyboardShortcut("f", modifiers: .command)
            .buttonStyle(.plain)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
        .onAppear { viewModel.appear() }
        .onDeleteCommand { viewModel.deleteSelected() }
        .sheet(item: $bookmarkDraft) { draft in
            SumiBookmarkFormView(
                draft: draft,
                folders: viewModel.folderPickerFolders(),
                onCancel: { bookmarkDraft = nil },
                onSave: { saved in
                    if let editingID = saved.editingID {
                        viewModel.updateBookmark(
                            id: editingID,
                            title: saved.title,
                            urlString: saved.urlString,
                            parentID: saved.parentID
                        )
                    } else {
                        viewModel.createBookmark(
                            title: saved.title,
                            urlString: saved.urlString,
                            parentID: saved.parentID
                        )
                    }
                    bookmarkDraft = nil
                }
            )
        }
        .sheet(item: $folderDraft) { draft in
            SumiFolderFormView(
                draft: draft,
                folders: viewModel.folderPickerFolders(excluding: draft.editingID),
                onCancel: { folderDraft = nil },
                onSave: { saved in
                    if let editingID = saved.editingID {
                        viewModel.updateFolder(
                            id: editingID,
                            title: saved.title,
                            parentID: saved.parentID
                        )
                    } else {
                        viewModel.createFolder(title: saved.title, parentID: saved.parentID)
                    }
                    folderDraft = nil
                }
            )
        }
    }

    private var surfaceThemeContext: ResolvedThemeContext {
        themeContext.nativeSurfaceThemeContext
    }

    private var tokens: ChromeThemeTokens {
        surfaceThemeContext.tokens(settings: sumiSettings)
    }

    private var selectionBackground: Color {
        surfaceThemeContext.nativeSurfaceSelectionBackground
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Bookmarks")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(tokens.primaryText)
                .padding(.horizontal, 22)
                .padding(.top, 28)
                .padding(.bottom, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.folders) { folder in
                        sidebarRow(folder)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 16)
            }
        }
        .frame(width: Layout.sidebarWidth, alignment: .leading)
    }

    private func sidebarRow(_ folder: SumiBookmarkFolder) -> some View {
        let selected = viewModel.selectedFolderID == folder.id
        return Button {
            viewModel.selectFolder(folder.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: folder.depth == 0 ? "book.closed.fill" : "folder")
                    .frame(width: 18, alignment: .center)
                Text(folder.title)
                    .lineLimit(1)
                Spacer(minLength: 8)
            }
            .padding(.leading, CGFloat(max(0, folder.depth)) * 14)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: Layout.rowCornerRadius, style: .continuous)
                .fill(selected ? selectionBackground : Color.clear)
        )
        .foregroundStyle(tokens.primaryText)
        .onDrop(of: [.text], isTargeted: nil) { _ in
            viewModel.dropDraggedItems(toParentID: folder.id)
        }
        .contextMenu {
            Button("New Folder") {
                folderDraft = SumiFolderFormDraft(editingID: nil, title: "", parentID: folder.id)
            }
            if folder.id != SumiBookmarkConstants.rootFolderID {
                Button("Edit Folder") {
                    if let entity = browserManager.bookmarkManager.entity(id: folder.id) {
                        folderDraft = viewModel.folderDraft(for: entity)
                    }
                }
                Button("Delete") {
                    if let entity = browserManager.bookmarkManager.entity(id: folder.id) {
                        viewModel.delete(entity)
                    }
                }
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            entityList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button {
                    bookmarkDraft = viewModel.bookmarkDraft()
                } label: {
                    Label("New Bookmark", systemImage: "bookmark.badge.plus")
                }

                Button {
                    folderDraft = viewModel.folderDraft()
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }

                Button {
                    viewModel.deleteSelected()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(!viewModel.canDeleteSelection)

                Menu {
                    ForEach(SumiBookmarkSortMode.allCases) { mode in
                        Button {
                            viewModel.sortMode = mode
                        } label: {
                            if viewModel.sortMode == mode {
                                Label(mode.title, systemImage: "checkmark")
                            } else {
                                Text(mode.title)
                            }
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }

                Button {
                    viewModel.importBookmarksFromMenu()
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }

                Button {
                    viewModel.exportBookmarksFromMenu()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }

                Spacer()

                searchField
                    .frame(width: 320)
            }

            if viewModel.hasSelection {
                HStack(spacing: 10) {
                    Text("\(viewModel.selectionCount) Selected")
                        .foregroundStyle(tokens.secondaryText)
                    Button("Open") {
                        viewModel.openSelected()
                    }
                    Button("Clear Selection") {
                        viewModel.clearSelection()
                    }
                }
                .font(.callout)
            } else if let message = viewModel.statusMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(tokens.secondaryText)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(tokens.secondaryText)
            TextField("Search Bookmarks", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .background(tokens.fieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tokens.separator.opacity(0.65), lineWidth: 1)
        )
    }

    private var entityList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if viewModel.visibleEntities.isEmpty {
                    emptyState
                } else {
                    ForEach(Array(viewModel.visibleEntities.enumerated()), id: \.element.id) { index, entity in
                        SumiBookmarkEntityRow(
                            entity: entity,
                            isSelected: viewModel.selectedEntityIDs.contains(entity.id),
                            canDrag: viewModel.canDragAndDrop,
                            beginDrag: { viewModel.beginDragging(entity) },
                            drop: { viewModel.dropDraggedItems(toParentID: viewModel.selectedFolderID, at: index) },
                            select: { viewModel.handleRowClick(entity) },
                            open: { viewModel.openFromRow(entity) },
                            edit: {
                                if entity.isFolder {
                                    folderDraft = viewModel.folderDraft(for: entity)
                                } else {
                                    bookmarkDraft = viewModel.bookmarkDraft(for: entity)
                                }
                            },
                            delete: { viewModel.delete(entity) },
                            copyLink: { viewModel.copyLink(entity) },
                            showInFolder: { viewModel.showInFolder(entity) },
                            openMode: { mode in viewModel.open(entity, mode: mode) },
                            newFolder: {
                                folderDraft = SumiFolderFormDraft(
                                    editingID: nil,
                                    title: "",
                                    parentID: entity.isFolder ? entity.id : viewModel.selectedFolderID
                                )
                            },
                            searchActive: !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    }
                }
            }
            .frame(maxWidth: Layout.contentMaxWidth, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .center, spacing: 12) {
            Image(systemName: "book.closed")
                .font(.system(size: 42))
                .foregroundStyle(tokens.secondaryText)
            Text("No Bookmarks")
                .font(.title3.weight(.semibold))
                .foregroundStyle(tokens.primaryText)
            Text("Saved pages and folders will appear here.")
                .foregroundStyle(tokens.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }
}

private struct SumiBookmarkEntityRow: View {
    let entity: SumiBookmarkEntity
    let isSelected: Bool
    let canDrag: Bool
    let beginDrag: () -> Void
    let drop: () -> Bool
    let select: () -> Void
    let open: () -> Void
    let edit: () -> Void
    let delete: () -> Void
    let copyLink: () -> Void
    let showInFolder: () -> Void
    let openMode: (BrowserManager.HistoryOpenMode) -> Void
    let newFolder: () -> Void
    let searchActive: Bool
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isHovering = false

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                Text(entity.title)
                    .lineLimit(1)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tokens.primaryText)
                if entity.isBookmark {
                    Text(entity.displayURL)
                        .lineLimit(1)
                        .font(.caption)
                        .foregroundStyle(tokens.secondaryText)
                } else {
                    Text("\(entity.childBookmarkCount) bookmarks")
                        .lineLimit(1)
                        .font(.caption)
                        .foregroundStyle(tokens.secondaryText)
                }
            }
            Spacer(minLength: 12)
            if let parentTitle = entity.parentTitle, searchActive {
                Text(parentTitle)
                    .font(.caption)
                    .foregroundStyle(tokens.secondaryText)
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 11)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowBackgroundColor)
        )
        .contentShape(Rectangle())
        .onTapGesture { select() }
        .onTapGesture(count: 2) { open() }
        .onHover { isHovering = $0 }
        .contextMenu { contextMenu }
        .modifier(SumiBookmarkDragDropModifier(canDrag: canDrag, beginDrag: beginDrag, drop: drop))
    }

    @ViewBuilder
    private var icon: some View {
        if entity.isFolder {
            Image(systemName: "folder")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(tokens.secondaryText)
                .frame(width: 22, height: 22)
        } else if let url = entity.url,
                  let cacheKey = SumiFaviconResolver.cacheKey(for: url),
                  let favicon = Tab.getCachedFavicon(for: cacheKey) {
            favicon
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
        } else {
            Image(systemName: "globe")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(tokens.secondaryText)
                .frame(width: 22, height: 22)
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button(entity.isFolder ? "Open All" : "Open") {
            openMode(.currentTab)
        }
        Button(entity.isFolder ? "Open All in New Tabs" : "Open in New Tab") {
            openMode(.newTab)
        }
        Button(entity.isFolder ? "Open All in New Window" : "Open in New Window") {
            openMode(.newWindow)
        }
        Divider()
        Button("Edit") {
            edit()
        }
        if entity.isBookmark {
            Button("Copy Link") {
                copyLink()
            }
        }
        if searchActive, entity.parentID != nil {
            Button("Show in Folder") {
                showInFolder()
            }
        }
        if entity.isFolder {
            Button("New Folder") {
                newFolder()
            }
        }
        Divider()
        Button("Delete", role: .destructive) {
            delete()
        }
    }

    private var rowBackgroundColor: Color {
        if isSelected {
            return themeContext.nativeSurfaceSelectionBackground
        }
        if isHovering {
            return tokens.fieldBackgroundHover
        }
        return Color.clear
    }
}

private struct SumiBookmarkDragDropModifier: ViewModifier {
    let canDrag: Bool
    let beginDrag: () -> Void
    let drop: () -> Bool

    func body(content: Content) -> some View {
        if canDrag {
            content
                .onDrag {
                    beginDrag()
                    return NSItemProvider(object: "bookmark" as NSString)
                }
                .onDrop(of: [UTType.text], isTargeted: nil) { _ in
                    drop()
                }
        } else {
            content
        }
    }
}

private struct SumiBookmarkFormView: View {
    @State private var draft: SumiBookmarkFormDraft
    let folders: [SumiBookmarkFolder]
    let onCancel: () -> Void
    let onSave: (SumiBookmarkFormDraft) -> Void

    init(
        draft: SumiBookmarkFormDraft,
        folders: [SumiBookmarkFolder],
        onCancel: @escaping () -> Void,
        onSave: @escaping (SumiBookmarkFormDraft) -> Void
    ) {
        _draft = State(initialValue: draft)
        self.folders = folders
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(draft.editingID == nil ? "New Bookmark" : "Edit Bookmark")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                Text("Name")
                TextField("Name", text: $draft.title)
                    .textFieldStyle(.roundedBorder)
                Text("URL")
                TextField("URL", text: $draft.urlString)
                    .textFieldStyle(.roundedBorder)
                Text("Location")
                Picker("Location", selection: $draft.parentID) {
                    ForEach(folders) { folder in
                        Text(String(repeating: "  ", count: folder.depth) + folder.title)
                            .tag(folder.id)
                    }
                }
                .labelsHidden()
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                Button(draft.editingID == nil ? "Add" : "Save") {
                    onSave(draft)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

private struct SumiFolderFormView: View {
    @State private var draft: SumiFolderFormDraft
    let folders: [SumiBookmarkFolder]
    let onCancel: () -> Void
    let onSave: (SumiFolderFormDraft) -> Void

    init(
        draft: SumiFolderFormDraft,
        folders: [SumiBookmarkFolder],
        onCancel: @escaping () -> Void,
        onSave: @escaping (SumiFolderFormDraft) -> Void
    ) {
        _draft = State(initialValue: draft)
        self.folders = folders
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(draft.editingID == nil ? "New Folder" : "Edit Folder")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                Text("Name")
                TextField("Name", text: $draft.title)
                    .textFieldStyle(.roundedBorder)
                Text("Location")
                Picker("Location", selection: $draft.parentID) {
                    ForEach(folders) { folder in
                        Text(String(repeating: "  ", count: folder.depth) + folder.title)
                            .tag(folder.id)
                    }
                }
                .labelsHidden()
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                Button(draft.editingID == nil ? "Add" : "Save") {
                    onSave(draft)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
