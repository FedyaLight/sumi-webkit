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
    private let didOpen: ((UUID) -> Void)?
    private let didClose: ((UUID) -> Void)?
    private let preparedTabVisibility: ExtensionPreparedTabVisibility

    init(
        preparedTabVisibility: ExtensionPreparedTabVisibility,
        didOpen: ((UUID) -> Void)? = nil,
        didClose: ((UUID) -> Void)? = nil
    ) {
        self.preparedTabVisibility = preparedTabVisibility
        self.didOpen = didOpen
        self.didClose = didClose
    }

    func emitDidOpenTab(
        _ tab: Tab,
        controller: WKWebExtensionController,
        adapter: ExtensionTabAdapter
    ) {
        preparedTabVisibility.withTabOpenCallback(tab: tab) {
            controller.didOpenTab(adapter)
            didOpen?(tab.id)
        }
    }

    func emitDidCloseTab(
        _ tab: Tab,
        controller: WKWebExtensionController,
        adapter: ExtensionTabAdapter
    ) {
        controller.didCloseTab(adapter, windowIsClosing: false)
        didClose?(tab.id)
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
        didClose?(tab.id)
    }

}
