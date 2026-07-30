import Foundation
import WebKit

@available(macOS 15.5, *)
enum ExtensionActionRuntimeResolution {
    struct Ready {
        let profileID: UUID
        let context: WKWebExtensionContext
        let popupTarget: ExtensionActionPopupInvocationTarget?
    }

    case ready(Ready)
    case blocked(BrowserExtensionActionPopupRequestResult)
}

/// Admits an action click into one exact profile-scoped WebKit context.
@available(macOS 15.5, *)
@MainActor
final class ExtensionActionRuntimeResolver {
    struct Environment {
        let installedExtensions: InstalledExtensionCollection
        let runtimeAccess: ExtensionRuntimeAccess
        let runtimeLifecycle: ExtensionRuntimeLifecycleAuthority
        let runtimeCatalog: ExtensionRuntimeCatalog
        let anchorStore: ExtensionActionPopupAnchorStore
        let anchorResolution: ExtensionActionPopupAnchorResolver
        let profileTransition: ExtensionProfileRuntimeTransition
        let contextResidency: ExtensionContextResidencyOwner
        let failureDiagnostics: ExtensionActionPopupFailureDiagnostics
        let resolvedProfileID: @MainActor (Tab) -> UUID?
        let primaryWindowID: @MainActor (Tab) -> UUID?
        let activeWindowID: @MainActor () -> UUID?
        let trace: @MainActor (String) -> Void
    }

    private let environment: Environment
    private let admissionPolicy = ExtensionActionAdmissionPolicy()

    init(environment: Environment) {
        self.environment = environment
    }

    func resolve(
        extensionID: String,
        currentTab: Tab?,
        popupTargetRequest: ExtensionActionPopupTargetRequest = .implicit
    ) async -> ExtensionActionRuntimeResolution {
        guard let extensionRecord = environment.installedExtensions.record(
            for: extensionID
        ) else {
            return .blocked(
                .blocked(
                    .extensionNotInstalled,
                    message: "The extension is not installed in Sumi's local extension store."
                )
            )
        }

        trace(
            "urlHubAction click extensionId=\(extensionID) manifestHash=\(extensionRecord.manifestRootFingerprint) resourcesPath=\(extensionRecord.packagePath) sourceBundlePath=\(extensionRecord.sourceBundlePath) extensionEnabled=\(extensionRecord.isEnabled) runtimeState=\(runtimeState.rawValue) contextLoaded=\(environment.runtimeAccess.getExtensionContext(extensionID, nil) != nil) currentProfile=\(currentProfileID?.uuidString ?? "nil") tabProfile=\(currentTab?.profileId?.uuidString ?? "nil") tabOffRecord=\(currentTab?.isEphemeral ?? false) currentURLShape=\(admissionPolicy.sanitizedTraceURL(currentTab?.url))"
        )
        if let rejection = admissionPolicy.rejection(
            for: extensionRecord,
            currentTab: currentTab
        ) {
            return .blocked(rejection)
        }
        trace(
            "urlHubAction preflight passed extensionId=\(extensionID) localExperimentalRecordEnabled=true currentTabEligible=\(currentTab != nil) currentPagePermission=true moduleWorkerUnsupported=false"
        )

        guard let profileID = currentTab.flatMap(environment.resolvedProfileID)
            ?? environment.runtimeAccess.fallbackProfileId() else {
            return .blocked(
                .blocked(
                    .noEligibleTab,
                    message: "No profile is available for the extension action."
                )
            )
        }
        let popupTarget = capturePopupTarget(
            extensionID: extensionID,
            profileID: profileID,
            currentTab: currentTab,
            request: popupTargetRequest
        )
        environment.profileTransition.switchProfile(profileID: profileID)

        let context: WKWebExtensionContext
        do {
            trace(
                "urlHubAction loading selected context extensionId=\(extensionRecord.id) profileId=\(profileID.uuidString) runtimeState=\(runtimeState.rawValue) packagePath=\(extensionRecord.packagePath)"
            )
            guard let loaded = try await environment.contextResidency.ensureExtensionLoaded(
                extensionId: extensionRecord.id,
                profileId: profileID
            ) else {
                return .blocked(
                    unavailableContextResult(
                        extensionID: extensionID,
                        profileID: profileID,
                        extensionRecord: extensionRecord
                    )
                )
            }
            context = loaded
        } catch {
            let bucket = failureBucket(
                extensionID: extensionID,
                profileID: profileID,
                extensionRecord: extensionRecord
            )
            let diagnostics = diagnosticLines(
                extensionID: extensionID,
                profileID: profileID,
                extensionRecord: extensionRecord,
                bucket: bucket,
                error: error
            )
            trace(
                "urlHubAction selected context load failed extensionId=\(extensionID) bucket=\(bucket.rawValue) error=\(error.localizedDescription) \(diagnostics.joined(separator: " "))"
            )
            return .blocked(
                .blocked(
                    .runtimeLoadFailed,
                    message: "\(extensionRecord.name) WebKit context load failed: \(error.localizedDescription)",
                    diagnostics: diagnostics
                )
            )
        }

        guard context.isLoaded else {
            let bucket = failureBucket(
                extensionID: extensionID,
                profileID: profileID,
                extensionRecord: extensionRecord
            )
            let diagnostics = diagnosticLines(
                extensionID: extensionID,
                profileID: profileID,
                extensionRecord: extensionRecord,
                bucket: bucket,
                error: environment.runtimeCatalog.loadError(
                    extensionID: extensionID,
                    profileID: profileID
                )
            )
            trace(
                "urlHubAction runtime gate failed extensionId=\(extensionID) profileId=\(profileID.uuidString) bucket=\(bucket.rawValue) \(diagnostics.joined(separator: " "))"
            )
            let blocker: BrowserExtensionActionPopupBlocker =
                bucket == .globalRuntimeLoadFailed
                    || bucket == .webExtensionCreationFailed
                    || bucket == .profileContextNotLoaded
                ? .runtimeLoadFailed
                : .runtimeUnavailable
            return .blocked(
                .blocked(
                    blocker,
                    message: "\(extensionRecord.name) could not load WebKit extension runtime for the action popup.",
                    diagnostics: diagnostics
                )
            )
        }

        trace(
            "urlHubAction runtime ready extensionId=\(extensionID) profileId=\(profileID.uuidString) loadedContexts=\(environment.runtimeAccess.profileRuntime.contexts(for: profileID).count) selectedContextLoaded=true currentTabEligible=\(currentTab != nil)"
        )
        return .ready(
            .init(
                profileID: profileID,
                context: context,
                popupTarget: popupTarget
            )
        )
    }

