import Foundation

@MainActor
struct DisplayedTabShortcutConversionPlan {
    let sourceTabId: UUID
    let runtime: RuntimePortRegistry
    let structure: RegularTabShortcutStructurePlan
    let selectedWindowIds: [UUID]
    let displayingWindowIds: [UUID]
    let presentationWindowIds: [UUID]
    let primaryWindowId: UUID?
    let firstWindowId: UUID
    let firstWindow: BrowserWindowState
}

@MainActor
struct DetachedTabShortcutConversionPlan {
    let sourceTabId: UUID
    let runtime: RuntimePortRegistry?
    let structure: RegularTabShortcutStructurePlan
}

@MainActor
struct AuthorizedDisplayedTabShortcutConversion {
    let tab: Tab
    let plan: DisplayedTabShortcutConversionPlan
    let structure: RegularTabShortcutStructurePlan
    let presentationWindows: [BrowserWindowState]
}

@MainActor
struct AuthorizedDetachedTabShortcutConversion {
    let tab: Tab
    let runtime: RuntimePortRegistry?
    let structure: RegularTabShortcutStructurePlan
}

@MainActor
enum AuthorizedTabShortcutConversion {
    case displayed(AuthorizedDisplayedTabShortcutConversion)
    case detached(AuthorizedDetachedTabShortcutConversion)
}

@MainActor
enum TabShortcutConversionPreparation {
    case displayed(DisplayedTabShortcutConversionPlan)
    case detached(DetachedTabShortcutConversionPlan)
    case rejected

    var structurePlan: RegularTabShortcutStructurePlan? {
        switch self {
        case .displayed(let plan): return plan.structure
        case .detached(let plan): return plan.structure
        case .rejected: return nil
        }
    }
}
