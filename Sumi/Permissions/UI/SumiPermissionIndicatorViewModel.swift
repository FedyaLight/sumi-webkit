import Combine
import Foundation
import WebKit

@MainActor
final class SumiPermissionIndicatorViewModel: ObservableObject {
    struct SourceSnapshot: Equatable {
        var coordinatorState: SumiPermissionCoordinatorState?
        var runtimeState: SumiRuntimePermissionState?
        var popupRecords: [SumiBlockedPopupRecord]
        var externalSchemeRecords: [SumiExternalSchemeAttemptRecord]
        var indicatorEvents: [SumiPermissionIndicatorEventRecord]
        var autoplayReloadRequired: Bool
        var displayDomain: String
        var tabId: String
        var pageId: String
        var now: Date

        init(
            coordinatorState: SumiPermissionCoordinatorState? = nil,
            runtimeState: SumiRuntimePermissionState? = nil,
            popupRecords: [SumiBlockedPopupRecord] = [],
            externalSchemeRecords: [SumiExternalSchemeAttemptRecord] = [],
            indicatorEvents: [SumiPermissionIndicatorEventRecord] = [],
            autoplayReloadRequired: Bool = false,
            displayDomain: String = "Current site",
            tabId: String = "",
            pageId: String = "",
            now: Date = Date()
        ) {
            self.coordinatorState = coordinatorState
            self.runtimeState = runtimeState
            self.popupRecords = popupRecords
            self.externalSchemeRecords = externalSchemeRecords
            self.indicatorEvents = indicatorEvents
            self.autoplayReloadRequired = autoplayReloadRequired
            self.displayDomain = normalizedDisplayDomain(displayDomain)
            self.tabId = normalizedId(tabId)
            self.pageId = normalizedId(pageId)
            self.now = now
        }
    }

    private struct CurrentContext: Equatable {
        let tabId: String
        let pageId: String
        let displayDomain: String
        let autoplayReloadRequired: Bool
    }

    @Published private(set) var state: SumiPermissionIndicatorState = .hidden

    private let now: () -> Date
    private var coordinator: (any SumiPermissionCoordinating)?
    private var runtimeController: (any SumiRuntimePermissionControlling)?
    private var popupStore: SumiBlockedPopupStore?
    private var externalSchemeStore: SumiExternalSchemeSessionStore?
    private var indicatorEventStore: SumiPermissionIndicatorEventStore?
    private var currentContext: CurrentContext?
    private weak var currentWebView: WKWebView?
    private var currentRuntimeState: SumiRuntimePermissionState?
    private var runtimeObservation: SumiRuntimePermissionObservation?
    private var eventTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private var isConfigured = false

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    deinit {
        eventTask?.cancel()
    }

    func configure(
        coordinator: any SumiPermissionCoordinating,
        runtimeController: any SumiRuntimePermissionControlling,
        popupStore: SumiBlockedPopupStore,
        externalSchemeStore: SumiExternalSchemeSessionStore,
        indicatorEventStore: SumiPermissionIndicatorEventStore
    ) {
        guard !isConfigured else { return }
        isConfigured = true

        self.coordinator = coordinator
        self.runtimeController = runtimeController
        self.popupStore = popupStore
        self.externalSchemeStore = externalSchemeStore
        self.indicatorEventStore = indicatorEventStore

        cancellables.removeAll()
        popupStore.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            .store(in: &cancellables)
        externalSchemeStore.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            .store(in: &cancellables)
        indicatorEventStore.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            .store(in: &cancellables)

        eventTask?.cancel()
        eventTask = Task { @MainActor [weak self, coordinator] in
            let stream = await coordinator.events()
            for await _ in stream {
                self?.refresh()
            }
        }

        refresh()
    }

