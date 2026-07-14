import AppKit
import WebKit

@available(macOS 15.5, *)
struct ExtensionOptionsWindowReceipt: Hashable, Sendable {
    let extensionID: String
    let registrationID: UUID

    init(extensionID: String, registrationID: UUID = UUID()) {
        self.extensionID = extensionID
        self.registrationID = registrationID
    }
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionOptionsWindowRegistry {
    struct Registration {
        let receipt: ExtensionOptionsWindowReceipt
        let profileID: UUID?
        let window: NSWindow
        let webView: WKWebView?
        let delegate: ExtensionOptionsWindowDelegate?
    }

    private var registrationsByExtensionID: [String: Registration] = [:]
    private let presentationClaims =
        ExtensionOptionsWindowPresentationClaimLedger()

    var extensionIDs: Set<String> {
        Set(registrationsByExtensionID.keys)
    }

    var windows: [String: NSWindow] {
        registrationsByExtensionID.mapValues(\.window)
    }

    func receipt(for extensionID: String) -> ExtensionOptionsWindowReceipt? {
        registrationsByExtensionID[extensionID]?.receipt
    }

    func registration(for extensionID: String) -> Registration? {
        registrationsByExtensionID[extensionID]
    }

    func owns(_ webView: WKWebView) -> Bool {
        registrationsByExtensionID.values.contains {
            $0.webView === webView
        }
    }

    func owns(_ window: NSWindow) -> Bool {
        registrationsByExtensionID.values.contains {
            $0.window === window
        }
    }

    func issuePresentationClaim(
        for extensionID: String,
        profileID: UUID?
    ) -> ExtensionOptionsWindowPresentationClaim {
        presentationClaims.issue(for: extensionID, profileID: profileID)
    }
    func isCurrent(
        _ claim: ExtensionOptionsWindowPresentationClaim
    ) -> Bool {
        presentationClaims.isCurrent(claim)
    }
    func invalidatePresentationClaim(for extensionID: String) {
        presentationClaims.invalidate(for: extensionID)
    }
    func invalidatePresentationClaims(backedBy profileIDs: Set<UUID>) {
        presentationClaims.invalidate(backedBy: profileIDs)
    }
    func invalidateAllPresentationClaims() {
        presentationClaims.invalidateAll()
    }
    func receipts(backedBy profileIDs: Set<UUID>) -> [ExtensionOptionsWindowReceipt] {
        registrationsByExtensionID.values.compactMap { registration in
            guard let profileID = registration.profileID else {
                // An unclassified profile-store window cannot safely survive
                // a destructive profile mutation.
                return registration.receipt
            }
            return profileIDs.contains(profileID) ? registration.receipt : nil
        }
    }

    func register(
        window: NSWindow,
        webView: WKWebView?,
        delegate: ExtensionOptionsWindowDelegate?,
        extensionID: String,
        profileID: UUID?,
        claim: ExtensionOptionsWindowPresentationClaim
    ) -> (
        receipt: ExtensionOptionsWindowReceipt,
        superseded: Registration?
    )? {
        guard claim.extensionID == extensionID,
              claim.profileID == profileID,
              isCurrent(claim) else {
            return nil
        }
        let receipt = ExtensionOptionsWindowReceipt(extensionID: extensionID)
        let superseded = registrationsByExtensionID.updateValue(
            Registration(
                receipt: receipt,
                profileID: profileID,
                window: window,
                webView: webView,
                delegate: delegate
            ),
            forKey: extensionID
        )
        return (receipt, superseded)
    }

    func retire(
        _ receipt: ExtensionOptionsWindowReceipt
    ) -> Registration? {
        guard registrationsByExtensionID[receipt.extensionID]?.receipt == receipt
        else { return nil }
        invalidatePresentationClaim(for: receipt.extensionID)
        return registrationsByExtensionID.removeValue(
            forKey: receipt.extensionID
        )
    }
}
