import Foundation
import XCTest

@testable import Sumi

@MainActor
final class EmptySplitSessionTests: XCTestCase {
    func testReplaceConsumesExactWindowPlaceholderAndRemovesOldTab() {
        let windowState = BrowserWindowState()
        let placeholderID = UUID()
        let placeholder = Tab(id: placeholderID)
        let incoming = Tab(url: URL(string: "https://incoming.example")!)
        let recorder = Recorder()
        let session = makeSession(recorder)
        session.register(placeholder, in: windowState.id)

        let receipt = makeReplacementReceipt(
            session: session,
            recorder: recorder,
            incoming: incoming,
            placeholder: placeholder,
            windowState: windowState
        )
        XCTAssertTrue(receipt.commitModel())
        receipt.publish()

        XCTAssertEqual(recorder.replacements.count, 1)
        XCTAssertIdentical(recorder.replacements[0].tab, incoming)
        XCTAssertIdentical(recorder.replacements[0].placeholder, placeholder)
        XCTAssertIdentical(recorder.replacements[0].windowState, windowState)
        XCTAssertEqual(recorder.removedTabIDs, [placeholderID])
        XCTAssertFalse(session.accepts(placeholder, in: windowState.id))
    }

    func testFailedReplacementKeepsRegistrationForRetry() {
        let windowState = BrowserWindowState()
        let placeholderID = UUID()
        let placeholder = Tab(id: placeholderID)
        let incoming = Tab(url: URL(string: "https://incoming.example")!)
        let recorder = Recorder()
        recorder.replacementResults = [false, true]
        let session = makeSession(recorder)
        session.register(placeholder, in: windowState.id)

        let rejected = makeReplacementReceipt(
            session: session,
            recorder: recorder,
            incoming: incoming,
            placeholder: placeholder,
            windowState: windowState
        )
        XCTAssertFalse(rejected.commitModel())
        rejected.rollback()
        let accepted = makeReplacementReceipt(
            session: session,
            recorder: recorder,
            incoming: incoming,
            placeholder: placeholder,
            windowState: windowState
        )
        XCTAssertTrue(accepted.commitModel())
        accepted.publish()

        XCTAssertEqual(recorder.replacements.count, 2)
        XCTAssertEqual(recorder.removedTabIDs, [placeholderID])
    }

    func testReplacingPlaceholderWithSameTabDoesNotRemoveIt() {
        let windowState = BrowserWindowState()
        let tab = Tab(url: URL(string: "https://same.example")!)
        let recorder = Recorder()
        let session = makeSession(recorder)
        session.register(tab, in: windowState.id)

        let receipt = makeReplacementReceipt(
            session: session,
            recorder: recorder,
            incoming: tab,
            placeholder: tab,
            windowState: windowState
        )
        XCTAssertTrue(receipt.commitModel())
        receipt.publish()
        XCTAssertTrue(recorder.removedTabIDs.isEmpty)
    }

    func testPreparedReplacementPublishesExactlyOnce() throws {
        let windowState = BrowserWindowState()
        let placeholderID = UUID()
        let placeholder = Tab(id: placeholderID)
        let incoming = Tab(url: URL(string: "https://incoming.example")!)
        let recorder = Recorder()
        let session = makeSession(recorder)
        session.register(placeholder, in: windowState.id)
        let receipt = makeReplacementReceipt(
            session: session,
            recorder: recorder,
            incoming: incoming,
            placeholder: placeholder,
            windowState: windowState
        )

        XCTAssertTrue(receipt.isCurrent())
        XCTAssertTrue(receipt.commitModel())
        XCTAssertFalse(receipt.commitModel())
        receipt.publish()
        receipt.publish()
        receipt.rollback()

        XCTAssertFalse(receipt.isCurrent())
        XCTAssertEqual(recorder.committedTopologyCount, 1)
        XCTAssertEqual(recorder.settledPresentationCount, 1)
        XCTAssertEqual(recorder.publishedReplacementCount, 1)
        XCTAssertEqual(recorder.rolledBackReplacementCount, 0)
        XCTAssertEqual(recorder.removedTabIDs, [placeholderID])
    }

