import SwiftUI

struct GeneralSearchEnginesSettingsSection: View {
    @Binding private var searchEngines: [SumiSearchEngine]
    @State private var searchEngineFilter = ""
    @State private var editingSearchEngine: SearchEngineEditorDraft?
    @State private var searchEnginePendingRemoval: SumiSearchEngine?
    @State private var showingRestoreDefaultsConfirmation = false
    @State private var searchEngineReorder = ReorderDragState<String>(threshold: 0)

    init(searchEngines: Binding<[SumiSearchEngine]>) {
        _searchEngines = searchEngines
    }

    var body: some View {
        SettingsSection(
            title: "Search Engines",
            subtitle: "The list order controls Tab-search priority in the command palette."
        ) {
            let displayedSearchEngines = filteredSearchEngines

            searchEnginesToolbar

            if displayedSearchEngines.isEmpty {
                SettingsEmptyState(
                    systemImage: "magnifyingglass",
                    title: searchEngineFilter.isEmpty ? "No Search Engines" : "No Matching Search Engines",
                    detail: searchEngineFilter.isEmpty
                        ? "Add a search engine to use it as a default or Tab search target."
                        : "Clear the filter to show every configured search engine."
                )
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    searchEngineListHeader
                    searchEngineRowsList(displayedSearchEngines)
                }
            }

            SettingsSectionFooter(infoText: tabSearchSummary) {
                showingRestoreDefaultsConfirmation = true
            }
        }
        .sheet(item: $editingSearchEngine) { draft in
            SearchEngineEditor(draft: draft) { engine in
                saveSearchEngine(engine)
            }
            .sumiNativeSurfaceColorScheme()
        }
        .confirmationDialog(
            "Remove Search Engine?",
            isPresented: searchEngineRemovalBinding
        ) {
            Button("Remove", role: .destructive) {
                removePendingSearchEngine()
            }
            Button("Cancel", role: .cancel) {
                searchEnginePendingRemoval = nil
            }
        } message: {
            Text(searchEnginePendingRemoval?.name ?? "")
        }
        .confirmationDialog(
            "Restore Default Search Engines?",
            isPresented: $showingRestoreDefaultsConfirmation
        ) {
            Button("Restore Defaults", role: .destructive) {
                searchEngines = SumiSearchEngine.defaultEngines()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your current list will be replaced with Sumi's default search engines.")
        }
    }

    private var filteredSearchEngines: [SumiSearchEngine] {
        searchEngines.filter { $0.matchesFilter(searchEngineFilter) }
    }

