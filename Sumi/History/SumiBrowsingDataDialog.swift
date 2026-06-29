import SwiftUI
import WebKit

struct SumiBrowsingDataDialog: View {
    @Environment(\.sumiSettings) private var sumiSettings
    @StateObject private var viewModel: SumiBrowsingDataDialogViewModel

    init(
        browserManager: BrowserManager,
        cleanupService: SumiBrowsingDataCleanupService? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: SumiBrowsingDataDialogViewModel(
                browserManager: browserManager,
                cleanupService: cleanupService ?? browserManager.browsingDataCleanupService
            )
        )
    }

    var body: some View {
        @Bindable var settings = sumiSettings

        VStack(alignment: .leading, spacing: 20) {
            header

            VStack(alignment: .leading, spacing: 18) {
                timeRangeRow

                dataToRemoveSection

                Divider()
                    .padding(.top, 4)

                automaticCleanupSection(
                    selection: $settings.browsingDataRetentionPeriod
                )
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            footer
        }
        .padding(24)
        .frame(width: 620, alignment: .leading)
        .background {
            SumiBrowsingDataSheetBackground()
                .ignoresSafeArea()
        }
        .presentationBackground {
            SumiBrowsingDataSheetBackground()
        }
        .onAppear {
            viewModel.appear()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Browsing data")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Choose which site data Sumi should remove.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var timeRangeRow: some View {
        HStack(alignment: .center, spacing: 16) {
            Picker("Time range:", selection: $viewModel.selectedRange) {
                ForEach(SumiBrowsingDataTimeRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()

            Spacer(minLength: 24)

            if viewModel.showsAllProfilesOption {
                Toggle(
                    "Clear all profiles",
                    isOn: Binding(
                        get: { viewModel.clearsAllProfiles },
                        set: { viewModel.setClearsAllProfiles($0) }
                    )
                )
                .toggleStyle(.checkbox)
                .fixedSize()
                .help("Apply the selected data types to every browser profile")
            }
        }
    }

    private var dataToRemoveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Data to remove")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(SumiBrowsingDataCategory.allCases) { category in
                    browsingDataToggle(category)
                }
            }
        }
    }

    private func automaticCleanupSection(
        selection: Binding<SumiBrowsingDataRetentionPeriod>
    ) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text("Automatic cleanup:")

                Picker("", selection: selection) {
                    ForEach(SumiBrowsingDataRetentionPeriod.allCases) { period in
                        Text(period.title).tag(period)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            GridRow {
                Color.clear
                    .frame(width: 0, height: 0)
                    .gridCellUnsizedAxes([.horizontal, .vertical])

                Text(automaticCleanupSubtitle(for: selection.wrappedValue))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 2)
    }

    private func automaticCleanupSubtitle(
        for period: SumiBrowsingDataRetentionPeriod
    ) -> String {
        guard period.isEnabled else {
            return "Sumi will not delete old browsing data automatically."
        }
        return "Deletes history older than \(period.title) and clears volatile WebKit data without removing sign-in storage."
    }

    private func browsingDataToggle(_ category: SumiBrowsingDataCategory) -> some View {
        Toggle(
            isOn: Binding(
                get: { viewModel.isSelected(category) },
                set: { viewModel.setCategory(category, selected: $0) }
            )
        ) {
            VStack(alignment: .leading, spacing: 4) {
                Text(category.title)
                Text(viewModel.subtitle(for: category))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.checkbox)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer()

            Button("Cancel", role: .cancel) {
                viewModel.cancel()
            }
            .keyboardShortcut(.cancelAction)

            Button(viewModel.deleteButtonTitle, role: .destructive) {
                viewModel.delete()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canDelete)
            .keyboardShortcut(.defaultAction)
        }
    }
}

private struct SumiBrowsingDataSheetBackground: View {
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    var body: some View {
        themeContext
            .tokens(settings: sumiSettings)
            .floatingBarBackground
    }
}

@MainActor
final class SumiBrowsingDataDialogViewModel: ObservableObject {
    @Published private(set) var summary = SumiBrowsingDataSummary()
    @Published private(set) var isLoadingSummary = false
    @Published private(set) var isDeleting = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var clearsAllProfiles = false
    @Published var selectedRange: SumiBrowsingDataTimeRange = .lastHour {
        didSet {
            guard selectedRange != oldValue else { return }
            refreshSummary()
        }
    }
    @Published private var selectedCategories = SumiBrowsingDataCategory.defaultSelection

