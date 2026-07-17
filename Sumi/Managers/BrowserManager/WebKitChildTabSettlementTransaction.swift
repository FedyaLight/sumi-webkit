import Foundation
import WebKit

/// Publishes one prepared child Tab into the tracked WebView graph and applies
/// presentation effects only after exact placement succeeds.
@MainActor
final class WebKitChildTabSettlementTransaction {
    struct Admission {
        fileprivate let transactionID: ObjectIdentifier
        fileprivate let placement: any AuxiliaryTrackedWebViewPlacing
        fileprivate let extensionTabs: (any ExtensionCreatedTabRegistering)?
    }

    private let residences: BrowserTabResidenceAuthority
    private weak var placement: (any AuxiliaryTrackedWebViewPlacing)?
    private let selection: BrowserTabSelectionCommand
    private weak var notifications: (any BackgroundTabOpenedNotifying)?
    private weak var extensionTabs: (any ExtensionCreatedTabRegistering)?

    init(
        residences: BrowserTabResidenceAuthority,
        placement: any AuxiliaryTrackedWebViewPlacing,
        selection: BrowserTabSelectionCommand,
        notifications: any BackgroundTabOpenedNotifying,
        extensionTabs: any ExtensionCreatedTabRegistering
    ) {
        self.residences = residences
        self.placement = placement
        self.selection = selection
        self.notifications = notifications
        self.extensionTabs = extensionTabs
    }

    func admit(isExtensionOriginated: Bool) -> Admission? {
        guard let placement,
              isExtensionOriginated == false || extensionTabs != nil
        else {
            return nil
        }
        return Admission(
            transactionID: ObjectIdentifier(self),
            placement: placement,
            extensionTabs: isExtensionOriginated ? extensionTabs : nil
        )
    }

    func commit(
        _ prepared: PreparedWebKitChildTab,
        admission: Admission,
        configuration: WKWebViewConfiguration,
        requestURL: URL?,
        source: PhysicalWebViewSourceReceipt,
        selected: Bool,
        isExtensionOriginated: Bool
    ) -> WKWebView? {
        guard admission.transactionID == ObjectIdentifier(self),
              isExtensionOriginated == false
                || admission.extensionTabs != nil
        else {
            WebKitChildTabRollback.discard(
                prepared.tab,
                webView: nil,
                residence: prepared.residence,
                sourceWindow: source.window,
                residences: residences
            )
            return nil
        }

        prepared.tab.visitedLinkStore.applyStore(
            to: configuration,
            for: source.executionProfile
        )
        let webView = prepared.tab.createPopupWebViewFromWebKitConfiguration(
            configuration,
            currentURL: requestURL,
            isExtensionOriginated: isExtensionOriginated,
            reason: "WebKitChildTabOpeningService.open"
        )
        let placementOutcome = admission.placement.registerAuxiliaryTrackedWebView(
            webView,
            for: prepared.tab,
            in: source.window.id
        )
        guard placementOutcome.isAccepted else {
            WebKitChildTabRollback.discard(
                prepared.tab,
                webView: webView,
                residence: prepared.residence,
                sourceWindow: source.window,
                residences: residences
            )
            return nil
        }

        source.window.markWebKitChildWindowAdopted(by: prepared.tab.id)
        if selected {
            selection.select(
                prepared.tab,
                in: source.window,
                loadPolicy: .immediate
            )
        } else if isExtensionOriginated == false {
            notifications?.presentBackgroundTabOpenedNotification(
                tabId: prepared.tab.id,
                in: source.window
            )
        }
        if isExtensionOriginated {
            admission.extensionTabs?
                .registerExtensionCreatedTabWithExtensionRuntimeIfLoaded(
                    prepared.tab,
                    reason: "WebKitChildTabOpeningService.open"
                )
        }
        return webView
    }
}
