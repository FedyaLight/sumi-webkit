import Foundation
import SumiWebRuntime

@MainActor
enum BrowserBackgroundMediaRuntimeFactory {
    static func runtime(
        webViews: BrowserBackgroundMediaWebViewProjection,
        energyPolicy: BrowserBackgroundMediaEnergyPolicy,
        tabs: BrowserRuntimeTabCatalog,
        visibility: BrowserBackgroundMediaVisibilityProjection
    ) -> SumiBackgroundMediaOptimizationRuntime {
        SumiBackgroundMediaOptimizationRuntime(
            liveWebViewEntries: { [webViews] tab in
                webViews.entries(for: tab)
            },
            energySaverActive: { [energyPolicy] in
                energyPolicy.isEnergySaverActive()
            },
            allKnownTabs: { [tabs] in
                tabs.allKnownTabs()
            },
            visibleTabIDsByWindow: { [visibility] in
                visibility.visibleTabIDsByWindow()
            }
        )
    }
}
