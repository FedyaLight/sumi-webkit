import SwiftUI

struct SumiHistoryCommands: Commands {
    let browserContext: SumiCommandsBrowserContext
    let shortcutManager: KeyboardShortcutManager
    @ObservedObject private var historyManager: HistoryManager
    @ObservedObject private var recentlyClosedManager: RecentlyClosedManager
    @ObservedObject private var menuFaviconInvalidator = SumiMenuFaviconInvalidator.shared

    init(
        browserContext: SumiCommandsBrowserContext,
        shortcutManager: KeyboardShortcutManager
    ) {
        self.browserContext = browserContext
        self.shortcutManager = shortcutManager
        self.historyManager = browserContext.historyManager
        self.recentlyClosedManager = browserContext.recentlyClosedManager
    }

    private func dynamicShortcut(_ action: ShortcutAction) -> some ViewModifier {
        let shortcut = shortcutManager.shortcut(for: action)
        let keyCombination = shortcut?.keyCombination
        return DynamicShortcutModifier(
            keyEquivalent: keyCombination.flatMap { KeyboardShortcutPresentation.keyEquivalent(for: $0) },
            modifiers: keyCombination.map { KeyboardShortcutPresentation.eventModifiers(for: $0.modifiers) } ?? []
        )
    }

    private var historyMenuFaviconPartition: SumiFaviconPartition {
        let _ = menuFaviconInvalidator.revision
        return browserContext.faviconPartition
    }

    private var recentVisitedItems: [HistoryListItem] {
        let _ = historyManager.revision
        return historyManager.recentVisitedItems(maxCount: 12)
    }

    var body: some Commands {
        CommandMenu("History") {
            let faviconPartition = historyMenuFaviconPartition

            Button("Back") {
                browserContext.goBackInActiveWindow()
            }
            .modifier(dynamicShortcut(.goBack))
            .disabled(!browserContext.canGoBackInActiveWindow)

            Button("Forward") {
                browserContext.goForwardInActiveWindow()
            }
            .modifier(dynamicShortcut(.goForward))
            .disabled(!browserContext.canGoForwardInActiveWindow)

            Divider()

            Button(
                recentlyClosedManager.mostRecentItem.map { item in
                    if case .window = item { return "Reopen Last Closed Window" }
                    if case .shortcutLauncher = item { return "Reopen Last Closed Pinned Tab" }
                    return "Reopen Last Closed Tab"
                } ?? "Reopen Last Closed Tab"
            ) {
                browserContext.reopenMostRecentClosedItem()
            }
            .modifier(dynamicShortcut(.undoCloseTab))
            .disabled(recentlyClosedManager.canReopenRecentlyClosedItem == false)

            Menu("Recently Closed") {
                let recentlyClosedItems = Array(recentlyClosedManager.items.prefix(30))
                if recentlyClosedItems.isEmpty {
                    Text("No Recently Closed Items")
                        .disabled(true)
                } else {
                    ForEach(recentlyClosedItems) { item in
                        Button {
                            browserContext.reopenRecentlyClosedItem(item)
                        } label: {
                            switch item {
                            case .tab(let tab):
                                SumiCommandMenuLabels.site(
                                    SumiCommandMenuLabels.recentlyClosedTitle(for: item),
                                    url: tab.url,
                                    partition: faviconPartition
                                )
                            case .shortcutLiveInstance(let shortcut):
                                SumiCommandMenuLabels.site(
                                    SumiCommandMenuLabels.recentlyClosedTitle(for: item),
                                    url: shortcut.url,
                                    partition: faviconPartition
                                )
                            case .shortcutLauncher(let shortcut):
                                SumiCommandMenuLabels.site(
                                    SumiCommandMenuLabels.recentlyClosedTitle(for: item),
                                    url: shortcut.pin.launchURL,
                                    partition: faviconPartition
                                )
                            case .window:
                                SumiCommandMenuLabels.system(
                                    SumiCommandMenuLabels.recentlyClosedTitle(for: item),
                                    systemImage: "macwindow"
                                )
                            }
                        }
                    }
                }
            }
            .disabled(recentlyClosedManager.items.isEmpty)

            Button("Reopen All Windows From Last Session") {
                browserContext.reopenAllWindowsFromLastSession()
            }
            .disabled(!browserContext.canRestoreAnyLastSession)

            Divider()

            let visits = recentVisitedItems
            if !visits.isEmpty {
                Text("Recently Visited")
                    .disabled(true)

                ForEach(visits) { visit in
                    Button {
                        browserContext.openHistoryURLFromMenuItem(visit.url)
                    } label: {
                        SumiCommandMenuLabels.site(
                            visit.displayTitle,
                            url: visit.url,
                            partition: faviconPartition
                        )
                    }
                }
            }

            Divider()

            Button("Show All History") {
                browserContext.showHistory()
            }
            .modifier(dynamicShortcut(.viewHistory))

            Divider()

            Button("Clear All History") {
                browserContext.clearAllHistoryFromMenu()
            }
            .keyboardShortcut(.delete, modifiers: [.command, .shift])
            .disabled(!historyManager.canClearHistory)
        }
    }
}
