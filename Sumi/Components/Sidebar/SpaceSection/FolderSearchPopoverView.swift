import AppKit
import SwiftUI

enum FolderSearchPopoverMetrics {
    static let width: CGFloat = 270
    static let searchHeight: CGFloat = 34
    static let rowHeight: CGFloat = 40
    static let maxVisibleRows = 6
    static let verticalPadding: CGFloat = 8

    static func contentHeight(candidateCount: Int) -> CGFloat {
        let visibleRows = max(1, min(candidateCount, maxVisibleRows))
        return verticalPadding * 2 + searchHeight + CGFloat(visibleRows) * rowHeight
    }
}

private enum FolderSearchKeyCommand {
    case moveUp
    case moveDown
    case accept
    case cancel
}

struct FolderSearchPopoverView: View {
    let folderName: String
    let candidates: [FolderSearchCandidate]
    let onHoverChanged: (Bool) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var selectedCandidateID: String?

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    private var filteredCandidates: [FolderSearchCandidate] {
        FolderSearchMatcher.filteredCandidates(candidates, query: query)
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        VStack(spacing: 0) {
            FolderSearchField(
                text: $query,
                placeholder: "Search \(folderName)",
                onKeyCommand: handleKeyCommand
            )
            .frame(height: FolderSearchPopoverMetrics.searchHeight)
            .padding(.horizontal, 8)

            resultsContent
        }
        .padding(.vertical, FolderSearchPopoverMetrics.verticalPadding)
        .frame(
            width: FolderSearchPopoverMetrics.width,
            height: FolderSearchPopoverMetrics.contentHeight(candidateCount: candidates.count),
            alignment: .top
        )
        .background(Color(nsColor: .clear))
        .onHover(perform: onHoverChanged)
        .onAppear {
            selectedCandidateID = filteredCandidates.first?.id
        }
        .onChange(of: filteredCandidates.map(\.id)) { _, ids in
            reconcileSelection(candidateIDs: ids)
        }
        .accessibilityIdentifier("folder-search-popover")
    }

    @ViewBuilder
    private var resultsContent: some View {
        if filteredCandidates.isEmpty {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No items" : "No matching tabs")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tokens.secondaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredCandidates) { candidate in
                        FolderSearchCandidateRow(
                            candidate: candidate,
                            isSelected: selectedCandidateID == candidate.id,
                            tokens: tokens,
                            cornerRadius: sumiSettings.resolvedCornerRadius(8),
                            onActivate: {
                                activate(candidate)
                            },
                            onHover: {
                                selectedCandidateID = candidate.id
                            }
                        )
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private func handleKeyCommand(_ command: FolderSearchKeyCommand) -> Bool {
        switch command {
        case .moveUp:
            moveSelection(delta: -1)
            return true
        case .moveDown:
            moveSelection(delta: 1)
            return true
        case .accept:
            activateSelectedCandidate()
            return true
        case .cancel:
            onClose()
            return true
        }
    }

    private func reconcileSelection(candidateIDs: [String]) {
        guard !candidateIDs.isEmpty else {
            selectedCandidateID = nil
            return
        }
        if let selectedCandidateID, candidateIDs.contains(selectedCandidateID) {
            return
        }
        selectedCandidateID = candidateIDs.first
    }

    private func moveSelection(delta: Int) {
        let candidates = filteredCandidates
        guard !candidates.isEmpty else {
            selectedCandidateID = nil
            return
        }

        let currentIndex = selectedCandidateID.flatMap { selectedID in
            candidates.firstIndex { $0.id == selectedID }
        } ?? 0
        let nextIndex = (currentIndex + delta + candidates.count) % candidates.count
        selectedCandidateID = candidates[nextIndex].id
    }

    private func activateSelectedCandidate() {
        guard let selectedCandidate = filteredCandidates.first(where: { $0.id == selectedCandidateID }) else {
            return
        }
        activate(selectedCandidate)
    }

    private func activate(_ candidate: FolderSearchCandidate) {
        candidate.activate()
        onClose()
    }
}

private struct FolderSearchCandidateRow: View {
    let candidate: FolderSearchCandidate
    let isSelected: Bool
    let tokens: ChromeThemeTokens
    let cornerRadius: CGFloat
    let onActivate: () -> Void
    let onHover: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            candidate.icon
                .resizable()
                .scaledToFit()
                .frame(width: SidebarRowLayout.faviconSize, height: SidebarRowLayout.faviconSize)
                .padding(.leading, 8)
                .padding(.trailing, SidebarRowLayout.iconTrailingSpacing)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(candidate.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tokens.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !candidate.secondaryText.isEmpty {
                    Text(candidate.secondaryText)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(tokens.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 8)
        }
        .frame(height: FolderSearchPopoverMetrics.rowHeight)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(isSelected ? tokens.sidebarRowHover : Color.clear)
        }
        .onHover { hovering in
            if hovering {
                onHover()
            }
        }
        .onTapGesture(perform: onActivate)
        .accessibilityIdentifier("folder-search-row-\(candidate.id)")
        .accessibilityLabel(candidate.title)
    }
}

private struct FolderSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onKeyCommand: (FolderSearchKeyCommand) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onKeyCommand: onKeyCommand)
    }

    func makeNSView(context: Context) -> KeyHandlingSearchField {
        let field = KeyHandlingSearchField(frame: .zero)
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchFieldDidChange(_:))
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.focusRingType = .none
        field.controlSize = .small
        field.font = .systemFont(ofSize: 13, weight: .regular)
        field.placeholderString = placeholder
        field.onKeyCommand = { command in
            context.coordinator.onKeyCommand(command)
        }
        return field
    }

    func updateNSView(_ nsView: KeyHandlingSearchField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onKeyCommand = onKeyCommand
        nsView.placeholderString = placeholder
        nsView.onKeyCommand = { command in
            context.coordinator.onKeyCommand(command)
        }
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        context.coordinator.focusIfNeeded(nsView)
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        var onKeyCommand: (FolderSearchKeyCommand) -> Bool
        private var didFocus = false

        init(
            text: Binding<String>,
            onKeyCommand: @escaping (FolderSearchKeyCommand) -> Bool
        ) {
            self.text = text
            self.onKeyCommand = onKeyCommand
        }

        @objc func searchFieldDidChange(_ sender: NSSearchField) {
            updateText(sender.stringValue)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            updateText(field.stringValue)
        }

        func focusIfNeeded(_ field: NSSearchField) {
            guard !didFocus else { return }
            DispatchQueue.main.async { [weak self, weak field] in
                guard let self,
                      let field,
                      let window = field.window,
                      !self.didFocus
                else { return }
                window.makeFirstResponder(field)
                field.selectText(nil)
                self.didFocus = true
            }
        }

        private func updateText(_ newValue: String) {
            guard text.wrappedValue != newValue else { return }
            text.wrappedValue = newValue
        }
    }

    @MainActor
    final class KeyHandlingSearchField: NSSearchField {
        var onKeyCommand: (FolderSearchKeyCommand) -> Bool = { _ in false }

        override func keyDown(with event: NSEvent) {
            if let command = Self.command(for: event),
               onKeyCommand(command) {
                return
            }
            super.keyDown(with: event)
        }

        private static func command(for event: NSEvent) -> FolderSearchKeyCommand? {
            switch event.keyCode {
            case 126:
                return .moveUp
            case 125, 48:
                return .moveDown
            case 36, 76:
                return .accept
            case 53:
                return .cancel
            default:
                return nil
            }
        }
    }
}
