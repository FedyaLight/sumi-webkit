import Foundation

/// Browser split-shortcut capabilities grouped without forwarding behavior.
@MainActor
struct SplitShortcutServices {
    let focus: SplitShortcutFocusService
    let memberRestoration: SplitShortcutMemberRestoreService
    let hostedUnload: ShortcutHostedSplitUnloadService
}
