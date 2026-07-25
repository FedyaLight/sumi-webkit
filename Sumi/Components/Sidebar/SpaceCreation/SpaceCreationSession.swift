import Combine
import Foundation
import SumiDomain

@MainActor
final class SpaceCreationSession: ObservableObject, Identifiable {
    static let defaultIcon = SumiPersistentGlyph.spaceDefaultIconValue

    let id = UUID()
    let reservedSpaceID: UUID
    let previousSpaceID: UUID?
    let originalWorkspaceTheme: WorkspaceTheme
    let source: SidebarTransientPresentationSource
    let transientSessionToken: SidebarTransientSessionToken?

    @Published var name: String
    @Published var icon: String
    @Published var profileID: UUID?
    @Published var createsNewProfile: Bool
    @Published var newProfileName: String
    @Published var workspaceTheme: WorkspaceTheme

    var cancelsOnDismiss = false

    init(
        reservedSpaceID: UUID,
        previousSpaceID: UUID?,
        originalWorkspaceTheme: WorkspaceTheme,
        source: SidebarTransientPresentationSource,
        transientSessionToken: SidebarTransientSessionToken?,
        name: String = "",
        icon: String = SpaceCreationSession.defaultIcon,
        profileID: UUID?,
        createsNewProfile: Bool = false,
        newProfileName: String = "",
        workspaceTheme: WorkspaceTheme
    ) {
        self.reservedSpaceID = reservedSpaceID
        self.previousSpaceID = previousSpaceID
        self.originalWorkspaceTheme = originalWorkspaceTheme
        self.source = source
        self.transientSessionToken = transientSessionToken
        self.name = name
        self.icon = icon
        self.profileID = profileID
        self.createsNewProfile = createsNewProfile
        self.newProfileName = newProfileName
        self.workspaceTheme = workspaceTheme
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

    var canCommit: Bool {
        guard trimmedName.isEmpty == false else { return false }
        guard createsNewProfile else { return true }
        return trimmedNewProfileName.isEmpty == false
    }
}
