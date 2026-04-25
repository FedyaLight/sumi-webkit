import SwiftUI
import WebKit

struct SumiBrowsingDataDialog: View {
    @StateObject private var viewModel: SumiBrowsingDataDialogViewModel

    init(
        browserManager: BrowserManager,
        cleanupService: SumiBrowsingDataCleanupService? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: SumiBrowsingDataDialogViewModel(
                browserManager: browserManager,
                cleanupService: cleanupService ?? .shared
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Browsing data")
                .font(.system(size: 28, weight: .semibold))

            timeRangeControls

            dataTypeCard

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            footer
        }
        .padding(24)
        .frame(width: 620, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 28, y: 12)
        .onAppear {
            viewModel.appear()
        }
    }

    private var timeRangeControls: some View {
        HStack(spacing: 8) {
            ForEach(SumiBrowsingDataTimeRange.primaryRanges) { range in
                timeRangeButton(range)
            }

            Menu {
                ForEach(SumiBrowsingDataTimeRange.moreRanges) { range in
                    Button {
                        viewModel.selectRange(range)
                    } label: {
                        if viewModel.selectedRange == range {
                            Label(range.title, systemImage: "checkmark")
                        } else {
                            Text(range.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.moreRangeIsSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text(viewModel.moreRangeTitle)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(timeRangeBackground(isSelected: viewModel.moreRangeIsSelected))
                .overlay(timeRangeBorder(isSelected: viewModel.moreRangeIsSelected))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
        }
    }

    private func timeRangeButton(_ range: SumiBrowsingDataTimeRange) -> some View {
        let isSelected = viewModel.selectedRange == range
        return Button {
            viewModel.selectRange(range)
        } label: {
            HStack(spacing: 8) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(range.title)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(timeRangeBackground(isSelected: isSelected))
            .overlay(timeRangeBorder(isSelected: isSelected))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func timeRangeBackground(isSelected: Bool) -> Color {
        isSelected
            ? Color.accentColor.opacity(0.18)
            : Color(nsColor: .windowBackgroundColor)
    }

    private func timeRangeBorder(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .stroke(
                isSelected ? Color.accentColor.opacity(0.55) : Color.accentColor.opacity(0.42),
                lineWidth: 1.5
            )
    }

    private var dataTypeCard: some View {
        VStack(spacing: 0) {
            ForEach(SumiBrowsingDataCategory.allCases) { category in
                browsingDataRow(category)
                if category != SumiBrowsingDataCategory.allCases.last {
                    Divider()
                        .padding(.leading, 54)
                }
            }
        }
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func browsingDataRow(_ category: SumiBrowsingDataCategory) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Toggle(
                "",
                isOn: Binding(
                    get: { viewModel.isSelected(category) },
                    set: { viewModel.setCategory(category, selected: $0) }
                )
            )
            .toggleStyle(.checkbox)
            .labelsHidden()
            .frame(width: 22)

            browsingDataIcon(category)

            VStack(alignment: .leading, spacing: 4) {
                Text(category.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(viewModel.subtitle(for: category))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func browsingDataIcon(_ category: SumiBrowsingDataCategory) -> some View {
        if let chromeIconName = category.chromeIconName,
           let image = SumiZenFolderIconCatalog.chromeImage(named: chromeIconName) {
            SumiZenBundledIconView(
                image: image,
                size: 24,
                tint: .secondary
            )
            .frame(width: 24, height: 24)
        } else {
            Image(systemName: category.iconName)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 24, height: 24)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer()
            Button("Cancel") {
                viewModel.cancel()
            }
            .buttonStyle(DialogButtonStyle(variant: .secondary))
            .keyboardShortcut(.cancelAction)

            Button(viewModel.deleteButtonTitle) {
                viewModel.delete()
            }
            .buttonStyle(DialogButtonStyle(variant: .danger))
            .disabled(!viewModel.canDelete)
            .keyboardShortcut(.defaultAction)
        }
    }
}

@MainActor
final class SumiBrowsingDataDialogViewModel: ObservableObject {
    @Published private(set) var summary = SumiBrowsingDataSummary()
    @Published private(set) var isLoadingSummary = false
    @Published private(set) var isDeleting = false
    @Published private(set) var errorMessage: String?
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

    init(
        browserManager: BrowserManager,
        cleanupService: SumiBrowsingDataCleanupService
    ) {
        self.browserManager = browserManager
        self.cleanupService = cleanupService
    }

    deinit {
        summaryTask?.cancel()
    }

    var moreRangeIsSelected: Bool {
        SumiBrowsingDataTimeRange.moreRanges.contains(selectedRange)
    }

    var moreRangeTitle: String {
        moreRangeIsSelected ? selectedRange.title : "More"
    }

    var canDelete: Bool {
        !selectedCategories.isEmpty && !isDeleting
    }

    var deleteButtonTitle: String {
        isDeleting ? "Deleting..." : "Delete"
    }

    func appear() {
        refreshSummary()
    }

    func selectRange(_ range: SumiBrowsingDataTimeRange) {
        selectedRange = range
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

    func toggleCategory(_ category: SumiBrowsingDataCategory) {
        setCategory(category, selected: !isSelected(category))
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
        browserManager?.closeDialog()
    }

    func delete() {
        guard !isDeleting, !selectedCategories.isEmpty else { return }
        Task { [weak self] in
            await self?.deleteNow()
        }
    }

    private func refreshSummary() {
        summaryTask?.cancel()
        errorMessage = nil
        summaryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            isLoadingSummary = true
            defer { isLoadingSummary = false }

            guard let browserManager,
                  let dataStore = browserManager.currentProfile?.dataStore
            else {
                summary = SumiBrowsingDataSummary()
                return
            }

            let latestSummary = await cleanupService.summary(
                range: selectedRange,
                historyManager: browserManager.historyManager,
                dataStore: dataStore
            )
            guard !Task.isCancelled else { return }
            summary = latestSummary
        }
    }

    private func deleteNow() async {
        guard let browserManager,
              let currentProfile = browserManager.currentProfile
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
            dataStore: currentProfile.dataStore
        )
        await currentProfile.refreshDataStoreStats()

        isDeleting = false
        browserManager.closeDialog()
    }

    private func plural(_ value: Int, singular: String, plural: String) -> String {
        value == 1 ? singular : plural
    }
}
