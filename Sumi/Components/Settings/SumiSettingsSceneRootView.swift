import AppKit
import Combine
import SwiftUI

struct SumiSettingsSceneRootView: View {
    @Environment(\.colorScheme) private var systemColorScheme

    let settings: SumiSettingsService
    let browserContext: SettingsBrowserContext
    let keyboardShortcutManager: KeyboardShortcutManager
    let updaterService: SumiUpdaterService
    let defaultBrowserService: SumiDefaultBrowserService

    var body: some View {
        let selectedPane = settings.currentSettingsTab
        let themeContext = systemThemeContext

        SumiSettingsSplitView(
            settings: settings,
            browserContext: browserContext,
            keyboardShortcutManager: keyboardShortcutManager,
            updaterService: updaterService,
            defaultBrowserService: defaultBrowserService,
            selectedPane: selectedPane,
            themeContext: themeContext
        )
        .frame(minWidth: 820, minHeight: 600)
        .ignoresSafeArea(.container, edges: .top)
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }

    /// Settings is an independent system window, so browser chrome lightness
    /// never overrides its AppKit appearance. The context only prevents hosted
    /// SwiftUI sections from falling back to Sumi's default dark environment.
    private var systemThemeContext: ResolvedThemeContext {
        var context = ResolvedThemeContext.default
        context.globalColorScheme = systemColorScheme
        context.chromeColorScheme = systemColorScheme
        context.sourceChromeColorScheme = systemColorScheme
        context.targetChromeColorScheme = systemColorScheme
        return context
    }
}

private struct SumiSettingsSplitView: NSViewControllerRepresentable {
    let settings: SumiSettingsService
    let browserContext: SettingsBrowserContext
    let keyboardShortcutManager: KeyboardShortcutManager
    let updaterService: SumiUpdaterService
    let defaultBrowserService: SumiDefaultBrowserService
    let selectedPane: SettingsTabs
    let themeContext: ResolvedThemeContext

    func makeNSViewController(context: Context) -> SumiSettingsSplitViewController {
        SumiSettingsSplitViewController(
            settings: settings,
            browserContext: browserContext,
            keyboardShortcutManager: keyboardShortcutManager,
            updaterService: updaterService,
            defaultBrowserService: defaultBrowserService,
            themeContext: themeContext
        )
    }

    func updateNSViewController(
        _ controller: SumiSettingsSplitViewController,
        context: Context
    ) {
        controller.update(selectedPane: selectedPane, themeContext: themeContext)
    }
}

@MainActor
private final class SumiSettingsSplitViewController: NSSplitViewController {
    private let settings: SumiSettingsService
    private let browserContext: SettingsBrowserContext
    private let keyboardShortcutManager: KeyboardShortcutManager
    private let updaterService: SumiUpdaterService
    private let defaultBrowserService: SumiDefaultBrowserService
    private let sidebarController: SumiSettingsSidebarViewController
    private let detailController = SumiSettingsDetailViewController()
    private let toolbarOwner = SettingsWindowToolbarOwner()
    private var hostingController: NSHostingController<AnyView>?
    private var profileUpdates: AnyCancellable?
    private var toolbarUpdates: AnyCancellable?
    private var selectedPane: SettingsTabs
    private var currentProfile: Profile?
    private var themeContext: ResolvedThemeContext

