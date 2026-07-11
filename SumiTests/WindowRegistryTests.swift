@testable import Sumi
import XCTest

@MainActor
final class WindowRegistryTests: XCTestCase {
    func testRegisteringSameObjectTwiceIsIdempotent() {
        let registry = WindowRegistry()
        let window = BrowserWindowState()
        var registrationCount = 0
        registry.prepareWindowRegistration = { _ in registrationCount += 1 }

        let firstResult = registry.register(window)
        let secondResult = registry.register(window)

        XCTAssertEqual(firstResult, .registered)
        XCTAssertEqual(secondResult, .alreadyRegistered)
        XCTAssertIdentical(registry.windows[window.id], window)
        XCTAssertEqual(registrationCount, 1)
    }

    func testRegisteringDifferentObjectWithSameIDIsRejectedWithoutReplacement() {
        let registry = WindowRegistry()
        let sharedID = UUID()
        let registeredWindow = BrowserWindowState(id: sharedID)
        let conflictingWindow = BrowserWindowState(id: sharedID)
        var registrationCount = 0
        registry.prepareWindowRegistration = { _ in registrationCount += 1 }

        XCTAssertEqual(registry.register(registeredWindow), .registered)
        let result = registry.register(conflictingWindow)

        XCTAssertEqual(result, .rejectedIdentityConflict)
        XCTAssertIdentical(registry.windows[sharedID], registeredWindow)
        XCTAssertNotIdentical(registry.windows[sharedID], conflictingWindow)
        XCTAssertEqual(registrationCount, 1)
    }

    func testAwaitNextRegisteredWindowReturnsNewWindow() async {
        let registry = WindowRegistry()
        let existingWindow = BrowserWindowState()
        registry.register(existingWindow)

        let awaitedWindowTask = Task { @MainActor in
            await registry.awaitNextRegisteredWindow(
                excluding: [existingWindow.id]
            )
        }

        let newWindow = BrowserWindowState()
        registry.register(newWindow)

        let awaitedWindow = await awaitedWindowTask.value
        XCTAssertEqual(awaitedWindow?.id, newWindow.id)
    }

    func testAwaiterCannotObserveRolledBackProvisionalWindow() async {
        let registry = WindowRegistry()
        let provisional = BrowserWindowState()

        XCTAssertEqual(registry.beginRegistration(provisional), .registered)
        XCTAssertTrue(registry.windows.isEmpty)

        let awaitedWindowTask = Task { @MainActor in
            await registry.awaitNextRegisteredWindow(
                excluding: [],
                timeoutNanoseconds: 500_000_000
            )
        }
        await Task.yield()

        XCTAssertTrue(
            registry.rollbackProvisionalRegistration(provisional)
        )
        let committed = BrowserWindowState()
        registry.register(committed)

        let awaitedWindow = await awaitedWindowTask.value
        XCTAssertIdentical(awaitedWindow, committed)
        XCTAssertNotIdentical(awaitedWindow, provisional)
    }

    func testAwaiterCannotObserveRegistrationRejectedByCommittedValidator()
        async
    {
        let registry = WindowRegistry()
        let rejected = BrowserWindowState()
        XCTAssertEqual(registry.beginRegistration(rejected), .registered)

        let awaitedWindowTask = Task { @MainActor in
            await registry.awaitNextRegisteredWindow(
                excluding: [],
                timeoutNanoseconds: 500_000_000
            )
        }
        await Task.yield()

        XCTAssertFalse(
            registry.commitRegistration(
                rejected,
                validatePublication: { candidate in
                    XCTAssertIdentical(candidate, rejected)
                    return false
                }
            )
        )
        XCTAssertNil(registry.windows[rejected.id])

        let accepted = BrowserWindowState()
        registry.register(accepted)
        let awaitedWindow = await awaitedWindowTask.value

        XCTAssertIdentical(awaitedWindow, accepted)
        XCTAssertNotIdentical(awaitedWindow, rejected)
    }

