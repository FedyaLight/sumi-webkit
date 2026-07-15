import Foundation

/// Exact unpublished catalog state retaining source launcher identity.
@MainActor
struct ShortcutSplitLauncherCatalogSnapshot {
    private let pinnedByProfile: [
        UUID: [ShortcutSplitLauncherCatalogPinReceipt]
    ]
    private let spacePinnedShortcuts: [
        UUID: [ShortcutSplitLauncherCatalogPinReceipt]
    ]
    private let pendingPinnedWithoutProfile: [
        ShortcutSplitLauncherCatalogPinReceipt
    ]

    init(_ pins: ShortcutPinCollectionStateOwner) {
        pinnedByProfile = pins.pinnedByProfileSnapshot().mapValues {
            $0.map(ShortcutSplitLauncherCatalogPinReceipt.init)
        }
        spacePinnedShortcuts = pins.spacePinnedShortcutsSnapshot().mapValues {
            $0.map(ShortcutSplitLauncherCatalogPinReceipt.init)
        }
        pendingPinnedWithoutProfile = pins.pendingPinnedWithoutProfileSnapshot()
            .map(ShortcutSplitLauncherCatalogPinReceipt.init)
    }

    func isCurrent(in pins: ShortcutPinCollectionStateOwner) -> Bool {
        Self.matches(pinnedByProfile, pins.pinnedByProfileSnapshot())
            && Self.matches(
                spacePinnedShortcuts,
                pins.spacePinnedShortcutsSnapshot()
            )
            && Self.matches(
                pendingPinnedWithoutProfile,
                pins.pendingPinnedWithoutProfileSnapshot()
            )
    }

    func restore(to pins: ShortcutPinCollectionStateOwner) {
        pins.replaceAll(
            pinnedByProfile: pinnedByProfile.mapValues { $0.map(\.pin) },
            spacePinnedShortcuts: spacePinnedShortcuts.mapValues {
                $0.map(\.pin)
            },
            pendingPinnedWithoutProfile: pendingPinnedWithoutProfile.map(\.pin)
        )
        precondition(isCurrent(in: pins))
    }

    func pin(withID id: UUID) -> ShortcutPin? {
        let matches = pinnedByProfile.values.flatMap { $0 }
            + spacePinnedShortcuts.values.flatMap { $0 }
            + pendingPinnedWithoutProfile
        let pins = matches.filter { $0.pin.id == id }.map(\.pin)
        return pins.count == 1 ? pins[0] : nil
    }

    func contains(
        _ receipt: ShortcutSplitLauncherCatalogPinReceipt
    ) -> Bool {
        guard let pin = pin(withID: receipt.pin.id) else { return false }
        return receipt.accepts(pin)
    }

    private static func matches(
        _ expected: [UUID: [ShortcutSplitLauncherCatalogPinReceipt]],
        _ current: [UUID: [ShortcutPin]]
    ) -> Bool {
        guard Set(expected.keys) == Set(current.keys) else { return false }
        return expected.allSatisfy { key, receipts in
            guard let pins = current[key], receipts.count == pins.count else {
                return false
            }
            return zip(receipts, pins).allSatisfy { pair in
                pair.0.accepts(pair.1)
            }
        }
    }

    private static func matches(
        _ expected: [ShortcutSplitLauncherCatalogPinReceipt],
        _ current: [ShortcutPin]
    ) -> Bool {
        expected.count == current.count
            && zip(expected, current).allSatisfy { pair in
                pair.0.accepts(pair.1)
            }
    }
}