    func testPreparedReplacementRollsBackExactlyOnceAndKeepsRetry() throws {
        let windowState = BrowserWindowState()
        let placeholderID = UUID()
        let placeholder = Tab(id: placeholderID)
        let incoming = Tab(url: URL(string: "https://incoming.example")!)
        let recorder = Recorder()
        let session = makeSession(recorder)
        session.register(placeholder, in: windowState.id)
        let receipt = makeReplacementReceipt(
            session: session,
            recorder: recorder,
            incoming: incoming,
            placeholder: placeholder,
            windowState: windowState
        )

        receipt.rollback()
        receipt.rollback()
        receipt.publish()

        XCTAssertEqual(recorder.rolledBackReplacementCount, 1)
        XCTAssertEqual(recorder.publishedReplacementCount, 0)
        XCTAssertTrue(recorder.removedTabIDs.isEmpty)
        let retry = makeReplacementReceipt(
            session: session,
            recorder: recorder,
            incoming: incoming,
            placeholder: placeholder,
            windowState: windowState
        )
        XCTAssertTrue(retry.commitModel())
        retry.publish()
        XCTAssertEqual(recorder.publishedReplacementCount, 1)
        XCTAssertEqual(recorder.removedTabIDs, [placeholderID])
    }

    func testCommitConsumesOnlyMatchingPlaceholder() {
        let windowID = UUID()
        let placeholderID = UUID()
        let placeholder = Tab(id: placeholderID)
        let sameIDReplacement = Tab(id: placeholderID)
        let recorder = Recorder()
        let session = makeSession(recorder)
        session.register(placeholder, in: windowID)

        session.commit(sameIDReplacement, in: windowID)
        let windowState = BrowserWindowState(id: windowID)
        let retry = makeReplacementReceipt(
            session: session,
            recorder: recorder,
            incoming: Tab(url: URL(string: "https://retry.example")!),
            placeholder: placeholder,
            windowState: windowState
        )
        XCTAssertTrue(retry.commitModel())
        retry.publish()

        session.register(placeholder, in: windowID)
        session.commit(placeholder, in: windowID)
        XCTAssertFalse(session.cancel(in: windowState))
    }

    func testCancelRemovesPlaceholderExactlyOnce() {
        let windowState = BrowserWindowState()
        let placeholderID = UUID()
        let placeholder = Tab(id: placeholderID)
        let recorder = Recorder()
        let session = makeSession(recorder)
        session.register(placeholder, in: windowState.id)

        XCTAssertTrue(session.cancel(in: windowState))
        XCTAssertFalse(session.cancel(in: windowState))
        XCTAssertEqual(recorder.removedTabIDs, [placeholderID])
    }

    func testRemovingWindowForgetsRegistrationWithoutClosingTab() {
        let windowState = BrowserWindowState()
        let recorder = Recorder()
        let session = makeSession(recorder)
        session.register(Tab(), in: windowState.id)

        session.removeWindow(windowState.id)

        XCTAssertFalse(session.cancel(in: windowState))
        XCTAssertTrue(recorder.removedTabIDs.isEmpty)
    }

    func testSameIDReplacementCannotConsumeOrRetireRegisteredPlaceholder() {
        let windowState = BrowserWindowState()
        let placeholder = Tab(id: UUID())
        let replacement = Tab(id: placeholder.id)
        let incoming = Tab(url: URL(string: "https://incoming.example")!)
        let recorder = Recorder()
        recorder.canonicalPlaceholder = replacement
        let session = makeSession(recorder)
        session.register(placeholder, in: windowState.id)

        session.commit(replacement, in: windowState.id)

        XCTAssertTrue(session.accepts(placeholder, in: windowState.id))
        XCTAssertFalse(session.accepts(replacement, in: windowState.id))
        XCTAssertFalse(session.cancel(in: windowState))
        let receipt = makeReplacementReceipt(
            session: session,
            recorder: recorder,
            incoming: incoming,
            placeholder: placeholder,
            windowState: windowState
        )
        XCTAssertFalse(receipt.isCurrent())
        XCTAssertTrue(recorder.removedTabs.isEmpty)
    }

    private func makeSession(_ recorder: Recorder) -> EmptySplitSession {
        EmptySplitSession(
            structuralTransactions:
                TestEmptySplitStructuralTransactionAuthority(),
            terminalMutations: TestEmptySplitTerminalMutationAuthority(),
            placeholderRetirement: TestEmptySplitPlaceholderRetirementPreparer(
                recorder: recorder
            )
        )
    }

