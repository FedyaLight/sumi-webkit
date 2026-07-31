import XCTest

@testable import Sumi

@MainActor
@discardableResult
func installWindowRegistryTestEventSink(
    on registry: WindowRegistry,
    prepareWindowRegistration: @escaping @MainActor (BrowserWindowState) -> Void = { _ in },
    publishWindowRegistration: @escaping @MainActor (BrowserWindowState) -> Void = { _ in },
    closeWindow: @escaping @MainActor (BrowserWindowState) -> Void = { _ in },
    activateWindow: @escaping @MainActor (BrowserWindowState) -> Void = { _ in },
    closeAllWindows: @escaping @MainActor () -> Void = {}
) -> WindowRegistry.EventSinkInstallationReceipt? {
    let receipt = registry.installEventSink(
        WindowRegistry.EventSink(
            prepareWindowRegistration: prepareWindowRegistration,
            publishWindowRegistration: publishWindowRegistration,
            closeWindow: closeWindow,
            activateWindow: activateWindow,
            closeAllWindows: closeAllWindows
        )
    )
    XCTAssertNotNil(receipt, "WindowRegistry test sink must be installed only once")
    return receipt
}
