import Foundation

@available(macOS 15.5, *)
enum ExtensionNormalTabLifecycleDebugEvent {
    case didActivateTab(UUID)
    case didSelectTab(UUID)
    case didDeselectTab(UUID)
}

/// Emits the ordered WebKit activation sequence for one captured receipt.
/// Each callback may re-enter Sumi, so no later event is emitted until the
/// validator proves that the complete receipt is still current.
@available(macOS 15.5, *)
@MainActor
final class ExtensionNormalTabActivationTransaction {
    private let validator: ExtensionNormalTabActivationValidator
    #if DEBUG
        private let debugEvent:
            @MainActor (ExtensionNormalTabLifecycleDebugEvent) -> Void

        init(
            validator: ExtensionNormalTabActivationValidator,
            debugEvent: @escaping @MainActor (
                ExtensionNormalTabLifecycleDebugEvent
            ) -> Void = { _ in }
        ) {
            self.validator = validator
            self.debugEvent = debugEvent
        }
    #else
        init(validator: ExtensionNormalTabActivationValidator) {
            self.validator = validator
        }
    #endif

    func activate(_ tab: Tab, previous: Tab?) {
        guard let evidence = validator.prepare(tab, previous: previous),
              validator.isCurrent(evidence)
        else {
            return
        }

        evidence.controller.didActivateTab(
            evidence.activated.adapter,
            previousActiveTab: evidence.previous?.adapter
        )
        #if DEBUG
            debugEvent(.didActivateTab(tab.id))
        #endif

        guard validator.isCurrent(evidence) else { return }
        evidence.controller.didSelectTabs([evidence.activated.adapter])
        #if DEBUG
            debugEvent(.didSelectTab(tab.id))
        #endif

        guard let previousEvidence = evidence.previous,
              validator.isCurrent(evidence)
        else {
            return
        }
        evidence.controller.didDeselectTabs([previousEvidence.adapter])
        #if DEBUG
            debugEvent(.didDeselectTab(previousEvidence.tab.id))
        #endif
    }
}
