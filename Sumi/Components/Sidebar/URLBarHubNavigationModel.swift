import SwiftUI

@MainActor
final class URLBarHubNavigationModel: ObservableObject {
    enum Mode: Equatable {
        case controls
        case protectionDetails
        case siteDataDetails
        case bookmark(SumiBookmarkEditorState)

        var preferredWidth: CGFloat {
            switch self {
            case .controls:
                return 234
            case .protectionDetails,
                 .siteDataDetails,
                 .bookmark:
                return 392
            }
        }

        var identity: String {
            switch self {
            case .controls:
                return "controls"
            case .protectionDetails:
                return "protection-details"
            case .siteDataDetails:
                return "site-data-details"
            case .bookmark(let state):
                return "bookmark-\(state.id)"
            }
        }
    }

    enum NavigationDirection {
        case forward
        case backward
    }

    static let modeAnimation = Animation.spring(
        response: 0.3,
        dampingFraction: 0.88,
        blendDuration: 0.08
    )

    @Published private(set) var mode: Mode = .controls
    @Published private(set) var navigationDirection: NavigationDirection = .forward
    @Published private(set) var containerWidth: CGFloat = Mode.controls.preferredWidth

    var modeTransition: AnyTransition {
        switch navigationDirection {
        case .forward:
            return .asymmetric(
                insertion: Self.submenuInsertionTransition,
                removal: Self.rootRemovalTransition
            )
        case .backward:
            return .asymmetric(
                insertion: Self.rootInsertionTransition,
                removal: Self.submenuRemovalTransition
            )
        }
    }

    func setMode(_ newMode: Mode, direction: NavigationDirection) {
        navigationDirection = direction
        containerWidth = mode.preferredWidth
        withAnimation(Self.modeAnimation) {
            mode = newMode
            containerWidth = newMode.preferredWidth
        }
    }

    func resetToControls() {
        navigationDirection = .backward
        mode = .controls
        containerWidth = Mode.controls.preferredWidth
    }

    private static var submenuInsertionTransition: AnyTransition {
        .offset(x: 24, y: 0)
            .combined(with: .opacity)
            .combined(with: .scale(scale: 0.985, anchor: .trailing))
    }

    private static var rootRemovalTransition: AnyTransition {
        .offset(x: -14, y: 0)
            .combined(with: .opacity)
            .combined(with: .scale(scale: 0.995, anchor: .leading))
    }

    private static var rootInsertionTransition: AnyTransition {
        .offset(x: -18, y: 0)
            .combined(with: .opacity)
            .combined(with: .scale(scale: 0.99, anchor: .leading))
    }

    private static var submenuRemovalTransition: AnyTransition {
        .offset(x: 24, y: 0)
            .combined(with: .opacity)
            .combined(with: .scale(scale: 0.985, anchor: .trailing))
    }
}
