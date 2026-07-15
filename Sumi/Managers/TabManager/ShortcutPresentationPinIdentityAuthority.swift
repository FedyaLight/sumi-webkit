@MainActor
enum ShortcutPresentationPinIdentityAuthority {
    case canonical
    case catalogHandoff(ShortcutPresentationCatalogIdentityHandoff)

    var isCanonical: Bool {
        if case .canonical = self { return true }
        return false
    }

    func accepts(current: ShortcutPin, expected: ShortcutPin) -> Bool {
        switch self {
        case .canonical:
            return current === expected
        case .catalogHandoff(let handoff):
            return current === expected
                || handoff.authorizesReplacement(
                    of: expected,
                    with: current
                )
        }
    }
}
