import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionNativeMessagingBackgroundWakeOwnerTests: XCTestCase {
    func testScheduleDeduplicatesByWakeKey() async {
        let owner = ExtensionNativeMessagingBackgroundWakeOwner()
        let wakeStarted = expectation(description: "wake started")
        var releaseWake: CheckedContinuation<Void, Never>?
        var wakeCount = 0

        owner.scheduleWake(
            wakeKey: "profile:extension",
            operation: "first",
            wake: {
                wakeCount += 1
                wakeStarted.fulfill()
                await withCheckedContinuation { continuation in
                    releaseWake = continuation
                }
            },
            logFailure: { _, _ in
                XCTFail("Wake should not fail")
            }
        )

        owner.scheduleWake(
            wakeKey: "profile:extension",
            operation: "second",
            wake: {
                XCTFail("Duplicate wake should be ignored")
            },
            logFailure: { _, _ in
                XCTFail("Duplicate wake should not log")
            }
        )

        await fulfillment(of: [wakeStarted], timeout: 1.0)
        XCTAssertEqual(wakeCount, 1)
        releaseWake?.resume()
        await owner.drainScheduledTasksForTests()
    }

    func testFinishedWakeIsRemovedAndCanBeScheduledAgain() async {
        let owner = ExtensionNativeMessagingBackgroundWakeOwner()
        var operations: [String] = []

        owner.scheduleWake(
            wakeKey: "profile:extension",
            operation: "first",
            wake: {
                operations.append("first")
            },
            logFailure: { _, _ in
                XCTFail("Wake should not fail")
            }
        )
        await owner.drainScheduledTasksForTests()

        owner.scheduleWake(
            wakeKey: "profile:extension",
            operation: "second",
            wake: {
                operations.append("second")
            },
            logFailure: { _, _ in
                XCTFail("Wake should not fail")
            }
        )
        await owner.drainScheduledTasksForTests()

        XCTAssertEqual(operations, ["first", "second"])
    }

    func testCancelWakeTasksForExtensionCancelsOnlyMatchingWakeKeys() async {
        let owner = ExtensionNativeMessagingBackgroundWakeOwner()
        let firstProfileID = UUID()
        let secondProfileID = UUID()
        let firstWakeStarted = expectation(description: "first wake started")
        let secondWakeStarted = expectation(description: "second wake started")
        var releaseFirstWake: CheckedContinuation<Void, Never>?
        var releaseSecondWake: CheckedContinuation<Void, Never>?

        owner.scheduleWake(
            wakeKey: ExtensionRuntimeResidencyState.scopedKey(
                extensionId: "first-extension",
                profileId: firstProfileID
            ),
            operation: "first",
            wake: {
                firstWakeStarted.fulfill()
                await withCheckedContinuation { continuation in
                    releaseFirstWake = continuation
                }
            },
            logFailure: { _, _ in /* no-op */ }
        )
        owner.scheduleWake(
            wakeKey: ExtensionRuntimeResidencyState.scopedKey(
                extensionId: "second-extension",
                profileId: secondProfileID
            ),
            operation: "second",
            wake: {
                secondWakeStarted.fulfill()
                await withCheckedContinuation { continuation in
                    releaseSecondWake = continuation
                }
            },
            logFailure: { _, _ in /* no-op */ }
        )

        await fulfillment(
            of: [firstWakeStarted, secondWakeStarted],
            timeout: 1.0
        )
        owner.cancelWakeTasks(forExtensionId: "first-extension")

        releaseFirstWake?.resume()
        releaseSecondWake?.resume()
        await owner.drainScheduledTasksForTests()
        XCTAssertTrue(owner.runtimeTasksForDrain().isEmpty)
    }

    func testFailureLoggerReceivesOperation() async {
        enum TestError: Error, Equatable {
            case failed
        }

        let owner = ExtensionNativeMessagingBackgroundWakeOwner()
        var loggedOperation: String?
        var didLogFailure = false

        owner.scheduleWake(
            wakeKey: "profile:extension",
            operation: "wake before sendMessage",
            wake: {
                throw TestError.failed
            },
            logFailure: { error, operation in
                XCTAssertEqual(error as? TestError, .failed)
                loggedOperation = operation
                didLogFailure = true
            }
        )

        await owner.drainScheduledTasksForTests()
        XCTAssertTrue(didLogFailure)
        XCTAssertEqual(loggedOperation, "wake before sendMessage")
    }

    func testCancelledContentScriptTaskCannotRemoveNewSameProfileTask()
        async {
        let profileID = UUID()
        let installed = InstalledExtensionCollection()
        installed.connectRecordChanges {}
        installed.upsert(Self.contentScriptRecord())
        let firstStarted = expectation(description: "first load started")
        let secondStarted = expectation(description: "second load started")
        var loadCount = 0
        var releaseFirst: CheckedContinuation<Void, Never>?
        var releaseSecond: CheckedContinuation<Void, Never>?
        let owner = ExtensionContentScriptContextPreparationOwner(
            installedExtensions: installed,
            runtimeIsEnabled: { true },
            context: { _, _ in nil },
            load: { _, _ in
                loadCount += 1
                if loadCount == 1 {
                    firstStarted.fulfill()
                    await withCheckedContinuation { releaseFirst = $0 }
                } else {
                    secondStarted.fulfill()
                    await withCheckedContinuation { releaseSecond = $0 }
                }
            },
            logFailure: { _, _, _, _ in }
        )

        let first = Task { await owner.ensureLoaded(profileID: profileID) }
        await fulfillment(of: [firstStarted], timeout: 1.0)
        owner.cancelAll()
        let second = Task { await owner.ensureLoaded(profileID: profileID) }
        await fulfillment(of: [secondStarted], timeout: 1.0)

        releaseFirst?.resume()
        _ = await first.value
        XCTAssertEqual(owner.runtimeTasksForDrain().count, 1)

        releaseSecond?.resume()
        _ = await second.value
        XCTAssertTrue(owner.runtimeTasksForDrain().isEmpty)
    }

    func testContentScriptPreparationReportsFailedWhenNoContextLoads() async {
        enum TestError: Error { case failed }
        let installed = InstalledExtensionCollection()
        installed.connectRecordChanges {}
        installed.upsert(Self.contentScriptRecord())
        let owner = ExtensionContentScriptContextPreparationOwner(
            installedExtensions: installed,
            runtimeIsEnabled: { true },
            context: { _, _ in nil },
            load: { _, _ in throw TestError.failed },
            logFailure: { _, _, _, _ in }
        )

        let result = await owner.ensureLoaded(profileID: UUID())

        XCTAssertEqual(result, .failed)
    }

    private static func contentScriptRecord() -> InstalledExtension {
        InstalledExtension(
            id: "content-script",
            name: "Content Script",
            version: "1",
            manifestVersion: 3,
            description: nil,
            isEnabled: true,
            installDate: .distantPast,
            lastUpdateDate: .distantPast,
            packagePath: "/tmp/content-script",
            iconPath: nil,
            sourceKind: .directory,
            backgroundModel: .none,
            incognitoMode: .spanning,
            sourcePathFingerprint: "source",
            manifestRootFingerprint: "manifest",
            sourceBundlePath: "/tmp/content-script",
            optionsPagePath: nil,
            defaultPopupPath: nil,
            hasBackground: false,
            hasAction: false,
            hasOptionsPage: false,
            hasContentScripts: true,
            hasExtensionPages: false,
            activationSummary: ExtensionActivationSummary(
                matchPatternStrings: ["<all_urls>"],
                broadScope: true,
                hasContentScripts: true,
                hasAction: false,
                hasOptionsPage: false,
                hasExtensionPages: false
            ),
            manifest: [:]
        )
    }
}

@available(macOS 15.5, *)
@MainActor
private extension ExtensionNativeMessagingBackgroundWakeOwner {
    func drainScheduledTasksForTests() async {
        while true {
            let tasks = runtimeTasksForDrain()
            guard tasks.isEmpty == false else { return }

            for task in tasks {
                await task.value
            }
        }
    }
}