    func testReentrantCloseDuringPublicationDoesNotResumeAwaiterWithRejectedWindow()
        async
    {
        let registry = WindowRegistry()
        let rejected = BrowserWindowState()
        XCTAssertEqual(registry.beginRegistration(rejected), .registered)
        registry.publishWindowRegistration = { candidate in
            XCTAssertIdentical(candidate, rejected)
            registry.unregister(candidate.id)
        }

        let awaitedWindowTask = Task { @MainActor in
            await registry.awaitNextRegisteredWindow(
                excluding: [],
                timeoutNanoseconds: 500_000_000
            )
        }
        await Task.yield()

        XCTAssertFalse(registry.commitRegistration(rejected))
        XCTAssertNil(registry.windows[rejected.id])

        registry.publishWindowRegistration = nil
        let accepted = BrowserWindowState()
        registry.register(accepted)
        let awaitedWindow = await awaitedWindowTask.value

        XCTAssertIdentical(awaitedWindow, accepted)
        XCTAssertNotIdentical(awaitedWindow, rejected)
    }

    func testAwaitNextRegisteredWindowReturnsAlreadyRegisteredWindowWhenAvailable() async {
        let registry = WindowRegistry()
        let firstWindow = BrowserWindowState()
        let secondWindow = BrowserWindowState()
        registry.register(firstWindow)
        registry.register(secondWindow)

        let awaitedWindow = await registry.awaitNextRegisteredWindow(
            excluding: [firstWindow.id]
        )

        XCTAssertEqual(awaitedWindow?.id, secondWindow.id)
    }

    func testAwaitNextRegisteredWindowTimesOutAndDoesNotPoisonFutureAwaiters() async {
        let registry = WindowRegistry()

        let timedOutWindow = await registry.awaitNextRegisteredWindow(
            excluding: [],
            timeoutNanoseconds: 20_000_000
        )

        XCTAssertNil(timedOutWindow)

        let awaitedWindowTask = Task { @MainActor in
            await registry.awaitNextRegisteredWindow(
                excluding: [],
                timeoutNanoseconds: 500_000_000
            )
        }
        let newWindow = BrowserWindowState()
        registry.register(newWindow)

        let awaitedWindow = await awaitedWindowTask.value
        XCTAssertEqual(awaitedWindow?.id, newWindow.id)
    }

    func testUnregisterRunsCloseCallbackOnlyOnceForDuplicateCloseSignals() {
        let registry = WindowRegistry()
        let window = BrowserWindowState()
        var closedWindowIds: [UUID] = []
        var allWindowsClosedCount = 0

        registry.onWindowClose = { closedWindowIds.append($0.id) }
        registry.onAllWindowsClosed = { allWindowsClosedCount += 1 }
        registry.register(window)
        registry.setActive(window)

        registry.unregister(window.id)
        registry.unregister(window.id)

        XCTAssertEqual(closedWindowIds, [window.id])
        XCTAssertEqual(allWindowsClosedCount, 1)
        XCTAssertNil(registry.activeWindowId)
        XCTAssertTrue(registry.windows.isEmpty)
    }

    func testReentrantUnregisterFromCloseCallbackRunsLifecycleExactlyOnce() {
        let registry = WindowRegistry()
        let window = BrowserWindowState()
        var closeCount = 0
        var allWindowsClosedCount = 0
        var didRequestReentrantClose = false
        registry.onWindowClose = { closingWindow in
            closeCount += 1
            XCTAssertIdentical(closingWindow, window)
            if didRequestReentrantClose == false {
                didRequestReentrantClose = true
                registry.unregister(closingWindow.id)
            }
        }
        registry.onAllWindowsClosed = { allWindowsClosedCount += 1 }
        registry.register(window)

        registry.unregister(window.id)

        XCTAssertEqual(closeCount, 1)
        XCTAssertEqual(allWindowsClosedCount, 1)
        XCTAssertTrue(registry.windows.isEmpty)
    }

