//
//  WebViewRuntimeGraph.swift
//  Sumi
//
//  Composes WebView runtime services shared across browser windows.
//

import AppKit
import CoreGraphics
import Foundation
import QuartzCore
import WebKit
import SumiWebRuntime

enum CompositorPaneDestination: String, CaseIterable {
    case single
    case left
    case right

    var viewIdentifier: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier("SumiCompositorPane.\(rawValue)")
    }
}

@MainActor
final class WebViewRuntimeGraph {
    let webViewSessions: WebViewSessionRepository
    fileprivate let resolveRuntimeTab: WebViewRuntimeTabRegistry.RuntimeTabResolver
    fileprivate let windowServices: WebViewWindowServices
    fileprivate let deferredServices: DeferredWebViewServices
    fileprivate let visibleContext: WebViewVisibleRuntimeContext
    fileprivate let initialDocumentContext: InitialDocumentWebViewRuntimeContext
    fileprivate let shutdownContext: WebViewShutdownRuntimeContext

    let runtimeTabs: WebViewRuntimeTabRegistry

    let ownershipQuery: WebViewOwnershipQuery

    init(
        webViewSessions: WebViewSessionRepository,
        resolveRuntimeTab: @escaping WebViewRuntimeTabRegistry.RuntimeTabResolver,
        windowServices: WebViewWindowServices,
        deferredServices: DeferredWebViewServices,
        visibleContext: WebViewVisibleRuntimeContext,
        initialDocumentContext: InitialDocumentWebViewRuntimeContext,
        shutdownContext: WebViewShutdownRuntimeContext
    ) {
        self.webViewSessions = webViewSessions
        self.resolveRuntimeTab = resolveRuntimeTab
        self.windowServices = windowServices
        self.deferredServices = deferredServices
        self.visibleContext = visibleContext
        self.initialDocumentContext = initialDocumentContext
        self.shutdownContext = shutdownContext
        let runtimeTabs = WebViewRuntimeTabRegistry(
            webViewSessions: webViewSessions
        )
        self.runtimeTabs = runtimeTabs
        ownershipQuery = WebViewOwnershipQuery(
            webViewSessions: webViewSessions
        )
    }

    let visibleWebViewRuntimeOwner = VisibleWebViewRuntimeOwner()

    let crossWindowSyncOwner = WebViewCrossWindowSyncOwner()

    private let backgroundTransitionLedger = WebViewBackgroundTransitionLedger()

    let webViewTrackingLifecycleOwner = WebViewTrackingLifecycleOwner()

    let trackedCleanupExecutionOwner = WebViewTrackedCleanupExecutionOwner()

    fileprivate lazy var trackedRegistrationOwner: WebViewTrackedRegistrationOwner = WebViewTrackedRegistrationOwner(
        webViewSessions: webViewSessions,
        mediaProtectionOwner: mediaProtectionOwner,
        trackingLifecycleOwner: webViewTrackingLifecycleOwner,
        trackedCleanupExecutionOwner: trackedCleanupExecutionOwner,
        containsWindow: windowServices.containsWindow,
        currentTabID: windowServices.currentTabID,
        selectTab: windowServices.selectTab,
        refreshCompositor: windowServices.refreshCompositor,
        removeWebViewFromContainers: { [weak self] webView in
            self?.compositorRuntime.removeWebViewFromContainers(webView)
        },
        pruneInvalidDeferredCommands: { [weak self] reason in
            self?.protectionRuntime.pruneInvalidCommands(reason: reason)
        },
        flushDeferredProtectedCommands: { [weak self] webViewID in
            self?.protectionRuntime.flush(for: webViewID)
        },
        finishDestructiveCleanupNavigation: { [weak self] webView in
            self?.websiteDataCleanupService.webViewDidLeaveRuntime(webView)
        },
        performFallbackWebViewCleanup: { [weak self] webView, tabID in
            self?.physicalCleanupService.clean(webView, tabID: tabID)
        },
        resolvedTab: { [weak self] tabID in
            guard let self else { return nil }
            if let tab = self.runtimeTabs.boundTab(tabID) {
                return tab
            }
            return self.runtimeTabs.resolve(
                tabID,
                resolveRuntimeTab: self.resolveRuntimeTab
            )
        },
        refreshPrimaryTrackedWebView: { [weak self] tab in
            self?.visibilityRuntime.refreshPrimaryWebView(for: tab)
        },
        removeRecentVisibility: { [visibleWebViewRuntimeOwner] owner in
            visibleWebViewRuntimeOwner.removeRecentVisibility(for: owner)
        }
    )

