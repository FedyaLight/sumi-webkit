import AppKit
import WebKit

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func makeActionPopupAnchorResolver() -> ExtensionActionPopupAnchorResolver {
        ExtensionActionPopupAnchorResolver(
            actionAnchorStore: actionAnchorStore,
            actionPopupAnchorStore: actionPopupAnchorStore,
            windowQuery: { [weak self] in self?.extensionWindowQuery },
            windowPresentation: { [weak self] in
                self?.extensionWindowPresentation
            },
            fallbackProfileId: { [weak self] in self?.fallbackProfileId },
            resolvedProfileId: { [weak self] window in
                self?.resolvedProfileId(for: window)
            },
            windowMatchesProfile: { [weak self] window, profileID in
                self?.windowMatchesProfile(window, profileId: profileID) == true
            },
            trace: { [weak self] message in
                self?.runtimeDiagnostics.trace(message())
            }
        )
    }

    func makeActionPopupTelemetry() -> ExtensionActionPopupTelemetry {
        ExtensionActionPopupTelemetry(
            manifest: { [weak self] extensionID in
                self?.runtimeCatalog.manifest(for: extensionID) ?? [:]
            },
            existingAdapter: { [weak self] tabID in
                self?.adapterStore.existingTabAdapter(for: tabID)
            },
            isPublished: { [weak self] tab in
                self?.publishedExtensionTabs.containsPublishedTab(tab) == true
            },
            logSession: { [weak self] extensionID, phase, popupWebView in
                guard RuntimeDiagnostics.isVerboseEnabled else { return }
                Task { @MainActor [weak self, weak popupWebView] in
                    guard let self else { return }
                    await SafariExtensionSessionDiagnosticsBuilder
                        .logIfDiagnosticsEnabled {
                            await SafariExtensionSessionDiagnosticsBuilder.build(
                                extensionId: extensionID,
                                phase: phase,
                                extensionManager: self,
                                popupWebView: popupWebView
                            )
                        }
                }
            }
        )
    }

    func makeActionPopupSourceAdmission()
        -> ExtensionActionPopupSourceAdmission {
        ExtensionActionPopupSourceAdmission(
            callbackAdmission: actionPopupCallbackAdmission,
            windowQuery: { [weak self] in self?.extensionWindowQuery },
            currentProfile: { [weak self] profileID in
                self?.runtime.profile(profileID)
                    ?? self?.runtime.ephemeralProfile(profileID)
            },
            resolvedProfileID: { [weak self] tab in
                self?.resolvedProfileId(for: tab)
            },
            windowMatchesProfile: { [weak self] window, profileID in
                self?.windowMatchesProfile(window, profileId: profileID)
                    == true
            }
        )
    }

    func makeActionPopupCoordinator() -> ExtensionActionPopupCoordinator {
        ExtensionActionPopupCoordinator(
            admission: actionPopupCallbackAdmission,
            targetCapture: ExtensionActionPopupTargetCapture(
                anchors: actionPopupAnchorStore,
                windows: { [weak self] in self?.extensionWindowQuery },
                windowMatchesProfile: { [weak self] window, profileID in
                    self?.windowMatchesProfile(window, profileId: profileID)
                        == true
                }
            ),
            sourceAdmission: actionPopupSourceAdmission,
            sessions: actionPopupSessionLedger,
            retirement: actionPopupRetirement,
            focusRestorer: actionPopupFocusRestorer,
            commitRecorder: actionPopupCommitRecorder,
            anchorResolver: actionPopupAnchorResolver,
            telemetry: actionPopupTelemetry,
            mutationIsBlocked: { [weak self] profileID in
                self?.runtime.websiteDataMutationAdmissionIsBlocked(profileID)
                    == true
            },
            waitForMutation: { [weak self] profileID in
                guard let self else { return false }
                return await self.runtime
                    .waitForWebsiteDataMutationAdmission(profileID)
            }
        )
    }
}
