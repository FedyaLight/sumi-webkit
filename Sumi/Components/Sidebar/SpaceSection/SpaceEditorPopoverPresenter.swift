import AppKit

@MainActor
final class SpaceEditorSession {
    let spaceID: UUID
    let originalName: String
    let originalIcon: String
    let originalProfileID: UUID?

    var name: String
    var icon: String
    var profileID: UUID?
    var cancelsOnDismiss = false

    init(space: Space) {
        spaceID = space.id
        originalName = space.name
        originalIcon = space.icon
        originalProfileID = space.profileId
        name = space.name
        icon = space.icon
        profileID = space.profileId
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canCommit: Bool {
        !trimmedName.isEmpty
    }

    var hasChanges: Bool {
        trimmedName != originalName
            || icon != originalIcon
            || profileID != originalProfileID
    }
}

@MainActor
private final class SpaceEditorViewController: NSViewController, NSTextFieldDelegate {
    private let session: SpaceEditorSession
    private let profiles: [Profile]
    private let settings: SumiSettingsService
    private let themeContext: ResolvedThemeContext
    private let onDone: () -> Void
    private let onCancel: () -> Void

    private let emojiPicker = EmojiPickerManager()
    private let iconButton = NSButton()
    private let nameField = NSTextField()
    private let profilePicker = NSPopUpButton()
    private let validationLabel = NSTextField(labelWithString: "Enter a name.")
    private let doneButton = NSButton()

    init(
        session: SpaceEditorSession,
        profiles: [Profile],
        settings: SumiSettingsService,
        themeContext: ResolvedThemeContext,
        onDone: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.session = session
        self.profiles = profiles
        self.settings = settings
        self.themeContext = themeContext
        self.onDone = onDone
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(
            frame: NSRect(
                origin: .zero,
                size: SpaceEditorPopoverPresenter.Metrics.contentSize(profileCount: profiles.count)
            )
        )
        view.setAccessibilityIdentifier("space-editor-popover")
        configureControls()
        installLayout()
        updateValidation()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(nameField)
    }

    func controlTextDidChange(_ obj: Notification) {
        session.name = nameField.stringValue
        updateValidation()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            done()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancel()
            return true
        }
        return false
    }

    private func configureControls() {
        iconButton.target = self
        iconButton.action = #selector(changeIcon)
        iconButton.bezelStyle = .rounded
        iconButton.imageScaling = .scaleProportionallyDown
        iconButton.setAccessibilityLabel("Change Icon")
        iconButton.toolTip = "Change Icon"
        iconButton.translatesAutoresizingMaskIntoConstraints = false
        emojiPicker.anchorView = iconButton
        updateIconButton()

        nameField.stringValue = session.name
        nameField.placeholderString = "Name"
        nameField.delegate = self
        nameField.setAccessibilityIdentifier("space-editor-name-field")

        profilePicker.target = self
        profilePicker.action = #selector(changeProfile)
        profilePicker.controlSize = .regular
        profilePicker.setAccessibilityIdentifier("space-editor-profile-picker")
        configureProfilePicker()

        validationLabel.textColor = .systemRed
        validationLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        validationLabel.maximumNumberOfLines = 1

        doneButton.title = "Done"
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        doneButton.target = self
        doneButton.action = #selector(done)

        let cancelButton = NSButton(
            title: "Cancel",
            target: self,
            action: #selector(cancel)
        )
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.setAccessibilityIdentifier("space-editor-cancel-button")
        cancelButton.setContentHuggingPriority(.required, for: .horizontal)
        doneButton.setContentHuggingPriority(.required, for: .horizontal)

        buttonRow = NSStackView(views: [validationLabel, NSView(), cancelButton, doneButton])
    }

    private var buttonRow: NSStackView!

