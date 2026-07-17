import Combine
import Foundation

@MainActor
final class TabStructuralInstallPublication {
    private let changes: ObservableObjectPublisher
    private let faviconService: any BrowserFaviconServicing

    init(
        changes: ObservableObjectPublisher,
        faviconService: any BrowserFaviconServicing
    ) {
        self.changes = changes
        self.faviconService = faviconService
    }

    func willInstallState() {
        changes.send()
    }

    func didInstallShortcuts(
        pinnedByProfile: [UUID: [ShortcutPin]],
        spacePinnedShortcuts: [UUID: [ShortcutPin]]
    ) {
        faviconService.syncShortcutPins(
            Array(pinnedByProfile.values.joined())
                + Array(spacePinnedShortcuts.values.joined())
        )
    }
}
