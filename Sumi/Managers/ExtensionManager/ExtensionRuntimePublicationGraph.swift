import Foundation

/// Final manager-owned browser publication lifetime. Only the terminal attach
/// use case remains distributed after root assembly.
@available(macOS 15.5, *)
@MainActor
struct ExtensionRuntimePublicationGraph {
    let lifetime: ExtensionRuntimePublicationLifetimeOwner
    let attacher: ExtensionBrowserRuntimeAttacher
}
