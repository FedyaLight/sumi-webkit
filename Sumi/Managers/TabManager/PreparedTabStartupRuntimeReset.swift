import Foundation

struct PreparedTabStartupRuntimeReset {
    let regularTabIDs: Set<UUID>
    let teardown: PreparedTabRuntimeTeardown?
}
