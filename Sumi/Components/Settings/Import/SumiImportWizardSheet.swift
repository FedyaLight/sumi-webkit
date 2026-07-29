import AppKit
import SwiftUI

/// One flow for every source: pick a browser, pick a profile, choose what to
/// bring over, import.
struct SumiImportWizardSheet: View {
    @State private var model: SumiImportWizardModel
    let onClose: () -> Void

    init(actions: SumiImportWizardActions, onClose: @escaping () -> Void) {
        _model = State(initialValue: SumiImportWizardModel(actions: actions))
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Divider()

            Group {
                switch model.step {
                case .source:
                    SumiImportSourceStepView(model: model)
                case .profile:
                    SumiImportProfileStepView(model: model)
                case .categories:
                    SumiImportCategoryStepView(model: model)
                case .applying:
                    progress
                case let .finished(message):
                    finished(message)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            footer
        }
        .padding(24)
        .frame(minWidth: 560, maxWidth: 680, minHeight: 420)
        .onAppear { model.detect() }
        .onDisappear { model.cancelWork() }
        .sheet(item: $model.explainerBrowser) { browser in
            SumiFullDiskAccessExplainerView(browser: browser) {
                model.explainerBrowser = nil
                model.detect()
            }
            .sumiNativeSurfaceColorScheme()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Import from another browser")
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var subtitle: String {
        switch model.step {
        case .source: return "Choose the browser you want to bring into Sumi."
        case .profile: return "Choose which profile to import."
        case .categories: return model.preview?.title ?? "Preparing…"
        case .applying: return "Importing…"
        case .finished: return "Done."
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Importing. Leave this window open until it finishes.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func finished(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Import complete", systemImage: "checkmark.circle")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            if model.step == .profile || model.step == .categories {
                Button("Back") { model.back() }
            }
            Spacer()
            switch model.step {
            case .finished:
                Button("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            case .applying:
                Button("Cancel", action: onClose).disabled(true)
            default:
                Button("Cancel", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button(model.applyMode == .replace ? "Replace" : "Import") {
                    model.apply()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(model.canImport == false)
            }
        }
    }
}

// MARK: - Steps

struct SumiImportSourceStepView: View {
    @Bindable var model: SumiImportWizardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.isDetecting {
                ProgressView().controlSize(.small)
            } else if model.browsers.isEmpty {
                Text("No other browsers were found on this Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(model.browsers) { browser in
                        row(browser)
                    }
                }
            }
        }
    }

    private func row(_ browser: SumiDetectedBrowser) -> some View {
        Button {
            model.select(browser)
        } label: {
            HStack(spacing: 10) {
                browserIcon(browser)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(browser.displayName)
                        .foregroundStyle(.primary)
                    if let issue = browser.accessIssue {
                        Text(issue.explanation)
                            .font(.caption)
                            .foregroundStyle(issue.isBlocking ? .red : .secondary)
                    } else {
                        Text(profileSummary(browser))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: browser.isImportable ? "chevron.right" : "exclamationmark.circle")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func profileSummary(_ browser: SumiDetectedBrowser) -> String {
        browser.profiles.count == 1
            ? browser.profiles[0].displayName
            : "\(browser.profiles.count) profiles"
    }

    @ViewBuilder
    private func browserIcon(_ browser: SumiDetectedBrowser) -> some View {
        if let bundleId = browser.bundleIdentifiers.first,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "globe")
                .foregroundStyle(.secondary)
        }
    }
}

struct SumiImportProfileStepView: View {
    @Bindable var model: SumiImportWizardModel

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(model.selectedBrowser?.profiles ?? []) { profile in
                    Button {
                        model.select(profile)
                    } label: {
                        HStack {
                            Text(profile.displayName)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct SumiImportCategoryStepView: View {
    @Bindable var model: SumiImportWizardModel

    var body: some View {
        if model.isPreparingPreview {
            ProgressView().controlSize(.small)
        } else if let preview = model.preview {
            VStack(alignment: .leading, spacing: 14) {
                Text(summary(preview))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Mode", selection: $model.applyMode) {
                    ForEach(SumiImportApplyMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: 10)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(SumiImportCategory.allCases) { category in
                        Toggle(isOn: binding(category)) { Text(category.title) }
                            .toggleStyle(.checkbox)
                            .disabled(
                                preview.suggestedCategories.contains(category) == false
                                    || (category == .profiles && model.requiresProfilesForBrowsingData)
                            )
                    }
                }

                if let staging = preview.bulkStaging, staging.entries.isEmpty == false {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Browsing data")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(SumiImportBulkKind.applyOrder.filter { staging.kinds.contains($0) }) { kind in
                            Toggle(isOn: bulkBinding(kind)) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(kind.title) (\(staging.recordCount(for: kind).formatted()))")
                                    if let note = note(for: kind) {
                                        Text(note).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .toggleStyle(.checkbox)
                            .disabled(staging.recordCount(for: kind) == 0)
                        }
                    }
                }

                if preview.warnings.isEmpty == false {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(preview.warnings, id: \.self) { warning in
                                Label(warning, systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxHeight: 110)
                }

                if model.applyMode == .replace, model.selectedCategories.contains(.profiles) {
                    Label(
                        "Replace retires local profiles that are not in the import and removes their "
                            + "website data, which backups do not include.",
                        systemImage: "exclamationmark.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func summary(_ preview: SumiImportPreview) -> String {
        let s = preview.summary
        return "\(s.profiles) profiles · \(s.spaces) spaces · \(s.essentials) essentials · "
            + "\(s.pinnedLaunchers) pinned · \(s.regularTabs) tabs · \(s.folders) folders · \(s.bookmarks) bookmarks"
    }

    /// Each note states the cost the user is accepting, not just the benefit.
    private func note(for kind: SumiImportBulkKind) -> LocalizedStringKey? {
        switch kind {
        case .history: return nil
        case .favicons: return "Site icons appear immediately instead of loading in over time."
        case .cookies:
            return "macOS may ask for your password. Cookies are not included in Sumi backups. Merge keeps existing Sumi cookies; Replace overwrites matching cookies."
        }
    }

    private func bulkBinding(_ kind: SumiImportBulkKind) -> Binding<Bool> {
        Binding(
            get: { model.selectedBulkKinds.contains(kind) },
            set: { enabled in
                model.setBulkKind(kind, enabled: enabled)
            }
        )
    }

    private func binding(_ category: SumiImportCategory) -> Binding<Bool> {
        Binding(
            get: { model.selectedCategories.contains(category) },
            set: { enabled in
                model.setCategory(category, enabled: enabled)
            }
        )
    }
}
