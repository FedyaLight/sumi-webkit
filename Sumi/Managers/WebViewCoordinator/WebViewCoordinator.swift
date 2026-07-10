//
//  WebViewCoordinator.swift
//  Sumi
//
//  Manages WebView instances across multiple windows
//

import AppKit
import CoreGraphics
import Foundation
import Observation
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
@Observable
class WebViewCoordinator {
    @ObservationIgnored
    let webViewSessions: WebViewSessionRepository

    @ObservationIgnored
    let runtimeTabs: WebViewRuntimeTabRegistry

    @ObservationIgnored
    let ownershipQuery: WebViewOwnershipQuery

    init(webViewSessions: WebViewSessionRepository) {
        self.webViewSessions = webViewSessions
        let runtimeTabs = WebViewRuntimeTabRegistry(
            webViewSessions: webViewSessions
        )
        self.runtimeTabs = runtimeTabs
        ownershipQuery = WebViewOwnershipQuery(
            webViewSessions: webViewSessions
        )
    }

    @ObservationIgnored
    let visibleWebViewRuntimeOwner = VisibleWebViewRuntimeOwner()

    @ObservationIgnored
    let crossWindowSyncOwner = WebViewCrossWindowSyncOwner()

    @ObservationIgnored
    private let backgroundTransitionLedger = WebViewBackgroundTransitionLedger()

    @ObservationIgnored
    let webViewTrackingLifecycleOwner = WebViewTrackingLifecycleOwner()

    @ObservationIgnored
    let trackedCleanupExecutionOwner = WebViewTrackedCleanupExecutionOwner()

