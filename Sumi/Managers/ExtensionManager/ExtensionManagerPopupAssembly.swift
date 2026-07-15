import Foundation

@available(macOS 15.5, *)
@MainActor
struct ExtensionPopupAssemblyProduct {
    let anchorResolver: ExtensionActionPopupAnchorResolver
    let telemetry: ExtensionActionPopupTelemetry
    let focus: ExtensionActionPopupFocusRestorer
    let retirement: ExtensionActionPopupRetirementService
    let commitRecorder: ExtensionActionPopupCommitRecorder
    let runtimeRetirement: ExtensionActionPopupRuntimeRetirement
}

@available(macOS 15.5, *)
@MainActor
extension ExtensionManagerAssembler {
    static func assemblePopup(
        _ f: ExtensionManagerAssemblyFoundation
    ) -> ExtensionPopupAssemblyProduct {
        let anchorResolver = makePopupAnchorResolver(f)
        let telemetry = makePopupTelemetry(f)
        let focus = ExtensionActionPopupFocusRestorer(
            browser: f.browser.action
        )
        let retirement = ExtensionActionPopupRetirementService(
            sessions: f.actions.actionPopupSessions,
            focusRestorer: focus,
            telemetry: telemetry
        )
        let commitRecorder = ExtensionActionPopupCommitRecorder(
            sessions: f.actions.actionPopupSessions,
            telemetry: telemetry
        )
        return ExtensionPopupAssemblyProduct(
            anchorResolver: anchorResolver,
            telemetry: telemetry,
            focus: focus,
            retirement: retirement,
            commitRecorder: commitRecorder,
            runtimeRetirement: ExtensionActionPopupRuntimeRetirement(
                sessions: retirement,
                invocations: f.actions.actionPopupInvocations
            )
        )
    }
}