    init(
        settings: SumiSettingsService,
        browserContext: SettingsBrowserContext,
        keyboardShortcutManager: KeyboardShortcutManager,
        updaterService: SumiUpdaterService,
        defaultBrowserService: SumiDefaultBrowserService,
        themeContext: ResolvedThemeContext
    ) {
        self.settings = settings
        self.browserContext = browserContext
        self.keyboardShortcutManager = keyboardShortcutManager
        self.updaterService = updaterService
        self.defaultBrowserService = defaultBrowserService
        self.selectedPane = settings.currentSettingsTab
        self.currentProfile = browserContext.currentProfile()
        self.themeContext = themeContext
        self.sidebarController = SumiSettingsSidebarViewController(
            selectedPane: settings.currentSettingsTab
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        detailController.onNavigateBack = { [weak self] in
            self?.toolbarOwner.goBack()
        }
        detailController.onNavigateForward = { [weak self] in
            self?.toolbarOwner.goForward()
        }

        sidebarController.onSelect = { [weak self] pane in
            guard let self else { return }
            settings.currentSettingsTab = pane
            if pane == .privacy {
                settings.privacySettingsRoute = .overview
            }
            showDetail(for: pane)
        }

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
        sidebarItem.minimumThickness = 210
        sidebarItem.maximumThickness = 280
        sidebarItem.preferredThicknessFraction = 0.27
        sidebarItem.canCollapse = false
        addSplitViewItem(sidebarItem)

        let detailItem = NSSplitViewItem(viewController: detailController)
        detailItem.minimumThickness = 560
        addSplitViewItem(detailItem)

        profileUpdates = browserContext.currentProfileUpdates
            .receive(on: RunLoop.main)
            .sink { [weak self] profile in
                guard let self else { return }
                currentProfile = profile
                showDetail(for: selectedPane)
            }

        toolbarUpdates = toolbarOwner.$presentation
            .receive(on: RunLoop.main)
            .sink { [weak self] presentation in
                self?.applyToolbarPresentation(presentation)
            }

        showDetail(for: selectedPane)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        configureWindowIfNeeded()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        configureWindowIfNeeded()
    }

    func update(selectedPane: SettingsTabs, themeContext: ResolvedThemeContext) {
        let appearanceChanged = self.themeContext != themeContext
        self.themeContext = themeContext
        sidebarController.select(selectedPane)
        if self.selectedPane != selectedPane || appearanceChanged {
            self.selectedPane = selectedPane
            showDetail(for: selectedPane)
        }
    }

    private func showDetail(for pane: SettingsTabs) {
        selectedPane = pane
        toolbarOwner.showRoot(title: SettingsPaneDescriptor.descriptor(for: pane).title)
        let root = AnyView(
            SumiSettingsDetailRoot(
                pane: pane,
                browserContext: browserContext,
                activeProfile: currentProfile,
                keyboardShortcutManager: keyboardShortcutManager,
                updaterService: updaterService,
                defaultBrowserService: defaultBrowserService
            )
            .environment(\.sumiSettings, settings)
            .environment(\.sumiModuleRegistry, browserContext.moduleRegistry)
            .environment(\.sumiProtectionCoordinator, browserContext.protectionCoordinator)
            .environment(\.sumiExtensionsModule, browserContext.extensionsModule)
            .environment(\.sumiBoostsModule, browserContext.boostsModule)
            .environment(keyboardShortcutManager)
            .environmentObject(toolbarOwner)
            .environment(\.resolvedThemeContext, themeContext)
            .environment(\.colorScheme, themeContext.globalColorScheme)
        )

        if let hostingController {
            hostingController.rootView = root
            return
        }

        let host = NSHostingController(rootView: root)
        detailController.addChild(host)
        detailController.contentView.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: detailController.contentView.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: detailController.contentView.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: detailController.contentView.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: detailController.contentView.bottomAnchor),
        ])
        hostingController = host
    }

    private func configureWindowIfNeeded() {
        guard let window = view.window else { return }
        window.title = String(localized: "Sumi Settings")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        window.tabbingMode = .disallowed
        window.styleMask.insert(.fullSizeContentView)
        window.styleMask.insert(.miniaturizable)
        window.styleMask.insert(.resizable)
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = true
        applyToolbarPresentation(toolbarOwner.presentation)
    }

    private func applyToolbarPresentation(
        _ presentation: SettingsWindowToolbarOwner.Presentation
    ) {
        detailController.apply(presentation)
    }
}

@MainActor
private final class SumiSettingsDetailViewController: NSViewController {
    let contentView = NSView()
    var onNavigateBack: (() -> Void)?
    var onNavigateForward: (() -> Void)?

    private let headerView = NSVisualEffectView()
    private let navigationControl = NSSegmentedControl()
    private let titleLabel = NSTextField(labelWithString: "")

