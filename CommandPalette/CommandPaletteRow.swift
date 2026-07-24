import Foundation
import SumiDomain

struct CommandPaletteSplitMemberPresentation: Identifiable, Equatable {
    enum Icon: Equatable {
        case glyph(String)
        case systemSymbol(String)
        case favicon(URL)
        case tab(TabFaviconPresentation)
    }

    let id: SplitMemberID
    let icon: Icon
}

/// Immutable presentation published by one Command Palette Session.
///
/// Live browser objects never cross this seam. Activation identities are
/// resolved against the originating window only when the row is committed.
struct CommandPaletteRow: Identifiable, Equatable {
    enum ID: Hashable {
        case search(String)
        case url(String)
        case tab(UUID)
        case navigationTarget(CommandPaletteNavigationTargetPresentation.Identity)
        case history(String)
        case bookmark(String)
        case command(ShortcutAction)
        case space(UUID)
        case extensionAction(String)
    }

    enum Icon: Equatable {
        case systemSymbol(String)
        case favicon(URL)
        case tab(TabFaviconPresentation)
        case splitView([CommandPaletteSplitMemberPresentation])
    }

    enum Accessory: Equatable {
        case none
        case chip(String)
        case arrow(String)
    }

    enum Activation: Equatable {
        case input(String)
        case literalURL(String)
        case tab(UUID)
        case navigationTarget(CommandPaletteNavigationTargetPresentation.Identity)
        case browserAction(ShortcutAction)
        case space(UUID)
        case extensionAction(String)
    }

    enum SecondaryAction: Equatable {
        case deleteHistory(HistoryQuery)
    }

    let id: ID
    let title: String
    let subtitle: String?
    let icon: Icon
    let accessory: Accessory
    let accessibilityLabel: String
    let activation: Activation
    let secondaryAction: SecondaryAction?
}

enum CommandPaletteCommitIntent: Equatable {
    case browserNavigation(CommandPaletteRow.Activation)
    case browserAction(ShortcutAction)
    case space(UUID)
    case extensionAction(String)
    case siteSearch(SumiSearchEngine, query: String)
}
