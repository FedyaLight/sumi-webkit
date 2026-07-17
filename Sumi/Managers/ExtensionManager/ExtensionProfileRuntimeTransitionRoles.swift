import Foundation

@available(macOS 15.5, *)
@MainActor
protocol ExtensionInactiveProfileContextRetiring: AnyObject {
    func unloadExtensionContextsForInactiveProfiles(keepingProfileId: UUID)
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionToolbarProfileReloading: AnyObject {
    func reloadPinnedToolbarExtensionsForCurrentProfile()
}
