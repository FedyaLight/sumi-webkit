import Foundation

@available(macOS 15.5, *)
@MainActor
struct ExtensionPopupCoordinationPhaseProduct {
    let popupCallbackAdmission: ExtensionActionPopupCallbackAdmission
    let popupCoordinator: ExtensionActionPopupCoordinator
}

@available(macOS 15.5, *)
@MainActor
struct ExtensionRuntimePopupPhaseProduct {
    let callbackAdmission: ExtensionActionPopupCallbackAdmission
    let coordinator: ExtensionActionPopupCoordinator
    let failureDiagnostics: ExtensionActionPopupFailureDiagnostics
    let bindingRecovery: ExtensionActionPopupBindingRecovery
    let anchorResolver: ExtensionActionPopupAnchorResolver
}

@available(macOS 15.5, *)
@MainActor
struct ExtensionRuntimeActionPhaseProduct {
    let actionInvocation: ExtensionActionInvocationService
    let keyboardCommands: ExtensionKeyboardCommandDispatchOwner
}

@available(macOS 15.5, *)
@MainActor
extension ExtensionManagerAssembler {
    static func assemblePopupCoordinationPhase(
        contexts: ExtensionContextGraphFoundation,
        actions: ExtensionActionGraphFoundation,
        browser: ExtensionManagerBrowserFoundation,
        controller: ExtensionControllerCoreAssemblyProduct,
        popup: ExtensionPopupAssemblyProduct
    ) -> ExtensionPopupCoordinationPhaseProduct {
        let popupCallbackAdmission = ExtensionActionPopupCallbackAdmission(
            runtimeBindingAdmission: controller.callbackAdmission,
            installedExtensions: contexts.installedExtensions
        )
        let popupCoordinator = ExtensionActionPopupCoordinator(
            admission: popupCallbackAdmission,
            targetCapture: ExtensionActionPopupTargetCapture(
                anchors: actions.actionPopupAnchors,
                browser: browser.action
            ),
            sourceAdmission: ExtensionActionPopupSourceAdmission(
                callbackAdmission: popupCallbackAdmission,
                browser: browser.action
            ),
            sessions: actions.actionPopupSessions,
            retirement: popup.retirement,
            focusRestorer: popup.focus,
            commitRecorder: popup.commitRecorder,
            anchorResolver: popup.anchorResolver,
            telemetry: popup.telemetry,
            mutationIsBlocked: { [websiteData = browser.websiteData] profileID in
                websiteData.isBlocked(profileID: profileID)
            },
            waitForMutation: { [websiteData = browser.websiteData] profileID in
                await websiteData.wait(profileID: profileID)
            }
        )
        return ExtensionPopupCoordinationPhaseProduct(
            popupCallbackAdmission: popupCallbackAdmission,
            popupCoordinator: popupCoordinator
        )
    }

    static func assemblePopupDiagnosticsPhase(
        installation: ExtensionInstallationGraphFoundation,
        runtime: ExtensionRuntimeAuthorityFoundation,
        contexts: ExtensionContextGraphFoundation,
        contextLifecycle: ExtensionContextLifecycleCoreProduct
    ) -> ExtensionActionPopupFailureDiagnostics {
        makePopupFailureDiagnostics(
            installation: installation,
            runtime: runtime,
            contexts: contexts,
            contextLifecycle: contextLifecycle
        )
    }

    static func assembleRuntimePopupPhase(
        runtime: ExtensionRuntimeAuthorityFoundation,
        contextLifecycle: ExtensionContextLifecycleCoreProduct,
        popup: ExtensionPopupAssemblyProduct,
        coordination: ExtensionRuntimeCoordinationPhaseProduct,
        popupCoordination: ExtensionPopupCoordinationPhaseProduct,
        diagnostics: ExtensionActionPopupFailureDiagnostics
    ) -> ExtensionRuntimePopupPhaseProduct {
        ExtensionRuntimePopupPhaseProduct(
            callbackAdmission: popupCoordination.popupCallbackAdmission,
            coordinator: popupCoordination.popupCoordinator,
            failureDiagnostics: diagnostics,
            bindingRecovery: ExtensionActionPopupBindingRecovery(
                contextRetirement: contextLifecycle.retirement,
                contextLoading: coordination.contextResidency,
                profileRuntime: runtime.profileRuntime
            ),
            anchorResolver: popup.anchorResolver
        )
    }