    private(set) lazy var navigationBroadcastOwner: WebViewNavigationBroadcastOwner = WebViewNavigationBroadcastOwner(
        crossWindowSyncOwner: crossWindowSyncOwner,
        webViewSessions: webViewSessions,
        isWebViewProtectedFromCompositorMutation: { [weak self] webView in
            self?.protectionRuntime.isProtected(webView) ?? false
        },
        deferProtectedNavigation: { [weak self] command, webView in
            self?.protectionRuntime.schedule(
                command,
                for: webView,
                reason: "WebViewNavigationBroadcastOwner.protectedTarget"
            ) ?? .invalidTarget
        }
    )

    private(set) lazy var processRecoveryService: WebContentProcessRecoveryService = WebContentProcessRecoveryService(
        isProtected: { [mediaProtectionOwner] webView in
            mediaProtectionOwner.isProtected(webView)
        },
        submit: { tab, webView, intent in
            tab.navigationCommandOwner.submitExactReload(
                on: webView,
                tab: tab,
                intent: intent,
                policy: .standard
            )
        }
    )

    let tabScopedCleanupValidationOwner = WebViewTabScopedCleanupValidationOwner()

    let cleanupScopeOwner = WebViewCleanupScopeOwner()

    let hiddenCloneEvictionOwner = WebViewHiddenCloneEvictionOwner()

    let mediaProtectionOwner = WebViewMediaProtectionOwner()

    let deferredProtectedCommandExecutionOwner = WebViewDeferredProtectedCommandExecutionOwner()

    private lazy var protectedCommandDispatchOwner: WebViewProtectedCommandDispatchOwner = WebViewProtectedCommandDispatchOwner(
        dependencies: .live(graph: self)
    )

    fileprivate lazy var runtimeAssembler: WebViewRuntimeAssembler = WebViewRuntimeAssembler(
        dependencies: .live(graph: self)
    )

    private(set) lazy var physicalCleanupService: WebViewPhysicalCleanupService =
        WebViewPhysicalCleanupService(
            webViewSessions: webViewSessions,
            processRecovery: processRecoveryService,
            mediaProtection: mediaProtectionOwner,
            protectedCommands: protectedCommandDispatchOwner,
            runtimeAssembler: runtimeAssembler
        )

    private let webViewCreationPlanner = WebViewCreationPlanner()

    private let replacementTransitionRegistry =
        WebViewReplacementTransitionRegistry()

    private lazy var replacementPipeline: WebViewReplacementPipeline = {
        let pipeline = WebViewReplacementPipeline(runtime: .init(
            webViewSessions: webViewSessions,
            quiesce: { [weak self] webView in
                self?.processRecoveryService.cancel(webView)
                self?.compositorRuntime.removeWebViewFromContainers(webView)
            },
            destroy: { [weak self] tabID, webView in
                guard let self else { return }
                self.websiteDataCleanupService.webViewDidLeaveRuntime(webView)
                self.physicalCleanupService.clean(webView, tabID: tabID)
            },
            restore: { [weak self] tabID, snapshot in
                guard let self else { return }
                if let tab = self.runtimeTabs.resolve(
                    tabID,
                    resolveRuntimeTab: self.resolveRuntimeTab
                ) {
                    self.visibilityRuntime.refreshPrimaryWebView(for: tab)
                }
                for windowID in snapshot.windowWebViews.keys
                    where self.windowServices.containsWindow(windowID) {
                    self.windowServices.refreshCompositor(windowID)
                }
            },
            uninstallObservationsIfUntracked: { [weak self] webView in
                self?.trackedRegistrationOwner
                    .uninstallMediaProtectionObservationsIfUntracked(webView)
            }
        ))
        replacementTransitionRegistry.install { [weak pipeline]
            profileIDs,
            reason in
            pipeline?.abort(profileIDs: profileIDs, reason: reason) ?? 0
        }
        return pipeline
    }()

