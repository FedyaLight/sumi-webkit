import Foundation

enum BrowserTabSelectionOutcome: Equatable {
    case committed
    case unchanged
    case deferred
    case rejected

    var wasCommitted: Bool {
        self == .committed || self == .unchanged
    }
}

@MainActor
final class BrowserTabSelectionOwner {
    private let activation: BrowserTabSelectionActivation
    private let performance: PageActivationPerformanceMonitor
    private let state: BrowserTabSelectionStateApplication
    private let materialization: BrowserTabSelectionMaterializationOwner
    private let presentation: BrowserTabSelectionPresentationEffects
    private let publication: BrowserTabSelectionPublicationTransaction

    init(
        activation: BrowserTabSelectionActivation,
        performance: PageActivationPerformanceMonitor,
        state: BrowserTabSelectionStateApplication,
        materialization: BrowserTabSelectionMaterializationOwner,
        presentation: BrowserTabSelectionPresentationEffects,
        publication: BrowserTabSelectionPublicationTransaction
    ) {
        self.activation = activation
        self.performance = performance
        self.state = state
        self.materialization = materialization
        self.presentation = presentation
        self.publication = publication
    }

    @discardableResult
    func selectTab(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        loadPolicy: TabSelectionLoadPolicy
    ) -> BrowserTabSelectionOutcome {
        applyTabSelection(
            tab,
            in: windowState,
            updateSpaceFromTab: true,
            updateTheme: true,
            rememberSelection: true,
            persistSelection: true,
            loadPolicy: loadPolicy
        )
    }

    @discardableResult
    func requestUserTabActivation(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        loadPolicy: TabSelectionLoadPolicy
    ) -> BrowserTabSelectionOutcome {
        let currentTabID = state.currentTab(in: windowState)?.id
        if currentTabID != tab.id {
            performance.begin(
                tabID: tab.id,
                in: windowState.id,
                residency: tab.hasCurrentWebView ? .live : .cold
            )
        }

        let outcome = applyTabSelection(
            tab,
            in: windowState,
            updateSpaceFromTab: true,
            updateTheme: true,
            rememberSelection: true,
            persistSelection: true,
            loadPolicy: loadPolicy
        )
        if currentTabID != tab.id, outcome != .committed {
            performance.cancel(in: windowState.id)
        }
        return outcome
    }

    @discardableResult
    func applyTabSelection(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        updateSpaceFromTab: Bool,
        updateTheme: Bool,
        rememberSelection: Bool,
        persistSelection: Bool,
        loadPolicy: TabSelectionLoadPolicy
    ) -> BrowserTabSelectionOutcome {
        let presentationSpaceID = tab.spaceId ?? windowState.currentSpaceId
        guard tab.isShortcutLiveInstance else {
            return applyAdmittedTabSelection(
                tab,
                in: windowState,
                updateSpaceFromTab: updateSpaceFromTab,
                updateTheme: updateTheme,
                rememberSelection: rememberSelection,
                persistSelection: persistSelection,
                loadPolicy: loadPolicy
            )
        }
        var outcome = BrowserTabSelectionOutcome.rejected
        let accepted = activation.commitShortcutActivation(
            tab,
            in: windowState,
            presentationSpaceID: presentationSpaceID
        ) { [self] admittedTab in
            outcome = applyAdmittedTabSelection(
                admittedTab,
                in: windowState,
                updateSpaceFromTab: updateSpaceFromTab,
                updateTheme: updateTheme,
                rememberSelection: rememberSelection,
                persistSelection: persistSelection,
                loadPolicy: loadPolicy
            )
        }
        return accepted ? outcome : .rejected
    }

    @discardableResult
    func publishPreparedSelectionEffects(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        previousTabID: UUID?,
        previousSpaceID: UUID?
    ) -> BrowserTabSelectionOutcome {
        guard windowState.currentTabId == tab.id,
              state.resolvedTab(tab.id, in: windowState) === tab
        else {
            return .rejected
        }
        let selectedTabChanged = previousTabID != tab.id
        let selectedSpaceChanged = previousSpaceID != windowState.currentSpaceId
        let requiresMaterialization = tab.isUnloaded
            && tab.requiresPrimaryWebView
        guard selectedTabChanged || selectedSpaceChanged || requiresMaterialization else {
            return .unchanged
        }
        return publishAdmittedSelectionEffects(
            tab,
            in: windowState,
            selectionApplication: WindowTabSelectionApplicationResult(
                previousTabId: previousTabID,
                previousSpaceId: previousSpaceID,
                stateDidChange: true
            ),
            updateTheme: true,
            persistSelection: false,
            reconcileSplitSelection: false,
            loadPolicy: .immediate
        )
    }

    func materializeVisibleTabWebViewIfNeeded(
        _ tab: Tab,
        in windowState: BrowserWindowState
    ) {
        materialization.materialize(tab, in: windowState)
    }

    func syncShortcutSelectionState(for windowState: BrowserWindowState) {
        state.synchronizeShortcutSelection(in: windowState)
    }

    func showEmptyState(
        in windowState: BrowserWindowState,
        persistSelection: Bool = true
    ) {
        if let currentSpace = state.space(windowState.currentSpaceId),
           let selectableTab = state.selectionTarget(
            in: currentSpace,
            windowState: windowState
           ) {
            _ = applyTabSelection(
                selectableTab,
                in: windowState,
                updateSpaceFromTab: false,
                updateTheme: false,
                rememberSelection: false,
                persistSelection: persistSelection,
                loadPolicy: .immediate
            )
            return
        }

        state.installEmptyState(in: windowState)
        presentation.publishEmptyState(in: windowState)
        if persistSelection {
            publication.persist(windowState)
        }
    }

    private func applyAdmittedTabSelection(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        updateSpaceFromTab: Bool,
        updateTheme: Bool,
        rememberSelection: Bool,
        persistSelection: Bool,
        loadPolicy: TabSelectionLoadPolicy
    ) -> BrowserTabSelectionOutcome {
        let selectionApplication = state.apply(
            tab,
            to: windowState,
            updateSpaceFromTab: updateSpaceFromTab,
            rememberSelection: rememberSelection
        )

        let selectedTabChanged = selectionApplication.previousTabId != tab.id
        let requiresMaterialization = tab.isUnloaded && tab.requiresPrimaryWebView
        guard selectionApplication.stateDidChange
            || selectedTabChanged
            || requiresMaterialization
        else {
            return .unchanged
        }

        return publishAdmittedSelectionEffects(
            tab,
            in: windowState,
            selectionApplication: selectionApplication,
            updateTheme: updateTheme,
            persistSelection: persistSelection,
            reconcileSplitSelection: true,
            loadPolicy: loadPolicy
        )
    }

    private func publishAdmittedSelectionEffects(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        selectionApplication: WindowTabSelectionApplicationResult,
        updateTheme: Bool,
        persistSelection: Bool,
        reconcileSplitSelection: Bool,
        loadPolicy: TabSelectionLoadPolicy
    ) -> BrowserTabSelectionOutcome {
        presentation.prepare(
            tab,
            in: windowState,
            previousSpaceID: selectionApplication.previousSpaceId,
            updateTheme: updateTheme,
            reconcileSplitSelection: reconcileSplitSelection
        )

        if tab.requiresPrimaryWebView {
            materialization.scheduleIfNeeded(
                tab,
                in: windowState,
                loadPolicy: loadPolicy
            )
        }

        presentation.publish(tab, in: windowState)

        publication.commit(
            tab,
            previousTabID: selectionApplication.previousTabId,
            in: windowState,
            persistSelection: persistSelection
        )
        return .committed
    }
}
