import Foundation
import WebKit

/// The only raw WebKit Tab lifecycle emitter shared by browser-owned Tab
/// transactions. Claiming, admission, and rollback deliberately stay in the
/// transactions that call this type.
@available(macOS 15.5, *)
@MainActor
final class ExtensionTabLifecycleEmitter:
    ExtensionTabLifecycleEventSink,
    ExtensionInitialTabLifecycleEventSink {
    #if DEBUG
        private var didOpen: ((UUID) -> Void)?
        private var didClose: ((UUID) -> Void)?
    #endif
    private let preparedTabVisibility: ExtensionPreparedTabVisibility

    init(preparedTabVisibility: ExtensionPreparedTabVisibility) {
        self.preparedTabVisibility = preparedTabVisibility
    }

    #if DEBUG
        func installDebugCallbacks(
            didOpen: @escaping (UUID) -> Void,
            didClose: @escaping (UUID) -> Void
        ) {
            self.didOpen = didOpen
            self.didClose = didClose
        }
    #endif

    func emitDidOpenTab(
        _ tab: Tab,
        controller: WKWebExtensionController,
        adapter: ExtensionTabAdapter
    ) {
        preparedTabVisibility.withTabOpenCallback(tab: tab) {
            controller.didOpenTab(adapter)
            #if DEBUG
                didOpen?(tab.id)
            #endif
        }
    }

    func emitDidCloseTab(
        _ tab: Tab,
        controller: WKWebExtensionController,
        adapter: ExtensionTabAdapter
    ) {
        controller.didCloseTab(adapter, windowIsClosing: false)
        #if DEBUG
            didClose?(tab.id)
        #endif
    }

    func emitDidOpenInitialTab(
        _ tab: Tab,
        controller: WKWebExtensionController,
        adapter: ExtensionTabAdapter
    ) {
        emitDidOpenTab(tab, controller: controller, adapter: adapter)
    }

    func emitDidCloseInitialTab(
        _ tab: Tab,
        controller: WKWebExtensionController,
        adapter: ExtensionTabAdapter
    ) {
        controller.didCloseTab(adapter, windowIsClosing: true)
        #if DEBUG
            didClose?(tab.id)
        #endif
    }
}
