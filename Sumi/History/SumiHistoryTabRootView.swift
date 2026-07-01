import AppKit
import SwiftUI

struct SumiHistoryTabRootView: View {
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @StateObject private var viewModel: HistoryPageViewModel
    @StateObject private var scrollHoverCoordinator = NativeSurfaceScrollHoverCoordinator()
    @State private var nativeModalInvalidationGeneration: UInt = 0
    private let browserContext: HistoryPageBrowserContext
    private let windowState: BrowserWindowState?

    private enum Layout {
        static let sidebarWidth: CGFloat = 220
        static let rowCornerRadius: CGFloat = 8
    }

    private var headerControlsAnimation: Animation {
        .easeInOut(duration: 0.18)
    }

    init(browserContext: HistoryPageBrowserContext, windowState: BrowserWindowState?) {
        self.browserContext = browserContext
        self.windowState = windowState
        _viewModel = StateObject(
            wrappedValue: HistoryPageViewModel(
                browserContext: browserContext,
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
        .background(tokens.windowBackground)
        .environment(\.resolvedThemeContext, surfaceThemeContext)
        .environment(\.colorScheme, surfaceThemeContext.chromeColorScheme)
        .environment(\.nativeSurfaceHoverUpdatesEnabled, nativeSurfaceHoverUpdatesEnabled)
        .onAppear {
            viewModel.appear()
        }
        .onReceive(browserContext.nativeModalPresentationUpdates) { _ in
            nativeModalInvalidationGeneration &+= 1
        }
        .onDisappear {
            scrollHoverCoordinator.reset()
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

    private var nativeSurfaceHoverUpdatesEnabled: Bool {
        let _ = nativeModalInvalidationGeneration
        return scrollHoverCoordinator.hoverUpdatesEnabled
            && !browserContext.isNativeModalPresented(windowState?.id)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("History")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(tokens.primaryText)
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
        Button {
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
                .fill(isSelected ? selectionBackground : Color.clear)
        )
        .foregroundStyle(tokens.primaryText)
        .chromeCursor(.pointingHand)
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
                    .foregroundStyle(tokens.secondaryText)
                TextField("Search History", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tokens.fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(tokens.separator.opacity(0.55), lineWidth: 1)
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
                    .chromeCursor(.pointingHand)

                    if viewModel.hasSelection {
                        Text("\(viewModel.selectionCount) Selected")
                            .font(.callout)
                            .foregroundStyle(tokens.secondaryText)
                            .transition(.move(edge: .leading).combined(with: .opacity))

                        Button("Open") {
                            viewModel.openSelectedItems()
                        }
                        .transition(.move(edge: .leading).combined(with: .opacity))
                        .chromeCursor(.pointingHand)

                        Button("Delete") {
                            withAnimation(headerControlsAnimation) {
                                viewModel.deleteSelectedItems()
                            }
                        }
                        .transition(.move(edge: .leading).combined(with: .opacity))
                        .chromeCursor(.pointingHand)

                        Button("Clear Selection") {
                            withAnimation(headerControlsAnimation) {
                                viewModel.clearSelection()
                            }
                        }
                        .transition(.move(edge: .leading).combined(with: .opacity))
                        .chromeCursor(.pointingHand)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let filter = viewModel.activeFilterDescription {
                HStack(spacing: 8) {
                    Text(filter)
                        .foregroundStyle(tokens.secondaryText)
                    Button("Clear Filter") {
                        withAnimation(headerControlsAnimation) {
                            viewModel.clearFilters()
                        }
                    }
                    .buttonStyle(.link)
                    .chromeCursor(.pointingHand)
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
        .suppressesNativeSurfaceHoverWhileScrolling(scrollHoverCoordinator, region: "history-list")
    }

    private var historyCard: some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
            ForEach(viewModel.sections) { section in
                Section {
                    ForEach(section.items) { item in
                        HistoryRow(item: item, viewModel: viewModel)
                            .onAppear {
                                viewModel.loadNextPageIfNeeded(after: item)
                            }
                            .padding(.bottom, 2)
                    }
                } header: {
                    Text(section.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tokens.primaryText)
                        .padding(.horizontal, 22)
                        .padding(.top, 20)
                        .padding(.bottom, 14)
                }

                if section.id != viewModel.sections.last?.id {
                    Divider()
                        .padding(.vertical, 20)
                } else {
                    Color.clear
                        .frame(height: 18)
                }
            }

            if viewModel.isLoadingNextPage {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 18)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tokens.separator.opacity(0.8), lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(alignment: .center, spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 42))
                .foregroundStyle(tokens.secondaryText)
            Text("No History")
                .font(.title3.weight(.semibold))
                .foregroundStyle(tokens.primaryText)
            Text("Visited pages will appear here.")
                .foregroundStyle(tokens.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }
}

private struct HistoryRow: View {
    let item: HistoryListItem
    @ObservedObject var viewModel: HistoryPageViewModel
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.nativeSurfaceHoverUpdatesEnabled) private var hoverUpdatesEnabled

    private enum RowLayout {
        static let selectionWidth: CGFloat = 22
        static let timeWidth: CGFloat = 56
        static let faviconSize: CGFloat = 20
        static let menuWidth: CGFloat = 32
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
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
                    .foregroundStyle(tokens.primaryText)
                    .frame(width: RowLayout.menuWidth, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: RowLayout.menuWidth, alignment: .center)
            .help("More")
            .chromeCursor(.pointingHand, isEnabled: hoverUpdatesEnabled)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowBackgroundColor)
        )
        .chromeCursor(.pointingHand, isEnabled: hoverUpdatesEnabled)
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
        HistoryFaviconView(url: item.url, partition: viewModel.faviconPartition)
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
                .foregroundStyle(tokens.secondaryText)
                .frame(width: RowLayout.timeWidth, alignment: .leading)

            favicon

            HStack(spacing: 8) {
                Text(item.displayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(tokens.primaryText)
                    .layoutPriority(2)

                Text(item.domain)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(tokens.secondaryText)
                    .layoutPriority(-1)

                if item.isSiteAggregate, item.visitCount > 0 {
                    Text("\(item.visitCount)")
                        .font(.caption)
                        .foregroundStyle(tokens.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(tokens.fieldBackground)
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rowBackgroundColor: Color {
        if viewModel.isSelected(item) {
            return themeContext.nativeSurfaceSelectionBackground
        }
        return Color.clear
    }
}

private struct HistoryFaviconView: View {
    let url: URL
    let partition: SumiFaviconPartition
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var image: NSImage?

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
            } else {
                Image(systemName: "globe")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(tokens.secondaryText)
            }
        }
        .task(id: faviconLoadID) {
            await loadImage()
        }
    }

    private var faviconLoadID: FaviconLoadID {
        FaviconLoadID(url: url, partition: partition)
    }

    @MainActor
    private func loadImage() async {
        let cachedImage = TabFaviconStore.getCachedImage(
            forDocumentURL: url,
            partition: partition,
            context: .historyBookmarkRow
        )
        image = cachedImage
        let loadedImage = await TabFaviconStore.loadCachedDisplayImage(
            forDocumentURL: url,
            partition: partition,
            context: .historyBookmarkRow,
            priority: .historyBookmarkVisibleRow
        )
        guard !Task.isCancelled else { return }
        image = loadedImage ?? cachedImage
    }
}

private struct FaviconLoadID: Hashable {
    let url: URL
    let partition: SumiFaviconPartition
}