    private func makeReplacementReceipt(
        session: EmptySplitSession,
        recorder: Recorder,
        incoming: Tab,
        placeholder: Tab,
        windowState: BrowserWindowState
    ) -> EmptySplitReplacementReceipt {
        recorder.replacements.append((incoming, placeholder, windowState))
        return EmptySplitReplacementReceipt(
            session: session,
            terminalMutations: TestEmptySplitTerminalMutationAuthority(),
            replacement: TestSplitPlaceholderReplacementMutation(
                recorder: recorder,
                incoming: incoming,
                placeholder: placeholder
            ),
            placeholder: placeholder,
            windowID: windowState.id
        )
    }
}

@MainActor
private final class TestSplitPlaceholderReplacementMutation:
    SplitPlaceholderReplacementMutation {
    private enum State { case prepared, committed, published, cancelled }

    private let recorder: Recorder
    private let incoming: Tab
    private let placeholder: Tab
    private var state = State.prepared

    init(recorder: Recorder, incoming: Tab, placeholder: Tab) {
        self.recorder = recorder
        self.incoming = incoming
        self.placeholder = placeholder
    }

    func isCurrent() -> Bool {
        guard case .prepared = state else { return false }
        return recorder.canonicalPlaceholder.map { $0 === placeholder } ?? true
    }

    func commitModel() -> Bool {
        guard isCurrent() else { return false }
        let accepted = recorder.replacementResults.isEmpty
            ? true
            : recorder.replacementResults.removeFirst()
        guard accepted else { return false }
        state = .committed
        recorder.committedTopologyCount += 1
        if placeholder !== incoming {
            recorder.removedTabs.append(placeholder)
        }
        return true
    }

    func settlePresentation() {
        guard case .committed = state else { return }
        recorder.settledPresentationCount += 1
    }

    func publish() {
        guard case .committed = state else { return }
        state = .published
        recorder.publishedReplacementCount += 1
    }

    func rollback() {
        guard case .prepared = state else { return }
        state = .cancelled
        recorder.rolledBackReplacementCount += 1
    }
}

@MainActor
private final class TestEmptySplitTerminalMutationAuthority:
    EmptySplitTerminalMutationAuthority {
    func withReversibleSideEffects(_ operation: () -> Bool) -> Bool {
        operation()
    }
}

@MainActor
private final class TestEmptySplitStructuralTransactionAuthority:
    EmptySplitStructuralTransactionAuthority {
    func withTransaction<T>(
        _ operation: @MainActor @Sendable () throws -> T
    ) rethrows -> T {
        try operation()
    }
}

@MainActor
private final class TestEmptySplitPlaceholderRetirementPreparer:
    EmptySplitPlaceholderRetirementPreparing {
    private let recorder: Recorder

    init(recorder: Recorder) {
        self.recorder = recorder
    }

    func prepareRetirement(
        _ placeholder: Tab
    ) -> (any EmptySplitPlaceholderRetirementMutation)? {
        if let canonicalPlaceholder = recorder.canonicalPlaceholder,
           canonicalPlaceholder !== placeholder {
            return nil
        }
        return TestEmptySplitPlaceholderRetirementMutation(
            recorder: recorder,
            placeholder: placeholder
        )
    }
}

@MainActor
private final class TestEmptySplitPlaceholderRetirementMutation:
    EmptySplitPlaceholderRetirementMutation {
    private enum State { case prepared, committed, published, cancelled }

    private let recorder: Recorder
    private let placeholder: Tab
    private var state = State.prepared

    init(recorder: Recorder, placeholder: Tab) {
        self.recorder = recorder
        self.placeholder = placeholder
    }

    func isCurrent() -> Bool {
        guard case .prepared = state else { return false }
        return recorder.canonicalPlaceholder.map { $0 === placeholder } ?? true
    }

    func commitModel() -> Bool {
        guard isCurrent() else { return false }
        state = .committed
        recorder.removedTabs.append(placeholder)
        return true
    }

    func publish() {
        guard case .committed = state else { return }
        state = .published
    }

    func rollback() {
        guard case .prepared = state else { return }
        state = .cancelled
    }
}

@MainActor
private final class Recorder {
    var replacements: [(
        tab: Tab,
        placeholder: Tab,
        windowState: BrowserWindowState
    )] = []
    var canonicalPlaceholder: Tab?
    var replacementResults: [Bool] = []
    var committedTopologyCount = 0
    var settledPresentationCount = 0
    var publishedReplacementCount = 0
    var rolledBackReplacementCount = 0
    var removedTabs: [Tab] = []

    var removedTabIDs: [UUID] { removedTabs.map(\.id) }
}