    private weak var browserManager: BrowserManager?
    private let cleanupService: SumiBrowsingDataCleanupService
    private var summaryTask: Task<Void, Never>?
    private var loadingDelayTask: Task<Void, Never>?

    init(
        browserManager: BrowserManager,
        cleanupService: SumiBrowsingDataCleanupService
    ) {
        self.browserManager = browserManager
        self.cleanupService = cleanupService
    }

    deinit {
        summaryTask?.cancel()
        loadingDelayTask?.cancel()
    }

    var canDelete: Bool {
        !selectedCategories.isEmpty && !isDeleting
    }

    var showsAllProfilesOption: Bool {
        regularProfileCount > 1
    }

    var deleteButtonTitle: String {
        isDeleting ? "Deleting..." : "Delete"
    }

    func appear() {
        refreshSummary()
    }

    func isSelected(_ category: SumiBrowsingDataCategory) -> Bool {
        selectedCategories.contains(category)
    }

    func setCategory(_ category: SumiBrowsingDataCategory, selected: Bool) {
        if selected {
            selectedCategories.insert(category)
        } else {
            selectedCategories.remove(category)
        }
    }

    func setClearsAllProfiles(_ value: Bool) {
        clearsAllProfiles = value && showsAllProfilesOption
        refreshSummary()
    }

    func subtitle(for category: SumiBrowsingDataCategory) -> String {
        if isLoadingSummary {
            return "Checking current profile..."
        }

        switch category {
        case .history:
            return summary.historyVisitCount == 0
                ? "No records"
                : "\(summary.historyVisitCount) \(plural(summary.historyVisitCount, singular: "record", plural: "records"))"
        case .siteData:
            return summary.siteDataSiteCount == 0
                ? "No site data"
                : "From \(summary.siteDataSiteCount) \(plural(summary.siteDataSiteCount, singular: "site", plural: "sites"))"
        case .cache:
            return summary.cacheSiteCount == 0
                ? "No cached site data"
                : "From \(summary.cacheSiteCount) \(plural(summary.cacheSiteCount, singular: "site", plural: "sites"))"
        }
    }

    func cancel() {
        browserManager?.dismissNativeModalPresentation()
    }

    func delete() {
        guard !isDeleting, !selectedCategories.isEmpty else { return }
        Task { [weak self] in
            await self?.deleteNow()
        }
    }

    private func refreshSummary() {
        summaryTask?.cancel()
        loadingDelayTask?.cancel()
        isLoadingSummary = false
        errorMessage = nil

        loadingDelayTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.isLoadingSummary = true
        }

        summaryTask = Task { @MainActor [weak self] in
            guard let self else { return }

            guard let browserManager,
                  browserManager.currentProfile != nil
            else {
                self.loadingDelayTask?.cancel()
                self.isLoadingSummary = false
                self.summary = SumiBrowsingDataSummary()
                return
            }

            let latestSummary = await cleanupService.summary(
                range: selectedRange,
                historyManager: browserManager.historyManager,
                profiles: browserManager.profileManager.profiles,
                includeAllProfiles: clearsAllProfiles
            )
            guard !Task.isCancelled else { return }

            self.loadingDelayTask?.cancel()
            self.isLoadingSummary = false
            self.summary = latestSummary
        }
    }

    private func deleteNow() async {
        guard let browserManager,
              browserManager.currentProfile != nil
        else {
            errorMessage = "No active profile."
            return
        }

        summaryTask?.cancel()
        isDeleting = true
        errorMessage = nil

        await cleanupService.clear(
            range: selectedRange,
            categories: selectedCategories,
            historyManager: browserManager.historyManager,
            profiles: browserManager.profileManager.profiles,
            includeAllProfiles: clearsAllProfiles
        )
        for profile in browserManager.profileManager.profiles where !profile.isEphemeral {
            await profile.refreshDataStoreStats()
        }

        isDeleting = false
        browserManager.dismissNativeModalPresentation()
    }

    private var regularProfileCount: Int {
        browserManager?.profileManager.profiles.filter { !$0.isEphemeral }.count ?? 0
    }

    private func plural(_ value: Int, singular: String, plural: String) -> String {
        value == 1 ? singular : plural
    }
}
