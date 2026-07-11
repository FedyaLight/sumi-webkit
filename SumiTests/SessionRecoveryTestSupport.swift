import XCTest

@testable import Sumi

/// Shared fakes and builders for the session-recovery service suites.
@MainActor
final class StartupSessionRestoreProviderFake: BrowserStartupSessionRestoreProviding {
    var canOfferRestoreShortcut: Bool
    var windowSnapshots: [LastSessionWindowSnapshot]
    var tabSnapshot: TabPersistenceSnapshot?
    private(set) var didConsumeRestoreOffer = false

    init(
        canOfferRestoreShortcut: Bool = false,
        windowSnapshots: [LastSessionWindowSnapshot] = [],
        tabSnapshot: TabPersistenceSnapshot? = nil
    ) {
        self.canOfferRestoreShortcut = canOfferRestoreShortcut
        self.windowSnapshots = windowSnapshots
        self.tabSnapshot = tabSnapshot
    }

    func markRestoreOfferConsumed() {
        didConsumeRestoreOffer = true
        canOfferRestoreShortcut = false
    }
}

@MainActor
final class WindowSessionReopenerFake: WindowSessionReopening {
    var reopenResult: Bool
    var reopenResults: [Bool] = []
    private(set) var reopenedSnapshots: [LastSessionWindowSnapshot] = []
    var reopenedSessions: [WindowSessionSnapshot] { reopenedSnapshots.map(\.session) }
    var onReopen: (@MainActor () async -> Void)?

    init(reopenResult: Bool = true) {
        self.reopenResult = reopenResult
    }

    @discardableResult
    func reopenWindow(from snapshot: LastSessionWindowSnapshot) async -> Bool {
        reopenedSnapshots.append(snapshot)
        await onReopen?()
        if reopenResults.isEmpty == false {
            return reopenResults.removeFirst()
        }
        return reopenResult
    }
}

@MainActor
final class TabSelectionRecorder {
    var selected: [(tab: Tab, window: BrowserWindowState)] = []
}

@MainActor
func makeSessionRecoveryWindowSession(
    currentTabId: UUID? = nil,
    isShowingEmptyState: Bool = false
) -> WindowSessionSnapshot {
    WindowSessionSnapshot(
        currentTabId: currentTabId,
        currentSpaceId: UUID(),
        currentProfileId: nil,
        activeShortcutPinId: nil,
        activeShortcutPinRole: nil,
        isShowingEmptyState: isShowingEmptyState,
        floatingBarReason: FloatingBarPresentationReason.none,
        activeTabsBySpace: [],
        activeShortcutsBySpace: [],
        sidebarWidth: Double(BrowserWindowState.sidebarDefaultWidth),
        savedSidebarWidth: Double(BrowserWindowState.sidebarDefaultWidth),
        sidebarContentWidth: Double(
            BrowserWindowState.sidebarContentWidth(
                for: BrowserWindowState.sidebarDefaultWidth
            )
        ),
        isSidebarVisible: true,
        floatingBarDraft: FloatingBarDraftState(text: "", navigateCurrentTab: false)
    )
}

extension XCTestCase {
    @MainActor
    func makeIsolatedLastSessionWindowsStore(
        suitePrefix: String
    ) throws -> LastSessionWindowsStore {
        let suiteName = "\(suitePrefix)-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        return LastSessionWindowsStore(userDefaults: userDefaults)
    }
}