    private var runtimeState: ExtensionManager.ExtensionRuntimeState {
        environment.runtimeLifecycle.state
    }

    private var currentProfileID: UUID? {
        environment.runtimeAccess.profileRuntime.currentProfileId
    }

    private func capturePopupTarget(
        extensionID: String,
        profileID: UUID,
        currentTab: Tab?,
        request: ExtensionActionPopupTargetRequest
    ) -> ExtensionActionPopupInvocationTarget? {
        if case .explicitAnchor(let requestedAnchorSessionToken) = request {
            guard let anchor = environment.anchorStore.anchor(
                      sessionToken: requestedAnchorSessionToken
                  ),
                  anchor.extensionID == extensionID,
                  anchor.profileID == profileID
            else {
                return nil
            }
            return .init(
                anchorSessionToken: requestedAnchorSessionToken,
                windowID: anchor.windowID
            )
        }
        let windowID = currentTab.flatMap(environment.primaryWindowID)
            ?? environment.activeWindowID()
        guard let windowID,
              let token = environment.anchorResolution.captureActionPopupAnchor(
            extensionId: extensionID,
            windowId: windowID,
            profileId: profileID,
            tab: currentTab
              )
        else {
            return nil
        }
        return .init(anchorSessionToken: token, windowID: windowID)
    }

    private func unavailableContextResult(
        extensionID: String,
        profileID: UUID,
        extensionRecord: InstalledExtension
    ) -> BrowserExtensionActionPopupRequestResult {
        let bucket = failureBucket(
            extensionID: extensionID,
            profileID: profileID,
            extensionRecord: extensionRecord
        )
        return .blocked(
            .contextUnavailable,
            message: "\(extensionRecord.name) has no enabled WebKit extension context for this profile.",
            diagnostics: diagnosticLines(
                extensionID: extensionID,
                profileID: profileID,
                extensionRecord: extensionRecord,
                bucket: bucket,
                error: environment.runtimeCatalog.loadError(
                    extensionID: extensionID,
                    profileID: profileID
                )
            )
        )
    }

    private func failureBucket(
        extensionID: String,
        profileID: UUID,
        extensionRecord: InstalledExtension
    ) -> ExtensionActionPopupRuntimeFailureBucket {
        environment.failureDiagnostics.classifyActionPopupRuntimeFailure(
            extensionId: extensionID,
            profileId: profileID,
            installedExtension: extensionRecord
        )
    }

    private func diagnosticLines(
        extensionID: String,
        profileID: UUID,
        extensionRecord: InstalledExtension,
        bucket: ExtensionActionPopupRuntimeFailureBucket,
        error: Error?
    ) -> [String] {
        environment.failureDiagnostics.actionPopupRuntimeDiagnosticLines(
            extensionId: extensionID,
            profileId: profileID,
            installedExtension: extensionRecord,
            failureBucket: bucket,
            lastLoadError: error
        )
    }

    private func trace(_ message: @autoclosure () -> String) {
        guard ExtensionManager.isWebKitRuntimeTraceEnabled else { return }
        environment.trace(message())
    }
}
