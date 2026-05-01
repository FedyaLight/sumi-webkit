import Combine
import Foundation

@MainActor
final class SumiPermissionPromptPresenter: ObservableObject {
    struct SourceSnapshot: Equatable {
        let coordinatorState: SumiPermissionCoordinatorState?
        let tabId: String
        let pageId: String
        let displayDomain: String
        let windowIsActive: Bool

        init(
            coordinatorState: SumiPermissionCoordinatorState? = nil,
            tabId: String = "",
            pageId: String = "",
            displayDomain: String = "Current site",
            windowIsActive: Bool = true
        ) {
            self.coordinatorState = coordinatorState
            self.tabId = Self.normalizedId(tabId)
            self.pageId = Self.normalizedId(pageId)
            self.displayDomain = Self.normalizedDisplayDomain(displayDomain)
            self.windowIsActive = windowIsActive
        }

        private static func normalizedId(_ value: String) -> String {
            value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        private static func normalizedDisplayDomain(_ value: String) -> String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Current site" : trimmed
        }
    }

    enum Candidate: Equatable {
        case query(SumiPermissionAuthorizationQuery)
        case systemBlocked(SumiPermissionCoordinatorDecision)

        var id: String {
            switch self {
            case .query(let query):
                return "query:\(query.id)"
            case .systemBlocked(let decision):
                let permissionIdentity = decision.permissionTypes
                    .map(\.identity)
                    .sorted()
                    .joined(separator: ",")
                let pageIdentity = decision.keys
                    .compactMap(\.transientPageId)
                    .sorted()
                    .joined(separator: ",")
                return "system:\(pageIdentity):\(permissionIdentity):\(decision.reason)"
            }
        }
    }

    @Published var isPresented = false
    @Published private(set) var viewModel: SumiPermissionPromptViewModel?

    private var coordinator: (any SumiPermissionCoordinating)?
    private var systemPermissionService: (any SumiSystemPermissionService)?
    private var externalAppResolver: (any SumiExternalAppResolving)?
    private var currentContext: SourceSnapshot?
    private weak var currentWindowState: BrowserWindowState?
    private var currentSourceId: String?
    private var sidebarPinningSourceId: String?
    private var sidebarPinningWindowID: UUID?
    private var sidebarPinningSource: SidebarTransientPresentationSource?
    private var sidebarPinningToken: SidebarTransientSessionToken?
    private var suppressedSourceIds = Set<String>()
    private var shownQuerySourceIds = Set<String>()
    private var eventTask: Task<Void, Never>?
    private var isConfigured = false

    deinit {
        eventTask?.cancel()
    }

    func configure(
        coordinator: any SumiPermissionCoordinating,
        systemPermissionService: any SumiSystemPermissionService,
        externalAppResolver: (any SumiExternalAppResolving)? = nil
    ) {
        guard !isConfigured else { return }
        isConfigured = true

        self.coordinator = coordinator
        self.systemPermissionService = systemPermissionService
        self.externalAppResolver = externalAppResolver

        eventTask?.cancel()
        eventTask = Task { @MainActor [weak self, coordinator] in
            let stream = await coordinator.events()
            for await _ in stream {
                await Task.yield()
                await self?.refresh(autoPresent: true)
            }
        }

        Task { @MainActor [weak self] in
            await Task.yield()
            await self?.refresh(autoPresent: true)
        }
    }

    func update(
        tab: Tab,
        windowState: BrowserWindowState,
        browserManager: BrowserManager
    ) {
        currentContext = SourceSnapshot(
            coordinatorState: nil,
            tabId: tab.id.uuidString,
            pageId: tab.currentPermissionPageId(),
            displayDomain: Self.displayDomain(for: tab.url),
            windowIsActive: windowState.window?.isKeyWindow ?? true
        )
        currentWindowState = windowState
        Task { @MainActor [weak self] in
            await Task.yield()
            await self?.refresh(autoPresent: true)
        }
        _ = browserManager
    }

    func clear() {
        currentContext = nil
        currentWindowState = nil
        finishSidebarPin(reason: "clear")
        currentSourceId = nil
        if viewModel != nil {
            viewModel = nil
        }
        if isPresented {
            isPresented = false
        }
    }

    func closeForCurrentTabChange() {
        finishSidebarPin(reason: "current-tab-change")
        currentSourceId = nil
        if viewModel != nil {
            viewModel = nil
        }
        if isPresented {
            isPresented = false
        }
    }

    func presentFromIndicatorClick() -> Bool {
        guard viewModel != nil else { return false }
        if !isPresented {
            isPresented = true
        }
        Task { @MainActor [weak self] in
            await self?.recordCurrentPromptShownIfNeeded()
        }
        return true
    }

    func refresh(autoPresent: Bool) async {
        guard let coordinator,
              let systemPermissionService,
              let context = currentContext
        else {
            closeForCurrentTabChange()
            return
        }

        let coordinatorState = await coordinator.stateSnapshot()
        let snapshot = SourceSnapshot(
            coordinatorState: coordinatorState,
            tabId: context.tabId,
            pageId: context.pageId,
            displayDomain: context.displayDomain,
            windowIsActive: context.windowIsActive
        )

        guard let candidate = Self.candidate(from: snapshot) else {
            closeForCurrentTabChange()
            return
        }

        if suppressedSourceIds.contains(candidate.id) {
            if currentSourceId == candidate.id {
                closeForCurrentTabChange()
            }
            return
        }

        if currentSourceId != candidate.id {
            finishSidebarPin(reason: "candidate-changed")
            currentSourceId = candidate.id
            viewModel = makeViewModel(
                for: candidate,
                coordinator: coordinator,
                systemPermissionService: systemPermissionService
            )
        }
        syncSidebarPin(for: candidate)

        if autoPresent, snapshot.windowIsActive {
            if !isPresented {
                isPresented = true
            }
            await recordPromptShownIfNeeded(candidate: candidate, coordinator: coordinator)
        }
    }

