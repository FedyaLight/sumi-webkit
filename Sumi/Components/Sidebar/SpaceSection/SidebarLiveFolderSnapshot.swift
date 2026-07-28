import Foundation

/// Demand-scoped live data consumed by the flattened scene projection.
struct SidebarLiveFolderSnapshot: Equatable {
    let source: SumiLiveFolderSource?
    let items: [SumiLiveFolderItem]
}
