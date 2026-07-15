import Foundation
import OSLog
import WebKit

@available(macOS 15.5, *)
@MainActor
extension ExtensionManagerAssembler {
    static func makePopupAnchorResolver(
        _ f: ExtensionManagerAssemblyFoundation
    ) -> ExtensionActionPopupAnchorResolver {
        ExtensionActionPopupAnchorResolver(
            actionAnchorStore: f.actions.actionAnchors,
            actionPopupAnchorStore: f.actions.actionPopupAnchors,
            browser: f.browser.action,
            fallbackProfileId: { [profileRuntime = f.runtime.profileRuntime] in
                profileRuntime.currentProfileId
                    ?? profileRuntime.currentRememberedProfile?.id
            },
            resolvedProfileId: { [profileRuntime = f.runtime.profileRuntime] window in
                if window.isIncognito { return window.ephemeralProfile?.id }
                return window.currentProfileId
                    ?? profileRuntime.currentProfileId
            },
            windowMatchesProfile: { [browser = f.browser.action] window, profileID in
                browser.popupWindow(window, matches: profileID)
            },
            trace: { [diagnostics = f.runtime.diagnostics] message in
                diagnostics.trace(message())
            }
        )
    }

    static func makePopupTelemetry(
        _ f: ExtensionManagerAssemblyFoundation
    ) -> ExtensionActionPopupTelemetry {
        ExtensionActionPopupTelemetry(
            manifest: { [catalog = f.runtime.catalog] in
                catalog.manifest(for: $0) ?? [:]
            },
            existingAdapter: { [adapters = f.actions.adapterStore] in
                adapters.existingTabAdapter(for: $0)
            },
            isPublished: { [browser = f.browser.action] in
                browser.popupTabIsPublished($0)
            },
            logSession: {
                [installed = f.contexts.installedExtensions,
                 profileRuntime = f.runtime.profileRuntime,
                 sessions = f.actions.actionPopupSessions,
                 browser = f.browser.action]
                extensionID, phase, popupWebView in
                guard RuntimeDiagnostics.isVerboseEnabled else { return }
                Task { @MainActor [weak popupWebView] in
                    await SafariExtensionSessionDiagnosticsBuilder
                        .logIfDiagnosticsEnabled {
                            await SafariExtensionSessionDiagnosticsBuilder.build(
                                extensionId: extensionID,
                                phase: phase,
                                installedExtensions: installed.records,
                                profileRuntime: profileRuntime,
                                isPopupActive: sessions.hasVisibleSession,
                                popupWebView: popupWebView,
                                runtime: .make(browser: browser)
                            )
                        }
                }
            }
        )
    }

    static func makeBackgroundWakes(
        _ f: ExtensionManagerAssemblyFoundation,
        nativeMessagingOwners: ExtensionDemandScopedNativeMessagingOwners
    ) -> ExtensionBackgroundWakeCoordinator {
        let coordinator = ExtensionBackgroundWakeCoordinator(
            backgroundRuntimeStateOwner: f.contexts.backgroundRuntimeState,
            nativeMessagingBackgroundWakeOwner: { [nativeMessagingOwners] in
                nativeMessagingOwners.wakeOwner()
            },
            contextIdentity: { [profileRuntime = f.runtime.profileRuntime] in
                profileRuntime.contextIdentity(for: $0)
            },
            resolvedProfileId: { [profileRuntime = f.runtime.profileRuntime] in
                $0 ?? profileRuntime.currentProfileId
                    ?? profileRuntime.currentRememberedProfile?.id
            },
            runtimeMetrics: f.runtime.metrics,
            trace: { [diagnostics = f.runtime.diagnostics] in diagnostics.trace($0) },
            logBackgroundWakeFailure: backgroundWakeFailureLogger(f)
        )
        #if DEBUG
            coordinator.installDebugBackgroundContentWake {
                [debug = f.actions.debugSignals] in
                debug.backgroundContentWake
            }
        #endif
        return coordinator
    }