    func testUnregisterActiveWindowClearsActiveWithoutPromotingAnotherWindow() {
        let registry = WindowRegistry()
        let closingWindow = BrowserWindowState()
        let survivingWindow = BrowserWindowState()
        var activatedWindowIds: [UUID] = []

        registry.register(closingWindow)
        registry.register(survivingWindow)
        registry.setActive(closingWindow)
        registry.onActiveWindowChange = { activatedWindowIds.append($0.id) }

        registry.unregister(closingWindow.id)

        XCTAssertNil(registry.activeWindowId)
        XCTAssertNil(registry.activeWindow)
        XCTAssertTrue(registry.windows.keys.contains(survivingWindow.id))
        XCTAssertTrue(activatedWindowIds.isEmpty)
    }

    func testUnregisterActiveWindowPromotesFocusedRegisteredAppKitWindow() {
        let registry = WindowRegistry()
        let closingWindow = BrowserWindowState()
        let survivingWindow = BrowserWindowState()
        let survivingAppKitWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        var activatedWindowIds: [UUID] = []

        registry.bindAppKitWindow(survivingAppKitWindow, to: survivingWindow)
        registry.keyAppKitWindowProvider = { survivingAppKitWindow }
        registry.mainAppKitWindowProvider = { nil }
        registry.register(closingWindow)
        registry.register(survivingWindow)
        registry.setActive(closingWindow)
        registry.onActiveWindowChange = { activatedWindowIds.append($0.id) }

        registry.unregister(closingWindow.id)

        XCTAssertEqual(registry.activeWindowId, survivingWindow.id)
        XCTAssertIdentical(registry.activeWindow, survivingWindow)
        XCTAssertEqual(activatedWindowIds, [survivingWindow.id])
    }

    func testSetActiveBeforeRegisterReplacesPreviousActiveWhenRegistered() {
        let registry = WindowRegistry()
        let previousWindow = BrowserWindowState()
        let pendingWindow = BrowserWindowState()
        var activatedWindowIds: [UUID] = []

        registry.register(previousWindow)
        registry.setActive(previousWindow)
        registry.onActiveWindowChange = { activatedWindowIds.append($0.id) }

        registry.setActive(pendingWindow)

        XCTAssertEqual(registry.activeWindowId, pendingWindow.id)
        XCTAssertNil(registry.activeWindow)
        XCTAssertTrue(activatedWindowIds.isEmpty)

        registry.register(pendingWindow)

        XCTAssertEqual(registry.activeWindowId, pendingWindow.id)
        XCTAssertIdentical(registry.activeWindow, pendingWindow)
        XCTAssertEqual(activatedWindowIds, [pendingWindow.id])
    }

    func testSetActiveBeforeRegisterBecomesActiveWhenRegistered() {
        let registry = WindowRegistry()
        let window = BrowserWindowState()
        var activatedWindowIds: [UUID] = []
        registry.onActiveWindowChange = { activatedWindowIds.append($0.id) }

        registry.setActive(window)

        XCTAssertEqual(registry.activeWindowId, window.id)
        XCTAssertNil(registry.activeWindow)
        XCTAssertTrue(activatedWindowIds.isEmpty)

        registry.register(window)

        XCTAssertEqual(registry.activeWindowId, window.id)
        XCTAssertIdentical(registry.activeWindow, window)
        XCTAssertEqual(activatedWindowIds, [window.id])
    }

    func testSettingAlreadyActiveWindowDoesNotRepublishActivation() {
        let registry = WindowRegistry()
        let window = BrowserWindowState()
        var activatedWindowIds: [UUID] = []
        registry.onActiveWindowChange = { activatedWindowIds.append($0.id) }
        registry.register(window)

        registry.setActive(window)
        registry.setActive(window)

        XCTAssertEqual(activatedWindowIds, [window.id])
    }

