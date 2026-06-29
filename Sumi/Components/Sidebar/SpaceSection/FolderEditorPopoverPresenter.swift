import AppKit
import SwiftUI

@MainActor
final class FolderEditorSession: ObservableObject, Identifiable {
    let id = UUID()
    let folderID: UUID
    let originalName: String
    let originalIcon: String

    @Published var name: String
    @Published var icon: String
    var cancelsOnDismiss = false

    init(folder: TabFolder) {
        folderID = folder.id
        originalName = folder.name
        originalIcon = folder.icon
        name = folder.name
        icon = folder.icon
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canCommit: Bool {
        !trimmedName.isEmpty
    }

    var hasChanges: Bool {
        trimmedName != originalName || icon != originalIcon
    }
}

struct FolderEditorPopover: View {
    @ObservedObject var session: FolderEditorSession
    let onDone: () -> Void
    let onCancel: () -> Void

    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                FolderEditorIconButton(icon: $session.icon)

                TextField("Name", text: $session.name)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFocused)
                    .onSubmit(doneIfPossible)
                    .accessibilityIdentifier("folder-editor-name-field")
            }

            HStack(spacing: 8) {
                if !session.canCommit {
                    Label("Enter a name.", systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])

                Button("Done", action: doneIfPossible)
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(!session.canCommit)
            }
        }
        .padding(14)
        .frame(width: FolderEditorPopoverPresenter.Metrics.contentSize.width)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("folder-editor-popover")
        .onAppear {
            isNameFocused = true
        }
    }

    private func doneIfPossible() {
        guard session.canCommit else { return }
        onDone()
    }
}

private struct FolderEditorIconButton: View {
    @Binding var icon: String

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @StateObject private var glyphPickerManager = FolderGlyphPickerManager()

    var body: some View {
        Button {
            toggleIconPicker()
        } label: {
            FolderEditorIconPreview(icon: icon)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .background(FolderGlyphPickerAnchor(manager: glyphPickerManager))
        .help("Change Icon")
        .accessibilityLabel("Change Icon")
    }

    private func toggleIconPicker() {
        glyphPickerManager.selectedIcon = SumiZenFolderIconCatalog.normalizedFolderIconValue(icon)
        glyphPickerManager.toggle(
            settings: sumiSettings,
            themeContext: themeContext
        ) { picked in
            icon = SumiZenFolderIconCatalog.normalizedFolderIconValue(picked)
        }
    }
}

private struct FolderEditorIconPreview: View {
    let icon: String

    var body: some View {
        ZStack {
            switch SumiZenFolderIconCatalog.resolveFolderIcon(icon) {
            case .bundled(let iconName):
                SumiZenBundledIconView(
                    image: SumiZenFolderIconCatalog.bundledFolderImage(named: iconName),
                    size: 18,
                    tint: .primary
                )
            case .none:
                Image(systemName: "folder")
                    .font(.system(size: 17, weight: .medium))
                    .symbolRenderingMode(.monochrome)
            }
        }
        .frame(width: 26, height: 26)
        .contentShape(Rectangle())
    }
}

@MainActor
struct FolderEditorPopoverPresentationContext {
    let sidebarPosition: SidebarPosition
    let settings: SumiSettingsService
    let commit: @MainActor (FolderEditorSession) -> Void
}

@MainActor
final class FolderEditorPopoverPresenter: NSObject, NSPopoverDelegate {
    enum Metrics {
        static let contentSize = NSSize(width: 320, height: 104)
    }

    private final class ActiveSession {
        let editorSession: FolderEditorSession
        let popover: NSPopover
        weak var windowState: BrowserWindowState?
        let commit: @MainActor (FolderEditorSession) -> Void
        let source: SidebarTransientPresentationSource
        let transientSessionToken: SidebarTransientSessionToken?
        var closeFallbackTask: Task<Void, Never>?
        var isClosing = false

        init(
            editorSession: FolderEditorSession,
            popover: NSPopover,
            windowState: BrowserWindowState,
            commit: @escaping @MainActor (FolderEditorSession) -> Void,
            source: SidebarTransientPresentationSource,
            transientSessionToken: SidebarTransientSessionToken?
        ) {
            self.editorSession = editorSession
            self.popover = popover
            self.windowState = windowState
            self.commit = commit
            self.source = source
            self.transientSessionToken = transientSessionToken
        }

        deinit {
            closeFallbackTask?.cancel()
        }
    }

    private var activeSession: ActiveSession?

