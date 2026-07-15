import Foundation

@MainActor
struct RegularTabShortcutConversionAcceptance {
    enum Disposition {
        case syncCommitted(ShortcutPin)
        case pipelineOwned
    }

    let pinID: UUID
    let disposition: Disposition

    var canonicalPin: ShortcutPin? {
        guard case .syncCommitted(let pin) = disposition else { return nil }
        return pin
    }
}