    @ObservationIgnored
    private lazy var trackedRegistrationOwner = WebViewTrackedRegistrationOwner(
        webViewSessions: webViewSessions,
        mediaProtectionOwner: mediaProtectionOwner,
        trackingLifecycleOwner: webViewTrackingLifecycleOwner,
        trackedCleanupExecutionOwner: trackedCleanupExecutionOwner,
        requireBrowserRuntimeContext: { [weak self] in
            guard let self else {
                preconditionFailure("WebViewCoordinator dependency used after deallocation")
            }
            return self.runtimeContextStore.requireBrowser()
        },
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
                runtime: self.runtimeContextStore.requireBrowser()
            )
        },
        refreshPrimaryTrackedWebView: { [weak self] tab in
            self?.visibilityRuntime.refreshPrimaryWebView(for: tab)
        },
        removeRecentVisibility: { [visibleWebViewRuntimeOwner] owner in
            visibleWebViewRuntimeOwner.removeRecentVisibility(for: owner)
        }
    )

    @ObservationIgnored
    private(set) lazy var navigationBroadcastOwner = WebViewNavigationBroadcastOwner(
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

    @ObservationIgnored
    private(set) lazy var processRecoveryService = WebContentProcessRecoveryService(
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

    @ObservationIgnored
    let tabScopedCleanupValidationOwner = WebViewTabScopedCleanupValidationOwner()

    @ObservationIgnored
    let cleanupScopeOwner = WebViewCleanupScopeOwner()

    @ObservationIgnored
    let hiddenCloneEvictionOwner = WebViewHiddenCloneEvictionOwner()

    @ObservationIgnored
    let runtimeContextStore = WebViewRuntimeContextStore()

    @ObservationIgnored
    let mediaProtectionOwner = WebViewMediaProtectionOwner()

    @ObservationIgnored
    let deferredProtectedCommandExecutionOwner = WebViewDeferredProtectedCommandExecutionOwner()

    @ObservationIgnored
    private lazy var protectedCommandDispatchOwner = WebViewProtectedCommandDispatchOwner(
        dependencies: .live(coordinator: self)
    )

    @ObservationIgnored
    private lazy var runtimeAssembler = WebViewRuntimeAssembler(
        dependencies: .live(coordinator: self)
    )

    @ObservationIgnored
    private(set) lazy var physicalCleanupService =
        WebViewPhysicalCleanupService(
            webViewSessions: webViewSessions,
            processRecovery: processRecoveryService,
            mediaProtection: mediaProtectionOwner,
            protectedCommands: protectedCommandDispatchOwner,
            runtimeAssembler: runtimeAssembler
        )

    @ObservationIgnored
    private let webViewCreationPlanner = WebViewCreationPlanner()

    @ObservationIgnored
    private let replacementTransitionRegistry =
        WebViewReplacementTransitionRegistry()

    @ObservationIgnored
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
                let context = self.runtimeContextStore.requireBrowser()
                if let tab = self.runtimeTabs.resolve(tabID, runtime: context) {
                    self.visibilityRuntime.refreshPrimaryWebView(for: tab)
                }
                for windowID in snapshot.windowWebViews.keys
                    where context.window(windowID) != nil {
                    context.refreshCompositor(windowID)
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

    @ObservationIgnored
    private lazy var replacementActivation = ReplacementNavigationActivation(
        runtime: .init(
            webViewSessions: webViewSessions,
            pipeline: replacementPipeline,
            installTrackedObservations: { [weak self] webView in
                self?.trackedRegistrationOwner
                    .installMediaProtectionObservationsIfNeeded(on: webView)
            },
            restorePresentation: { [weak self] tabID, snapshot in
                guard let self else { return }
                let context = self.runtimeContextStore.requireBrowser()
                if let tab = self.runtimeTabs.resolve(tabID, runtime: context) {
                    self.visibilityRuntime.refreshPrimaryWebView(for: tab)
                }
                for windowID in snapshot.windowWebViews.keys
                    where context.window(windowID) != nil {
                    context.refreshCompositor(windowID)
                }
            },
            pruneDeferredCommands: { [weak self] reason in
                self?.protectionRuntime.pruneInvalidCommands(reason: reason)
            }
        )
    )

    @ObservationIgnored
    lazy var tabWebViewMaterialization:
        TabWebViewMaterializationService = makeTabWebViewMaterializationService()

    private func makeTabWebViewMaterializationService()
        -> TabWebViewMaterializationService {
        TabWebViewMaterializationService(
            runtime: .init(
                webViewSessions: webViewSessions,
                initialDocumentWarmup: { [weak self] in
                    guard let self else {
                        preconditionFailure("WebViewCoordinator deallocated")
                    }
                    let context = self.runtimeContextStore
                        .requireInitialDocument()
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
                register: { [weak self] webView, tabID, windowID in
                    self?.trackedRegistrationOwner.register(
                        webView,
                        for: tabID,
                        in: windowID
                    )
                },
                promotePrimary: { [weak self] owner, webView in
                    guard let self else { return false }
                    return self.webViewTrackingLifecycleOwner
                        .promoteTrackedWebViewToPrimary(
                            owner: owner,
                            expectedWebView: webView,
                            in: self.webViewSessions
                        )
                },
                primaryCandidate: { [weak self] tabID in
                    guard let self else { return nil }
                    return self.visibleWebViewRuntimeOwner
                        .preferredPrimaryWebViewCandidate(
                            for: tabID,
                            runtime: self.runtimeAssembler
                                .requireVisiblePreparationRuntime(),
                            webViewSessions: self.webViewSessions
                        )
                },
                notifyActivatedIfCurrent: { [weak self] tab, windowID in
                    guard let self else { return }
                    let context = self.runtimeContextStore.requireBrowser()
                    guard let window = context.window(windowID),
                          context.currentTab(window)?.id == tab.id else {
                        return
                    }
                    context.notifyTabActivatedIfLoaded(tab)
                }
            ),
            planner: webViewCreationPlanner
        )
    }

    @ObservationIgnored
    private(set) lazy var ownershipService = WebViewOwnershipService(
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

    @ObservationIgnored
    private(set) lazy var protectionRuntime = WebViewProtectionRuntime(
        mediaProtection: mediaProtectionOwner,
        protectedCommands: protectedCommandDispatchOwner,
        processRecovery: processRecoveryService,
        webViewSessions: webViewSessions,
        visibleRuntime: visibleWebViewRuntimeOwner,
        websiteDataCleanup: websiteDataCleanupService
    )

    @ObservationIgnored
    private(set) lazy var compositorRuntime = WebViewCompositorRuntime(
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

    @ObservationIgnored
    private(set) lazy var visibilityRuntime = WebViewVisibilityRuntime(
        visibleRuntime: visibleWebViewRuntimeOwner,
        materialization: tabWebViewMaterialization,
        runtimeAssembler: runtimeAssembler,
        runtimeContextStore: runtimeContextStore
    )

    @ObservationIgnored
    private(set) lazy var lifecycleService = WebViewLifecycleService(
        webViewSessions: webViewSessions,
        runtimeContextStore: runtimeContextStore,
        ownershipQuery: ownershipQuery,
        processRecovery: processRecoveryService,
        deferredProtectedCommands: deferredProtectedCommandExecutionOwner,
        mediaProtection: mediaProtectionOwner,
        websiteDataCleanup: websiteDataCleanupService,
        protection: protectionRuntime,
        compositor: compositorRuntime,
        visibility: visibilityRuntime,
        visibleRuntime: visibleWebViewRuntimeOwner,
        cleanupScope: cleanupScopeOwner,
        trackedRegistration: trackedRegistrationOwner,
        physicalCleanup: physicalCleanupService,
        runtimeAssembler: runtimeAssembler
    )

    @ObservationIgnored
    private(set) lazy var visiblePreparationService =
        WebViewVisiblePreparationService(
            visibility: visibilityRuntime,
            webViewSessions: webViewSessions,
            ownershipQuery: ownershipQuery,
            ownershipService: ownershipService
        )

    @ObservationIgnored
    private lazy var tabWebViewRebuild = TabWebViewRebuildService(
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
                guard let self else { return [] }
                return Set(
                    self.runtimeContextStore.requireBrowser().allWindows().map(\.id)
                )
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

    @ObservationIgnored
    private(set) lazy var rebuildService = WebViewRebuildService(
        runtimeTabs: runtimeTabs,
        websiteDataCleanup: websiteDataCleanupService,
        engine: tabWebViewRebuild
    )

    @ObservationIgnored
    private lazy var profileTransitionService = ProfileTransitionService(
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

    @ObservationIgnored
    private(set) lazy var profileAssignmentService =
        WebViewProfileAssignmentService(
            runtimeTabs: runtimeTabs,
            runtimeContextStore: runtimeContextStore,
            transitions: profileTransitionService,
            replacementPipeline: replacementPipeline
        )

    @ObservationIgnored
    private(set) lazy var websiteDataCleanupService = WebsiteDataCleanupService(
        browserRuntimeContext: { [weak self] in
            guard let self else {
                preconditionFailure(
                    "WebsiteDataCleanupService outlived its coordinator"
                )
            }
            return self.runtimeContextStore.requireBrowser()
        },
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
                runtime: self.runtimeContextStore.requireBrowser()
            )
        }
    )

}
