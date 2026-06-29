import Foundation

struct SumiSystemPermissionSnapshot: Codable, Equatable, Hashable, Sendable {
    let kind: SumiSystemPermissionKind
    let state: SumiSystemPermissionAuthorizationState
    let canRequestFromSystem: Bool
    let shouldOpenSystemSettings: Bool
    let reason: String

    init(
        kind: SumiSystemPermissionKind,
        state: SumiSystemPermissionAuthorizationState,
        reason: String? = nil
    ) {
        self.kind = kind
        self.state = state
        self.canRequestFromSystem = state.canRequestFromSystem
        self.shouldOpenSystemSettings = state.shouldOpenSystemSettings
        self.reason = reason ?? Self.defaultReason(kind: kind, state: state)
    }

    /// Encodes an optional snapshot to a UTF-8 JSON string for persistence.
    /// Returns `nil` for a `nil` snapshot or when encoding fails; failures are
    /// surfaced via `RuntimeDiagnostics` (no throw, no payload contents logged).
    static func encodedJSONString(for snapshot: SumiSystemPermissionSnapshot?) -> String? {
        guard let snapshot else {
            return nil
        }
        do {
            let data = try JSONEncoder().encode(snapshot)
            guard let encoded = String(data: data, encoding: .utf8) else {
                RuntimeDiagnostics.emit(
                    "[Permissions] Failed to UTF-8 encode system permission snapshot."
                )
                return nil
            }
            return encoded
        } catch {
            RuntimeDiagnostics.emit(
                "[Permissions] Failed to encode system permission snapshot: \(error.localizedDescription)"
            )
            return nil
        }
    }

    private static func defaultReason(
        kind: SumiSystemPermissionKind,
        state: SumiSystemPermissionAuthorizationState
    ) -> String {
        let label = kind.displayLabel
        switch state {
        case .notDetermined:
            return "\(label) access has not been requested from macOS."
        case .authorized:
            return "\(label) access is authorized by macOS."
        case .denied:
            return "\(label) access was denied for Sumi in macOS settings."
        case .restricted:
            return "\(label) access is restricted by macOS or device policy."
        case .systemDisabled:
            return "\(label) access is disabled globally in macOS settings."
        case .unavailable:
            return "\(label) access is unavailable on this Mac or runtime."
        case .missingUsageDescription:
            return "\(label) access is missing the required Info.plist usage description."
        case .missingEntitlement:
            return "\(label) access is missing the required sandbox entitlement."
        }
    }
}
