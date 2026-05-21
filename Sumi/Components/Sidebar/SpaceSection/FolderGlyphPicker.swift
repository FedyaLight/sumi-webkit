//
//  FolderGlyphPicker.swift
//  Sumi
//

import AppKit
import SwiftUI

@MainActor
final class FolderGlyphPickerManager: NSObject, ObservableObject {
    var popover: NSPopover?
    weak var anchorView: NSView?
    var sidebarRecoveryCoordinator: SidebarHostRecoveryHandling = SidebarHostRecoveryCoordinator.shared

    @Published var selectedIcon: String = ""
    @Published var committedIcon: String = ""

    private let pickerViewModel = FolderGlyphPickerViewModel()
    private var hostingController: NSHostingController<AnyView>?
    private var activeCommitHandler: ((String) -> Void)?
    private var activeSettings: SumiSettingsService?
    private var activeThemeContext: ResolvedThemeContext?
    private var didSelectIcon = false

    func toggle(
        settings: SumiSettingsService? = nil,
        themeContext: ResolvedThemeContext? = nil,
        onCommit: ((String) -> Void)? = nil
    ) {
        guard let anchorView else { return }

        if popover?.isShown == true {
            popover?.close()
            return
        }

        committedIcon = ""
        didSelectIcon = false
        activeCommitHandler = onCommit
        activeSettings = settings
        activeThemeContext = themeContext
        ensureHostingController()
        pickerViewModel.resetForOpen(currentIcon: selectedIcon)

        if popover == nil {
            let pop = NSPopover()
            pop.contentViewController = hostingController
            pop.behavior = .semitransient
            pop.delegate = self
            pop.contentSize = NSSize(
                width: SumiEmojiPickerMetrics.popoverWidth,
                height: SumiEmojiPickerMetrics.popoverHeight
            )
            pop.animates = true
            popover = pop
        }

        popover?.contentSize = NSSize(
            width: SumiEmojiPickerMetrics.popoverWidth,
            height: SumiEmojiPickerMetrics.popoverHeight
        )
        popover?.appearance = anchorView.window?.effectiveAppearance

        guard let window = anchorView.window,
              let screen = window.screen
        else {
            popover?.show(
                relativeTo: anchorView.bounds,
                of: anchorView,
                preferredEdge: .minY
            )
            return
        }

        let anchorFrameInWindow = anchorView.convert(anchorView.bounds, to: nil)
        let anchorFrameInScreen = window.convertToScreen(anchorFrameInWindow)

        let popoverWidth = SumiEmojiPickerMetrics.popoverWidth
        let screenFrame = screen.visibleFrame

        var positioningRect = anchorView.bounds

        let rightEdge = anchorFrameInScreen.maxX
        let leftEdge = anchorFrameInScreen.minX

        if rightEdge + popoverWidth > screenFrame.maxX {
            let overflow = (rightEdge + popoverWidth) - screenFrame.maxX
            positioningRect.origin.x -= overflow
        } else if leftEdge < screenFrame.minX {
            let overflow = screenFrame.minX - leftEdge
            positioningRect.origin.x += overflow
        }

        popover?.show(
            relativeTo: positioningRect,
            of: anchorView,
            preferredEdge: .maxY
        )
    }

    private func ensureHostingController() {
        let panel = makePanel()
        if let hostingController {
            hostingController.rootView = panel
            return
        }

        let hosting = NSHostingController(rootView: panel)
        hosting.view.frame = NSRect(
            x: 0,
            y: 0,
            width: SumiEmojiPickerMetrics.popoverWidth,
            height: SumiEmojiPickerMetrics.popoverHeight
        )
        hostingController = hosting
    }

    private func makePanel() -> AnyView {
        let panel = FolderGlyphPickerPanel(
            model: pickerViewModel,
            onIconSelected: { [weak self] icon in
                DispatchQueue.main.async { [weak self] in
                    self?.didSelectIcon = true
                    self?.selectedIcon = icon
                }
            }
        )

        if let activeSettings, let activeThemeContext {
            return AnyView(
                panel
                    .environment(\.sumiSettings, activeSettings)
                    .environment(\.resolvedThemeContext, activeThemeContext)
            )
        }

        if let activeSettings {
            return AnyView(panel.environment(\.sumiSettings, activeSettings))
        }

        return AnyView(panel)
    }
}

