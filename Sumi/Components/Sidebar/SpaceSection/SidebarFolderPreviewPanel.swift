import AppKit
import SwiftUI

enum SidebarFolderPreviewKeyCommand {
    case moveUp
    case moveDown
    case accept
    case cancel
}

/// Zen's `#zen-folder-tabs-popup` content: a search header over the collapsed
/// folder's tabs, rendered as in-window chrome instead of a popover.
struct SidebarFolderPreviewPanel: View {
    let folderName: String
    let candidates: [FolderSearchCandidate]
    let previousFirstResponder: PreviousFirstResponder
    let onHoverChanged: (Bool) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var selectedCandidateID: String?
    @State private var keyboardScrollRequest: KeyboardScrollRequest?

    /// Carries a token so repeated keyboard moves onto the same row still scroll.
    private struct KeyboardScrollRequest: Equatable {
        let candidateID: String
        let token: Int
    }

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.chromeThemeTokens) private var scopedChromeTokens

    private var filteredCandidates: [FolderSearchCandidate] {
        FolderSearchMatcher.filteredCandidates(candidates, query: query)
    }

    private var tokens: ChromeThemeTokens {
        scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings)
    }

    private var cornerRadius: CGFloat {
        sumiSettings.resolvedCornerRadius(10)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            Rectangle()
                .fill(tokens.primaryText.opacity(0.1))
                .frame(height: SidebarFolderPreviewMetrics.separatorHeight)
            resultsContent
        }
        .frame(
            width: SidebarFolderPreviewMetrics.width,
            height: SidebarFolderPreviewMetrics.panelHeight(candidateCount: candidates.count),
            alignment: .top
        )
        .background {
            MouseEventShieldView(
                suppressesUnderlyingWebContentHover: true,
                cursorPolicy: .none,
                blocksScrollWheel: false
            )
        }
        // Same native surface the downloads popover gets from `NSPopover`; an
        // in-window panel has to ask for the material itself.
        .background(NativeChromeMaterialBackground(role: .inWindowPopover))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(tokens.floatingSurfaceBorder, lineWidth: 1, antialiased: false)
        }
        .shadow(color: .black.opacity(0.22), radius: 14, y: 4)
        .sidebarHover(onChange: onHoverChanged)
        .onAppear {
            selectedCandidateID = filteredCandidates.first?.id
        }
        .onChange(of: filteredCandidates.map(\.id)) { _, ids in
            reconcileSelection(candidateIDs: ids)
        }
        .accessibilityIdentifier("folder-preview-panel")
    }

    private var searchHeader: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(SidebarThemeTokens.Typography.FolderPreview.searchFieldIcon)
                .foregroundStyle(tokens.primaryText)
                .opacity(0.7)
                .frame(
                    width: SidebarFolderPreviewMetrics.searchIconSize,
                    height: SidebarFolderPreviewMetrics.searchIconSize
                )
                .padding(.leading, SidebarFolderPreviewMetrics.searchIconLeading)
                .padding(.trailing, SidebarFolderPreviewMetrics.searchIconTrailing)
                .accessibilityHidden(true)

            SidebarFolderPreviewSearchField(
                text: $query,
                placeholder: "Search \(folderName)...",
                previousFirstResponder: previousFirstResponder,
                onKeyCommand: handleKeyCommand
            )
            .frame(maxWidth: .infinity)
        }
        .padding(SidebarFolderPreviewMetrics.headerPadding)
        .frame(height: SidebarFolderPreviewMetrics.searchHeaderHeight)
    }

    @ViewBuilder
    private var resultsContent: some View {
        if filteredCandidates.isEmpty {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Text("No tabs matching that search 🤔")
                    .font(SidebarThemeTokens.Typography.FolderPreview.emptyState)
                    .foregroundStyle(tokens.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredCandidates) { candidate in
                            SidebarFolderPreviewRow(
                                candidate: candidate,
                                isSelected: selectedCandidateID == candidate.id,
                                tokens: tokens,
                                onActivate: {
                                    activate(candidate)
                                },
                                onHover: {
                                    selectedCandidateID = candidate.id
                                }
                            )
                            .id(candidate.id)
                        }
                    }
                    .padding(.horizontal, SidebarFolderPreviewMetrics.listHorizontalPadding)
                }
                // Only arrow/Tab selection scrolls, never hover selection: rows
                // move under a stationary pointer while the wheel turns, so
                // scrolling to the hovered row would chase itself to the end of
                // the list. Zen likewise calls scrollIntoView from its key
                // handler alone.
                .onChange(of: keyboardScrollRequest) { _, request in
                    guard let request else { return }
                    proxy.scrollTo(request.candidateID, anchor: .top)
                }
            }
        }
    }

    private func handleKeyCommand(_ command: SidebarFolderPreviewKeyCommand) -> Bool {
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
        let nextID = candidates[nextIndex].id
        selectedCandidateID = nextID
        keyboardScrollRequest = KeyboardScrollRequest(
            candidateID: nextID,
            token: (keyboardScrollRequest?.token ?? 0) + 1
        )
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

private struct SidebarFolderPreviewRow: View {
    let candidate: FolderSearchCandidate
    let isSelected: Bool
    let tokens: ChromeThemeTokens
    let onActivate: () -> Void
    let onHover: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            SidebarFolderPreviewRowIcon(
                icon: candidate.icon,
                tokens: tokens
            )
            .frame(
                width: SidebarFolderPreviewMetrics.rowIconSize,
                height: SidebarFolderPreviewMetrics.rowIconSize
            )
            .padding(.leading, SidebarFolderPreviewMetrics.rowIconLeading)
            .padding(.trailing, SidebarFolderPreviewMetrics.rowIconTrailing)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(candidate.title)
                    .font(SidebarThemeTokens.Typography.FolderPreview.rowTitle)
                    .foregroundStyle(tokens.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !candidate.secondaryText.isEmpty {
                    Text(candidate.secondaryText)
                        .font(SidebarThemeTokens.Typography.FolderPreview.rowSecondaryText)
                        .foregroundStyle(tokens.primaryText.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .frame(height: SidebarFolderPreviewMetrics.rowContentHeight)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(
                cornerRadius: SidebarFolderPreviewMetrics.rowCornerRadius,
                style: .continuous
            )
            .fill(isSelected ? tokens.primaryText.opacity(0.1) : Color.clear)
        }
        .padding(.vertical, SidebarFolderPreviewMetrics.rowVerticalGutter)
        .sidebarHover { hovering in
            if hovering {
                onHover()
            }
        }
        .onTapGesture(perform: onActivate)
        .accessibilityIdentifier("folder-preview-row-\(candidate.id)")
        .accessibilityLabel(candidate.title)
    }
}

/// Renders a preview row's icon through the shared shortcut resolver, loading
/// the stored favicon first so a folder that was never expanded this session
/// still shows real icons rather than globes.
private struct SidebarFolderPreviewRowIcon: View {
    let icon: FolderSearchCandidateIcon
    let tokens: ChromeThemeTokens

    @Environment(SidebarFaviconImageStore.self) private var faviconImageStore

    var body: some View {
        content
            .task(id: storedFaviconLoadKey) {
                await loadStoredFaviconIfNeeded()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch icon {
        case .systemImage(let systemName):
            templateIcon(systemName)
        case .resolved(let image):
            faviconImage(image)
        case .shortcut(let pin, let liveTab, let partition):
            shortcutIcon(
                SidebarShortcutIconResolver.resolve(
                    pin: pin,
                    liveTab: liveTab,
                    loadedStoredFavicon: faviconImageStore.image(
                        for: pin.launchURL,
                        partition: partition
                    )
                )
            )
        }
    }

    @ViewBuilder
    private func shortcutIcon(_ presentation: SidebarShortcutIconPresentation) -> some View {
        if let glyphText = presentation.glyphText {
            Text(glyphText)
                .font(SidebarThemeTokens.Typography.FolderPreview.rowGlyphText(
                    iconSize: SidebarFolderPreviewMetrics.rowIconSize
                ))
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .frame(
                    width: SidebarFolderPreviewMetrics.rowIconSize,
                    height: SidebarFolderPreviewMetrics.rowIconSize
                )
        } else if let systemImageName = presentation.systemImageName {
            templateIcon(systemImageName)
        } else if let image = presentation.image {
            faviconImage(image)
        } else {
            templateIcon(SumiPersistentGlyph.launcherSystemImageFallback)
        }
    }

    private func templateIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(SidebarThemeTokens.Typography.FolderPreview.rowTemplateIcon(
                iconSize: SidebarFolderPreviewMetrics.rowIconSize
            ))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(tokens.primaryText)
    }

    private func faviconImage(_ image: Image) -> some View {
        image
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var storedFaviconLoadKey: String {
        guard case .shortcut(let pin, _, let partition) = icon else {
            return "disabled"
        }
        return faviconImageStore.loadKey(
            launchURL: pin.launchURL,
            partition: partition,
            isEnabled: pin.iconAsset == nil,
            disabledID: pin.id.uuidString
        )
    }

    private func loadStoredFaviconIfNeeded() async {
        guard case .shortcut(let pin, _, let partition) = icon,
              pin.iconAsset == nil
        else { return }

        await faviconImageStore.load(
            launchURL: pin.launchURL,
            partition: partition
        )
    }
}

private struct SidebarFolderPreviewSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let previousFirstResponder: PreviousFirstResponder
    let onKeyCommand: (SidebarFolderPreviewKeyCommand) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            previousFirstResponder: previousFirstResponder,
            onKeyCommand: onKeyCommand
        )
    }

    /// Hand the keyboard back only if this field still has it. A click on a
    /// sidebar row already made that row first responder, and stealing it back
    /// would break the gesture it just started.
    static func dismantleNSView(_ nsView: NSTextField, coordinator: Coordinator) {
        coordinator.restoreFocusIfHeld(by: nsView)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(frame: .zero)
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.controlSize = .small
        field.lineBreakMode = .byTruncatingTail
        field.font = .systemFont(ofSize: 13, weight: .regular)
        field.placeholderString = placeholder
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onKeyCommand = onKeyCommand
        nsView.placeholderString = placeholder
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        context.coordinator.focusIfNeeded(nsView)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onKeyCommand: (SidebarFolderPreviewKeyCommand) -> Bool
        private let previousFirstResponder: PreviousFirstResponder
        private var didFocus = false
        private var didAttemptFocus = false

        init(
            text: Binding<String>,
            previousFirstResponder: PreviousFirstResponder,
            onKeyCommand: @escaping (SidebarFolderPreviewKeyCommand) -> Bool
        ) {
            self.text = text
            self.previousFirstResponder = previousFirstResponder
            self.onKeyCommand = onKeyCommand
        }

        func restoreFocusIfHeld(by field: NSTextField) {
            guard didFocus,
                  let window = field.window,
                  fieldHoldsFocus(field, in: window)
            else { return }

            if let responder = previousFirstResponder.responder,
               (responder as? NSView)?.window ?? window === window,
               window.makeFirstResponder(responder) {
                return
            }
            _ = window.makeFirstResponder(nil)
        }

        /// The field editor, not the field, is first responder while editing.
        private func fieldHoldsFocus(_ field: NSTextField, in window: NSWindow) -> Bool {
            switch window.firstResponder {
            case let responder where responder === field:
                return true
            case let textView as NSTextView:
                return textView.isFieldEditor && textView.delegate === field
            default:
                return false
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            updateText(field.stringValue)
        }

        /// The field editor owns key input once the field is editing, so list
        /// navigation has to arrive as edit commands rather than raw key codes.
        func control(
            _: NSControl,
            textView _: NSTextView,
            doCommandBy selector: Selector
        ) -> Bool {
            guard let command = Self.command(for: selector) else { return false }
            return onKeyCommand(command)
        }

        private static func command(for selector: Selector) -> SidebarFolderPreviewKeyCommand? {
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                return .moveUp
            case #selector(NSResponder.moveDown(_:)):
                return .moveDown
            // Zen cycles the list with Tab and back-cycles with Shift-Tab.
            case #selector(NSResponder.insertBacktab(_:)):
                return .moveUp
            case #selector(NSResponder.insertTab(_:)):
                return .moveDown
            case #selector(NSResponder.insertNewline(_:)):
                return .accept
            case #selector(NSResponder.cancelOperation(_:)):
                return .cancel
            default:
                return nil
            }
        }

        /// Zen focuses and selects the search input as soon as the popup shows.
        ///
        /// Exactly one attempt, made once the field is on screen. The panel opens
        /// on a hover timer that can land in the middle of a click on the folder
        /// header underneath, and taking first responder then installs a field
        /// editor across that gesture — enough to drop the row's `mouseUp`.
        /// A press in flight therefore forfeits autofocus for this presentation
        /// rather than being retried until the button comes up, which put the
        /// steal right at the end of the click instead of avoiding it.
        func focusIfNeeded(_ field: NSTextField) {
            guard !didFocus, !didAttemptFocus else { return }
            DispatchQueue.main.async { [weak self, weak field] in
                guard let self,
                      let field,
                      !self.didFocus,
                      !self.didAttemptFocus,
                      // No window yet: a later update makes the attempt instead.
                      let window = field.window
                else { return }

                self.didAttemptFocus = true
                guard NSEvent.pressedMouseButtons == 0 else { return }

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
}