    static func assembleRuntimeActionPhase(
        runtime: ExtensionRuntimeAuthorityFoundation,
        contexts: ExtensionContextGraphFoundation,
        actions: ExtensionActionGraphFoundation,
        browser: ExtensionManagerBrowserFoundation,
        actionPolicy: ExtensionActionPolicyAssemblyProduct,
        controller: ExtensionControllerCoreAssemblyProduct,
        coordination: ExtensionRuntimeCoordinationPhaseProduct,
        runtimePopup: ExtensionRuntimePopupPhaseProduct
    ) -> ExtensionRuntimeActionPhaseProduct {
        ExtensionRuntimeActionPhaseProduct(
            actionInvocation: makeActionInvocation(
                runtime: runtime,
                contexts: contexts,
                actions: actions,
                browser: browser.action,
                actionPolicy: actionPolicy,
                controller: controller,
                coordination: coordination,
                runtimePopup: runtimePopup
            ),
            keyboardCommands: ExtensionKeyboardCommandDispatchOwner(
                profileRuntime: runtime.profileRuntime,
                diagnostics: runtime.diagnostics
            )
        )
    }

    private static func makePopupFailureDiagnostics(
        installation: ExtensionInstallationGraphFoundation,
        runtime: ExtensionRuntimeAuthorityFoundation,
        contexts: ExtensionContextGraphFoundation,
        contextLifecycle: ExtensionContextLifecycleCoreProduct
    ) -> ExtensionActionPopupFailureDiagnostics {
        ExtensionActionPopupFailureDiagnostics(
            installedExtensions: { [installed = contexts.installedExtensions] in
                installed.records
            },
            controllerExists: { [profileRuntime = runtime.profileRuntime] in
                profileRuntime.controller(for: $0) != nil
            },
            extensionResourcesRoot: {
                [metadata = installation.metadataStore]
                sourceKind, packagePath, sourceBundlePath in
                try metadata.extensionResourcesRoot(
                    sourceKind: sourceKind,
                    packagePath: packagePath,
                    sourceBundlePath: sourceBundlePath
                )
            },
            lastExtensionLoadError: { [catalog = runtime.catalog] in
                catalog.loadError(extensionID: $0, profileID: $1)
            },
            extensionSnapshot: { [state = contextLifecycle.profileState] in
                state.extensionSnapshot(extensionId: $0, profileId: $1)
            },
            profileIdForContext: { [profileRuntime = runtime.profileRuntime] in
                profileRuntime.profileId(for: $0)
            },
            currentProfileId: { [profileRuntime = runtime.profileRuntime] in
                profileRuntime.currentProfileId
            },
            runtimeState: { [lifecycle = runtime.lifecycle] in
                lifecycle.state
            }
        )
    }