extension FolderGlyphPickerManager: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        let selectedIconForCommit = selectedIcon
        let shouldCommitSelection = didSelectIcon

        if shouldCommitSelection {
            if let activeCommitHandler {
                activeCommitHandler(selectedIconForCommit)
            } else {
                committedIcon = selectedIconForCommit
            }
        }

        let window = anchorView?.window
        sidebarRecoveryCoordinator.recover(in: window)
        sidebarRecoveryCoordinator.recover(anchor: anchorView)

        activeCommitHandler = nil
        didSelectIcon = false
    }
}

struct FolderGlyphPickerAnchor: NSViewRepresentable {
    let manager: FolderGlyphPickerManager

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        manager.anchorView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

@MainActor
private final class FolderGlyphPickerViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var debouncedSearch = ""
    @Published var currentIcon: String = ""

    private var debounceTask: Task<Void, Never>?

    func resetForOpen(currentIcon: String) {
        debounceTask?.cancel()
        debounceTask = nil
        searchText = ""
        debouncedSearch = ""
        self.currentIcon = SumiZenFolderIconCatalog.normalizedFolderIconValue(currentIcon)
    }

    func setSearchText(_ value: String) {
        searchText = value
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == debouncedSearch {
            debounceTask?.cancel()
            debounceTask = nil
            return
        }
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: SumiEmojiPickerMetrics.searchDebounce)
            guard !Task.isCancelled else { return }
            debouncedSearch = normalized
        }
    }
}

private struct FolderGlyphPickerPanel: View {
    @ObservedObject var model: FolderGlyphPickerViewModel
    let onIconSelected: (String) -> Void

    @State private var displayedEntries: [FolderGlyphPickerEntry] = FolderGlyphPickerCatalog.allEntries

    private let columns = [GridItem(.adaptive(minimum: 36), spacing: 4)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FolderGlyphSearchField(
                text: Binding(
                    get: { model.searchText },
                    set: { model.setSearchText($0) }
                ),
                placeholder: "Search icons..."
            )
            .accessibilityIdentifier("folder-glyph-picker-search")

            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    FolderGlyphResetGridCell(
                        isSelected: model.currentIcon.isEmpty,
                        onTap: {
                            model.currentIcon = ""
                            onIconSelected("")
                        }
                    )

                    ForEach(displayedEntries) { entry in
                        FolderGlyphGridCell(
                            entry: entry,
                            isSelected: entry.storageValue == model.currentIcon,
                            onTap: {
                                model.currentIcon = entry.storageValue
                                onIconSelected(entry.storageValue)
                            }
                        )
                    }
                }
                .padding(.bottom, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .frame(width: SumiEmojiPickerMetrics.popoverWidth, height: SumiEmojiPickerMetrics.popoverHeight)
        .background(FloatingChromeSurfaceFill(.panel))
        .modifier(FolderGlyphPickerAppearModifier())
        .accessibilityIdentifier("folder-glyph-picker-panel")
        .onAppear {
            displayedEntries = FolderGlyphPickerCatalog.entries(
                matching: model.debouncedSearch,
                in: FolderGlyphPickerCatalog.allEntries
            )
        }
        .onChange(of: model.debouncedSearch) { _, newValue in
            displayedEntries = FolderGlyphPickerCatalog.entries(
                matching: newValue,
                in: FolderGlyphPickerCatalog.allEntries
            )
        }
    }
}

