import Foundation

/// Read-only projection of open regular windows, independent of history policy.
@MainActor
final class OpenWindowSessionCatalog {
    private let allWindows: @MainActor () -> [BrowserWindowState]
    private let makeWindowSessionSnapshot: @MainActor (BrowserWindowState) -> WindowSessionSnapshot?

    init(
        allWindows: @escaping @MainActor () -> [BrowserWindowState],
        makeWindowSessionSnapshot: @escaping @MainActor (BrowserWindowState) -> WindowSessionSnapshot?
    ) {
        self.allWindows = allWindows
        self.makeWindowSessionSnapshot = makeWindowSessionSnapshot
    }

    func regularWindowSnapshots(excludingWindowID: UUID?) -> [LastSessionWindowSnapshot] {
        allWindows()
            .filter { !$0.isIncognito && $0.id != excludingWindowID }
            .compactMap { windowState in
                guard let session = makeWindowSessionSnapshot(windowState) else { return nil }
                return LastSessionWindowSnapshot(
                    id: windowState.restoredSessionWindowId ?? windowState.id,
                    session: session
                )
            }
    }

    func snapshot(of windowState: BrowserWindowState) -> WindowSessionSnapshot? {
        makeWindowSessionSnapshot(windowState)
    }

    func deterministicRegularWindow(excludingWindowID: UUID) -> BrowserWindowState? {
        allWindows()
            .filter { $0.isIncognito == false && $0.id != excludingWindowID }
            .min { $0.id.uuidString < $1.id.uuidString }
    }

    func containsRegularWindow(_ windowState: BrowserWindowState) -> Bool {
        allWindows().contains {
            $0 === windowState && $0.isIncognito == false
        }
    }
}
