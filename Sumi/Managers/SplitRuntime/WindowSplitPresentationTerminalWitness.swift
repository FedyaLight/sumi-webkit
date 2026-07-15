@MainActor
struct WindowSplitPresentationTerminalWitness {
    let plan: WindowSplitPresentationSettlementPlan
    let residences: WindowSplitPresentationResidenceTransaction
    let validator: WindowSplitPresentationSettlementValidator
    let windowStates: [UUID: BrowserWindowShortcutMutationState]

    func isCurrent(_ window: WindowSplitPresentationWindowPlan) -> Bool {
        residences.publishedModelIsExact()
            && validator.terminalWindowIsCurrent(
                plan,
                window,
                expectedWindowState: windowStates[window.window.id]
            )
    }
}