    override func loadView() {
        let rootView = NSView()
        view = rootView

        headerView.material = .headerView
        headerView.blendingMode = .withinWindow
        headerView.state = .followsWindowActiveState
        headerView.translatesAutoresizingMaskIntoConstraints = false

        navigationControl.segmentCount = 2
        navigationControl.trackingMode = .momentary
        navigationControl.segmentStyle = .automatic
        navigationControl.controlSize = .regular
        navigationControl.target = self
        navigationControl.action = #selector(navigate(_:))
        navigationControl.setImage(
            NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back"),
            forSegment: 0
        )
        navigationControl.setImage(
            NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Forward"),
            forSegment: 1
        )
        navigationControl.setToolTip(String(localized: "Back"), forSegment: 0)
        navigationControl.setToolTip(String(localized: "Forward"), forSegment: 1)
        navigationControl.setWidth(30, forSegment: 0)
        navigationControl.setWidth(30, forSegment: 1)

        titleLabel.font = .systemFont(ofSize: 13, weight: .bold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let headerStack = NSStackView(views: [navigationControl, titleLabel])
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 12
        headerStack.detachesHiddenViews = true
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        contentView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(headerView)
        headerView.addSubview(headerStack)
        headerView.addSubview(separator)
        rootView.addSubview(contentView)

        NSLayoutConstraint.activate([
            headerView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            headerView.topAnchor.constraint(equalTo: rootView.topAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 52),

            headerStack.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 18),
            headerStack.trailingAnchor.constraint(lessThanOrEqualTo: headerView.trailingAnchor, constant: -8),
            headerStack.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            separator.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),

            contentView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            contentView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
        ])
    }

    func apply(_ presentation: SettingsWindowToolbarOwner.Presentation) {
        loadViewIfNeeded()
        titleLabel.stringValue = presentation.title
        navigationControl.setEnabled(presentation.canGoBack, forSegment: 0)
        navigationControl.setEnabled(presentation.canGoForward, forSegment: 1)
        navigationControl.isHidden = presentation.canGoBack == false
            && presentation.canGoForward == false
    }

    @objc private func navigate(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0:
            onNavigateBack?()
        case 1:
            onNavigateForward?()
        default:
            break
        }
    }
}

private struct SumiSettingsDetailRoot: View {
    let pane: SettingsTabs
    let browserContext: SettingsBrowserContext
    let activeProfile: Profile?
    let keyboardShortcutManager: KeyboardShortcutManager
    let updaterService: SumiUpdaterService
    let defaultBrowserService: SumiDefaultBrowserService