    private static func makeActionInvocation(
        runtime: ExtensionRuntimeAuthorityFoundation,
        contexts: ExtensionContextGraphFoundation,
        actions: ExtensionActionGraphFoundation,
        browser: ExtensionBrowserAttachmentAuthority.ActionBrowserProjection,
        actionPolicy: ExtensionActionPolicyAssemblyProduct,
        controller: ExtensionControllerCoreAssemblyProduct,
        coordination: ExtensionRuntimeCoordinationPhaseProduct,
        runtimePopup: ExtensionRuntimePopupPhaseProduct
    ) -> ExtensionActionInvocationService {
        let requestAdmission = ExtensionActionRequestAdmission(
            runtimeBindingAdmission: controller.callbackAdmission,
            profileRuntime: runtime.profileRuntime,
            allTabs: { [browser] in browser.actionInvocationTabs() },
            profileID: { [browser] in
                browser.actionInvocationProfileID(for: $0)
            },
            currentProfileID: { [profileRuntime = runtime.profileRuntime] in
                profileRuntime.currentProfileId
                    ?? profileRuntime.currentRememberedProfile?.id
            },
            installedExtensions: contexts.installedExtensions
        )
        let admission = ExtensionActionInvocationAdmission(
            runtimeBindingAdmission: controller.callbackAdmission,
            requestAdmission: requestAdmission,
            installedExtensions: contexts.installedExtensions,
            adapterStore: actions.adapterStore
        )
        let pageAccess = ExtensionActionPageAccessAuthorizer(
            environment: .init(
                siteAccess: actionPolicy.siteAccess,
                decisions: actionPolicy.permissionDecisions,
                prompt: {
                    [prompt = actionPolicy.permissionPrompt,
                     profileRuntime = runtime.profileRuntime]
                    context, targets, reason, dedupeKey in
                    await prompt.promptForDecision(
                        extensionContext: context,
                        targets: targets,
                        reason: reason,
                        dedupeKey: dedupeKey,
                        extensionIdentifier:
                            profileRuntime.extensionId(for: context)
                    )
                }
            ),
            admission: admission
        )
        let runtimeResolver = ExtensionActionRuntimeResolver(
            environment: .init(
                installedExtensions: contexts.installedExtensions,
                runtimeAccess: controller.runtimeAccess,
                runtimeLifecycle: runtime.lifecycle,
                runtimeCatalog: runtime.catalog,
                anchorStore: actions.actionPopupAnchors,
                anchorResolution: runtimePopup.anchorResolver,
                profileTransition: coordination.profileTransition,
                contextResidency: coordination.contextResidency,
                failureDiagnostics: runtimePopup.failureDiagnostics,
                resolvedProfileID: { [browser] in
                    browser.actionInvocationProfileID(for: $0)
                },
                primaryWindowID: { [browser] in
                    browser.actionInvocationPrimaryWindowID(for: $0)
                },
                activeWindowID: { [browser] in
                    browser.actionInvocationActiveWindowID()
                },
                trace: { [diagnostics = runtime.diagnostics] in
                    diagnostics.trace($0)
                }
            )
        )
        #if DEBUG
            let environment = ExtensionActionInvocationService.Environment(
                runtimeResolver: runtimeResolver,
                requestAdmission: requestAdmission,
                pageAccess: pageAccess,
                admission: admission,
                actionPublication: actionPolicy.actionSurfaces,
                runtimeMetrics: runtime.metrics,
                stableAdapter: { [browser] in
                    browser.actionInvocationStableAdapter(for: $0)
                },
                registerTab: { [browser] tab, reason in
                    browser.registerActionInvocationTab(tab, reason: reason)
                },
                actionDispatchProbe: { [debug = actions.debugSignals] extensionID in
                    debug.dispatchExtensionAction(extensionID)
                },
                trace: { [diagnostics = runtime.diagnostics] in
                    diagnostics.trace($0)
                }
            )
        #else
            let environment = ExtensionActionInvocationService.Environment(
                runtimeResolver: runtimeResolver,
                requestAdmission: requestAdmission,
                pageAccess: pageAccess,
                admission: admission,
                actionPublication: actionPolicy.actionSurfaces,
                runtimeMetrics: runtime.metrics,
                stableAdapter: { [browser] in
                    browser.actionInvocationStableAdapter(for: $0)
                },
                registerTab: { [browser] tab, reason in
                    browser.registerActionInvocationTab(tab, reason: reason)
                },
                trace: { [diagnostics = runtime.diagnostics] in
                    diagnostics.trace($0)
                }
            )
        #endif
        return ExtensionActionInvocationService(
            environment: environment,
            actionDispatch: ExtensionActionDispatch(
                admission: admission,
                popupInvocations: actions.actionPopupInvocations
            ),
            popupBindingRecovery: runtimePopup.bindingRecovery
        )
    }
}
