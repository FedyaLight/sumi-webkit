import Foundation
import Observation

/// Runtime-only state of the currently attached shell and transient chrome.
/// This authority is never encoded into the durable window snapshot.
@MainActor
@Observable
final class WindowPresentationState {
    var isDownloadsPopoverPresented = false
    var isFloatingBarVisible = false
    var urlBarFrame: CGRect = .zero
    var visibility: SumiWindowVisibilityState = .unknown
    var pendingSplitGroupFocusRequest: SplitGroupFocusRequest?
}
