import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeDiagnosticsOwner {
    private weak var manager: ExtensionManager?

    init(manager: ExtensionManager) {
        self.manager = manager
    }

    func trace(_ message: String) {
        RuntimeDiagnostics.logger(category: "ExtensionRuntimeTrace")
            .debug("\(message, privacy: .public)")
    }

    static func objectDescription(_ object: AnyObject?) -> String {
        guard let object else { return "nil" }
        return String(describing: Unmanaged.passUnretained(object).toOpaque())
    }

    #if DEBUG || SUMI_DIAGNOSTICS
        func traceNativeMessagingContextBinding(
            phase: String,
            extensionId: String?,
            profileId: UUID?,
            loadSource: SafariAppExtensionRuntimeLoadSource? = nil,
            webExtension: WKWebExtension? = nil,
            extensionContext: WKWebExtensionContext? = nil,
            controller: WKWebExtensionController? = nil,
            configuration: WKWebViewConfiguration? = nil,
            webView: WKWebView? = nil
        ) {
            guard RuntimeDiagnostics.isVerboseEnabled,
                  let manager
            else { return }

            let profileController = profileId.flatMap {
                manager.extensionControllersByProfile[$0]
            }
            let effectiveController = controller ?? configuration?.webExtensionController
                ?? webView?.configuration.webExtensionController
                ?? extensionContext?.webViewConfiguration?.webExtensionController
                ?? profileController
            let delegate = effectiveController?.delegate
            let delegateObject = delegate.map { $0 as AnyObject }
            let delegateNSObject: NSObjectProtocol? = delegate
            let sendSelector = #selector(
                WKWebExtensionControllerDelegate.webExtensionController(
                    _:sendMessage:toApplicationWithIdentifier:for:replyHandler:
                )
            )
            let connectSelector = #selector(
                WKWebExtensionControllerDelegate.webExtensionController(
                    _:connectUsing:for:completionHandler:
                )
            )
            let controllerOwnsContext: String = {
                guard let effectiveController, let extensionContext else { return "-" }
                return String(
                    effectiveController.extensionContext(for: extensionContext.baseURL)
                        === extensionContext
                )
            }()
            let nativeMessagingGranted: String = {
                guard let extensionContext else { return "-" }
                return String(
                    manager.isGrantedPermissionStatus(
                        extensionContext.permissionStatus(for: .nativeMessaging)
                    )
                )
            }()
            let unsupportedNativeMessaging: String = {
                guard let extensionContext else { return "-" }
                return String(
                    extensionContext.unsupportedAPIs.contains {
                        $0.localizedCaseInsensitiveContains("nativeMessaging")
                    }
                )
            }()
            let configurationController = configuration?.webExtensionController
            let webViewController = webView?.configuration.webExtensionController
            let contextConfigurationController =
                extensionContext?.webViewConfiguration?.webExtensionController
            let delegateIsSumiControllerBridge: Bool = {
                guard let delegateObject else { return false }
                return delegateObject === manager.controllerDelegateBridge
            }()
            let controllerIsProfile: Bool = {
                guard let effectiveController, let profileController else { return false }
                return effectiveController === profileController
            }()
            let contextConfigurationControllerMatches: Bool = {
                guard let contextConfigurationController, let effectiveController else {
                    return false
                }
                return contextConfigurationController === effectiveController
            }()
            let configurationControllerMatches: Bool = {
                guard let configurationController, let effectiveController else { return false }
                return configurationController === effectiveController
            }()
            let webViewControllerMatches: Bool = {
                guard let webViewController, let effectiveController else { return false }
                return webViewController === effectiveController
            }()
            let delegateRespondsToSend = delegateNSObject?.responds(to: sendSelector) ?? false
            let delegateRespondsToConnect = delegateNSObject?.responds(to: connectSelector) ?? false

            RuntimeDiagnostics.debug(category: "SafariNativeMessagingContext") {
                """
                phase=\(phase) \
                extBucket=\(SafariExtensionNativeMessagingRoutingProbe.extensionIdBucket(extensionId)) \
                profile=\(SafariExtensionNativeMessagingRoutingProbe.profileIdBucket(profileId)) \
                loadSource=\(loadSource?.rawValue ?? "-") \
                webExtension=\(Self.objectDescription(webExtension)) \
                context=\(Self.objectDescription(extensionContext)) \
                controller=\(Self.objectDescription(effectiveController)) \
                profileController=\(Self.objectDescription(profileController)) \
                controllerIsProfile=\(controllerIsProfile) \
                controllerOwnsContext=\(controllerOwnsContext) \
                nativeMessagingGranted=\(nativeMessagingGranted) \
                unsupportedNativeMessaging=\(unsupportedNativeMessaging) \
                delegate=\(delegateObject.map { String(describing: type(of: $0)) } ?? "nil") \
                delegateIsSumiBridge=\(delegateIsSumiControllerBridge) \
                delegateSend=\(delegateRespondsToSend) \
                delegateConnect=\(delegateRespondsToConnect) \
                contextConfigControllerMatches=\(contextConfigurationControllerMatches) \
                configControllerMatches=\(configurationControllerMatches) \
                webViewControllerMatches=\(webViewControllerMatches)
                """
            }
        }
    #endif

    func tabDescription(_ tab: Tab) -> String {
        guard let manager else {
            return "tab=\(tab.id.uuidString.prefix(8))"
        }

        let webViews = manager.liveWebViews(for: tab)
            .map { Self.objectDescription($0) }
            .joined(separator: ",")
        let resolvedURL = manager.resolvedLiveWebView(for: tab)?.url?.absoluteString
            ?? tab.url.absoluteString
        return "tab=\(tab.id.uuidString.prefix(8)) url=\(resolvedURL) webViews=[\(webViews)]"
    }
}
