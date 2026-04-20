import Foundation

/// Phase 0 reference: every `NSEvent.addLocalMonitorForEvents` call site in Sumi.
///
/// Local monitors run **before** normal dispatch; multiple monitors compose in **reverse registration order**
/// (newest first). When debugging “click/menu freezes”, verify no monitor returns `nil` unexpectedly or
/// performs heavy synchronous work while another framework (e.g. `NSMenu` modal loop) still owns input.
///
/// Inventory (search `addLocalMonitorForEvents` to refresh):
/// - [`AppDelegate`](App/AppDelegate.swift) — `.otherMouseDown` routing.
/// - [`CommandPaletteView`](CommandPalette/CommandPaletteView.swift) — outside-click dismissal; always returns the event.
/// - [`HoverSidebarManager`](Sumi/Managers/HoverSidebarManager/HoverSidebarManager.swift) — mouse move / drag for hover sidebar.
/// - [`KeyboardShortcutManager`](Sumi/Managers/KeyboardShortcutManager/KeyboardShortcutManager.swift) — `.keyDown` routing.
/// - [`ShortcutRecorderView`](Sumi/Components/Settings/ShortcutRecorderView.swift) — key capture while recording.
///
/// Sidebar context menus are AppKit view/NSMenu backed and do not install a local mouse monitor.
enum EventMonitorInventory {
    static let documentation = """
    Prefer consolidating new global/local monitors behind a single coordinator when possible.
    """

    static func assertMainThreadForMenuSideEffects(file: StaticString = #file, line: UInt = #line) {
        assert(Thread.isMainThread, "Menu actions and NSMenu callbacks must stay on the main thread.", file: file, line: line)
    }
}