    static func candidate(from snapshot: SourceSnapshot) -> Candidate? {
        if let query = activeQuery(
            from: snapshot.coordinatorState,
            pageId: snapshot.pageId
        ) {
            let primary = SumiPermissionPromptViewModel.primaryPermissionType(
                permissionTypes: query.permissionTypes,
                presentationPermissionType: query.presentationPermissionType
            )
            guard SumiPermissionPromptViewModel.isPromptable(primary) else { return nil }
            return .query(query)
        }

        guard let event = snapshot.coordinatorState?.latestSystemBlockedEvent,
              case .systemBlocked(let decision) = event,
              decisionMatchesPage(decision, pageId: snapshot.pageId)
        else {
            return nil
        }

        let primary = SumiPermissionPromptViewModel.primaryPermissionType(
            permissionTypes: decision.permissionTypes,
            presentationPermissionType: nil
        )
        guard SumiPermissionPromptViewModel.isPromptable(primary) else { return nil }
        return .systemBlocked(decision)
    }

    private func makeViewModel(
        for candidate: Candidate,
        coordinator: any SumiPermissionCoordinating,
        systemPermissionService: any SumiSystemPermissionService
    ) -> SumiPermissionPromptViewModel {
        let sourceId = candidate.id
        let finish: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            if case .systemBlocked = candidate {
                self.suppressedSourceIds.insert(sourceId)
            }
            if self.currentSourceId == sourceId {
                self.finishSidebarPin(reason: "finished")
                self.viewModel = nil
                self.currentSourceId = nil
                self.isPresented = false
            }
        }

        switch candidate {
        case .query(let query):
            return SumiPermissionPromptViewModel(
                query: query,
                coordinator: coordinator,
                systemPermissionService: systemPermissionService,
                externalAppResolver: externalAppResolver,
                onFinished: finish
            )
        case .systemBlocked(let decision):
            return SumiPermissionPromptViewModel(
                systemBlockedDecision: decision,
                coordinator: coordinator,
                systemPermissionService: systemPermissionService,
                externalAppResolver: externalAppResolver,
                onFinished: finish
            )
        }
    }

    private func recordCurrentPromptShownIfNeeded() async {
        guard let coordinator,
              let sourceId = currentSourceId,
              let viewModel,
              let queryId = viewModel.queryId,
              !shownQuerySourceIds.contains(sourceId)
        else {
            return
        }
        shownQuerySourceIds.insert(sourceId)
        await coordinator.recordPromptShown(queryId: queryId)
    }

    private func recordPromptShownIfNeeded(
        candidate: Candidate,
        coordinator: any SumiPermissionCoordinating
    ) async {
        guard case .query(let query) = candidate,
              let sourceId = currentSourceId,
              !shownQuerySourceIds.contains(sourceId)
        else {
            return
        }
        shownQuerySourceIds.insert(sourceId)
        await coordinator.recordPromptShown(queryId: query.id)
    }

    private func syncSidebarPin(for candidate: Candidate) {
        guard let windowState = currentWindowState else { return }
        let sourceId = candidate.id
        if sidebarPinningSourceId == sourceId,
           sidebarPinningWindowID == windowState.id,
           sidebarPinningToken != nil
        {
            return
        }

        finishSidebarPin(reason: "sync")
        let source = windowState.sidebarTransientSessionCoordinator.preparedPresentationSource(
            window: windowState.window
        )
        let token = windowState.sidebarTransientSessionCoordinator.beginSession(
            kind: .permissionPrompt,
            source: source,
            path: "SumiPermissionPromptPresenter.\(sourceId)"
        )
        sidebarPinningSourceId = sourceId
        sidebarPinningWindowID = windowState.id
        sidebarPinningSource = source
        sidebarPinningToken = token
    }

    private func finishSidebarPin(reason: String) {
        guard let token = sidebarPinningToken else { return }
        sidebarPinningSource?.coordinator?.finishSession(
            token,
            reason: "SumiPermissionPromptPresenter.\(reason)"
        )
        sidebarPinningSourceId = nil
        sidebarPinningWindowID = nil
        sidebarPinningSource = nil
        sidebarPinningToken = nil
    }

    private static func activeQuery(
        from coordinatorState: SumiPermissionCoordinatorState?,
        pageId: String
    ) -> SumiPermissionAuthorizationQuery? {
        guard let coordinatorState else { return nil }
        if let direct = coordinatorState.activeQueriesByPageId[pageId] {
            return direct
        }
        return coordinatorState.activeQueriesByPageId.first {
            normalizedId($0.key) == pageId
        }?.value
    }

    private static func decisionMatchesPage(
        _ decision: SumiPermissionCoordinatorDecision,
        pageId: String
    ) -> Bool {
        decision.keys.contains { key in
            normalizedId(key.transientPageId ?? "") == pageId
        }
    }

    private static func displayDomain(for url: URL) -> String {
        if let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines),
           !host.isEmpty {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        let absolute = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        return absolute.isEmpty ? "Current site" : absolute
    }

    private static func normalizedId(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