    func update(
        tab: Tab,
        windowId: UUID,
        browserManager: BrowserManager
    ) {
        let tabId = tab.id.uuidString.lowercased()
        let pageId = tab.currentPermissionPageId()
        currentContext = CurrentContext(
            tabId: tabId,
            pageId: Self.normalizedId(pageId),
            displayDomain: Self.displayDomain(for: tab.url),
            autoplayReloadRequired: tab.isAutoplayReloadRequired
        )

        let webView = browserManager.getWebView(for: tab.id, in: windowId)
            ?? tab.existingWebView
        if currentWebView !== webView {
            runtimeObservation?.cancel()
            runtimeObservation = nil
            currentWebView = webView

            if let webView, let runtimeController {
                currentRuntimeState = runtimeController.currentRuntimeState(for: webView, pageId: pageId)
                runtimeObservation = runtimeController.observeRuntimeState(for: webView, pageId: pageId) { [weak self] runtimeState in
                    self?.currentRuntimeState = runtimeState
                    self?.refresh()
                }
            } else {
                currentRuntimeState = nil
            }
        }

        refresh()
    }

    func clear() {
        currentContext = nil
        currentRuntimeState = nil
        runtimeObservation?.cancel()
        runtimeObservation = nil
        currentWebView = nil
        guard state != .hidden else { return }
        state = .hidden
    }

    func refresh() {
        Task { @MainActor [weak self] in
            await Task.yield()
            await self?.refreshFromSources()
        }
    }

    static func state(from snapshot: SourceSnapshot) -> SumiPermissionIndicatorState {
        let pageId = normalizedId(snapshot.pageId)
        let tabId = normalizedId(snapshot.tabId)
        let displayDomain = normalizedDisplayDomain(snapshot.displayDomain)
        var candidates: [SumiPermissionIndicatorState] = []

        if let query = activeQuery(from: snapshot.coordinatorState, pageId: pageId) {
            candidates.append(
                pendingQueryState(
                    query,
                    coordinatorState: snapshot.coordinatorState,
                    fallbackTabId: tabId,
                    fallbackDisplayDomain: displayDomain
                )
            )
        }

        if let runtimeState = snapshot.runtimeState {
            candidates.append(contentsOf: runtimeStates(
                runtimeState,
                tabId: tabId,
                pageId: pageId,
                displayDomain: displayDomain
            ))
        }

        candidates.append(contentsOf: coordinatorEventStates(
            from: snapshot.coordinatorState,
            tabId: tabId,
            pageId: pageId,
            displayDomain: displayDomain
        ))
        candidates.append(contentsOf: popupStates(
            snapshot.popupRecords,
            tabId: tabId,
            pageId: pageId,
            fallbackDisplayDomain: displayDomain
        ))
        candidates.append(contentsOf: externalSchemeStates(
            snapshot.externalSchemeRecords,
            tabId: tabId,
            pageId: pageId,
            fallbackDisplayDomain: displayDomain
        ))
        candidates.append(contentsOf: indicatorEventStates(snapshot.indicatorEvents))

        if snapshot.autoplayReloadRequired {
            candidates.append(
                SumiPermissionIndicatorState.visible(
                    category: .reloadRequired,
                    primaryPermissionType: .autoplay,
                    displayDomain: displayDomain,
                    tabId: tabId,
                    pageId: pageId,
                    priority: .autoplayReloadRequired,
                    visualStyle: .reloadRequired,
                    latestEventReason: "autoplay-reload-required"
                )
            )
        }

        return SumiPermissionIndicatorState.resolved(from: candidates)
    }

    private func refreshFromSources() async {
        guard let currentContext else {
            guard state != .hidden else { return }
            state = .hidden
            return
        }

        let coordinatorState = await coordinator?.stateSnapshot()
        let pageId = currentContext.pageId
        let snapshot = SourceSnapshot(
            coordinatorState: coordinatorState,
            runtimeState: currentRuntimeState,
            popupRecords: popupStore?.records(forPageId: pageId) ?? [],
            externalSchemeRecords: externalSchemeStore?.records(forPageId: pageId) ?? [],
            indicatorEvents: indicatorEventStore?.recordsSnapshot(forPageId: pageId, now: now()) ?? [],
            autoplayReloadRequired: currentContext.autoplayReloadRequired,
            displayDomain: currentContext.displayDomain,
            tabId: currentContext.tabId,
            pageId: currentContext.pageId,
            now: now()
        )
        let nextState = Self.state(from: snapshot)
        guard state != nextState else { return }
        state = nextState
    }

    private static func activeQuery(
        from coordinatorState: SumiPermissionCoordinatorState?,
        pageId: String
    ) -> SumiPermissionAuthorizationQuery? {
        guard let coordinatorState else { return nil }
        if let direct = coordinatorState.activeQueriesByPageId[pageId] {
            return direct
        }
        return coordinatorState.activeQueriesByPageId.first { normalizedId($0.key) == pageId }?.value
    }

