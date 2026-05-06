import SwiftUI

struct SumiHistoryCommands: Commands {
    let browserManager: BrowserManager
    let shortcutManager: KeyboardShortcutManager
    @ObservedObject private var historyManager: HistoryManager
    @ObservedObject private var recentlyClosedManager: RecentlyClosedManager
    @ObservedObject private var menuFaviconInvalidator = SumiMenuFaviconInvalidator.shared

    init(browserManager: BrowserManager, shortcutManager: KeyboardShortcutManager) {
        self.browserManager = browserManager
        self.shortcutManager = shortcutManager
        self.historyManager = browserManager.historyManager
        self.recentlyClosedManager = browserManager.recentlyClosedManager
    }

    private func dynamicShortcut(_ action: ShortcutAction) -> some ViewModifier {
        let shortcut = shortcutManager.shortcut(for: action)
        let keyCombination = shortcut?.keyCombination
        return DynamicShortcutModifier(
            keyEquivalent: keyCombination.flatMap { KeyboardShortcutPresentation.keyEquivalent(for: $0) },
            modifiers: keyCombination.map { KeyboardShortcutPresentation.eventModifiers(for: $0.modifiers) } ?? []
        )
    }

    var body: some Commands {
        CommandMenu("History") {
            let _ = historyManager.revision
            let _ = menuFaviconInvalidator.revision

            Button("Back") {
                browserManager.goBackInActiveWindow()
            }
            .modifier(dynamicShortcut(.goBack))
            .disabled(!browserManager.canGoBackInActiveWindow)

            Button("Forward") {
                browserManager.goForwardInActiveWindow()
            }
            .modifier(dynamicShortcut(.goForward))
            .disabled(!browserManager.canGoForwardInActiveWindow)

            Divider()

            Button(
                recentlyClosedManager.mostRecentItem.map { item in
                    if case .window = item { return "Reopen Last Closed Window" }
                    return "Reopen Last Closed Tab"
                } ?? "Reopen Last Closed Tab"
            ) {
                browserManager.reopenLastClosedItem()
            }
            .modifier(dynamicShortcut(.undoCloseTab))
            .disabled(recentlyClosedManager.canReopenRecentlyClosedItem == false)

            Menu("Recently Closed") {
                let recentlyClosedItems = Array(recentlyClosedManager.items.prefix(30))
                if recentlyClosedItems.isEmpty {
                    Button("No Recently Closed Items") {}
                        .disabled(true)
                } else {
                    ForEach(recentlyClosedItems) { item in
                        Button {
                            browserManager.reopenRecentlyClosedItem(item)
                        } label: {
                            switch item {
                            case .tab(let tab):
                                SumiCommandMenuLabels.site(
                                    SumiCommandMenuLabels.recentlyClosedTitle(for: item),
                                    url: tab.url
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
                browserManager.reopenAllWindowsFromLastSession()
            }
            .disabled(!browserManager.canRestoreAnyLastSession)

            Divider()

            let visits = historyManager.recentVisitedItems(maxCount: 12)
            if !visits.isEmpty {
                Button("Recently Visited") {}
                    .disabled(true)

                ForEach(visits) { visit in
                    Button {
                        browserManager.openHistoryURLFromMenuItem(visit.url)
                    } label: {
                        SumiCommandMenuLabels.site(visit.displayTitle, url: visit.url)
                    }
                }
            }

            Divider()

            Button("Show All History") {
                browserManager.showHistory()
            }
            .modifier(dynamicShortcut(.viewHistory))

            Divider()

            Button("Clear All History") {
                browserManager.clearAllHistoryFromMenu()
            }
            .keyboardShortcut(.delete, modifiers: [.command, .shift])
            .disabled(!historyManager.canClearHistory)
        }
    }
}
