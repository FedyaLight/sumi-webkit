/// Exact proof retained until the surrounding split transaction settles.
@MainActor
final class ShortcutSplitLauncherReleaseReceipt {
    private let planner: ShortcutSplitLauncherReleasePlanner
    private let placements: [ShortcutSplitLauncherReleasePlacement]

    init(
        planner: ShortcutSplitLauncherReleasePlanner,
        placements: [ShortcutSplitLauncherReleasePlacement]
    ) {
        self.planner = planner
        self.placements = placements
    }

    func isCurrent() -> Bool {
        planner.accepts(placements)
    }
}
