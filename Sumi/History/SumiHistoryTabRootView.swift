import AppKit
import SwiftUI

struct SumiHistoryTabRootView: View {
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @ObservedObject var browserManager: BrowserManager
    @StateObject private var viewModel: HistoryPageViewModel

    private enum Layout {
        static let sidebarWidth: CGFloat = 240
        static let contentMaxWidth: CGFloat = 920
        static let rowCornerRadius: CGFloat = 8
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(themeContext.tokens(settings: sumiSettings).windowBackground)
        .onAppear {
            viewModel.appear()
        }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(viewModel.ranges) { range in
                    sidebarRow(range)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
        }
        .frame(width: Layout.sidebarWidth, alignment: .leading)
    }

    private func sidebarRow(_ range: HistoryRangeCount) -> some View {
        let selected = viewModel.selectedRange == range.id && viewModel.activeFilterDescription == nil
        return Button {
            viewModel.selectRange(range.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: iconName(for: range.id))
                    .frame(width: 18, alignment: .center)
                Text(range.id.title)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(range.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: Layout.rowCornerRadius, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.14) : Color.clear)
        )
        .foregroundStyle(selected ? Color.accentColor : Color.primary)
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                Text("History")
                    .font(.system(size: 28, weight: .semibold))
                Spacer()
                if viewModel.hasSelection {
                    Text("\(viewModel.selectionCount) Selected")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Open") {
                        viewModel.openSelectedItems()
                    }
                    Button("Delete") {
                        viewModel.deleteSelectedItems()
                    }
                    Button("Clear Selection") {
                        viewModel.clearSelection()
                    }
                } else if viewModel.canDeleteVisibleResults {
                    Button("Delete Results") {
                        viewModel.deleteVisibleResults()
                    }
                }
                Button("Clear All") {
                    viewModel.clearAllHistory()
                }
                .disabled(!viewModel.canClearHistory)
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search History", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 1)
            )

            if let filter = viewModel.activeFilterDescription {
                HStack(spacing: 8) {
                    Text(filter)
                        .foregroundStyle(.secondary)
                    Button("Clear Filter") {
                        viewModel.clearFilters()
                    }
                    .buttonStyle(.link)
                }
                .font(.callout)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
    }

    private var historyList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18, pinnedViews: []) {
                if viewModel.sections.isEmpty || !viewModel.hasVisibleItems {
                    emptyState
                } else {
                    ForEach(viewModel.sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.title)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(section.items) { item in
                                    HistoryRow(item: item, viewModel: viewModel)
                                }
                            }
                        }
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

    private func iconName(for range: HistoryRange) -> String {
        switch range {
        case .all:
            return "clock.arrow.circlepath"
        case .allSites:
            return "globe"
        case .older:
            return "archivebox"
        default:
            return "calendar"
        }
    }
}

private struct HistoryRow: View {
    let item: HistoryListItem
    @ObservedObject var viewModel: HistoryPageViewModel
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            selectionControl

            rowOpenButton
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowBackgroundColor)
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
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
    }

    private var rowOpenButton: some View {
        Button {
            viewModel.openFromRow(item)
        } label: {
            HStack(spacing: 12) {
                favicon

                rowContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.displayTitle)
    }

    private var favicon: some View {
        HistoryFaviconView(url: item.url)
            .frame(width: 20, height: 20)
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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(item.displayTitle)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
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
                Text(subtitle)
                    .font(.callout)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            if item.isSiteAggregate == false {
                Text(item.timeText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rowBackgroundColor: Color {
        if viewModel.isSelected(item) {
            return Color.accentColor.opacity(0.14)
        }
        return isHovering ? Color.accentColor.opacity(0.08) : Color.clear
    }

    private var subtitle: String {
        if item.isSiteAggregate {
            return item.domain
        }
        return item.displayURL
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