    private lazy var replacementActivation: ReplacementNavigationActivation = ReplacementNavigationActivation(
        runtime: .init(
            webViewSessions: webViewSessions,
            pipeline: replacementPipeline,
            installTrackedObservations: { [weak self] webView in
                self?.trackedRegistrationOwner
                    .installMediaProtectionObservationsIfNeeded(on: webView)
            },
            restorePresentation: { [weak self] tabID, snapshot in
                guard let self else { return }
                if let tab = self.runtimeTabs.resolve(
                    tabID,
                    resolveRuntimeTab: self.resolveRuntimeTab
                ) {
                    self.visibilityRuntime.refreshPrimaryWebView(for: tab)
                }
                for windowID in snapshot.windowWebViews.keys
                    where self.windowServices.containsWindow(windowID) {
                    self.windowServices.refreshCompositor(windowID)
                }
            },
            pruneDeferredCommands: { [weak self] reason in
                self?.protectionRuntime.pruneInvalidCommands(reason: reason)
            }
        )
    )

    lazy var tabWebViewMaterialization: TabWebViewMaterializationService =
        WebViewRuntimeGraphAssembly.makeTabWebViewMaterialization(
            graph: self,
            planner: webViewCreationPlanner
        )

    private(set) lazy var ownershipService: WebViewOwnershipService = WebViewOwnershipService(
        webViewSessions: webViewSessions,
        runtimeTabs: runtimeTabs,
        query: ownershipQuery,
        trackedRegistration: trackedRegistrationOwner,
        materialization: tabWebViewMaterialization,
        websiteDataCleanup: websiteDataCleanupService,
        processRecovery: processRecoveryService,
        mediaProtection: mediaProtectionOwner,
        protectedCommands: protectedCommandDispatchOwner,
        replacementPipeline: replacementPipeline
    )

    private(set) lazy var protectionRuntime: WebViewProtectionRuntime = WebViewProtectionRuntime(
        mediaProtection: mediaProtectionOwner,
        protectedCommands: protectedCommandDispatchOwner,
        processRecovery: processRecoveryService,
        webViewSessions: webViewSessions,
        visibleRuntime: visibleWebViewRuntimeOwner,
        websiteDataCleanup: websiteDataCleanupService
    )

    private(set) lazy var compositorRuntime: WebViewCompositorRuntime = WebViewCompositorRuntime(
        visibleRuntime: visibleWebViewRuntimeOwner,
        backgroundTransitions: backgroundTransitionLedger,
        scheduleProtectedCommand: { [weak self] command, webView, reason in
            self?.protectionRuntime.schedule(
                command,
                for: webView,
                reason: reason
            ) ?? .invalidTarget
        },
        pruneInvalidProtectedCommands: { [weak self] reason in
            self?.protectionRuntime.pruneInvalidCommands(reason: reason)
        }
    )

    private(set) lazy var visibilityRuntime: WebViewVisibilityRuntime = WebViewVisibilityRuntime(
        visibleRuntime: visibleWebViewRuntimeOwner,
        materialization: tabWebViewMaterialization,
        runtimeAssembler: runtimeAssembler,
        globallyVisibleTabIDs: visibleContext.globallyVisibleTabIDs
    )

