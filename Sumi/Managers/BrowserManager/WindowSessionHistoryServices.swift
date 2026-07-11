import Foundation

/// Composition-only grouping of the window session-history services. Holds
/// no behavior and forwards nothing: callsites reach the exact service they
/// need (catalog reads, archive writes, recorder captures).
@MainActor
struct WindowSessionHistoryServices {
    let catalog: OpenWindowSessionCatalog
    let archive: LastSessionWindowArchive
    let recorder: ClosedWindowHistoryRecorder
}
