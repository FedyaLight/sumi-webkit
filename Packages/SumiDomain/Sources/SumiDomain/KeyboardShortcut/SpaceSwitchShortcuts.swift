import Foundation

/// The ordinal ↔ action mapping for "switch to the Nth space".
///
/// Both consumers cross this seam: the keyboard dispatcher turns an action back
/// into a strip position, and the sidebar turns a strip position into the action
/// whose binding it renders. Neither has to know the enum cases.
public enum SpaceSwitchShortcuts {
    /// Ordered by strip position: `actions[0]` switches to the first space.
    public static let actions: [ShortcutAction] = [
        .goToSpace1, .goToSpace2, .goToSpace3, .goToSpace4, .goToSpace5,
        .goToSpace6, .goToSpace7, .goToSpace8, .goToSpace9, .goToSpace10,
    ]

    /// The action that activates the space at `index`, or `nil` for spaces past
    /// the covered range — those simply have no shortcut.
    public static func action(forSpaceAt index: Int) -> ShortcutAction? {
        guard actions.indices.contains(index) else { return nil }
        return actions[index]
    }

    /// The strip position `action` activates, or `nil` when it is not a
    /// space-switching action.
    public static func spaceIndex(for action: ShortcutAction) -> Int? {
        actions.firstIndex(of: action)
    }
}