    private(set) lazy var lifecycleService: WebViewLifecycleService = WebViewLifecycleService(
        webViewSessions: webViewSessions,
        ownershipQuery: ownershipQuery,
        resolveTab: { [weak self] tabID in
            guard let self else { return nil }
            return self.runtimeTabs.resolve(
                tabID,
                resolveRuntimeTab: self.resolveRuntimeTab
            )
        },
        processRecovery: processRecoveryService,
        deferredProtectedCommands: deferredProtectedCommandExecutionOwner,
        mediaProtection: mediaProtectionOwner,
        websiteDataCleanup: websiteDataCleanupService,
        replacementPipeline: replacementPipeline,
        protection: protectionRuntime,
        compositor: compositorRuntime,
        visibility: visibilityRuntime,
        visibleRuntime: visibleWebViewRuntimeOwner,
        cleanupScope: cleanupScopeOwner,
        trackedRegistration: trackedRegistrationOwner,
        physicalCleanup: physicalCleanupService,
        runtimeAssembler: runtimeAssembler
    )

    private(set) lazy var visiblePreparationService: WebViewVisiblePreparationService =
        WebViewVisiblePreparationService(
            visibility: visibilityRuntime,
            webViewSessions: webViewSessions,
            ownershipQuery: ownershipQuery,
            ownershipService: ownershipService
        )

    private lazy var tabWebViewRebuild: TabWebViewRebuildService = TabWebViewRebuildService(
        runtime: .init(
            webViewSessions: webViewSessions,
            pipeline: replacementPipeline,
            activation: replacementActivation,
            isProtected: { [weak self] webView in
                self?.protectionRuntime.isProtected(webView) ?? false
            },
            deferProtected: { [weak self] command, webView, reason in
                self?.protectionRuntime.schedule(
                    command,
                    for: webView,
                    reason: reason
                ) ?? .invalidTarget
            },
            liveWindowIDs: { [weak self] in
                self?.windowServices.liveWindowIDs() ?? []
            },
            primaryCandidate: { [weak self] tabID in
                guard let self else { return nil }
                return self.visibleWebViewRuntimeOwner
                    .preferredPrimaryWebViewCandidate(
                        for: tabID,
                        runtime: self.runtimeAssembler
                            .requireVisiblePreparationRuntime(),
                        webViewSessions: self.webViewSessions
                    )?.owner
            }
        )
    )

    private(set) lazy var rebuildService: WebViewRebuildService = WebViewRebuildService(
        runtimeTabs: runtimeTabs,
        websiteDataCleanup: websiteDataCleanupService,
        engine: tabWebViewRebuild
    )

    private lazy var profileTransitionService: ProfileTransitionService = ProfileTransitionService(
        runtime: .init(
            webViewSessions: webViewSessions,
            admissionIsBlocked: { [weak self] profileID in
                self?.websiteDataCleanupService.admissionIsBlocked(
                    profileID: profileID
                ) ?? true
            },
            deferAdmission: { [weak self] profileID, key, replay in
                self?.websiteDataCleanupService.deferOrdinaryAdmission(
                    profileID: profileID,
                    key: key,
                    replay: replay
                ) ?? false
            },
            isProtected: { [weak self] webView in
                self?.protectionRuntime.isProtected(webView) ?? false
            },
            deferProtectedCommand: { [weak self] command, webView, reason in
                self?.protectionRuntime.schedule(
                    command,
                    for: webView,
                    reason: reason
                ) ?? .invalidTarget
            },
            provisioning: ProfileReplacementProvisioning(),
            pipeline: replacementPipeline,
            activation: replacementActivation
        )
    )

    private(set) lazy var profileAssignmentService: WebViewProfileAssignmentService =
        WebViewProfileAssignmentService(
            runtimeTabs: runtimeTabs,
            resolveRuntimeTab: resolveRuntimeTab,
            transitions: profileTransitionService,
            replacementPipeline: replacementPipeline
        )

