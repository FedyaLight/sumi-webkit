import Foundation
import Observation

struct WindowSpaceSwitchRequest: Equatable {
    let id = UUID()
    let targetSpaceID: UUID
}

/// Hands window commands to the mounted sidebar transition renderer. When no
/// interactive sidebar is mounted, callers keep their non-visual fallback.
@MainActor
@Observable
final class WindowSpaceSwitchPresentationState {
    private(set) var request: WindowSpaceSwitchRequest?

    @ObservationIgnored
    private var consumers: Set<UUID> = []

    func registerConsumer(_ id: UUID) {
        consumers.insert(id)
    }

    func unregisterConsumer(_ id: UUID) {
        consumers.remove(id)
        if consumers.isEmpty {
            request = nil
        }
    }

    @discardableResult
    func requestAnimatedSwitch(to targetSpaceID: UUID) -> Bool {
        guard !consumers.isEmpty else { return false }
        request = WindowSpaceSwitchRequest(targetSpaceID: targetSpaceID)
        return true
    }

    func consume(_ consumedRequest: WindowSpaceSwitchRequest) {
        guard request?.id == consumedRequest.id else { return }
        request = nil
    }
}

/// Runtime-only state of the currently attached shell and transient chrome.
/// This authority is never encoded into the durable window snapshot.
@MainActor
@Observable
final class WindowPresentationState {
    var isDownloadsPopoverPresented = false
    var isCommandPaletteVisible = false
    var urlBarFrame: CGRect = .zero
    var nativeDisplayMode: BrowserWindowDisplayMode = .normal
    var pendingSplitGroupFocusRequest: SplitGroupFocusRequest?
    let spaceSwitch = WindowSpaceSwitchPresentationState()
}
