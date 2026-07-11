import Foundation
import WebKit

/// Immutable proof captured while a normal window's selected Tab is still
/// private to the native window transaction.
@available(macOS 15.5, *)
@MainActor
struct ExtensionInitialTabPublicationEvidence {
    let window: BrowserWindowState
    let tab: Tab
    let webView: FocusableWKWebView
    let profile: Profile
    let dataStore: WKWebsiteDataStore
    let profileID: UUID
    let extensionLoadGeneration: UInt64
    let tabGeneration: UInt64
    let contextBindingGeneration: UInt64
    let controller: WKWebExtensionController
    let adapter: ExtensionTabAdapter
    let createdAdapter: Bool
    let stateToken: TabExtensionPrepublicationToken
    let reason: String
}

@available(macOS 15.5, *)
@MainActor
struct ExtensionInitialTabDelegatedOpenEvidence {
    let generation: UInt64
    let controller: WKWebExtensionController
    let claim: TabExtensionOpenPublicationClaim
}