    private(set) lazy var websiteDataCleanupService: WebsiteDataCleanupService = WebsiteDataCleanupService(
        liveWebViews: { [weak self] tab in
            self?.ownershipQuery.suspensionLiveWebViews(for: tab) ?? []
        },
        waitForMutationPermission: { [weak self] webView in
            guard let self else { return false }
            return await self.mediaProtectionOwner.waitUntilUnprotected(webView)
        },
        restoreSubmission: { tab, targetURL in
            tab.navigationCommandOwner.restoreAfterDestructiveDataCleanup(
                tab,
                targetURL: targetURL
            )
        },
        abortOwnershipTransitions: { [weak self] profileIDs in
            _ = self?.replacementTransitionRegistry.abort(
                profileIDs: profileIDs,
                reason: .destructiveDataCleanup
            )
        },
        waitForOwnershipTransitions: { [webViewSessions] in
            await webViewSessions.waitUntilOwnershipTransitionsAreSettled()
        },
        runtimeMutationGeneration: { [webViewSessions] in
            webViewSessions.residenceGeneration
        },
        runtimeTabs: { [weak self] in
            guard let self else { return nil }
            return self.runtimeTabs.canonicalRuntimeOwnedTabs(
                resolveRuntimeTab: self.resolveRuntimeTab
            )
        }
    )

}

private extension WebViewRuntimeAssembler.Dependencies {
    @MainActor
    static func live(graph: WebViewRuntimeGraph) -> Self {
        Self(
            webViewSessions: graph.webViewSessions,
            visibleContext: graph.visibleContext,
            shutdownContext: graph.shutdownContext,
            visibleWebViewRuntimeOwner: graph.visibleWebViewRuntimeOwner,
            hiddenCloneEvictionOwner: graph.hiddenCloneEvictionOwner,
            removeWebViewFromContainers: { [weak graph] webView in
                graph?.compositorRuntime.removeWebViewFromContainers(webView)
            },
            isWebViewProtectedFromCompositorMutation: { [weak graph] webView in
                graph?.protectionRuntime.isProtected(webView) ?? false
            },
            enqueueDeferredProtectedCommand: { [weak graph] command, webView, reason in
                graph?.protectionRuntime.schedule(
                    command,
                    for: webView,
                    reason: reason
                ) ?? .notProtected
            },
            resolvedTab: { [weak graph] tabID in
                guard let graph else { return nil }
                return graph.runtimeTabs.resolve(
                    tabID,
                    resolveRuntimeTab: graph.resolveRuntimeTab
                )
            },
            trackedLiveWebViews: { [weak graph] tab in
                graph?.ownershipQuery.trackedLiveWebViews(for: tab) ?? []
            },
            cleanupUnprotectedTrackedWebView: { [weak graph] webView, owner, tab in
                graph?.lifecycleService.cleanupUnprotectedTrackedWebView(
                    webView,
                    owner: owner,
                    tab: tab
                )
            },
            refreshPrimaryTrackedWebView: { [weak graph] tab in
                graph?.tabWebViewMaterialization.refreshPrimary(for: tab)
            }
        )
    }
}