    private static func pendingQueryState(
        _ query: SumiPermissionAuthorizationQuery,
        coordinatorState: SumiPermissionCoordinatorState?,
        fallbackTabId: String,
        fallbackDisplayDomain: String
    ) -> SumiPermissionIndicatorState {
        let primary = primaryPermissionType(
            from: query.permissionTypes,
            presentationPermissionType: query.presentationPermissionType
        )
        let related = relatedPermissionTypes(
            for: primary,
            sourceTypes: query.permissionTypes
        )
        let queueCount = coordinatorState?.queueCountByPageId[normalizedId(query.pageId)] ?? 0
        let badge = max(related.count, queueCount + 1)
        return SumiPermissionIndicatorState.visible(
            category: .pendingRequest,
            primaryPermissionType: primary,
            relatedPermissionTypes: related,
            displayDomain: normalizedDisplayDomain(query.displayDomain.isEmpty ? fallbackDisplayDomain : query.displayDomain),
            tabId: fallbackTabId,
            pageId: normalizedId(query.pageId),
            priority: priority(for: primary, category: .pendingRequest),
            visualStyle: .attention,
            badgeCount: badge > 1 ? badge : nil,
            latestEventReason: query.policyReasons.last
        )
    }

    private static func runtimeStates(
        _ runtimeState: SumiRuntimePermissionState,
        tabId: String,
        pageId: String,
        displayDomain: String
    ) -> [SumiPermissionIndicatorState] {
        var candidates: [SumiPermissionIndicatorState] = []

        if runtimeState.screenCapture.hasActiveStream {
            candidates.append(
                activeRuntimeState(
                    .screenCapture,
                    priority: .activeScreenCapture,
                    tabId: tabId,
                    pageId: pageId,
                    displayDomain: displayDomain
                )
            )
        }

        if runtimeState.camera.hasActiveStream,
           runtimeState.microphone.hasActiveStream
        {
            candidates.append(
                activeRuntimeState(
                    .cameraAndMicrophone,
                    relatedPermissionTypes: [.camera, .microphone],
                    priority: .activeCameraAndMicrophone,
                    badgeCount: 2,
                    tabId: tabId,
                    pageId: pageId,
                    displayDomain: displayDomain
                )
            )
        } else if runtimeState.camera.hasActiveStream {
            candidates.append(
                activeRuntimeState(
                    .camera,
                    priority: .activeCamera,
                    tabId: tabId,
                    pageId: pageId,
                    displayDomain: displayDomain
                )
            )
        } else if runtimeState.microphone.hasActiveStream {
            candidates.append(
                activeRuntimeState(
                    .microphone,
                    priority: .activeMicrophone,
                    tabId: tabId,
                    pageId: pageId,
                    displayDomain: displayDomain
                )
            )
        }

        switch runtimeState.geolocation {
        case .active, .paused:
            candidates.append(
                activeRuntimeState(
                    .geolocation,
                    priority: .activeGeolocation,
                    tabId: tabId,
                    pageId: pageId,
                    displayDomain: displayDomain
                )
            )
        case .unavailable, .none, .revoked, .unsupportedProvider:
            break
        }

        return candidates
    }

    private static func activeRuntimeState(
        _ permissionType: SumiPermissionType,
        relatedPermissionTypes: [SumiPermissionType]? = nil,
        priority: SumiPermissionIndicatorPriority,
        badgeCount: Int? = nil,
        tabId: String,
        pageId: String,
        displayDomain: String
    ) -> SumiPermissionIndicatorState {
        SumiPermissionIndicatorState.visible(
            category: .activeRuntime,
            primaryPermissionType: permissionType,
            relatedPermissionTypes: relatedPermissionTypes,
            displayDomain: displayDomain,
            tabId: tabId,
            pageId: pageId,
            priority: priority,
            visualStyle: .active,
            badgeCount: badgeCount
        )
    }

