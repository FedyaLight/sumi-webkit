import Foundation
import SumiDomain
import WebKit

/// The configuration-time policy plan used to construct one normal-tab WebView
/// generation. Runtime rule-list lookup and hot-swap results remain observable
/// through the user-content-controller diagnostics; this state deliberately
/// does not pretend to be that post-construction physical snapshot.
@MainActor
struct TabConfigurationPolicyState: Equatable {
    var profileID: UUID?
    var websiteDataStoreIdentity: ObjectIdentifier?
    var protectionAttachment: SumiProtectionAttachmentState?
    var safariContentBlockerAttachment:
        SumiSafariContentBlockerAttachmentState?
    var autoplayState: SumiRuntimeAutoplayState?

    static let unknown = Self(
        profileID: nil,
        websiteDataStoreIdentity: nil,
        protectionAttachment: nil,
        safariContentBlockerAttachment: nil,
        autoplayState: nil
    )

    var fingerprint: TabConfigurationPolicyFingerprint {
        TabConfigurationPolicyFingerprint(
            profileID: profileID,
            websiteDataStoreIdentity: websiteDataStoreIdentity,
            isProtectionEnabled: protectionAttachment?.isEnabled == true,
            protectionRuleListIdentifiers: protectionAttachment?
                .effectiveWebViewRuleListIdentifiers ?? [],
            safariRuleIdentities: safariContentBlockerAttachment?
                .effectiveWebViewRuleIdentities ?? [],
            autoplayState: autoplayState
        )
    }
}

/// Configuration properties that must match across every physical WebView in
/// one clone generation. Site/diagnostic metadata is intentionally excluded.
@MainActor
struct TabConfigurationPolicyFingerprint: Equatable {
    let profileID: UUID?
    let websiteDataStoreIdentity: ObjectIdentifier?
    let isProtectionEnabled: Bool
    let protectionRuleListIdentifiers: [String]
    let safariRuleIdentities: [String]
    let autoplayState: SumiRuntimeAutoplayState?
}

@MainActor
struct PreparedNormalTabWebViewConfiguration {
    let configuration: WKWebViewConfiguration
    let policyState: TabConfigurationPolicyState
}