    func testProvisionalRollbackDoesNotEmitCloseLifecycle() {
        let registry = WindowRegistry()
        let window = BrowserWindowState()
        var closeCount = 0
        var allWindowsClosedCount = 0
        registry.onWindowClose = { _ in closeCount += 1 }
        registry.onAllWindowsClosed = { allWindowsClosedCount += 1 }
        XCTAssertEqual(registry.beginRegistration(window), .registered)

        XCTAssertTrue(registry.rollbackProvisionalRegistration(window))

        XCTAssertTrue(registry.windows.isEmpty)
        XCTAssertEqual(closeCount, 0)
        XCTAssertEqual(allWindowsClosedCount, 0)
    }

    func testProvisionalRollbackRejectsCommittedWindow() {
        let registry = WindowRegistry()
        let window = BrowserWindowState()
        var closeCount = 0
        registry.onWindowClose = { _ in closeCount += 1 }
        registry.register(window)

        XCTAssertFalse(registry.rollbackProvisionalRegistration(window))

        XCTAssertIdentical(registry.windows[window.id], window)
        XCTAssertEqual(closeCount, 0)
    }

    func testProvisionalRollbackRequiresExactObjectIdentity() {
        let registry = WindowRegistry()
        let sharedID = UUID()
        let provisional = BrowserWindowState(id: sharedID)
        let impostor = BrowserWindowState(id: sharedID)
        XCTAssertEqual(registry.beginRegistration(provisional), .registered)

        XCTAssertFalse(registry.rollbackProvisionalRegistration(impostor))
        XCTAssertTrue(registry.commitRegistration(provisional))

        XCTAssertIdentical(registry.windows[sharedID], provisional)
    }

    func testProvisionalCommitRequiresExactObjectIdentity() {
        let registry = WindowRegistry()
        let sharedID = UUID()
        let provisional = BrowserWindowState(id: sharedID)
        let impostor = BrowserWindowState(id: sharedID)
        XCTAssertEqual(registry.beginRegistration(provisional), .registered)

        XCTAssertFalse(registry.commitRegistration(impostor))
        XCTAssertTrue(registry.windows.isEmpty)
        XCTAssertTrue(registry.commitRegistration(provisional))

        XCTAssertIdentical(registry.windows[sharedID], provisional)
    }

    func testRejectedRegistrationUsesBalancedLifecycleOnlyForExactCommittedObject() {
        let registry = WindowRegistry()
        let sharedID = UUID()
        let committed = BrowserWindowState(id: sharedID)
        let impostor = BrowserWindowState(id: sharedID)
        var closed: [UUID] = []
        var allClosedCount = 0
        registry.onWindowClose = { closed.append($0.id) }
        registry.onAllWindowsClosed = { allClosedCount += 1 }
        registry.register(committed)

        XCTAssertFalse(registry.discardRejectedRegistration(impostor))
        XCTAssertIdentical(registry.windows[sharedID], committed)
        XCTAssertTrue(registry.discardRejectedRegistration(committed))

        XCTAssertNil(registry.windows[sharedID])
        XCTAssertEqual(closed, [sharedID])
        XCTAssertEqual(allClosedCount, 1)
    }

    func testWindowStateContainingReturnsParentForChildWindow() {
        let registry = WindowRegistry()
        let parentWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let childWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let windowState = BrowserWindowState()
        registry.bindAppKitWindow(parentWindow, to: windowState)
        parentWindow.addChildWindow(childWindow, ordered: .above)
        registry.register(windowState)

        XCTAssertIdentical(registry.appKitWindow(for: windowState), parentWindow)
        XCTAssertIdentical(registry.windowState(containing: childWindow), windowState)
        XCTAssertIdentical(windowState.shellWindow(in: registry), parentWindow)
    }

    func testBindAppKitWindowStoresShellHandle() {
        let registry = WindowRegistry()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let windowState = BrowserWindowState()
        registry.register(windowState)
        registry.bindAppKitWindow(window, to: windowState)

        XCTAssertIdentical(registry.appKitWindow(for: windowState.id), window)
        XCTAssertIdentical(windowState.shellWindow(in: registry), window)

        registry.unregister(windowState.id)
        XCTAssertNil(registry.appKitWindow(for: windowState.id))
        XCTAssertNil(windowState.shellWindow(in: registry))
    }
}
