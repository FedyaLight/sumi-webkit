import Foundation

struct BrowserToast: Equatable, Identifiable {
    enum Kind: Equatable {
        case profileSwitch(profileName: String)
        case tabClosure(count: Int)
        case copyURL
    }

    let id = UUID()
    let kind: Kind

    var duration: TimeInterval {
        switch kind {
        case .profileSwitch, .copyURL:
            return 2
        case .tabClosure:
            return 3
        }
    }

    var icon: String {
        switch kind {
        case .profileSwitch:
            return "person.crop.circle"
        case .tabClosure:
            return "arrow.uturn.backward"
        case .copyURL:
            return "checkmark.circle.fill"
        }
    }

    var title: String {
        switch kind {
        case .profileSwitch(let profileName):
            return "Switched to \(profileName)"
        case .tabClosure(let count):
            return "\(count) tab\(count == 1 ? "" : "s") closed"
        case .copyURL:
            return "Copied Current URL"
        }
    }

    @MainActor
    func subtitle(shortcutManager: KeyboardShortcutManager) -> String? {
        switch kind {
        case .tabClosure:
            if let shortcut = shortcutManager.shortcutDisplayString(for: .undoCloseTab) {
                return "Press \(shortcut) to reopen"
            }
            return "Use History to reopen"
        case .profileSwitch, .copyURL:
            return nil
        }
    }
}
