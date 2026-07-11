import Foundation
import WebKit

@MainActor
struct TabSuspensionContextRuntime {
    let selectedTabIDs: @MainActor () -> Set<UUID>
    let visibleTabIDsByWindow: @MainActor () -> [UUID: Set<UUID>]

    static let inactive = Self(
        selectedTabIDs: { [] },
        visibleTabIDsByWindow: { [:] }
    )
}

@MainActor
struct TabSuspensionWebViewRuntime {
    let liveWebViews: @MainActor (Tab) -> [WKWebView]
    let suspendWebViews: @MainActor (Tab, String) -> Bool
    let isProtectedFromCompositorMutation: @MainActor (WKWebView) -> Bool

    static let inactive = Self(
        liveWebViews: { _ in [] },
        suspendWebViews: { _, _ in false },
        isProtectedFromCompositorMutation: { _ in false }
    )
}

@MainActor
struct TabSuspensionCatalogRuntime {
    let allKnownTabs: @MainActor () -> [Tab]
    let refreshLazyRestoreQueue: @MainActor (TabSuspensionEvaluationContext) -> Void

    static let inactive = Self(
        allKnownTabs: { [] },
        refreshLazyRestoreQueue: { _ in /* No-op. */ }
    )
}

@MainActor
struct TabSuspensionRuntimePorts {
    let context: TabSuspensionContextRuntime
    let webView: TabSuspensionWebViewRuntime
    let catalog: TabSuspensionCatalogRuntime
}

@MainActor
final class TabSuspensionContextSource {
    private var runtime: TabSuspensionContextRuntime = .inactive
    private var currentPolicy: @MainActor () -> TabSuspensionPolicy = {
        TabSuspensionPolicy(memoryMode: .balanced)
    }

    func attach(runtime: TabSuspensionContextRuntime) {
        self.runtime = runtime
    }

    func configurePolicy(
        using currentPolicy: @escaping @MainActor () -> TabSuspensionPolicy
    ) {
        self.currentPolicy = currentPolicy
    }

    func context() -> TabSuspensionEvaluationContext {
        TabSuspensionEvaluationContext(
            visibleTabIDs: globallyVisibleTabIDs(),
            selectedTabIDs: runtime.selectedTabIDs(),
            policy: currentPolicy()
        )
    }

    func globallyVisibleTabIDs() -> Set<UUID> {
        runtime.visibleTabIDsByWindow().values.reduce(into: Set<UUID>()) {
            $0.formUnion($1)
        }
    }
}
