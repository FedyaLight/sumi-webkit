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
import SumiWebRuntime
import WebKit

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
    fileprivate let resolveCollectionTab: @MainActor (UUID) -> Tab?
    fileprivate let windowServices: WebViewWindowServices
    fileprivate let deferredServices: DeferredWebViewServices
    fileprivate let visibleContext: WebViewVisibleRuntimeContext
    fileprivate let initialDocumentContext: InitialDocumentWebViewRuntimeContext
    fileprivate let profileReferenceAdmission: ProfileReferenceAdmissionLedger
    fileprivate let pageActivationPerformance: PageActivationPerformanceMonitor

    let runtimeTabs: WebViewRuntimeTabRegistry

    let ownershipQuery: WebViewOwnershipQuery

    init(
        webViewSessions: WebViewSessionRepository,
        resolveRuntimeTab: @escaping WebViewRuntimeTabRegistry.RuntimeTabResolver,
        resolveCollectionTab: @escaping @MainActor (UUID) -> Tab?,
        windowServices: WebViewWindowServices,
        deferredServices: DeferredWebViewServices,
        visibleContext: WebViewVisibleRuntimeContext,
        initialDocumentContext: InitialDocumentWebViewRuntimeContext,
        profileReferenceAdmission: ProfileReferenceAdmissionLedger,
        pageActivationPerformance: PageActivationPerformanceMonitor
    ) {
        self.webViewSessions = webViewSessions
        self.resolveRuntimeTab = resolveRuntimeTab
        self.resolveCollectionTab = resolveCollectionTab
        self.windowServices = windowServices
        self.deferredServices = deferredServices
        self.visibleContext = visibleContext
        self.initialDocumentContext = initialDocumentContext
        self.profileReferenceAdmission = profileReferenceAdmission
        self.pageActivationPerformance = pageActivationPerformance
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
        cancelProcessRecovery: { [weak self] webView in
            self?.processRecoveryService.cancel(webView)
        },
        finishDestructiveCleanupNavigation: { [weak self] webView in
            self?.websiteDataCleanupService.webViewDidLeaveRuntime(webView)
        },
        performFallbackWebViewCleanup: { [weak self] webView, tabID in
            self?.physicalCleanupService.clean(webView, tabID: tabID)
        },
        resolvedTab: { [weak self] tabID in
            guard let self else { return nil }
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

    lazy var runtimeWebViews = WebViewRuntimeWebViewResolver(
        sessions: webViewSessions,
        mediaProtection: mediaProtectionOwner
    )

    private lazy var deferredCommandTabResolver =
        DeferredWebViewCommandTabResolver(
            runtimeTabs: runtimeTabs,
            resolveRuntimeTab: resolveRuntimeTab,
            resolveCollectionTab: resolveCollectionTab
        )

    fileprivate lazy var deferredCommandAuthority = DeferredWebViewCommandAuthority(
        webViews: runtimeWebViews,
        webViewSessions: webViewSessions,
        tabs: deferredCommandTabResolver,
        tabScopedCleanupValidation: tabScopedCleanupValidationOwner,
        visibleRuntime: visibleWebViewRuntimeOwner,
        windows: windowServices,
        spaceProfileIntents: deferredServices
    )

    private let deferredCommandRetryLedger = DeferredProtectedCommandRetryLedger()

    private lazy var deferredCommandAdmission = DeferredProtectedCommandAdmissionService(
        mediaProtection: mediaProtectionOwner,
        webViews: runtimeWebViews,
        authority: deferredCommandAuthority,
        retryLedger: deferredCommandRetryLedger,
        finishCleanupSuppression: { [weak self] webViewIDs in
            self?.websiteDataCleanupService.webViewsDidLeaveRuntime(webViewIDs)
        }
    )

    fileprivate lazy var visibleRuntimeProvider = VisibleWebViewRuntimeProvider(
        webViewSessions: webViewSessions,
        context: visibleContext,
        visibleRuntime: visibleWebViewRuntimeOwner
    )

    fileprivate lazy var shutdownRuntime = SumiWebViewShutdown.NormalTabRuntime(
        removeWebViewFromContainers: { [weak self] webView in
            self?.compositorRuntime.removeWebViewFromContainers(webView)
        }
    )

    private(set) lazy var physicalCleanupService: WebViewPhysicalCleanupService =
        WebViewPhysicalCleanupService(
            webViewSessions: webViewSessions,
            processRecovery: processRecoveryService,
            mediaProtection: mediaProtectionOwner,
            protectedCommands: deferredCommandAdmission,
            shutdownRuntime: shutdownRuntime
        )

    private(set) lazy var retiredGenerationDestroyer =
        WebViewRetiredGenerationDestroyer(runtime: .init(
            webViewSessions: webViewSessions,
            retireNavigationGeneration: { [weak self] tabID, webViews, preferredWebView in
                guard let self,
                      let tab = self.runtimeTabs.tabForCleanup(
                          tabID,
                          resolveRuntimeTab: self.resolveRuntimeTab
                      ) else { return }
                tab.webViewsDidLeaveNavigationRuntime(
                    webViews,
                    preferredAuthorityWebView: preferredWebView
                )
            },
            destroy: { [weak self] tabID, webView in
                guard let self else { return }
                self.websiteDataCleanupService.webViewDidLeaveRuntime(webView)
                self.physicalCleanupService.clean(webView, tabID: tabID)
            },
            uninstallObservationsIfUntracked: { [weak self] webView in
                self?.trackedRegistrationOwner
                    .uninstallMediaProtectionObservationsIfUntracked(webView)
            }
        ))

    private let webViewCreationPlanner = WebViewCreationPlanner()

    private let replacementTransitionRegistry = WebViewReplacementTransitionRegistry()

    private lazy var replacementPipeline: WebViewReplacementPipeline = {
        let pipeline = WebViewReplacementPipeline(runtime: .init(
            webViewSessions: webViewSessions,
            quiesce: { [weak self] webView in
                self?.processRecoveryService.cancel(webView)
                self?.compositorRuntime.removeWebViewFromContainers(webView)
            },
            retiredGenerationDestroyer: retiredGenerationDestroyer,
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

    private(set) lazy var canonicalWebViewPlacement =
        CanonicalWebViewPlacementService(
            webViewSessions: webViewSessions,
            trackedRegistration: trackedRegistrationOwner
        )

    private(set) lazy var detachedWebViewReplacement =
        DetachedWebViewReplacementService(
            runtimeTabs: runtimeTabs,
            webViewSessions: webViewSessions,
            pipeline: replacementPipeline
        )

    private(set) lazy var untrackedWebViewInstallationService =
        UntrackedWebViewInstallationService(
            runtimeTabs: runtimeTabs,
            query: ownershipQuery,
            placement: canonicalWebViewPlacement,
            detachedReplacement: detachedWebViewReplacement
        )

    private(set) lazy var detachedWebViewCleanup = DetachedWebViewCleanupService(
        runtimeTabs: runtimeTabs,
        webViewSessions: webViewSessions,
        websiteDataCleanup: websiteDataCleanupService,
        processRecovery: processRecoveryService,
        mediaProtection: mediaProtectionOwner,
        protectedCommands: deferredCommandAdmission
    )

    lazy var tabWebViewMaterialization: TabWebViewMaterializationService =
        TabWebViewMaterializationService.live(
            webViewSessions: webViewSessions,
            initialDocumentContext: initialDocumentContext,
            placement: canonicalWebViewPlacement,
            visibleRuntime: visibleRuntimeProvider,
            windowServices: windowServices,
            planner: webViewCreationPlanner
        )

    private lazy var hiddenCloneEviction = HiddenCloneEvictionService(
        owner: hiddenCloneEvictionOwner,
        webViewSessions: webViewSessions,
        runtime: .init(
            tabForID: { [weak self] tabID in
                guard let self else { return nil }
                return runtimeTabs.resolve(
                    tabID,
                    resolveRuntimeTab: resolveRuntimeTab
                )
            },
            liveWebViews: { [weak self] tab in
                self?.ownershipQuery.trackedLiveWebViews(for: tab) ?? []
            },
            globallyVisibleTabIDs: { [] },
            isWebViewProtectedFromCompositorMutation: { [weak self] webView in
                self?.mediaProtectionOwner.isProtected(webView) ?? false
            },
            enqueueDeferredProtectedCommand: { [weak self] command, webView, reason in
                self?.deferredCommandAdmission.schedule(
                    command,
                    for: webView,
                    reason: reason
                ).wasScheduled ?? false
            },
            cleanupUnprotectedTrackedWebView: { [weak self] webView, owner, tab in
                self?.trackedRegistrationOwner.cleanupUnprotectedTrackedWebView(
                    webView,
                    owner: owner,
                    tab: tab
                ) ?? false
            },
            refreshPrimaryTrackedWebView: { [weak self] tab in
                self?.tabWebViewMaterialization.refreshPrimary(for: tab)
            }
        ),
        globallyVisibleTabIDs: visibleContext.globallyVisibleTabIDs
    )

    private(set) lazy var trackedWebViewAdmission = TrackedWebViewAdmissionService(
        runtimeTabs: runtimeTabs,
        query: ownershipQuery,
        placement: canonicalWebViewPlacement,
        materialization: tabWebViewMaterialization,
        websiteDataCleanup: websiteDataCleanupService
    )

    private(set) lazy var untrackedWebViewMaterialization =
        UntrackedWebViewMaterializationService(
            runtimeTabs: runtimeTabs,
            query: ownershipQuery,
            websiteDataCleanup: websiteDataCleanupService
        )

    private(set) lazy var extensionTabWebViewReplacement =
        ExtensionTabWebViewReplacementService(
            runtimeTabs: runtimeTabs,
            query: ownershipQuery,
            websiteDataCleanup: websiteDataCleanupService,
            trackedAdmission: trackedWebViewAdmission,
            untrackedInstallation: untrackedWebViewInstallationService
        )

    private(set) lazy var protectionRuntime: WebViewProtectionRuntime = WebViewProtectionRuntime(
        mediaProtection: mediaProtectionOwner,
        commandAdmission: deferredCommandAdmission,
        commandProcessor: deferredCommandProcessor,
        processRecovery: processRecoveryService,
        webViewSessions: webViewSessions,
        webViews: runtimeWebViews,
        visibleRuntime: visibleWebViewRuntimeOwner,
        websiteDataCleanup: websiteDataCleanupService
    )

    private(set) lazy var compositorRuntime: WebViewCompositorRuntime = WebViewCompositorRuntime(
        visibleRuntime: visibleWebViewRuntimeOwner,
        pageActivationPerformance: pageActivationPerformance,
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
        visibleRuntimeProvider: visibleRuntimeProvider,
        hiddenCloneEviction: hiddenCloneEviction
    )

    private lazy var windowCleanupOwner = WebViewWindowCleanupOwner.live(
        cleanupScope: cleanupScopeOwner,
        sessions: webViewSessions,
        visibleRuntime: visibleWebViewRuntimeOwner,
        mediaProtection: mediaProtectionOwner,
        runtimeTabs: runtimeTabs,
        resolveRuntimeTab: resolveRuntimeTab,
        commandAdmission: deferredCommandAdmission,
        trackedRegistration: trackedRegistrationOwner,
        materialization: tabWebViewMaterialization,
        compositor: compositorRuntime,
        flushDeferredCommands: { [weak self] webViewID in
            self?.protectionRuntime.flush(for: webViewID)
        },
        websiteDataCleanup: websiteDataCleanupService
    )

    private lazy var deferredCleanupExecutor = DeferredWebViewCleanupExecutor.live(
        sessions: webViewSessions,
        closeWebView: deferredServices.handleWebKitClose,
        compositor: compositorRuntime,
        trackedRegistration: trackedRegistrationOwner,
        runtimeTabs: runtimeTabs,
        materialization: tabWebViewMaterialization,
        processRecovery: processRecoveryService,
        shutdownRuntime: shutdownRuntime
    )

    private lazy var deferredWindowMaintenanceExecutor =
        DeferredWebViewWindowMaintenanceExecutor.live(
            windowCleanup: windowCleanupOwner,
            visibility: visibilityRuntime
        )

    private lazy var deferredConfigurationExecutor = DeferredWebViewConfigurationExecutor.live(
        rebuild: { [weak self] tab, preferredPrimaryWindowID, intent in
            guard let self else { return .failed }
            return self.rebuildService.rebuildLiveWebViewsResult(
                for: tab,
                preferredPrimaryWindowID: preferredPrimaryWindowID,
                load: intent.targetURL,
                configuration: intent.configuration,
                reason: "WebViewRebuildService.deferredRebuildLiveWebViews",
                intentRevision: intent.revision,
                rebuildKind: intent.kind
            )
        },
        services: deferredServices
    )

    private lazy var deferredCommandExecutor = DeferredWebViewCommandExecutor(
        cleanup: deferredCleanupExecutor,
        windowMaintenance: deferredWindowMaintenanceExecutor,
        configuration: deferredConfigurationExecutor
    )

    private lazy var deferredCommandProcessor = DeferredProtectedCommandProcessor(
        mediaProtection: mediaProtectionOwner,
        webViews: runtimeWebViews,
        authority: deferredCommandAuthority,
        executor: deferredCommandExecutor,
        retryLedger: deferredCommandRetryLedger,
        finishCleanupSuppression: { [weak self] webViewIDs in
            self?.websiteDataCleanupService.webViewsDidLeaveRuntime(webViewIDs)
        }
    )

    private(set) lazy var lifecycleService: WebViewLifecycleService = WebViewLifecycleService(
        webViewSessions: webViewSessions,
        runtimeTabs: runtimeTabs,
        ownershipQuery: ownershipQuery,
        resolveTab: { [weak self] tabID in
            guard let self else { return nil }
            return self.runtimeTabs.tabForCleanup(
                tabID,
                resolveRuntimeTab: self.resolveRuntimeTab
            )
        },
        processRecovery: processRecoveryService,
        deferredCommandProcessor: deferredCommandProcessor,
        mediaProtection: mediaProtectionOwner,
        websiteDataCleanup: websiteDataCleanupService,
        replacementPipeline: replacementPipeline,
        protection: protectionRuntime,
        compositor: compositorRuntime,
        materialization: tabWebViewMaterialization,
        visibleRuntime: visibleWebViewRuntimeOwner,
        windowCleanup: windowCleanupOwner,
        trackedRegistration: trackedRegistrationOwner,
        physicalCleanup: physicalCleanupService,
        shutdownRuntime: shutdownRuntime
    )

    private(set) lazy var visiblePreparationService: WebViewVisiblePreparationService =
        WebViewVisiblePreparationService(
            visibility: visibilityRuntime,
            webViewSessions: webViewSessions,
            ownershipQuery: ownershipQuery,
            trackedAdmission: trackedWebViewAdmission,
            regularTab: resolveCollectionTab
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
                        runtime: self.visibleRuntimeProvider.runtime(),
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

    private(set) lazy var profileAssignmentService =
        WebViewProfileRuntimeComposition.make(
            webViewSessions: webViewSessions,
            runtimeTabs: runtimeTabs,
            resolveRuntimeTab: resolveRuntimeTab,
            replacementPipeline: replacementPipeline,
            replacementActivation: replacementActivation,
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
            preparedIsProtected: { [weak self] webView in
                self?.protectionRuntime.isProtected(webView) ?? true
            },
            deferProtectedCommand: { [weak self] command, webView, reason in
                self?.protectionRuntime.schedule(
                    command,
                    for: webView,
                    reason: reason
                ) ?? .invalidTarget
            },
            profileReferenceAdmission: profileReferenceAdmission
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
