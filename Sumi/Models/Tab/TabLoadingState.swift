import Foundation

enum TabLoadingState: Equatable {
    case idle
    case didStartProvisionalNavigation
    case didCommit
    case didFinish
    case didFail(Error)
    case didFailProvisionalNavigation(Error)

    static func == (lhs: TabLoadingState, rhs: TabLoadingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.didStartProvisionalNavigation, .didStartProvisionalNavigation),
             (.didCommit, .didCommit),
             (.didFinish, .didFinish):
            return true
        case (.didFail, .didFail),
             (.didFailProvisionalNavigation, .didFailProvisionalNavigation):
            return lhs.description == rhs.description
        default:
            return false
        }
    }

    var isLoading: Bool {
        switch self {
        case .idle, .didFinish, .didFail, .didFailProvisionalNavigation:
            return false
        case .didStartProvisionalNavigation, .didCommit:
            return true
        }
    }

    var description: String {
        switch self {
        case .idle:
            return "Idle"
        case .didStartProvisionalNavigation:
            return "Loading started"
        case .didCommit:
            return "Content loading"
        case .didFinish:
            return "Loading finished"
        case .didFail(let error):
            return "Loading failed: \(error.localizedDescription)"
        case .didFailProvisionalNavigation(let error):
            return "Connection failed: \(error.localizedDescription)"
        }
    }
}

extension Tab {
    typealias LoadingState = TabLoadingState
}
