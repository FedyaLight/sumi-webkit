//
//  General.swift
//  Sumi
//

import SwiftUI

struct SettingsGeneralTab: View {
    @Environment(\.sumiSettings) var sumiSettings
    @State private var searchEngineFilter = ""
    @State private var editingSearchEngine: SearchEngineEditorDraft?
    @State private var searchEnginePendingRemoval: SumiSearchEngine?
    @State private var showingRestoreDefaultsConfirmation = false
    @State private var searchEngineDrag: SearchEngineReorderState?

    var body: some View {
        @Bindable var settings = sumiSettings

        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(
                title: "Window",
                subtitle: "Core browser-window behavior."
            ) {
                SettingsRow(
                    title: "Warn before quitting",
                    subtitle: "Ask for confirmation before closing Sumi."
                ) {
                    Toggle("", isOn: $settings.askBeforeQuit)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                SettingsRow(
                    title: "Glance",
                    subtitle: "Preview links without fully opening a tab."
                ) {
                    Toggle("", isOn: $settings.glanceEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            SettingsSection(
                title: "Search",
                subtitle: "Choose the default web search and how the floating bar behaves before typing."
            ) {
                SettingsRow(
                    title: "Floating bar empty state",
                    subtitle: "Choose what appears before you start typing."
                ) {
                    Picker("", selection: $settings.floatingBarEmptyStateMode) {
                        ForEach(FloatingBarEmptyStateMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .settingsTrailingControl(width: 160)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Default search engine",
                    subtitle: "Used for plain text typed into the URL bar."
                ) {
                    Picker("", selection: $settings.searchEngineId) {
                        ForEach(settings.searchEngines) { engine in
                            Text(engine.name).tag(engine.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .settingsTrailingControl(width: 210)
                }
            }

            SettingsSection(
                title: "Search Engines",
                subtitle: "The list order controls Tab-search priority in the floating bar."
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

                SettingsDivider()

                HStack(spacing: 10) {
                    Text(tabSearchSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 12)

                    Button("Restore Defaults") {
                        showingRestoreDefaultsConfirmation = true
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .sheet(item: $editingSearchEngine) { draft in
            SearchEngineEditor(draft: draft) { result in
                saveSearchEngine(result)
            }
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
                restoreDefaultSearchEngines()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your current list will be replaced with Sumi's default search engines.")
        }
    }

    private var filteredSearchEngines: [SumiSearchEngine] {
        sumiSettings.searchEngines.filter { $0.matchesFilter(searchEngineFilter) }
    }

    private var isFilteringSearchEngines: Bool {
        !searchEngineFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var tabSearchSummary: String {
        let count = sumiSettings.searchEngines.filter(\.tabSearchEnabled).count
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
                .frame(width: 64, alignment: .trailing)
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
            .animation(SearchEngineReorderMetrics.reorderAnimation, value: searchEngineDrag?.projectedIndex)

            if let drag = searchEngineDrag,
               !isFilteringSearchEngines,
               let engine = sumiSettings.searchEngines.first(where: { $0.id == drag.id }) {
                searchEngineFloatingRow(engine, drag: drag)
            }
        }
        .coordinateSpace(name: SearchEngineReorderMetrics.coordinateSpaceName)
    }

    private func searchEngineRow(_ engine: SumiSearchEngine, index: Int) -> some View {
        let isDraggedSource = searchEngineDrag?.id == engine.id

        return searchEngineRowBody(engine, index: index, allowsDrag: true, isInteractive: true)
        .frame(height: SearchEngineReorderMetrics.rowHeight)
        .opacity(isDraggedSource ? 0.001 : 1)
        .allowsHitTesting(!isDraggedSource)
        .offset(y: searchEngineRowOffset(for: engine, index: index))
    }

    private func searchEngineFloatingRow(_ engine: SumiSearchEngine, drag: SearchEngineReorderState) -> some View {
        searchEngineRowBody(engine, index: drag.sourceIndex, allowsDrag: false, isInteractive: false)
            .frame(height: SearchEngineReorderMetrics.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SettingsSurfaceStyle.compactCornerRadius, style: .continuous)
                    .fill(SettingsSurfaceStyle.fieldBackground)
            )
            .clipShape(RoundedRectangle(cornerRadius: SettingsSurfaceStyle.compactCornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(0.16), radius: 10, y: 4)
            .offset(y: drag.floatingTopY)
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

            if isInteractive {
                HStack(spacing: 6) {
                    Button {
                        editingSearchEngine = SearchEngineEditorDraft(engine: engine)
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                    .frame(width: 26, height: 26)
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .help("Edit search engine")

                    Button(role: .destructive) {
                        if canDeleteSearchEngine(engine) {
                            searchEnginePendingRemoval = engine
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .frame(width: 26, height: 26)
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .disabled(!canDeleteSearchEngine(engine))
                    .help(canDeleteSearchEngine(engine) ? "Delete search engine" : "At least one search engine is required")
                }
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                        .frame(width: 26, height: 26)
                    Image(systemName: "trash")
                        .frame(width: 26, height: 26)
                }
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
                .accessibilityHidden(true)
            }
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

    private func searchEngineDragGesture(for engine: SumiSearchEngine, index: Int) -> some Gesture {
        DragGesture(
            minimumDistance: SearchEngineReorderMetrics.dragThreshold,
            coordinateSpace: .named(SearchEngineReorderMetrics.coordinateSpaceName)
        )
            .onChanged { value in
                guard !isFilteringSearchEngines else { return }

                var drag = searchEngineDrag
                if drag?.id != engine.id {
                    let rowTopY = SearchEngineReorderMetrics.rowTopY(for: index)
                    drag = SearchEngineReorderState(
                        id: engine.id,
                        sourceIndex: index,
                        projectedIndex: index,
                        pointerOffsetY: min(
                            max(value.startLocation.y - rowTopY, 0),
                            SearchEngineReorderMetrics.rowHeight
                        ),
                        currentLocationY: value.location.y
                    )
                }

                drag?.currentLocationY = value.location.y
                if let currentLocationY = drag?.currentLocationY {
                    drag?.projectedIndex = projectedSearchEngineIndex(locationY: currentLocationY)
                }
                searchEngineDrag = drag
            }
            .onEnded { _ in
                guard let drag = searchEngineDrag, drag.id == engine.id else {
                    runWithoutSearchEngineReorderAnimations {
                        searchEngineDrag = nil
                    }
                    return
                }

                runWithoutSearchEngineReorderAnimations {
                    commitSearchEngineDrag(drag)
                    searchEngineDrag = nil
                }
            }
    }

    private func runWithoutSearchEngineReorderAnimations(_ operation: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, operation)
    }

    private func projectedSearchEngineIndex(locationY: CGFloat) -> Int {
        let count = sumiSettings.searchEngines.count
        guard count > 0 else { return 0 }

        let projected = Int(floor(locationY / SearchEngineReorderMetrics.rowStep))
        return min(max(projected, 0), count - 1)
    }

    private func searchEngineRowOffset(for engine: SumiSearchEngine, index: Int) -> CGFloat {
        guard !isFilteringSearchEngines,
              let drag = searchEngineDrag
        else { return 0 }

        if drag.id == engine.id {
            return 0
        }

        if drag.sourceIndex < drag.projectedIndex,
           index > drag.sourceIndex,
           index <= drag.projectedIndex {
            return -SearchEngineReorderMetrics.rowStep
        }

        if drag.projectedIndex < drag.sourceIndex,
           index >= drag.projectedIndex,
           index < drag.sourceIndex {
            return SearchEngineReorderMetrics.rowStep
        }

        return 0
    }

    private func tabSearchBinding(for engine: SumiSearchEngine) -> Binding<Bool> {
        Binding(
            get: {
                sumiSettings.searchEngines.first(where: { $0.id == engine.id })?.tabSearchEnabled ?? false
            },
            set: { isEnabled in
                guard let index = sumiSettings.searchEngines.firstIndex(where: { $0.id == engine.id }) else { return }
                var engines = sumiSettings.searchEngines
                engines[index].tabSearchEnabled = isEnabled
                sumiSettings.searchEngines = engines
            }
        )
    }

    private func commitSearchEngineDrag(_ drag: SearchEngineReorderState) {
        guard drag.sourceIndex != drag.projectedIndex,
              sumiSettings.searchEngines.indices.contains(drag.sourceIndex)
        else { return }

        var engines = sumiSettings.searchEngines
        let movedEngine = engines.remove(at: drag.sourceIndex)
        let targetIndex = min(max(drag.projectedIndex, 0), engines.count)
        engines.insert(movedEngine, at: targetIndex)
        sumiSettings.searchEngines = engines
    }

    private func canDeleteSearchEngine(_ engine: SumiSearchEngine) -> Bool {
        sumiSettings.searchEngines.contains { $0.id == engine.id } && sumiSettings.searchEngines.count > 1
    }

    private func saveSearchEngine(_ result: SearchEngineEditorResult) {
        var engines = sumiSettings.searchEngines
        if let index = engines.firstIndex(where: { $0.id == result.engine.id }) {
            engines[index] = result.engine
        } else {
            engines.append(result.engine)
        }

        sumiSettings.searchEngines = engines
    }

    private func removePendingSearchEngine() {
        guard let engine = searchEnginePendingRemoval,
              canDeleteSearchEngine(engine)
        else {
            searchEnginePendingRemoval = nil
            return
        }

        sumiSettings.searchEngines.removeAll { $0.id == engine.id }
        searchEnginePendingRemoval = nil
    }

    private func restoreDefaultSearchEngines() {
        let engines = SumiSearchEngine.defaultEngines()
        sumiSettings.searchEngines = engines
        if !engines.contains(where: { $0.id == sumiSettings.searchEngineId }) {
            sumiSettings.searchEngineId = SumiSearchEngine.defaultSearchEngineID(in: engines)
        }
    }
}

private enum SearchEngineReorderMetrics {
    static let coordinateSpaceName = "SearchEngineRows"
    static let dragThreshold: CGFloat = 2
    static let rowHeight: CGFloat = 48
    static let separatorHeight: CGFloat = 1
    static let rowStep = rowHeight + separatorHeight
    static let reorderAnimation: Animation = .easeInOut(duration: 0.16)

    static func rowTopY(for index: Int) -> CGFloat {
        CGFloat(index) * rowStep
    }
}

private struct SearchEngineReorderState: Equatable {
    let id: String
    let sourceIndex: Int
    var projectedIndex: Int
    let pointerOffsetY: CGFloat
    var currentLocationY: CGFloat

    var floatingTopY: CGFloat {
        currentLocationY - pointerOffsetY
    }
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

private struct SearchEngineEditorDraft: Identifiable, Equatable {
    let id = UUID()
    var engineID: String?
    var name = ""
    var domain = ""
    var searchURLTemplate = ""
    var colorHex = "#666666"
    var tabSearchEnabled = false

    init() {}

    init(engine: SumiSearchEngine) {
        self.engineID = engine.id
        self.name = engine.name
        self.domain = engine.domain
        self.searchURLTemplate = engine.searchURLTemplate
        self.colorHex = engine.colorHex
        self.tabSearchEnabled = engine.tabSearchEnabled
    }
}

private struct SearchEngineEditorResult {
    let engine: SumiSearchEngine
}

private struct SearchEngineEditor: View {
    let draft: SearchEngineEditorDraft
    let onSave: (SearchEngineEditorResult) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var domain: String
    @State private var searchURLTemplate: String
    @State private var color: Color

    init(
        draft: SearchEngineEditorDraft,
        onSave: @escaping (SearchEngineEditorResult) -> Void
    ) {
        self.draft = draft
        self.onSave = onSave
        _name = State(initialValue: draft.name)
        _domain = State(initialValue: draft.domain)
        _searchURLTemplate = State(initialValue: draft.searchURLTemplate)
        _color = State(initialValue: Color(hex: draft.colorHex))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(draft.engineID == nil ? "Add Search Engine" : "Edit Search Engine")
                .font(.headline)

            Form {
                TextField("Name", text: $name)
                TextField("Domain", text: $domain)
                    .help("Optional. If empty, Sumi uses the host from the search URL.")
                TextField("Search URL", text: $searchURLTemplate)
                    .help("Use {query} where the typed search text should go.")
                ColorPicker("Color", selection: $color, supportsOpacity: false)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Preview")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(previewURLString ?? "Enter a valid search URL to preview the result.")
                        .font(.caption)
                        .foregroundStyle(previewURLString == nil ? .secondary : .primary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }

                if let validationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(validationMessage != nil)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDomain: String {
        domain.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedTemplate: String {
        SumiSearchEngine.normalizedTemplate(searchURLTemplate)
    }

    private var normalizedColorHex: String {
        color.toHexString() ?? draft.colorHex
    }

    private var sampleURL: URL? {
        let sampleTemplate = normalizedURLTemplate(normalizedTemplate)
        let sampleString = sampleTemplate.replacingOccurrences(of: SumiSearchEngine.queryToken, with: "sumi")
        return URL(string: sampleString)
    }

    private var resolvedDomain: String {
        if !trimmedDomain.isEmpty {
            return trimmedDomain
        }
        return sampleURL?.host ?? ""
    }

    private var previewURLString: String? {
        guard validationMessage == nil else { return nil }
        return SumiSearchEngine(
            id: draft.engineID ?? UUID().uuidString,
            name: trimmedName,
            domain: resolvedDomain,
            searchURLTemplate: normalizedTemplate,
            colorHex: normalizedColorHex,
            tabSearchEnabled: draft.tabSearchEnabled
        )
        .searchURL(for: "sumi browser")?
        .absoluteString
    }

    private var validationMessage: String? {
        guard !trimmedName.isEmpty else { return "Name is required." }
        guard normalizedTemplate.contains(SumiSearchEngine.queryToken) else {
            return "Search URL must contain {query} where the query should go."
        }
        guard let sampleURL,
              let scheme = sampleURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              sampleURL.host?.isEmpty == false
        else {
            return "Enter a valid http or https search URL."
        }
        guard !resolvedDomain.isEmpty else { return "Domain is required." }
        return nil
    }

    private func save() {
        guard validationMessage == nil else { return }

        let engine = SumiSearchEngine(
            id: draft.engineID ?? UUID().uuidString,
            name: trimmedName,
            domain: resolvedDomain,
            searchURLTemplate: normalizedTemplate,
            colorHex: normalizedColorHex,
            tabSearchEnabled: draft.tabSearchEnabled
        )
        onSave(SearchEngineEditorResult(engine: engine))
        dismiss()
    }

    private func normalizedURLTemplate(_ template: String) -> String {
        if template.hasPrefix("http://") || template.hasPrefix("https://") {
            return template
        }
        return "https://\(template)"
    }

}
