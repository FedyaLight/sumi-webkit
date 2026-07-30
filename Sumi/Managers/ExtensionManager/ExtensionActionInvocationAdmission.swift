import Foundation
import WebKit

/// Immutable authority snapshot for one user click on an extension action.
/// It binds the exact runtime objects (context, controller, revisions, load
/// generation), the exact installed-extension catalog record, and — when the
/// click targeted a page — the exact Tab with the profile and committed
/// document authority on which the click was authorized.
@available(macOS 15.5, *)
@MainActor
struct ExtensionActionInvocationEvidence {
    enum AdapterAuthority {
        case unresolved
        case notApplicable
        case absent
        case exact(ExtensionTabAdapter)
    }

    let request: ExtensionActionRequestEvidence
    let runtimeBinding: ExtensionControllerCallbackEvidence
    let installedRecord: InstalledExtension
    let adapterAuthority: AdapterAuthority

    var extensionID: String { runtimeBinding.extensionID }
    var profileID: UUID { runtimeBinding.profileID }
    var context: WKWebExtensionContext { runtimeBinding.context }
    var page: ExtensionActionRequestEvidence.PageAuthority? { request.page }
    var adapter: ExtensionTabAdapter? {
        guard case .exact(let adapter) = adapterAuthority else { return nil }
        return adapter
    }
}

/// Captures and revalidates the exact authority of one action invocation.
/// Composes the controller/context callback admission for the runtime-binding
/// slice and adds catalog, Tab and adapter authority. It performs no fallback
/// resolution and never repairs stale identity from mutable global state.
@available(macOS 15.5, *)
@MainActor
final class ExtensionActionInvocationAdmission {
    private let runtimeBindingAdmission: ExtensionControllerCallbackAdmission
    private let requestAdmission: ExtensionActionRequestAdmission
    private let installedExtensions: InstalledExtensionCollection
    private let adapterStore: ExtensionBrowserAdapterStore

    init(
        runtimeBindingAdmission: ExtensionControllerCallbackAdmission,
        requestAdmission: ExtensionActionRequestAdmission,
        installedExtensions: InstalledExtensionCollection,
        adapterStore: ExtensionBrowserAdapterStore
    ) {
        self.runtimeBindingAdmission = runtimeBindingAdmission
        self.requestAdmission = requestAdmission
        self.installedExtensions = installedExtensions
        self.adapterStore = adapterStore
    }

    /// Completes the pre-await click authority with the exact resolved runtime
    /// binding. It never silently adopts a newer catalog record, Tab profile
    /// or document produced while runtime resolution was suspended.
    func capture(
        request: ExtensionActionRequestEvidence,
        profileID: UUID,
        context: WKWebExtensionContext,
        controller: WKWebExtensionController?
    ) -> ExtensionActionInvocationEvidence? {
        guard requestAdmission.isCurrent(request),
              request.resolvedProfileID == profileID,
              let controller,
              let binding = runtimeBindingAdmission.capture(
            context: context,
            controller: controller
        ),
            binding.extensionID == request.extensionID,
            binding.profileID == profileID
        else {
            return nil
        }
        if let bindingAtClick = request.runtimeBindingAtClick,
           sameRuntimeBinding(bindingAtClick, binding) == false {
            return nil
        }
        guard let record = installedExtensions.record(
            for: request.extensionID
        ), record.isEnabled else {
            return nil
        }
        return ExtensionActionInvocationEvidence(
            request: request,
            runtimeBinding: binding,
            installedRecord: record,
            adapterAuthority: request.page == nil ? .notApplicable : .unresolved
        )
    }

    /// Binds the resolved adapter into the evidence. The adapter must be the
    /// exact live adapter registered for the clicked Tab; a replaced or
    /// pruned adapter fails the whole invocation instead of being re-resolved.
    func admitAdapter(
        _ adapter: ExtensionTabAdapter?,
        for evidence: ExtensionActionInvocationEvidence
    ) -> ExtensionActionInvocationEvidence? {
        guard baseAuthorityIsCurrent(evidence),
              let page = evidence.page else { return nil }
        if let adapter {
            guard adapterStore.existingTabAdapter(for: page.tab.id) === adapter,
                  adapter.represents(page.tab)
            else {
                return nil
            }
            return replacingAdapterAuthority(.exact(adapter), in: evidence)
        }
        guard adapterStore.existingTabAdapter(for: page.tab.id) == nil else {
            return nil
        }
        return replacingAdapterAuthority(.absent, in: evidence)
    }

    /// Exact currency check. Must pass after every await and before every
    /// independent effect of the invocation.
    func isCurrent(_ evidence: ExtensionActionInvocationEvidence) -> Bool {
        guard baseAuthorityIsCurrent(evidence) else { return false }
        if let page = evidence.page {
            guard page.tab.profileAssignment.changeRevision
                == page.profileAssignmentRevision,
                page.tab.profileId == page.profileID,
                page.resolvedProfileID == evidence.profileID
            else {
                return false
            }
            switch evidence.adapterAuthority {
            case .unresolved:
                return false
            case .notApplicable:
                return false
            case .absent:
                guard adapterStore.existingTabAdapter(for: page.tab.id) == nil else {
                    return false
                }
            case .exact(let adapter):
                guard adapterStore.existingTabAdapter(
                    for: page.tab.id
                ) === adapter,
                    adapter.represents(page.tab)
                else {
                    return false
                }
            }
        } else {
            guard case .notApplicable = evidence.adapterAuthority else {
                return false
            }
        }
        return true
    }

    private func baseAuthorityIsCurrent(
        _ evidence: ExtensionActionInvocationEvidence
    ) -> Bool {
        requestAdmission.isCurrent(evidence.request)
            && runtimeBindingAdmission.isCurrent(evidence.runtimeBinding)
            && installedExtensions.record(for: evidence.extensionID)?
                .isEnabled == true
    }

    private func sameRuntimeBinding(
        _ lhs: ExtensionControllerCallbackEvidence,
        _ rhs: ExtensionControllerCallbackEvidence
    ) -> Bool {
        lhs.context === rhs.context
            && lhs.controller === rhs.controller
            && lhs.profileID == rhs.profileID
            && lhs.extensionID == rhs.extensionID
            && lhs.controllerBindingRevision == rhs.controllerBindingRevision
            && lhs.contextBindingRevision == rhs.contextBindingRevision
            && lhs.extensionLoadRevision == rhs.extensionLoadRevision
    }

    private func replacingAdapterAuthority(
        _ adapterAuthority: ExtensionActionInvocationEvidence.AdapterAuthority,
        in evidence: ExtensionActionInvocationEvidence
    ) -> ExtensionActionInvocationEvidence {
        ExtensionActionInvocationEvidence(
            request: evidence.request,
            runtimeBinding: evidence.runtimeBinding,
            installedRecord: evidence.installedRecord,
            adapterAuthority: adapterAuthority
        )
    }
}