    private static func coordinatorEventStates(
        from coordinatorState: SumiPermissionCoordinatorState?,
        tabId: String,
        pageId: String,
        displayDomain: String
    ) -> [SumiPermissionIndicatorState] {
        guard let coordinatorState else { return [] }
        return [
            coordinatorState.latestSystemBlockedEvent,
            coordinatorState.latestEvent,
        ]
        .compactMap { $0 }
        .compactMap { eventState($0, tabId: tabId, pageId: pageId, displayDomain: displayDomain) }
    }

    private static func eventState(
        _ event: SumiPermissionCoordinatorEvent,
        tabId: String,
        pageId: String,
        displayDomain: String
    ) -> SumiPermissionIndicatorState? {
        switch event {
        case .queryActivated(let query),
             .queryQueued(let query, _),
             .queryPromoted(let query):
            guard normalizedId(query.pageId) == pageId else { return nil }
            return pendingQueryState(
                query,
                coordinatorState: nil,
                fallbackTabId: tabId,
                fallbackDisplayDomain: displayDomain
            )
        case .systemBlocked,
             .querySettled,
             .requestCancelled,
             .pageCancelled,
             .profileCancelled,
             .sessionCancelled,
             .queryCoalesced,
             .promptSuppressed:
            return nil
        }
    }

    private static func popupStates(
        _ records: [SumiBlockedPopupRecord],
        tabId: String,
        pageId: String,
        fallbackDisplayDomain: String
    ) -> [SumiPermissionIndicatorState] {
        guard !records.isEmpty else { return [] }
        let displayDomain = normalizedDisplayDomain(
            records.first?.topOrigin.displayDomain ?? fallbackDisplayDomain
        )
        let attemptCount = records.reduce(0) { $0 + max(1, $1.attemptCount) }
        return [
            SumiPermissionIndicatorState.visible(
                category: .blockedEvent,
                primaryPermissionType: .popups,
                displayDomain: displayDomain,
                tabId: tabId,
                pageId: pageId,
                priority: .blockedPopup,
                visualStyle: .blocked,
                badgeCount: attemptCount > 1 ? attemptCount : nil,
                latestEventReason: records.last?.reason.rawValue
            )
        ]
    }

    private static func externalSchemeStates(
        _ records: [SumiExternalSchemeAttemptRecord],
        tabId: String,
        pageId: String,
        fallbackDisplayDomain: String
    ) -> [SumiPermissionIndicatorState] {
        guard !records.isEmpty else { return [] }
        let first = records[0]
        let permissionTypes = uniquePermissionTypes(
            records.map { SumiPermissionType.externalScheme($0.scheme) }
        )
        let primary = permissionTypes.first ?? .externalScheme(first.scheme)
        let hasBlockedAttempt = records.contains { $0.result != .opened }
        let attemptCount = records.reduce(0) { $0 + max(1, $1.attemptCount) }
        let displayDomain = normalizedDisplayDomain(
            first.topOrigin.displayDomain.isEmpty ? fallbackDisplayDomain : first.topOrigin.displayDomain
        )
        let title = hasBlockedAttempt
            ? "External app blocked on \(displayDomain)"
            : "External app opened from \(displayDomain)"
        let accessibilityLabel = hasBlockedAttempt
            ? "External app attempt blocked on \(displayDomain)"
            : "External app opened from \(displayDomain)"

        return [
            SumiPermissionIndicatorState.visible(
                category: .blockedEvent,
                primaryPermissionType: primary,
                relatedPermissionTypes: permissionTypes,
                displayDomain: displayDomain,
                tabId: tabId,
                pageId: pageId,
                priority: .blockedExternalScheme,
                visualStyle: hasBlockedAttempt ? .blocked : .neutral,
                badgeCount: attemptCount > 1 ? attemptCount : nil,
                latestEventReason: records.last?.reason,
                title: title,
                accessibilityLabel: accessibilityLabel
            )
        ]
    }

    private static func indicatorEventStates(
        _ records: [SumiPermissionIndicatorEventRecord]
    ) -> [SumiPermissionIndicatorState] {
        records.compactMap { record in
            guard shouldDisplayURLBarIndicatorEvent(record) else { return nil }
            return SumiPermissionIndicatorState.visible(
                category: record.category,
                primaryPermissionType: record.primaryPermissionType,
                relatedPermissionTypes: record.permissionTypes,
                displayDomain: record.displayDomain,
                tabId: record.tabId,
                pageId: record.pageId,
                priority: record.priority,
                visualStyle: record.visualStyle,
                badgeCount: record.attemptCount > 1 ? record.attemptCount : nil,
                latestEventReason: record.reason
            )
        }
    }