private extension WebViewProtectedCommandDispatchOwner.Dependencies {
    @MainActor
    static func live(graph: WebViewRuntimeGraph) -> Self {
        Self(
            mediaProtectionOwner: graph.mediaProtectionOwner,
            executionOwner: graph.deferredProtectedCommandExecutionOwner,
            tabScopedCleanupValidationOwner: graph.tabScopedCleanupValidationOwner,
            webViewSessions: graph.webViewSessions,
            resolveWebView: { [weak graph] webViewID in
                graph?.protectionRuntime.resolveWebView(with: webViewID)
            },
            resolvedTab: { [weak graph] tabID in
                guard let graph else { return nil }
                return graph.runtimeTabs.resolve(
                    tabID,
                    resolveRuntimeTab: graph.resolveRuntimeTab
                )
            },
            containsWindow: graph.windowServices.containsWindow,
            handleWebKitClose: graph.deferredServices.handleWebKitClose,
            executeProfileAssignment: graph.deferredServices.executeProfileAssignment,
            validateSpaceProfileAssignment: graph.deferredServices
                .validateSpaceProfileAssignment,
            executeSpaceProfileAssignment: graph.deferredServices
                .executeSpaceProfileAssignment,
            compositorContainerView: { [weak graph] windowID in
                graph?.compositorRuntime.containerView(for: windowID)
            },
            removeWebViewFromContainers: { [weak graph] webView in
                graph?.compositorRuntime.removeWebViewFromContainers(webView)
            },
            cleanupTrackedWebView: { [weak graph] webView, owner in
                graph?.lifecycleService.cleanupTrackedWebView(
                    webView,
                    owner: owner
                )
            },
            cleanupWindow: { [weak graph] windowID in
                graph?.lifecycleService.cleanupWindow(windowID)
            },
            cleanupAllWebViews: { [weak graph] in
                graph?.lifecycleService.cleanupAllWebViews()
            },
            rebuildLiveWebViews: {
                [weak graph]
                tab, preferredPrimaryWindowId, intent in
                guard let graph else { return .failed }
                return graph.rebuildService.rebuildLiveWebViewsResult(
                    for: tab,
                    preferredPrimaryWindowID: preferredPrimaryWindowId,
                    load: intent.targetURL,
                    configuration: intent.configuration,
                    reason: "WebViewRebuildService.deferredRebuildLiveWebViews",
                    intentRevision: intent.revision,
                    rebuildKind: intent.kind
                )
            },
            evictHiddenWebViews: { [weak graph] windowID, visibleTabIDs in
                graph?.visibilityRuntime.evictHiddenWebViewsIfNeeded(
                    in: windowID,
                    visibleTabIDs: visibleTabIDs
                )
            },
            visibleTabIDSet: { [weak graph] windowID in
                graph?.visibilityRuntime.visibleTabIDs(in: windowID) ?? []
            },
            performFallbackWebViewCleanup: { [weak graph] webView, tabID in
                graph?.physicalCleanupService.clean(webView, tabID: tabID)
            },
            finishCleanupSuppression: { [weak graph] webViewIDs in
                graph?.protectionRuntime
                    .finishCleanupSuppression(for: webViewIDs)
            }
        )
    }
}

private enum WebViewRuntimeGraphAssembly {
    @MainActor
    static func makeTabWebViewMaterialization(
        graph: WebViewRuntimeGraph,
        planner: WebViewCreationPlanner
    ) -> TabWebViewMaterializationService {
        TabWebViewMaterializationService(
            runtime: TabWebViewMaterializationService.Runtime(
                webViewSessions: graph.webViewSessions,
                initialDocumentWarmup: { [weak graph] in
                    guard let graph else {
                        preconditionFailure("WebViewRuntimeGraph deallocated")
                    }
                    let context = graph.initialDocumentContext
                    return InitialDocumentWarmupRuntime(
                        needsInitialDocumentExtensionContextLoad: {
                            context.needsInitialDocumentExtensionContextLoad($0)
                        },
                        ensureInitialExtensionContextsLoaded: {
                            await context.ensureInitialExtensionContextsLoaded($0)
                        },
                        refreshCompositorForWindow: {
                            context.refreshCompositorForWindow($0)
                        }
                    )
                },
                register: { [weak graph] webView, tabID, windowID in
                    graph?.trackedRegistrationOwner.register(
                        webView,
                        for: tabID,
                        in: windowID
                    )
                },
                promotePrimary: { [weak graph] owner, webView in
                    guard let graph else { return false }
                    return graph.webViewTrackingLifecycleOwner
                        .promoteTrackedWebViewToPrimary(
                            owner: owner,
                            expectedWebView: webView,
                            in: graph.webViewSessions
                        )
                },
                primaryCandidate: { [weak graph] tabID in
                    guard let graph else { return nil }
                    return graph.visibleWebViewRuntimeOwner
                        .preferredPrimaryWebViewCandidate(
                            for: tabID,
                            runtime: graph.runtimeAssembler
                                .requireVisiblePreparationRuntime(),
                            webViewSessions: graph.webViewSessions
                        )
                },
                notifyActivatedIfCurrent: { [weak graph] tab, windowID in
                    graph?.windowServices.notifyTabActivatedIfCurrent(
                        tab,
                        windowID
                    )
                }
            ),
            planner: planner
        )
    }
}
