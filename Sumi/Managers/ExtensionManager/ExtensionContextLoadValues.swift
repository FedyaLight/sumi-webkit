import Foundation
import WebKit

@available(macOS 15.5, *)
struct ExtensionLoadedContext {
    let context: WKWebExtensionContext
    let controller: WKWebExtensionController
    let bindingReceipt: ExtensionContextBindingReceipt
    let loadClaim: ExtensionContextLoadClaim
    let mutationLease: ExtensionRuntimeMutationLease?
    /// The scope that admits extension-created bootstrap tabs during the
    /// activation transaction. It is released after background startup work,
    /// so later user actions are never mistaken for install chrome.
    let bootstrapChromeScope: ExtensionBootstrapChromeAdmission.Scope?

    init(
        context: WKWebExtensionContext,
        controller: WKWebExtensionController,
        bindingReceipt: ExtensionContextBindingReceipt,
        loadClaim: ExtensionContextLoadClaim,
        mutationLease: ExtensionRuntimeMutationLease?,
        bootstrapChromeScope: ExtensionBootstrapChromeAdmission.Scope? = nil
    ) {
        self.context = context
        self.controller = controller
        self.bindingReceipt = bindingReceipt
        self.loadClaim = loadClaim
        self.mutationLease = mutationLease
        self.bootstrapChromeScope = bootstrapChromeScope
    }
}

@available(macOS 15.5, *)
struct ExtensionPreparedContext {
    let context: WKWebExtensionContext
    let runtimeIdentifier: String
}

@available(macOS 15.5, *)
struct ExtensionControllerBindingSnapshot {
    let profileID: UUID
    let controller: WKWebExtensionController
    let revision: UInt64
}

@available(macOS 15.5, *)
enum ExtensionContextLoadOperation {
    case loadEnabled
    case install
    case safariEnable

    var recordsRuntimeMetrics: Bool {
        switch self {
        case .loadEnabled:
            return true
        case .install, .safariEnable:
            return false
        }
    }

    var runtimeTraceOperation: String {
        switch self {
        case .loadEnabled:
            return "loadEnabledExtension"
        case .install:
            return "performInstallation"
        case .safariEnable:
            return "enableSafariAppExtension"
        }
    }

    var webExtensionCreatedPhase: String {
        switch self {
        case .loadEnabled:
            return "webExtensionCreated"
        case .install:
            return "installWebExtensionCreated"
        case .safariEnable:
            return "safariEnableWebExtensionCreated"
        }
    }

    var contextPreparedPhase: String {
        switch self {
        case .loadEnabled:
            return "contextPrepared"
        case .install:
            return "installContextPrepared"
        case .safariEnable:
            return "safariEnableContextPrepared"
        }
    }

    var beforeControllerLoadPhase: String {
        switch self {
        case .loadEnabled:
            return "beforeControllerLoad"
        case .install:
            return "installBeforeControllerLoad"
        case .safariEnable:
            return "safariEnableBeforeControllerLoad"
        }
    }

    var afterControllerLoadPhase: String {
        switch self {
        case .loadEnabled:
            return "afterControllerLoad"
        case .install:
            return "installAfterControllerLoad"
        case .safariEnable:
            return "safariEnableAfterControllerLoad"
        }
    }

    var beforeControllerLoadStorePhase: String {
        switch self {
        case .loadEnabled:
            return "before-loadEnabledExtension-controller-load"
        case .install:
            return "before-install-controller-load"
        case .safariEnable:
            return "before-safari-enable-controller-load"
        }
    }

    var emitsLoadedTrace: Bool {
        switch self {
        case .loadEnabled:
            return true
        case .install, .safariEnable:
            return false
        }
    }
}

@available(macOS 15.5, *)
struct ExtensionContextLoadRequest {
    let extensionId: String
    let profileId: UUID
    let sourceKind: WebExtensionSourceKind
    let sourceBundlePath: String
    let packageRoot: URL
    let manifest: [String: Any]
    let operation: ExtensionContextLoadOperation
    let activationCause: ExtensionActivationCause
    let claim: ExtensionContextLoadClaim
    let mutationLease: ExtensionRuntimeMutationLease?
}

@available(macOS 15.5, *)
struct WebExtensionRuntimeSourceKey: Equatable {
    let sourceKind: WebExtensionSourceKind
    let sourceBundlePath: String
    let packageRootPath: String
}