    var body: some View {
        ScrollView {
            SumiSettingsPaneContent(
                pane: pane,
                browserContext: browserContext,
                activeProfile: activeProfile,
                keyboardShortcutManager: keyboardShortcutManager,
                updaterService: updaterService,
                defaultBrowserService: defaultBrowserService
            )
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 30)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SumiSettingsPaneContent: View {
    let pane: SettingsTabs
    let browserContext: SettingsBrowserContext
    let activeProfile: Profile?
    let keyboardShortcutManager: KeyboardShortcutManager
    let updaterService: SumiUpdaterService
    let defaultBrowserService: SumiDefaultBrowserService

    @ViewBuilder
    var body: some View {
        switch pane {
        case .appearance:
            SettingsAppearanceTab()
        case .general:
            SettingsGeneralTab(defaultBrowserService: defaultBrowserService)
        case .startup:
            SettingsStartupTab()
        case .downloads:
            SettingsDownloadsTab()
        case .performance:
            SettingsPerformanceTab()
        case .privacy:
            PrivacySettingsView(
                repository: browserContext.makePermissionRepository(),
                activeProfile: activeProfile
            )
        case .profiles:
            SumiProfilesSettingsPane(
                profileManager: browserContext.profileManager,
                profileInventory: browserContext.profileInventory,
                requestProfileDeletion: browserContext.requestProfileDeletion
            )
        case .shortcuts:
            ShortcutsSettingsView(shortcutManager: keyboardShortcutManager)
        case .extensions:
            SumiExtensionsSettingsPane(
                extensionsModule: browserContext.extensionsModule,
                currentProfileID: activeProfile?.id,
                extensionSurfaceStore: browserContext.extensionSurfaceStore
            )
        case .advanced:
            SumiDataRecoverySettingsPane(actions: browserContext.dataRecoveryActions)
        case .about:
            SettingsAboutTab(updaterService: updaterService)
        }
    }
}

@MainActor
private final class SumiSettingsSidebarViewController: NSViewController,
    NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private enum Item {
        case pane(SettingsPaneDescriptor)
        case spacer
    }

    var onSelect: ((SettingsTabs) -> Void)?

    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private var items: [Item] = []
    private var selectedPane: SettingsTabs
    private var suppressesSelectionCallback = false

    init(selectedPane: SettingsTabs) {
        self.selectedPane = selectedPane
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let sidebarView = NSVisualEffectView()
        sidebarView.material = .sidebar
        sidebarView.blendingMode = .behindWindow
        sidebarView.state = .followsWindowActiveState
        view = sidebarView

        searchField.placeholderString = String(localized: "Search Settings")
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("settings"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowSizeStyle = .medium
        tableView.style = .sourceList
        tableView.dataSource = self
        tableView.delegate = self

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(searchField)
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            searchField.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        reload(query: "")
    }

    func controlTextDidChange(_ notification: Notification) {
        reload(query: searchField.stringValue)
    }

    func select(_ pane: SettingsTabs) {
        selectedPane = pane
        selectCurrentPane()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard items.indices.contains(row) else { return 30 }
        if case .spacer = items[row] {
            return 12
        }
        return 30
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard items.indices.contains(row) else { return false }
        if case .spacer = items[row] {
            return false
        }
        return true
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard items.indices.contains(row) else { return nil }
        guard case .pane(let descriptor) = items[row] else {
            return NSView()
        }
        let identifier = NSUserInterfaceItemIdentifier("SettingsPane")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? makePaneCell(identifier: identifier)
        cell.textField?.stringValue = descriptor.title
        cell.imageView?.image = NSImage(
            systemSymbolName: descriptor.icon,
            accessibilityDescription: descriptor.title
        )
        cell.imageView?.contentTintColor = .controlAccentColor
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard suppressesSelectionCallback == false else { return }
        guard tableView.selectedRow >= 0,
              items.indices.contains(tableView.selectedRow),
              case .pane(let descriptor) = items[tableView.selectedRow]
        else { return }
        let pane = descriptor.tab
        selectedPane = pane
        onSelect?(pane)
    }

    private func reload(query: String) {
        let descriptors = SettingsPaneDescriptor.filtered(by: query)
        let groups = SettingsPaneGroup.allCases.compactMap { group -> [SettingsPaneDescriptor]? in
            let panes = descriptors.filter { $0.group == group }
            return panes.isEmpty ? nil : panes
        }
        items = groups.enumerated().flatMap { index, panes in
            let rows = panes.map(Item.pane)
            return index == groups.startIndex ? rows : [.spacer] + rows
        }
        tableView.reloadData()
        selectCurrentPane()
    }

    private func selectCurrentPane() {
        suppressesSelectionCallback = true
        defer { suppressesSelectionCallback = false }
        if let row = items.firstIndex(where: { item in
            if case .pane(let descriptor) = item {
                return descriptor.tab == selectedPane
            }
            return false
        }) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            return
        }
        tableView.deselectAll(nil)
    }

    private func makePaneCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let imageView = NSImageView()
        imageView.symbolConfiguration = .init(pointSize: 15, weight: .medium)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.imageView = imageView
        cell.textField = label
        cell.addSubview(imageView)
        cell.addSubview(label)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 5),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 18),
            imageView.heightAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -5),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}

private struct SumiSettingsWindowActionInstaller: View {
    @Environment(\.openSettings) private var openSettings
    let navigation: SettingsNavigationOwner

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear {
                navigation.installPresentationAction {
                    openSettings()
                }
            }
    }
}

extension View {
    func installsSumiSettingsWindowAction(_ navigation: SettingsNavigationOwner) -> some View {
        background(SumiSettingsWindowActionInstaller(navigation: navigation))
    }
}
