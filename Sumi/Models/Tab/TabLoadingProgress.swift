import Combine
import Foundation

/// Isolates page-load progress from `Tab`'s own observation graph.
///
/// `estimatedProgress` changes many times per navigation. Publishing it on
/// `Tab` would fire `Tab.objectWillChange` on every tick, re-evaluating every
/// `@ObservedObject var tab: Tab` sidebar row even though those rows never
/// render progress. Hosting it on a dedicated object means only the chrome
/// loading bar — which subscribes here directly — reacts to the churn, so the
/// source can publish every raw tick without any coalescing hack.
@MainActor
final class TabLoadingProgress: ObservableObject {
    @Published var estimatedProgress: Double = 0.0
}
