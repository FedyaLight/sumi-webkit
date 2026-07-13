import Combine

/// Isolates page-load progress from `Tab`'s own observation graph.
///
/// `estimatedProgress` changes many times per navigation. Publishing it on
/// `Tab` would fire `Tab.objectWillChange` on every tick, re-evaluating every
/// sidebar row even though those rows never render progress. Only the chrome
/// loading bar subscribes to this dedicated per-tab object.
@MainActor
final class TabLoadingProgress: ObservableObject {
    @Published var estimatedProgress = 0.0
}
