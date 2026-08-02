/// The conservative suspension answer for the canonical committed document.
/// It is derived from physical document replicas, never mutable logical state.
enum TabDocumentSuspensionDecision: Equatable {
    case awaitingEvidence
    case allowed
    case vetoed(Reason)

    enum Reason: Equatable {
        case pageReportedUnableToSuspend
        case pdfDocument
    }
}

/// A report emitted by one concrete main-frame document. `documentNonce` is
/// generated once by that document and `sequence` orders updates from it.
struct TabDocumentSuspensionReport: Equatable {
    let documentNonce: String
    let documentLeaseToken: String
    let sequence: UInt64
    let canBeSuspended: Bool
}
