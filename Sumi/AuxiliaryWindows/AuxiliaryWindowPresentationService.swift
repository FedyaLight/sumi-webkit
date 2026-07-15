import AppKit
import Foundation
import WebKit

@MainActor
enum AuxiliaryWindowExtensionIdentityResolver {
    static func resolve(
        extensionIntegration: AuxiliaryWindowExtensionIntegration?,
        extensionContext: WKWebExtensionContext?,
        openerTab: Tab?,
        extensionOwnedSourceURL: URL?,
        explicitExtensionID: String?
    ) -> String? {
        if let extensionIntegration {
            return extensionIntegration.resolveExtensionID(
                extensionContext,
                openerTab,
                extensionOwnedSourceURL,
                explicitExtensionID
            )
        }

        if let explicitExtensionID {
            return explicitExtensionID
        }

        for candidate in [extensionOwnedSourceURL, openerTab?.url] {
            guard let url = candidate,
                  ExtensionURLIdentity.isOwned(url),
                  let host = url.host,
                  host.isEmpty == false else {
                continue
            }
            return host
        }
        return nil
    }
}

@MainActor
struct AuxiliaryWindowExtensionIntegration {
    typealias ExtensionIDResolver = @MainActor (
        WKWebExtensionContext?,
        Tab?,
        URL?,
        String?
    ) -> String?
    typealias MiniWindowAdapterFactory = @MainActor (
        UUID,
        Tab,
        AuxiliaryCompactWindow,
        Bool,
        Bool
    ) -> ExtensionMiniWindowAdapter?

    /// Titles are resolved at presentation time. Keeping the query live avoids
    /// retaining a stale installation snapshot across enable/disable, update,
    /// and uninstall transitions.
    let installedExtensions: @MainActor () -> [InstalledExtension]
    let events: any AuxiliaryWindowExtensionEventHandling
    let resolveExtensionID: ExtensionIDResolver
    let makeMiniWindowAdapter: MiniWindowAdapterFactory
}

enum AuxiliaryWindowTitleResolver {
    static func title(
        for url: URL?,
        extensionID: String?,
        installedExtensions: [InstalledExtension]
    ) -> String {
        if ExtensionURLIdentity.isOwned(url) {
            return ExtensionDisplayNameResolver.displayName(
                forOwnedURL: url,
                installedExtensions: installedExtensions
            ) ?? ExtensionDisplayNameResolver.displayName(
                for: extensionID,
                installedExtensions: installedExtensions
            ) ?? "Extension"
        }

        if let host = url?.host, host.isEmpty == false {
            return host
        }
        return "Popup"
    }
}

@MainActor
struct AuxiliaryWindowPresentationRequest {
    let tab: Tab
    let webView: WKWebView
    let geometry: AuxiliaryWindowGeometry
    let openerTab: Tab?
    let explicitOpenerWindow: NSWindow?
    let titleURL: URL?
    let shouldActivateApp: Bool
    let isPrivate: Bool
    let nestedDepth: Int
    let extensionIntegration: AuxiliaryWindowExtensionIntegration?
    let extensionID: String?
}

@MainActor
struct AuxiliaryWindowPresentation {
    let session: AuxiliaryWindowSession
    let receipt: AuxiliaryWindowSessionReceipt
}

@MainActor
final class AuxiliaryWindowPresentationService {
    private let sessions: AuxiliaryWindowSessionRegistry
    private let context: any AuxiliaryWindowContextResolving
    private let permissions: any AuxiliaryWindowPermissionHandling
    private let nestingPolicy: AuxiliaryWindowNestingPolicy
    private let teardown: AuxiliaryWindowTeardownService
    private let focus: AuxiliaryWindowFocusService

    init(
        sessions: AuxiliaryWindowSessionRegistry,
        context: any AuxiliaryWindowContextResolving,
        permissions: any AuxiliaryWindowPermissionHandling,
        nestingPolicy: AuxiliaryWindowNestingPolicy,
        teardown: AuxiliaryWindowTeardownService,
        focus: AuxiliaryWindowFocusService
    ) {
        self.sessions = sessions
        self.context = context
        self.permissions = permissions
        self.nestingPolicy = nestingPolicy
        self.teardown = teardown
        self.focus = focus
    }

    func present(
        _ request: AuxiliaryWindowPresentationRequest,
        nestedPopups: AuxiliaryPopupOpeningService
    ) -> AuxiliaryWindowPresentation {
        let sessionID = UUID()
        let openerWindow = request.explicitOpenerWindow
            ?? request.openerTab.flatMap(context.parentWindow(for:))
        let window = AuxiliaryCompactWindow(
            contentRect: request.geometry.contentRect
        )
        window.title = AuxiliaryWindowTitleResolver.title(
            for: request.titleURL,
            extensionID: request.extensionID,
            installedExtensions: request.extensionIntegration?
                .installedExtensions() ?? []
        )

        let container = NSView(
            frame: NSRect(origin: .zero, size: request.geometry.contentRect.size)
        )
        window.contentView = container
        request.webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(request.webView)
        NSLayoutConstraint.activate([
            request.webView.topAnchor.constraint(equalTo: container.topAnchor),
            request.webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            request.webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            request.webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        let uiDelegate = AuxiliaryWindowUIDelegate(
            sessions: sessions,
            popups: nestedPopups,
            teardown: teardown,
            permissions: permissions,
            nestingPolicy: nestingPolicy,
            nestedDepth: request.nestedDepth
        )
        request.webView.uiDelegate = uiDelegate

        let windowDelegate = AuxiliaryWindowSessionDelegate(
            teardown: teardown,
            focus: focus
        )
        window.delegate = windowDelegate

        let miniWindowAdapter: ExtensionMiniWindowAdapter?
        if let extensionIntegration = request.extensionIntegration {
            miniWindowAdapter = extensionIntegration.makeMiniWindowAdapter(
                sessionID,
                request.tab,
                window,
                request.isPrivate,
                request.shouldActivateApp
            )
        } else {
            miniWindowAdapter = nil
        }

        let session = AuxiliaryWindowSession(
            id: sessionID,
            tab: request.tab,
            window: window,
            webView: request.webView,
            openerTab: request.openerTab,
            openerWindow: openerWindow,
            shouldActivateApp: request.shouldActivateApp,
            isPrivate: request.isPrivate,
            ownerExtensionID: request.extensionID,
            miniWindowAdapter: miniWindowAdapter,
            extensionEvents: request.extensionIntegration?.events,
            uiDelegate: uiDelegate,
            windowDelegate: windowDelegate
        )

        let receipt = sessions.register(session)
        uiDelegate.bind(receipt)
        windowDelegate.bind(receipt)
        miniWindowAdapter?.bind(receipt)
        window.present(shouldActivateApp: request.shouldActivateApp)
        if request.extensionID != nil, request.shouldActivateApp {
            focus.record(receipt)
        }
        return AuxiliaryWindowPresentation(
            session: session,
            receipt: receipt
        )
    }

    func isCurrent(_ receipt: AuxiliaryWindowSessionReceipt) -> Bool {
        sessions.session(for: receipt) != nil
    }
}
