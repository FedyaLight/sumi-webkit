import Foundation

@MainActor
final class ShortcutPinCollectionStateOwner {
    private(set) var pinnedByProfile: [UUID: [ShortcutPin]] = [:]
    private(set) var spacePinnedShortcuts: [UUID: [ShortcutPin]] = [:]
    private(set) var pendingPinnedWithoutProfile: [ShortcutPin] = []

    func replacePinnedByProfile(_ pinnedByProfile: [UUID: [ShortcutPin]]) {
        self.pinnedByProfile = pinnedByProfile
    }

    func replaceSpacePinnedShortcuts(_ spacePinnedShortcuts: [UUID: [ShortcutPin]]) {
        self.spacePinnedShortcuts = spacePinnedShortcuts
    }

    func pinnedByProfileSnapshot() -> [UUID: [ShortcutPin]] {
        pinnedByProfile
    }

    func spacePinnedShortcutsSnapshot() -> [UUID: [ShortcutPin]] {
        spacePinnedShortcuts
    }

    func pendingPinnedWithoutProfileSnapshot() -> [ShortcutPin] {
        pendingPinnedWithoutProfile
    }

    func replaceAll(
        pinnedByProfile: [UUID: [ShortcutPin]],
        spacePinnedShortcuts: [UUID: [ShortcutPin]],
        pendingPinnedWithoutProfile: [ShortcutPin]
    ) {
        self.pinnedByProfile = pinnedByProfile
        self.spacePinnedShortcuts = spacePinnedShortcuts
        self.pendingPinnedWithoutProfile = pendingPinnedWithoutProfile
    }

    func removeAll() {
        pinnedByProfile.removeAll()
        spacePinnedShortcuts.removeAll()
        pendingPinnedWithoutProfile.removeAll()
    }

    func essentialPins(for profileId: UUID?) -> [ShortcutPin] {
        guard let profileId else { return [] }
        return sortedPins(pinnedByProfile[profileId] ?? [])
    }

    func spacePinnedPins(for spaceId: UUID) -> [ShortcutPin] {
        sortedPins(spacePinnedShortcuts[spaceId] ?? [])
    }

    func folderPinnedPins(for folderId: UUID, in spaceId: UUID) -> [ShortcutPin] {
        spacePinnedPins(for: spaceId)
            .filter { $0.folderId == folderId }
    }

    func shortcutPin(by id: UUID) -> ShortcutPin? {
        for pins in pinnedByProfile.values {
            if let match = pins.first(where: { $0.id == id }) {
                return match
            }
        }
        for pins in spacePinnedShortcuts.values {
            if let match = pins.first(where: { $0.id == id }) {
                return match
            }
        }
        return nil
    }

    func hasSpacePinnedShortcuts(in spaceId: UUID) -> Bool {
        spacePinnedShortcuts[spaceId]?.isEmpty == false
    }

    @discardableResult
    func removePinnedPins(for profileId: UUID) -> [ShortcutPin] {
        pinnedByProfile.removeValue(forKey: profileId) ?? []
    }

    func drainPendingPinnedWithoutProfile() -> [ShortcutPin] {
        let pins = pendingPinnedWithoutProfile
        pendingPinnedWithoutProfile.removeAll()
        return pins
    }

    private func sortedPins(_ pins: [ShortcutPin]) -> [ShortcutPin] {
        pins.sorted { lhs, rhs in
            if lhs.index != rhs.index { return lhs.index < rhs.index }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
