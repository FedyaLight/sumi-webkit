import Foundation

/// Narrow liveness evidence for operations that capture browser-owned objects
/// and may execute after the browser composition has started retiring.
@available(macOS 15.5, *)
@MainActor
struct ExtensionBrowserRuntimeAvailability {
    private let provider: @MainActor () -> Bool

    init(_ provider: @escaping @MainActor () -> Bool) {
        self.provider = provider
    }

    var isAvailable: Bool { provider() }
}

/// Exact browser-owned profile lookup used by extension runtime operations.
/// It intentionally carries no window, Tab, WebView, mutation, or module
/// capabilities.
@available(macOS 15.5, *)
@MainActor
struct ExtensionBrowserProfileQuery {
    private let currentProfileProvider: @MainActor () -> Profile?
    private let profileProvider: @MainActor (UUID) -> Profile?
    private let ephemeralProfileProvider: @MainActor (UUID) -> Profile?

    init(
        currentProfile: @escaping @MainActor () -> Profile?,
        profile: @escaping @MainActor (UUID) -> Profile?,
        ephemeralProfile: @escaping @MainActor (UUID) -> Profile?
    ) {
        currentProfileProvider = currentProfile
        profileProvider = profile
        ephemeralProfileProvider = ephemeralProfile
    }

    func currentProfile() -> Profile? {
        currentProfileProvider()
    }

    func profile(_ profileID: UUID) -> Profile? {
        profileProvider(profileID)
    }

    func ephemeralProfile(_ profileID: UUID) -> Profile? {
        ephemeralProfileProvider(profileID)
    }

    func anyProfile(_ profileID: UUID) -> Profile? {
        profile(profileID) ?? ephemeralProfile(profileID)
    }

    static func detached(initialProfile: Profile?) -> Self {
        Self(
            currentProfile: { [weak initialProfile] in initialProfile },
            profile: { [weak initialProfile] profileID in
                guard initialProfile?.id == profileID else { return nil }
                return initialProfile
            },
            ephemeralProfile: { _ in nil }
        )
    }
}

/// Exact admission boundary shared by extension pages and browser website-data
/// cleanup. Callers can only inspect or await admission; they cannot reach the
/// browser cleanup service itself.
@available(macOS 15.5, *)
@MainActor
struct ExtensionWebsiteDataMutationAdmission {
    private let blocked: @MainActor (UUID) -> Bool
    private let waiter: @MainActor (UUID) async -> Bool

    init(
        isBlocked: @escaping @MainActor (UUID) -> Bool,
        wait: @escaping @MainActor (UUID) async -> Bool
    ) {
        blocked = isBlocked
        waiter = wait
    }

    func isBlocked(profileID: UUID) -> Bool {
        blocked(profileID)
    }

    func wait(profileID: UUID) async -> Bool {
        await waiter(profileID)
    }

    static let detached = ExtensionWebsiteDataMutationAdmission(
        isBlocked: { _ in false },
        wait: { _ in true }
    )
}
