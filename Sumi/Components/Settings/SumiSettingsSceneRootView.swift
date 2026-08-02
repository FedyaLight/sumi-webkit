import AppKit
import Combine
import SwiftUI

struct SumiSettingsSceneRootView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @StateObject private var toolbarOwner = SettingsWindowToolbarOwner()

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
            toolbarOwner: toolbarOwner,
            selectedPane: selectedPane,
            themeContext: themeContext
        )
        .frame(minWidth: 820, minHeight: 600)
        .ignoresSafeArea(.container, edges: .top)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .navigationTitle(toolbarOwner.presentation.title)
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
    let toolbarOwner: SettingsWindowToolbarOwner
    let selectedPane: SettingsTabs
    let themeContext: ResolvedThemeContext

    func makeNSViewController(context: Context) -> SumiSettingsSplitViewController {
        SumiSettingsSplitViewController(
            settings: settings,
            browserContext: browserContext,
            keyboardShortcutManager: keyboardShortcutManager,
            updaterService: updaterService,
            defaultBrowserService: defaultBrowserService,
            toolbarOwner: toolbarOwner,
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
private final class SumiSettingsSplitViewController: NSSplitViewController, NSToolbarDelegate {
    private enum ToolbarIdentifier {
        static let windowChrome = NSToolbar.Identifier("SumiSettingsWindowChrome")
        static let navigation = NSToolbarItem.Identifier("SumiSettingsNavigation")
        static let back = NSToolbarItem.Identifier("SumiSettingsBack")
        static let forward = NSToolbarItem.Identifier("SumiSettingsForward")
    }

    private let settings: SumiSettingsService
    private let browserContext: SettingsBrowserContext
    private let keyboardShortcutManager: KeyboardShortcutManager
    private let updaterService: SumiUpdaterService
    private let defaultBrowserService: SumiDefaultBrowserService
    private let sidebarController: SumiSettingsSidebarViewController
    private let detailController = SumiSettingsDetailViewController()
    private let toolbarOwner: SettingsWindowToolbarOwner
    private let windowToolbar = NSToolbar(identifier: ToolbarIdentifier.windowChrome)
    private var navigationToolbarItem: NSToolbarItemGroup?
    private var backToolbarItem: NSToolbarItem?
    private var forwardToolbarItem: NSToolbarItem?
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
        toolbarOwner: SettingsWindowToolbarOwner,
        themeContext: ResolvedThemeContext
    ) {
        self.settings = settings
        self.browserContext = browserContext
        self.keyboardShortcutManager = keyboardShortcutManager
        self.updaterService = updaterService
        self.defaultBrowserService = defaultBrowserService
        self.toolbarOwner = toolbarOwner
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
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        window.tabbingMode = .disallowed
        window.styleMask.insert(.fullSizeContentView)
        window.styleMask.insert(.miniaturizable)
        window.styleMask.insert(.resizable)
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = true
        windowToolbar.delegate = self
        windowToolbar.displayMode = .iconOnly
        windowToolbar.allowsUserCustomization = false
        windowToolbar.allowsDisplayModeCustomization = false
        windowToolbar.autosavesConfiguration = false
        if window.toolbar !== windowToolbar {
            window.toolbar = windowToolbar
        }
        applyToolbarPresentation(toolbarOwner.presentation)
    }

    private func applyToolbarPresentation(
        _ presentation: SettingsWindowToolbarOwner.Presentation
    ) {
        backToolbarItem?.isEnabled = presentation.canGoBack
        forwardToolbarItem?.isEnabled = presentation.canGoForward
        navigationToolbarItem?.isHidden = presentation.canGoBack == false
            && presentation.canGoForward == false
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .sidebarTrackingSeparator,
            ToolbarIdentifier.navigation,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case ToolbarIdentifier.navigation:
            return makeNavigationToolbarItem()
        default:
            return nil
        }
    }

    private func makeNavigationToolbarItem() -> NSToolbarItemGroup {
        let backItem = makeNavigationItem(
            identifier: ToolbarIdentifier.back,
            label: String(localized: "Back"),
            systemImage: "chevron.left",
            action: #selector(navigateBack)
        )
        let forwardItem = makeNavigationItem(
            identifier: ToolbarIdentifier.forward,
            label: String(localized: "Forward"),
            systemImage: "chevron.right",
            action: #selector(navigateForward)
        )
        let group = NSToolbarItemGroup(itemIdentifier: ToolbarIdentifier.navigation)
        group.label = String(localized: "Navigation")
        group.controlRepresentation = .expanded
        group.subitems = [backItem, forwardItem]
        group.isNavigational = true

        navigationToolbarItem = group
        backToolbarItem = backItem
        forwardToolbarItem = forwardItem
        return group
    }

    private func makeNavigationItem(
        identifier: NSToolbarItem.Identifier,
        label: String,
        systemImage: String,
        action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: label)
        item.target = self
        item.action = action
        item.isNavigational = true
        return item
    }

    @objc private func navigateBack() {
        toolbarOwner.goBack()
    }

    @objc private func navigateForward() {
        toolbarOwner.goForward()
    }
}

@MainActor
private final class SumiSettingsDetailViewController: NSViewController {
    let contentView = NSView()

    override func loadView() {
        let rootView = NSView()
        view = rootView

        contentView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(contentView)

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: rootView.safeAreaLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
        ])
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
