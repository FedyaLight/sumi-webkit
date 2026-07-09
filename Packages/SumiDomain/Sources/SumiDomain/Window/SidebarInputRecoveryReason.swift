import Foundation

public enum SidebarInputRecoveryReason: String, CaseIterable, CustomStringConvertible, Sendable {
    case menuEnded = "menu-ended"
    case popoverDismissed = "popover-dismissed"
    case structuralMenuAction = "structural-menu-action"
    case ownerUnresolvedAfterSoftRecovery = "owner-unresolved-after-soft-recovery"
    case dragSessionRecovery = "drag-session-recovery"
    case explicitFallback = "explicit-fallback"
    case unknownFallback = "unknown-fallback"

    public var description: String { rawValue }
}
