import Combine
import Foundation

@MainActor
final class SpaceCreationSession: ObservableObject, Identifiable {
    static let defaultIcon = "✨"
    static let defaultProfileIcon = SumiProfileIcon.defaultIcon

    let id = UUID()
    let previousSpaceID: UUID?
    let source: SidebarTransientPresentationSource
    let transientSessionToken: SidebarTransientSessionToken?

    @Published var name: String
    @Published var icon: String
    @Published var profileID: UUID?
    @Published var createsNewProfile: Bool
    @Published var newProfileName: String
    @Published var newProfileIcon: String

    var cancelsOnDismiss = false

    init(
        previousSpaceID: UUID?,
        source: SidebarTransientPresentationSource,
        transientSessionToken: SidebarTransientSessionToken?,
        name: String = "",
        icon: String = SpaceCreationSession.defaultIcon,
        profileID: UUID?,
        createsNewProfile: Bool = false,
        newProfileName: String = "",
        newProfileIcon: String = SpaceCreationSession.defaultProfileIcon
    ) {
        self.previousSpaceID = previousSpaceID
        self.source = source
        self.transientSessionToken = transientSessionToken
        self.name = name
        self.icon = icon
        self.profileID = profileID
        self.createsNewProfile = createsNewProfile
        self.newProfileName = newProfileName
        self.newProfileIcon = newProfileIcon
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var resolvedIcon: String {
        SumiPersistentGlyph.normalizedSpaceIconValue(
            icon.isEmpty ? Self.defaultIcon : icon
        )
    }

    var trimmedNewProfileName: String {
        newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var resolvedNewProfileIcon: String {
        SumiProfileIcon.storedValue(
            newProfileIcon.isEmpty ? Self.defaultProfileIcon : newProfileIcon
        )
    }

    var canCommit: Bool {
        guard trimmedName.isEmpty == false else { return false }
        guard createsNewProfile else { return true }
        return trimmedNewProfileName.isEmpty == false
    }
}