    private func installLayout() {
        let titleRow = NSStackView(views: [iconButton, nameField])
        titleRow.orientation = .horizontal
        titleRow.spacing = 8
        titleRow.alignment = .centerY

        let profileLabel = NSTextField(labelWithString: "Profile")
        profileLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        profileLabel.textColor = .secondaryLabelColor

        let profileRow = NSStackView(views: [profileLabel, profilePicker])
        profileRow.orientation = .horizontal
        profileRow.spacing = 8
        profileRow.alignment = .centerY

        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.alignment = .centerY
        buttonRow.views[1].setContentHuggingPriority(.defaultLow, for: .horizontal)

        var stackViews: [NSView] = [titleRow]
        if profiles.count > 1 {
            stackViews.append(profileRow)
        }
        stackViews.append(buttonRow)
        let stack = NSStackView(views: stackViews)
        stack.orientation = .vertical
        stack.spacing = 12
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate(
            [
                iconButton.widthAnchor.constraint(equalToConstant: 30),
                iconButton.heightAnchor.constraint(equalToConstant: 30),
                nameField.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),
                profilePicker.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
                titleRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
                buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
                stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
                stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
                stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
                stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),
            ]
        )

        if profiles.count > 1 {
            profileRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private func configureProfilePicker() {
        profilePicker.removeAllItems()
        for profile in profiles {
            profilePicker.addItem(withTitle: profile.name)
            profilePicker.lastItem?.representedObject = profile.id
            let icon = SumiProfileIcon.storedValue(profile.icon)
            profilePicker.lastItem?.image = SidebarContextMenuImageStore.image(
                for: SidebarContextMenuIcon.emoji(icon)
            )
        }

        if let selectedIndex = profiles.firstIndex(where: { $0.id == session.profileID }) {
            profilePicker.selectItem(at: selectedIndex)
        } else if profiles.isEmpty == false {
            profilePicker.selectItem(at: 0)
        }
        profilePicker.isEnabled = profiles.count > 1
    }

    private func updateIconButton() {
        let icon = SumiPersistentGlyph.normalizedSpaceIconValue(session.icon)
        if SumiPersistentGlyph.presentsAsEmoji(icon) {
            iconButton.title = icon
            iconButton.image = nil
            iconButton.imagePosition = .noImage
            iconButton.font = .systemFont(ofSize: 16)
            return
        }

        iconButton.title = ""
        iconButton.image = NSImage(
            systemSymbolName: SumiPersistentGlyph.resolvedSpaceSystemImageName(icon),
            accessibilityDescription: "Change Icon"
        )
        iconButton.imagePosition = .imageOnly
    }

    private func updateValidation() {
        let canCommit = !nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        validationLabel.isHidden = canCommit
        doneButton.isEnabled = canCommit
    }

    @objc private func changeIcon() {
        emojiPicker.selectedEmoji = SumiPersistentGlyph.presentsAsEmoji(session.icon)
            ? session.icon
            : ""
        emojiPicker.toggle(
            settings: settings,
            themeContext: themeContext
        ) { [weak self] picked in
            guard let self else { return }
            self.session.icon = SumiPersistentGlyph.normalizedSpaceIconValue(picked)
            self.updateIconButton()
        }
    }

    @objc private func changeProfile() {
        session.profileID = profilePicker.selectedItem?.representedObject as? UUID
    }

    @objc private func done() {
        session.name = nameField.stringValue
        updateValidation()
        guard session.canCommit else { return }
        onDone()
    }

    @objc private func cancel() {
        onCancel()
    }
}

@MainActor
struct SpaceEditorPopoverPresentationContext {
    let sidebarPosition: SidebarPosition
    let profiles: [Profile]
    let settings: SumiSettingsService
    let commit: @MainActor (SpaceEditorSession) -> Void
}

@MainActor
final class SpaceEditorPopoverPresenter: NSObject, NSPopoverDelegate {
    enum Metrics {
        static let fullContentSize = NSSize(width: 340, height: 144)
        static let compactContentSize = NSSize(width: 340, height: 104)
        static func contentSize(profileCount: Int) -> NSSize {
            profileCount > 1 ? fullContentSize : compactContentSize
        }
    }

    private final class ActiveSession {
        let editorSession: SpaceEditorSession
        let popover: NSPopover
        weak var windowState: BrowserWindowState?
        let commit: @MainActor (SpaceEditorSession) -> Void
        let source: SidebarTransientPresentationSource
        let transientSessionToken: SidebarTransientSessionToken?
        var closeFallbackTask: Task<Void, Never>?
        var isClosing = false

        init(
            editorSession: SpaceEditorSession,
            popover: NSPopover,
            windowState: BrowserWindowState,
            commit: @escaping @MainActor (SpaceEditorSession) -> Void,
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
        space: Space,
        in windowState: BrowserWindowState,
        themeContext: ResolvedThemeContext,
        presentationContext: SpaceEditorPopoverPresentationContext,
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

        let editorSession = SpaceEditorSession(space: space)
        let surfaceThemeContext = themeContext.nativeSurfaceThemeContext
        let surfaceColorScheme = surfaceThemeContext.nativeSurfaceColorScheme
        let profiles = presentationContext.profiles
        let viewController = SpaceEditorViewController(
            session: editorSession,
            profiles: profiles,
            settings: presentationContext.settings,
            themeContext: surfaceThemeContext,
            onDone: { [weak self] in
                self?.closeActive(committing: true)
            },
            onCancel: { [weak self, weak editorSession] in
                editorSession?.cancelsOnDismiss = true
                self?.closeActive(committing: false)
            }
        )

        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = viewController
        popover.contentSize = Self.Metrics.contentSize(profileCount: profiles.count)
        popover.appearance = PopoverPresenterChromeSupport.appearance(
            for: surfaceColorScheme,
            fallback: anchor.view.window?.effectiveAppearance ?? windowState.window?.effectiveAppearance
        )

        let token = source.coordinator?.beginSession(
            kind: .spaceEditorPopover,
            source: source,
            path: "SpaceEditorPopoverPresenter.present"
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
        popover.show(relativeTo: anchor.rect, of: anchor.view, preferredEdge: anchor.preferredEdge)
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

        finishClosedSession(activeSession, reason: "SpaceEditorPopoverPresenter.popoverDidClose")
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
                self.finishClosedSession(activeSession, reason: "SpaceEditorPopoverPresenter.closeFallback")
            },
            onNotShown: { [weak self, weak activeSession] in
                guard let self, let activeSession else { return }
                self.finishClosedSession(activeSession, reason: "SpaceEditorPopoverPresenter.closeNotShown")
            }
        )
    }

    private func finishClosedSession(_ closedSession: ActiveSession, reason: String) {
        guard activeSession === closedSession else { return }

        activeSession = nil
        closedSession.closeFallbackTask?.cancel()

        let finalize: () -> Void = {
            guard !closedSession.editorSession.cancelsOnDismiss else { return }
            closedSession.commit(closedSession.editorSession)
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