    private var isFilteringSearchEngines: Bool {
        !searchEngineFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var tabSearchSummary: String {
        let count = searchEngines.filter(\.tabSearchEnabled).count
        switch count {
        case 0:
            return "No engines appear as Tab-search suggestions."
        case 1:
            return "1 engine appears as a Tab-search suggestion."
        default:
            return "\(count) engines appear as Tab-search suggestions."
        }
    }

    private var searchEnginesToolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Filter search engines", text: $searchEngineFilter)
                    .textFieldStyle(.plain)

                if !searchEngineFilter.isEmpty {
                    Button {
                        searchEngineFilter = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Clear filter")
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: SettingsSurfaceStyle.compactCornerRadius, style: .continuous)
                    .fill(SettingsSurfaceStyle.fieldBackground)
            )

            Button {
                editingSearchEngine = SearchEngineEditorDraft()
            } label: {
                Label("Add", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var searchEngineListHeader: some View {
        HStack(spacing: 12) {
            Color.clear
                .frame(width: 18)

            Color.clear
                .frame(width: 12)

            Text("Search engine")
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Tab Search")
                .frame(width: 86, alignment: .center)

            Text("Actions")
                .frame(width: 68, alignment: .center)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.top, 4)
        .padding(.bottom, 5)
    }

    private func searchEngineRowsList(_ engines: [SumiSearchEngine]) -> some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(engines.enumerated()), id: \.element.id) { index, engine in
                    searchEngineRow(engine, index: index)

                    if index < engines.count - 1 {
                        SettingsDivider()
                    }
                }
            }
            .animation(
                SearchEngineReorderMetrics.reorderAnimation,
                value: searchEngineReorder.draggedProjectedIndex
            )

            if let draggedID = searchEngineReorder.draggedID,
               !isFilteringSearchEngines,
               let sourceIndex = searchEngineReorder.draggedSourceIndex,
               let engine = searchEngines.first(where: { $0.id == draggedID }) {
                searchEngineFloatingRow(engine, sourceIndex: sourceIndex)
            }
        }
        .coordinateSpace(name: SearchEngineReorderMetrics.coordinateSpaceName)
    }

    private func searchEngineRow(_ engine: SumiSearchEngine, index: Int) -> some View {
        let isDraggedSource = searchEngineReorder.draggedID == engine.id

        return searchEngineRowBody(engine, index: index, allowsDrag: true, isInteractive: true)
            .frame(height: SearchEngineReorderMetrics.rowHeight)
            .opacity(isDraggedSource ? 0.001 : 1)
            .allowsHitTesting(!isDraggedSource)
            .offset(y: searchEngineRowOffset(for: engine, index: index))
    }

    private func searchEngineFloatingRow(
        _ engine: SumiSearchEngine,
        sourceIndex: Int
    ) -> some View {
        searchEngineRowBody(engine, index: sourceIndex, allowsDrag: false, isInteractive: false)
            .frame(height: SearchEngineReorderMetrics.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SettingsSurfaceStyle.compactCornerRadius, style: .continuous)
                    .fill(SettingsSurfaceStyle.fieldBackground)
            )
            .clipShape(
                RoundedRectangle(cornerRadius: SettingsSurfaceStyle.compactCornerRadius, style: .continuous)
            )
            .shadow(color: SettingsSurfaceStyle.floatingRowShadow, radius: 10, y: 4)
            .offset(y: searchEngineReorder.draggedOverlayFrame()?.minY ?? 0)
            .transaction { transaction in
                transaction.animation = nil
            }
            .allowsHitTesting(false)
            .zIndex(10)
    }

    private func searchEngineRowBody(
        _ engine: SumiSearchEngine,
        index: Int,
        allowsDrag: Bool,
        isInteractive: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if allowsDrag {
                SearchEngineDragHandle(isEnabled: !isFilteringSearchEngines)
                    .frame(width: 18)
                    .gesture(searchEngineDragGesture(for: engine, index: index))
                    .help(isFilteringSearchEngines ? "Clear the filter to reorder" : "Drag to reorder")
            } else {
                SearchEngineDragHandle(isEnabled: true)
                    .frame(width: 18)
            }

            Circle()
                .fill(engine.color)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .strokeBorder(SettingsSurfaceStyle.stroke, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(engine.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(engine.domain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isInteractive {
                Toggle("", isOn: tabSearchBinding(for: engine))
                    .toggleStyle(SearchEngineCircularCheckboxStyle())
                    .labelsHidden()
                    .frame(width: 86, alignment: .center)
                    .help(engine.tabSearchEnabled ? "Hide from Tab search" : "Show in Tab search")
            } else {
                SearchEngineCircularCheckboxMark(isOn: engine.tabSearchEnabled)
                    .frame(width: 86, alignment: .center)
                    .accessibilityHidden(true)
            }

            searchEngineActions(for: engine, isInteractive: isInteractive)
        }
    }

    @ViewBuilder
    private func searchEngineActions(
        for engine: SumiSearchEngine,
        isInteractive: Bool
    ) -> some View {
        if isInteractive {
            HStack(spacing: 12) {
                Button {
                    editingSearchEngine = SearchEngineEditorDraft(engine: engine)
                } label: {
                    Image(systemName: "pencil")
                        .font(SettingsTypography.searchEngineActionIcon)
                }
                .buttonStyle(NavButtonStyle(size: .small))
                .help("Edit search engine")

                Button(role: .destructive) {
                    if canDeleteSearchEngine(engine) {
                        searchEnginePendingRemoval = engine
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(SettingsTypography.searchEngineActionIcon)
                }
                .buttonStyle(NavButtonStyle(size: .small))
                .disabled(!canDeleteSearchEngine(engine))
                .help(canDeleteSearchEngine(engine)
                    ? "Delete search engine"
                    : "At least one search engine is required")
            }
            .frame(width: 68, alignment: .center)
        } else {
            HStack(spacing: 12) {
                Image(systemName: "pencil")
                    .font(SettingsTypography.searchEngineActionIcon)
                    .frame(width: 28, height: 28)
                Image(systemName: "trash")
                    .font(SettingsTypography.searchEngineActionIcon)
                    .frame(width: 28, height: 28)
            }
            .foregroundStyle(.secondary)
            .frame(width: 68, alignment: .center)
            .accessibilityHidden(true)
        }
    }

    private var searchEngineRemovalBinding: Binding<Bool> {
        Binding(
            get: { searchEnginePendingRemoval != nil },
            set: { isPresented in
                if !isPresented { searchEnginePendingRemoval = nil }
            }
        )
    }

    private var searchEngineReorderGeometry: ReorderGeometry {
        let frames = searchEngines.indices.map { index in
            CGRect(
                x: 0,
                y: CGFloat(index) * SearchEngineReorderMetrics.rowStep,
                width: 1,
                height: SearchEngineReorderMetrics.rowHeight
            )
        }
        return ReorderGeometry(axis: .vertical, slotFrames: frames)
    }

    private func searchEngineDragGesture(
        for engine: SumiSearchEngine,
        index: Int
    ) -> some Gesture {
        makeReorderDragGesture(
            id: engine.id,
            coordinateSpaceName: SearchEngineReorderMetrics.coordinateSpaceName,
            minimumDistance: SearchEngineReorderMetrics.dragThreshold,
            isEnabled: { !isFilteringSearchEngines },
            orderedIDs: { searchEngines.map(\.id) },
            geometry: { searchEngineReorderGeometry },
            state: $searchEngineReorder,
            onCommit: { move in commitSearchEngineDrag(move) }
        )
    }

    private func commitSearchEngineDrag(_ move: ReorderMove<String>) {
        let updated = GeneralSearchEngineMutation.moving(move, in: searchEngines)
        guard updated.map(\.id) != searchEngines.map(\.id) else { return }
        searchEngines = updated
    }

    private func searchEngineRowOffset(for engine: SumiSearchEngine, index: Int) -> CGFloat {
        guard !isFilteringSearchEngines,
              let sourceIndex = searchEngineReorder.draggedSourceIndex,
              let projectedIndex = searchEngineReorder.draggedProjectedIndex
        else { return 0 }

        if searchEngineReorder.draggedID == engine.id {
            return 0
        }

        if sourceIndex < projectedIndex,
           index > sourceIndex,
           index <= projectedIndex {
            return -SearchEngineReorderMetrics.rowStep
        }

        if projectedIndex < sourceIndex,
           index >= projectedIndex,
           index < sourceIndex {
            return SearchEngineReorderMetrics.rowStep
        }

        return 0
    }

    private func tabSearchBinding(for engine: SumiSearchEngine) -> Binding<Bool> {
        Binding(
            get: {
                searchEngines.first(where: { $0.id == engine.id })?.tabSearchEnabled ?? false
            },
            set: { isEnabled in
                searchEngines = GeneralSearchEngineMutation.settingTabSearch(
                    isEnabled,
                    for: engine.id,
                    in: searchEngines
                )
            }
        )
    }

    private func canDeleteSearchEngine(_ engine: SumiSearchEngine) -> Bool {
        searchEngines.contains { $0.id == engine.id } && searchEngines.count > 1
    }

    private func saveSearchEngine(_ engine: SumiSearchEngine) {
        searchEngines = GeneralSearchEngineMutation.upserting(engine, in: searchEngines)
    }

    private func removePendingSearchEngine() {
        defer { searchEnginePendingRemoval = nil }
        guard let engineID = searchEnginePendingRemoval?.id,
              let updated = GeneralSearchEngineMutation.removing(
                engineID: engineID,
                from: searchEngines
              )
        else {
            return
        }

        searchEngines = updated
    }
}

private enum SearchEngineReorderMetrics {
    static let coordinateSpaceName = "SearchEngineRows"
    static let dragThreshold: CGFloat = 2
    static let rowHeight: CGFloat = 48
    static let separatorHeight: CGFloat = 1
    static let rowStep = rowHeight + separatorHeight
    static let reorderAnimation: Animation = .easeInOut(duration: 0.16)
}

private struct SearchEngineDragHandle: View {
    let isEnabled: Bool

    var body: some View {
        VStack(spacing: 3) {
            dotRow
            dotRow
        }
        .frame(width: 18, height: 18)
        .foregroundStyle(isEnabled ? .secondary : .tertiary)
        .contentShape(Rectangle())
        .opacity(isEnabled ? 1 : 0.55)
    }

    private var dotRow: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .frame(width: 2.5, height: 2.5)
            }
        }
    }
}

private struct SearchEngineCircularCheckboxMark: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    isOn ? Color.accentColor : Color.secondary.opacity(0.55),
                    lineWidth: isOn ? 0 : 1.5
                )
                .background(
                    Circle()
                        .fill(isOn ? Color.accentColor : Color.clear)
                )

            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 16, height: 16)
        .contentShape(Circle())
    }
}

private struct SearchEngineCircularCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            SearchEngineCircularCheckboxMark(isOn: configuration.isOn)
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}