    private static func backgroundWakeFailureLogger(
        _ f: ExtensionManagerAssemblyFoundation
    ) -> @MainActor (
        Error,
        WKWebExtensionContext,
        ExtensionManager.ExtensionBackgroundWakeReason,
        String
    ) -> Void {
        { [profileRuntime = f.runtime.profileRuntime]
            error, context, reason, operation in
            let extensionID = profileRuntime.extensionId(for: context)
                ?? "(unknown)"
            let profileID = profileRuntime.profileId(for: context)?
                .uuidString ?? "(unknown)"
            ExtensionManager.logger.error(
                "Failed to \(operation, privacy: .public) for extension \(extensionID, privacy: .public) profile \(profileID, privacy: .public) reason \(reason.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    static func makeControllerProvisioning(
        _ f: ExtensionManagerAssemblyFoundation,
        delegateBridge: ExtensionControllerDelegateBridge,
        delegateReadiness: ExtensionControllerDelegateReadiness
    ) -> ExtensionControllerProvisioningOwner {
        ExtensionControllerProvisioningOwner(
            dependencies: .init(
                browserConfiguration: f.controller.browserConfiguration,
                profileRuntime: f.runtime.profileRuntime,
                currentProfileId: { [profileRuntime = f.runtime.profileRuntime] in
                    profileRuntime.currentProfileId
                },
                assignControllerDelegate: { [delegateBridge] controller in
                    controller.delegate = delegateBridge
                },
                controllerDelegateReadiness: delegateReadiness,
                traceControllerBinding: {
                    [diagnostics = f.runtime.diagnostics,
                     profileRuntime = f.runtime.profileRuntime,
                     delegateBridge]
                    phase, profileID, controller, configuration in
                    diagnostics.traceNativeMessagingContextBinding(
                        phase: phase,
                        extensionId: nil,
                        profileId: profileID,
                        controller: controller,
                        configuration: configuration,
                        profileController: profileID.flatMap {
                            profileRuntime.controller(for: $0)
                        },
                        expectedControllerDelegate: delegateBridge
                    )
                },
                controllerDescription: {
                    ExtensionRuntimeDiagnostics.objectDescription($0)
                },
                trace: { [diagnostics = f.runtime.diagnostics] message in
                    diagnostics.trace(message())
                }
            )
        )
    }

    static func makeActionSurfaces(
        _ f: ExtensionManagerAssemblyFoundation,
        authority: ExtensionLoadedContextAuthority,
        ensureBackgroundAvailableIfRequired: @escaping @MainActor (
            WKWebExtension,
            WKWebExtensionContext,
            ExtensionManager.ExtensionBackgroundWakeReason,
            @escaping @MainActor () -> Bool
        ) async throws -> Void,
        reconcileOpenTabs: @escaping @MainActor (String) -> Void
    ) -> ExtensionActionSurfacePublisher {
        ExtensionActionSurfacePublisher(
            authority: authority,
            extensionIDForContext: { [profileRuntime = f.runtime.profileRuntime] in
                profileRuntime.extensionId(for: $0)
            },
            setActionSurfaceState: { [surface = f.actions.surfacePublication] extensionID, state in
                surface.setActionSurfaceState(state, extensionID: extensionID)
            },
            removeActionSurfaceState: { [surface = f.actions.surfacePublication] in
                surface.removeActionSurfaceState(extensionID: $0)
            },
            publishActionPresentationChange: {
                [surface = f.actions.surfacePublication] in
                surface.publishActionPresentationChange($0)
            },
            exactContextIdentity: {
                [profileRuntime = f.runtime.profileRuntime] context in
                profileRuntime.exactContextIdentity(for: context).map {
                    (
                        extensionID: $0.extensionId,
                        profileID: $0.profileId
                    )
                }
            },
            actionForLoadedContext: { [browser = f.browser.action] context, tab in
                browser.action(for: context, preferredTab: tab)
            },
            ensureBackgroundAvailableIfRequired:
                ensureBackgroundAvailableIfRequired,
            reconcileOpenTabsAfterExtensionContextLoad:
                reconcileOpenTabs
        )
    }

    static func makePermissionPreludes(
        _ f: ExtensionManagerAssemblyFoundation
    ) -> ExtensionPermissionsOriginsCompatibilityPreludeInstallationOwner {
        ExtensionPermissionsOriginsCompatibilityPreludeInstallationOwner(
            isPrivateUserScriptSPIAvailable: {
                SafariExtensionPermissionsOriginsCompatibility
                    .isPrivateUserScriptSPIAvailable
            },
            preludeTargets: { [profileRuntime = f.runtime.profileRuntime] profileID in
                profileRuntime.contexts(for: profileID).map {
                    extensionID, context in
                    .init(
                        extensionId: extensionID,
                        isLoaded: context.isLoaded,
                        baseURL: context.baseURL,
                        installPrelude: { userContentController in
                            SafariExtensionPermissionsOriginsCompatibility
                                .installPrelude(
                                    into: userContentController,
                                    extensionContext: context
                                )
                        }
                    )
                }
            },
            trace: { [diagnostics = f.runtime.diagnostics] in diagnostics.trace($0) }
        )
    }
}
