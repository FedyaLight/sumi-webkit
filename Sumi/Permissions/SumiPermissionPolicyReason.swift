import Foundation

enum SumiPermissionPolicyReason {
    static let allowed = "permission-policy-allowed"
    static let requiresSinglePermissionType = "permission-policy-requires-single-permission-type"
    static let cameraAndMicrophoneRequiresCoordinatorExpansion =
        "camera-and-microphone-must-be-expanded-by-coordinator"
    static let storageAccessSameOrigin = "storage-access-requires-distinct-requesting-and-top-origins"
    static let emptyExternalSchemeUnsupported = "external-scheme-missing-scheme"
    static let invalidRequestingOrigin = "requesting-origin-invalid-or-opaque"
    static let invalidTopOrigin = "top-origin-invalid-or-opaque"
    static let unsupportedRequestingOrigin = "requesting-origin-unsupported-scheme"
    static let unsupportedTopOrigin = "top-origin-unsupported-scheme"
    static let internalPage = "internal-browser-page"
    static let fileOriginDenied = "file-origin-not-allowed-for-sensitive-permission"
    static let insecureRequestingOrigin = "requesting-origin-not-secure"
    static let insecureTopOrigin = "top-origin-not-secure"
    static let virtualURLMismatch = "visible-url-does-not-match-committed-origin"
    static let miniWindowSensitiveDenied = "mini-window-sensitive-permission-denied"
    static let peekSensitiveDenied = "peek-sensitive-permission-denied"
    static let extensionPageUnsupported = "extension-page-site-permission-unsupported"
    static let unknownSurfaceSensitiveDenied = "unknown-surface-sensitive-permission-denied"
    static let requiresUserActivation = "user-activation-required"
    static let systemAuthorizationNotDetermined = "system-authorization-not-determined"
    static let systemAuthorizationBlocked = "system-authorization-blocked"
    static let policyDenied = "policy-denied"
    static let policyAllowed = "policy-allowed"
}
