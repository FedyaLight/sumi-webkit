import AppKit
import SwiftUI

struct SumiHistoryTabRootView: View {
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @ObservedObject var browserManager: BrowserManager
    @StateObject private var viewModel: HistoryPageViewModel

    private enum Layout {
        static let sidebarWidth: CGFloat = 220
        static let rowCornerRadius: CGFloat = 8
    }

    private var headerControlsAnimation: Animation {
        .easeInOut(duration: 0.18)
    }

    init(browserManager: BrowserManager, windowState: BrowserWindowState?) {
        self.browserManager = browserManager
        _viewModel = StateObject(
            wrappedValue: HistoryPageViewModel(
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
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(themeContext.tokens(settings: sumiSettings).windowBackground)
        .onAppear {
            viewModel.appear()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("History")
                .font(.system(size: 26, weight: .semibold))
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 6) {
                navigationRow(
                    title: "History",
                    iconName: "clock.arrow.circlepath",
                    isSelected: true
                ) {}

                navigationRow(
                    title: "Browsing data",
                    iconName: "trash",
                    isSelected: false
                ) {
                    viewModel.showBrowsingDataDialog()
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .frame(width: Layout.sidebarWidth, alignment: .leading)
    }

    private func navigationRow(
        title: String,
        iconName: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        return Button {
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 20, alignment: .center)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                Spacer()
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: Layout.rowCornerRadius, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            historyList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search History", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
            )

            headerControls
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var headerControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.hasVisibleItems {
                HStack(spacing: 12) {
                    Button("Select All") {
                        withAnimation(headerControlsAnimation) {
                            viewModel.selectAllVisibleItems()
                        }
                    }
                    .disabled(viewModel.allVisibleItemsSelected)

                    if viewModel.hasSelection {
                        Text("\(viewModel.selectionCount) Selected")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .transition(.move(edge: .leading).combined(with: .opacity))

                        Button("Open") {
                            viewModel.openSelectedItems()
                        }
                        .transition(.move(edge: .leading).combined(with: .opacity))

                        Button("Delete") {
                            withAnimation(headerControlsAnimation) {
                                viewModel.deleteSelectedItems()
                            }
                        }
                        .transition(.move(edge: .leading).combined(with: .opacity))

                        Button("Clear Selection") {
                            withAnimation(headerControlsAnimation) {
                                viewModel.clearSelection()
                            }
                        }
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let filter = viewModel.activeFilterDescription {
                HStack(spacing: 8) {
                    Text(filter)
                        .foregroundStyle(.secondary)
                    Button("Clear Filter") {
                        withAnimation(headerControlsAnimation) {
                            viewModel.clearFilters()
                        }
                    }
                    .buttonStyle(.link)
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(headerControlsAnimation, value: viewModel.hasVisibleItems)
        .animation(headerControlsAnimation, value: viewModel.hasSelection)
        .animation(headerControlsAnimation, value: viewModel.selectionCount)
        .animation(headerControlsAnimation, value: viewModel.activeFilterDescription)
    }

    private var historyList: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 0) {
                if viewModel.sections.isEmpty || !viewModel.hasVisibleItems {
                    emptyState
                } else {
                    historyCard
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 26)
        }
    }

    private var historyCard: some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
            ForEach(viewModel.sections) { section in
                VStack(alignment: .leading, spacing: 14) {
                    Text(section.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 22)

                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(section.items) { item in
                            HistoryRow(item: item, viewModel: viewModel)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .leading)

                if section.id != viewModel.sections.last?.id {
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(alignment: .center, spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("No History")
                .font(.title3.weight(.semibold))
            Text("Visited pages will appear here.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }

}

private struct HistoryRow: View {
    let item: HistoryListItem
    @ObservedObject var viewModel: HistoryPageViewModel
    @State private var isHovering = false

    private enum RowLayout {
        static let selectionWidth: CGFloat = 22
        static let timeWidth: CGFloat = 56
        static let faviconSize: CGFloat = 20
        static let menuWidth: CGFloat = 32
    }

    var body: some View {
        HStack(spacing: 12) {
            selectionControl
                .frame(width: RowLayout.selectionWidth, alignment: .center)

            rowOpenButton
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

            Menu {
                rowMenuContent
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .rotationEffect(.degrees(90))
                    .foregroundStyle(.primary)
                    .frame(width: RowLayout.menuWidth, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: RowLayout.menuWidth, alignment: .center)
            .help("More")
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowBackgroundColor)
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            rowMenuContent
        }
    }

    @ViewBuilder
    private var rowMenuContent: some View {
        Button("Open") {
            viewModel.open(item, mode: .currentTab)
        }
        Button("Open in New Tab") {
            viewModel.open(item, mode: .newTab)
        }
        Button("Open in New Window") {
            viewModel.open(item, mode: .newWindow)
        }
        Divider()
        Button("Show All History From This Site") {
            viewModel.showAllHistory(from: item)
        }
        Button("Copy Link") {
            viewModel.copyLink(item)
        }
        Divider()
        Button(item.isSiteAggregate ? "Delete Site History" : "Delete") {
            viewModel.delete(item)
        }
    }

    private var rowOpenButton: some View {
        Button {
            viewModel.openFromRow(item)
        } label: {
            rowContent
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
        .accessibilityLabel(item.displayTitle)
    }

    private var favicon: some View {
        HistoryFaviconView(url: item.url)
            .frame(width: RowLayout.faviconSize, height: RowLayout.faviconSize)
    }

    private var selectionControl: some View {
        Toggle(
            "",
            isOn: Binding(
                get: {
                    viewModel.isSelected(item)
                },
                set: { isSelected in
                    guard isSelected != viewModel.isSelected(item) else { return }
                    viewModel.toggleSelection(item)
                }
            )
        )
        .toggleStyle(.checkbox)
        .labelsHidden()
        .frame(width: 18, height: 18)
        .help("Select")
        .accessibilityLabel("Select")
    }

    private var rowContent: some View {
        HStack(spacing: 14) {
            Text(item.isSiteAggregate ? "" : item.timeText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: RowLayout.timeWidth, alignment: .leading)

            favicon

            HStack(spacing: 8) {
                Text(item.displayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                    .layoutPriority(2)

                Text(item.domain)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .layoutPriority(-1)

                if item.isSiteAggregate, item.visitCount > 0 {
                    Text("\(item.visitCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rowBackgroundColor: Color {
        if viewModel.isSelected(item) {
            return Color.accentColor.opacity(0.14)
        }
        return isHovering ? Color.accentColor.opacity(0.08) : Color.clear
    }

}

private struct HistoryFaviconView: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "globe")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        if let cacheKey = SumiFaviconResolver.cacheKey(for: url),
           let cachedImage = TabFaviconStore.getCachedImage(for: cacheKey) {
            image = cachedImage
            return
        }
        image = nil
    }
}
