import Foundation
import SumiDomain

@MainActor
struct PreparedRegularTabShortcutConversion {
    let sourceTab: Tab
    let preparation: TabShortcutConversionPreparation
    let structure: RegularTabShortcutStructurePlan
    let candidatePin: ShortcutPin
    let destination: TabShortcutPinDestination
}

/// Stable, fully typed input for a regular-tab drop into an existing shortcut
/// sidebar group. The candidate pin is created once and `member` is the exact
/// durable leaf the drop layout must contain.
@MainActor
struct PreparedRegularTabShortcutSidebarDrop {
    let candidatePin: ShortcutPin
    let member: SplitMember
    let expectedSplitGroups: [SumiDomain.SplitGroup]

    let conversion: PreparedRegularTabShortcutConversion
    let targetGroup: SumiDomain.SplitGroup
}
