import Combine
import Foundation

/// Demand-driven publishers for the sidebar page. Creating this value installs
/// no observers; subscriptions exist only for the mounted page model.
struct SidebarUpdateStreams {
    let inventoryRevision: AnyPublisher<UInt, Never>
    let profiles: AnyPublisher<[Profile], Never>
    let profileRuntimeChanged: AnyPublisher<Void, Never>
    let liveFoldersChanged: AnyPublisher<Void, Never>
}