private struct FolderGlyphSearchField: View {
    @Binding var text: String
    let placeholder: String

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @FocusState private var isFocused: Bool

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    private var fieldFont: Font {
        .system(size: 13)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tokens.secondaryText)
                .frame(width: 14, height: 14)

            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(fieldFont)
                        .foregroundStyle(tokens.secondaryText)
                        .lineLimit(1)
                        .allowsHitTesting(false)
                }

                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(fieldFont)
                    .foregroundStyle(tokens.primaryText)
                    .tint(tokens.accent)
                    .focused($isFocused)
                    .accessibilityLabel(placeholder)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(tokens.floatingBarChipBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isFocused ? tokens.accent.opacity(0.82) : tokens.separator.opacity(0.72),
                    lineWidth: isFocused ? 1.5 : 1
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(.easeInOut(duration: 0.14), value: isFocused)
    }
}

private struct FolderGlyphPickerAppearModifier: ViewModifier {
    @State private var presented = false

    func body(content: Content) -> some View {
        content
            .opacity(presented ? 1 : 0)
            .scaleEffect(presented ? 1 : SumiEmojiPickerMetrics.appearScale, anchor: .top)
            .offset(y: presented ? 0 : SumiEmojiPickerMetrics.appearOffsetY)
            .onAppear {
                presented = false
                DispatchQueue.main.async {
                    withAnimation(
                        .spring(
                            response: SumiEmojiPickerMetrics.appearSpringResponse,
                            dampingFraction: SumiEmojiPickerMetrics.appearSpringDamping
                        )
                    ) {
                        presented = true
                    }
                }
            }
            .onDisappear {
                withAnimation(.easeOut(duration: SumiEmojiPickerMetrics.disappearEaseDuration)) {
                    presented = false
                }
            }
    }
}

private struct FolderGlyphGridCell: View {
    let entry: FolderGlyphPickerEntry
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var hovering = false

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if let image = SumiZenFolderIconCatalog.bundledFolderImage(named: entry.iconName) {
                    SumiZenBundledIconView(
                        image: image,
                        size: 21,
                        tint: tokens.primaryText
                    )
                } else {
                    Image(systemName: "folder")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(tokens.primaryText)
                }
            }
            .frame(width: 34, height: 34)
            .background(cellBackground)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(entry.displayName)
        .accessibilityLabel(entry.displayName)
    }

    private var cellBackground: Color {
        if isSelected {
            Color(nsColor: .selectedContentBackgroundColor).opacity(0.55)
        } else if hovering {
            Color(nsColor: .quaternaryLabelColor).opacity(0.45)
        } else {
            Color.clear
        }
    }
}

private struct FolderGlyphResetGridCell: View {
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var hovering = false

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "folder")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(tokens.secondaryText)
                .frame(width: 34, height: 34)
                .background(cellBackground)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Default Folder Icon")
        .accessibilityLabel("Default Folder Icon")
    }

    private var cellBackground: Color {
        if isSelected {
            Color(nsColor: .selectedContentBackgroundColor).opacity(0.55)
        } else if hovering {
            Color(nsColor: .quaternaryLabelColor).opacity(0.45)
        } else {
            Color.clear
        }
    }
}

private struct FolderGlyphPickerEntry: Identifiable, Hashable {
    let iconName: String
    let storageValue: String
    let displayName: String
    let searchHaystack: String

    var id: String { iconName }
}

private enum FolderGlyphPickerCatalog {
    static let allEntries: [FolderGlyphPickerEntry] = SumiZenFolderIconCatalog
        .bundledFolderIconNames()
        .map { iconName in
            let displayName = Self.displayName(for: iconName)
            return FolderGlyphPickerEntry(
                iconName: iconName,
                storageValue: SumiZenFolderIconCatalog.storageValue(for: iconName),
                displayName: displayName,
                searchHaystack: "\(iconName) \(displayName)".lowercased()
            )
        }

    static func entries(
        matching query: String,
        in entries: [FolderGlyphPickerEntry]
    ) -> [FolderGlyphPickerEntry] {
        let queryTokens = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split { $0.isWhitespace }
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !queryTokens.isEmpty else { return entries }

        return entries.filter { entry in
            queryTokens.allSatisfy { entry.searchHaystack.contains($0) }
        }
    }

    private static func displayName(for iconName: String) -> String {
        iconName
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: " 1", with: "")
            .capitalized
    }
}