    func present(
        folder: TabFolder,
        in windowState: BrowserWindowState,
        themeContext: ResolvedThemeContext,
        presentationContext: FolderEditorPopoverPresentationContext,
        source: SidebarTransientPresentationSource
    ) {
        if activeSession != nil {
            closeActive(committing: true)
            return
        }

        guard let anchor = resolvedPresentationAnchor(
            source: source,
            in: windowState,
            sidebarPosition: presentationContext.sidebarPosition
        ) else {
            return
        }

        let editorSession = FolderEditorSession(folder: folder)
        let surfaceThemeContext = themeContext.nativeSurfaceThemeContext
        let surfaceColorScheme = surfaceThemeContext.nativeSurfaceColorScheme
        let hostingController = NSHostingController(
            rootView: FolderEditorPopover(
                session: editorSession,
                onDone: { [weak self] in
                    self?.closeActive(committing: true)
                },
                onCancel: { [weak self, weak editorSession] in
                    editorSession?.cancelsOnDismiss = true
                    self?.closeActive(committing: false)
                }
            )
            .environment(windowState)
            .environment(\.sumiSettings, presentationContext.settings)
            .environment(\.resolvedThemeContext, surfaceThemeContext)
            .environment(\.colorScheme, surfaceColorScheme)
            .preferredColorScheme(surfaceColorScheme)
            .frame(
                width: Self.Metrics.contentSize.width,
                height: Self.Metrics.contentSize.height
            )
        )

        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = hostingController
        popover.contentSize = Self.Metrics.contentSize
        popover.appearance = PopoverPresenterChromeSupport.appearance(
            for: surfaceColorScheme,
            fallback: anchor.view.window?.effectiveAppearance ?? windowState.window?.effectiveAppearance
        )

        let token = source.coordinator?.beginSession(
            kind: .folderEditorPopover,
            source: source,
            path: "FolderEditorPopoverPresenter.present"
        )

        activeSession = ActiveSession(
            editorSession: editorSession,
            popover: popover,
            windowState: windowState,
            commit: presentationContext.commit,
            source: source,
            transientSessionToken: token
        )

        windowState.window?.makeKeyAndOrderFront(nil)
        popover.show(
            relativeTo: anchor.rect,
            of: anchor.view,
            preferredEdge: anchor.preferredEdge
        )
    }

    func closeActive(committing: Bool) {
        guard let activeSession else { return }
        activeSession.editorSession.cancelsOnDismiss = !committing
        closeActiveSession(activeSession)
    }

    func popoverDidClose(_ notification: Notification) {
        guard let popover = notification.object as? NSPopover,
              let activeSession,
              activeSession.popover === popover
        else { return }

        finishClosedSession(activeSession, reason: "FolderEditorPopoverPresenter.popoverDidClose")
    }

    private func closeActiveSession(_ activeSession: ActiveSession) {
        guard !activeSession.isClosing else { return }
        activeSession.isClosing = true

        PopoverPresenterChromeSupport.closePopoverWithFallback(
            popover: activeSession.popover,
            closeFallbackTask: &activeSession.closeFallbackTask,
            onFallback: { [weak self, weak activeSession] in
                guard let self,
                      let activeSession,
                      self.activeSession === activeSession
                else { return }

                self.finishClosedSession(
                    activeSession,
                    reason: "FolderEditorPopoverPresenter.closeFallback"
                )
            },
            onNotShown: { [weak self, weak activeSession] in
                guard let self, let activeSession else { return }
                self.finishClosedSession(activeSession, reason: "FolderEditorPopoverPresenter.closeNotShown")
            }
        )
    }

    private func finishClosedSession(
        _ closedSession: ActiveSession,
        reason: String
    ) {
        guard activeSession === closedSession else { return }

        activeSession = nil
        closedSession.closeFallbackTask?.cancel()

        let finalize: () -> Void = {
            if !closedSession.editorSession.cancelsOnDismiss {
                closedSession.commit(closedSession.editorSession)
            }
        }

        if let coordinator = closedSession.source.coordinator {
            coordinator.finishSession(
                closedSession.transientSessionToken,
                reason: reason,
                teardown: finalize
            )
        } else {
            finalize()
            WorkspaceThemePickerPopoverPresenter.performUncoordinatedSidebarDismissRecovery(
                windowState: closedSession.windowState,
                source: closedSession.source,
                anchor: closedSession.source.originOwnerView,
                using: SidebarHostRecoveryCoordinator.shared
            )
        }
    }

    private func resolvedPresentationAnchor(
        source: SidebarTransientPresentationSource,
        in windowState: BrowserWindowState,
        sidebarPosition: SidebarPosition
    ) -> (view: NSView, rect: NSRect, preferredEdge: NSRectEdge)? {
        let preferredEdge: NSRectEdge = sidebarPosition == .left ? .maxX : .minX

        if let ownerView = source.originOwnerView,
           ownerView.window != nil,
           ownerView.superview != nil,
           !ownerView.isHiddenOrHasHiddenAncestor,
           ownerView.alphaValue > 0 {
            return (ownerView, ownerView.bounds, preferredEdge)
        }

        guard let contentView = windowState.window?.contentView ?? source.window?.contentView else {
            return nil
        }

        return (
            contentView,
            WorkspaceThemePickerPopoverPresenter.fallbackAnchorRect(
                in: contentView.bounds,
                isSidebarVisible: windowState.isSidebarVisible,
                sidebarWidth: windowState.sidebarWidth,
                savedSidebarWidth: windowState.savedSidebarWidth,
                sidebarPosition: sidebarPosition
            ),
            preferredEdge
        )
    }
}
