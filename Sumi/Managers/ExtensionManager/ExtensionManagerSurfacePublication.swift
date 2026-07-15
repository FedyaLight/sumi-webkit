import Combine
import Foundation

/// Owns the values published from the extension runtime to browser chrome.
/// Runtime leaves receive only the mutation they need; this owner never
/// stores, resolves, or returns an ExtensionManager or browser service.
@available(macOS 15.5, *)
@MainActor
final class ExtensionManagerSurfacePublication {
    @Published private(set) var actionStatesByExtensionID:
        [String: BrowserExtensionActionSurfaceState] = [:]
    @Published private(set) var pinnedToolbarExtensionIDs: [String] = []

    private let runtimeLoadStatus: ExtensionRuntimeLoadStatusAuthority
    private let actionPresentationChanges = PassthroughSubject<
        ExtensionActionPresentationChange,
        Never
    >()
    private let siteAccessPolicyChanges = PassthroughSubject<Void, Never>()

    init(runtimeLoadStatus: ExtensionRuntimeLoadStatusAuthority) {
        self.runtimeLoadStatus = runtimeLoadStatus
    }

    var actionStatesPublisher:
        Published<[String: BrowserExtensionActionSurfaceState]>.Publisher {
        $actionStatesByExtensionID
    }

    var siteAccessPolicyChangePublisher: AnyPublisher<Void, Never> {
        siteAccessPolicyChanges.eraseToAnyPublisher()
    }

    var actionPresentationChangePublisher: AnyPublisher<
        ExtensionActionPresentationChange,
        Never
    > {
        actionPresentationChanges.eraseToAnyPublisher()
    }

    var extensionsLoaded: Bool {
        runtimeLoadStatus.extensionsLoaded
    }

    @discardableResult
    func markRuntimePublicationReady() -> Bool {
        runtimeLoadStatus.markExtensionsLoaded()
    }

    @discardableResult
    func resetRuntimePublicationReadiness() -> Bool {
        runtimeLoadStatus.reset()
    }

    func setActionSurfaceState(
        _ state: BrowserExtensionActionSurfaceState,
        extensionID: String
    ) {
        actionStatesByExtensionID[extensionID] = state
    }

    func removeActionSurfaceState(extensionID: String) {
        actionStatesByExtensionID.removeValue(forKey: extensionID)
    }

    func publishActionPresentationChange(
        _ change: ExtensionActionPresentationChange
    ) {
        actionPresentationChanges.send(change)
    }

    func replaceActionSurfaceStates(
        _ states: [String: BrowserExtensionActionSurfaceState]
    ) {
        actionStatesByExtensionID = states
    }

    func clearActionSurfaceStates() {
        actionStatesByExtensionID.removeAll()
    }

    func replacePinnedToolbarExtensionIDs(_ ids: [String]) {
        pinnedToolbarExtensionIDs = ids
    }

    func publishSiteAccessPolicyChange() {
        siteAccessPolicyChanges.send(())
    }
}