    private static func shouldDisplayURLBarIndicatorEvent(
        _ record: SumiPermissionIndicatorEventRecord
    ) -> Bool {
        switch record.category {
        case .pendingRequest:
            return record.permissionTypes.contains(.filePicker)
        case .activeRuntime,
             .reloadRequired:
            return true
        case .hidden,
             .blockedEvent,
             .systemBlocked,
             .storedException,
             .mixed:
            return false
        }
    }

    private static func primaryPermissionType(
        from permissionTypes: [SumiPermissionType],
        presentationPermissionType: SumiPermissionType? = nil
    ) -> SumiPermissionType {
        if let presentationPermissionType {
            return presentationPermissionType
        }
        let identities = Set(permissionTypes.map(\.identity))
        if identities.contains(SumiPermissionType.camera.identity),
           identities.contains(SumiPermissionType.microphone.identity)
        {
            return .cameraAndMicrophone
        }

        let ordered: [SumiPermissionType] = [
            .screenCapture,
            .camera,
            .microphone,
            .geolocation,
            .notifications,
            .popups,
            .autoplay,
            .storageAccess,
            .filePicker,
        ]
        for candidate in ordered where identities.contains(candidate.identity) {
            return candidate
        }
        return permissionTypes.first ?? .notifications
    }

    private static func relatedPermissionTypes(
        for primary: SumiPermissionType,
        sourceTypes: [SumiPermissionType]
    ) -> [SumiPermissionType] {
        if primary == .cameraAndMicrophone {
            return [.camera, .microphone]
        }
        return uniquePermissionTypes(sourceTypes.isEmpty ? [primary] : sourceTypes)
    }

    private static func priority(
        for permissionType: SumiPermissionType,
        category: SumiPermissionIndicatorCategory
    ) -> SumiPermissionIndicatorPriority {
        switch category {
        case .pendingRequest:
            switch permissionType {
            case .storageAccess:
                return .storageAccessBlockedOrPending
            case .filePicker:
                return .filePickerCurrentEvent
            default:
                return permissionType.isSensitivePowerful
                    ? .pendingSensitiveRequest
                    : .genericPermissionsFallback
            }
        case .systemBlocked:
            return permissionType.isSensitivePowerful
                ? .systemBlockedSensitive
                : .genericPermissionsFallback
        case .blockedEvent:
            switch permissionType {
            case .popups:
                return .blockedPopup
            case .externalScheme:
                return .blockedExternalScheme
            case .notifications:
                return .blockedNotification
            case .storageAccess:
                return .storageAccessBlockedOrPending
            case .filePicker:
                return .filePickerCurrentEvent
            default:
                return .genericPermissionsFallback
            }
        case .reloadRequired:
            return .autoplayReloadRequired
        case .activeRuntime:
            switch permissionType {
            case .screenCapture:
                return .activeScreenCapture
            case .cameraAndMicrophone:
                return .activeCameraAndMicrophone
            case .camera:
                return .activeCamera
            case .microphone:
                return .activeMicrophone
            case .geolocation:
                return .activeGeolocation
            default:
                return .genericPermissionsFallback
            }
        case .storedException, .mixed, .hidden:
            return .genericPermissionsFallback
        }
    }

    private static func uniquePermissionTypes(
        _ permissionTypes: [SumiPermissionType]
    ) -> [SumiPermissionType] {
        var seen = Set<String>()
        var result: [SumiPermissionType] = []
        for permissionType in permissionTypes {
            guard seen.insert(permissionType.identity).inserted else { continue }
            result.append(permissionType)
        }
        return result
    }

    nonisolated private static func displayDomain(for url: URL) -> String {
        if let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines),
           !host.isEmpty {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        let absolute = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        return absolute.isEmpty ? "Current site" : absolute
    }

    nonisolated private static func normalizedId(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    nonisolated private static func normalizedDisplayDomain(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Current site" : trimmed
    }
}

private func normalizedId(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

private func normalizedDisplayDomain(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "Current site" : trimmed
}
