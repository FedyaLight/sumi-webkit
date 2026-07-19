@testable import Sumi
import XCTest

@available(macOS 15.5, *)
@MainActor
final class ExtensionSettingsSectionCommandRoutingTests: XCTestCase {
    func testTemporaryMissingSiteAccessSnapshotCannotPersistFallbackAsk() {
        XCTAssertFalse(
            ExtensionSettingsSiteAccessMutationAdmission.shouldPersist(
                oldValue: SafariExtensionSiteAccessLevel.allow,
                newValue: .ask,
                persistedValue: nil
            )
        )
    }

    func testUserSiteAccessChangePersistsAgainstLoadedPolicy() {
        XCTAssertTrue(
            ExtensionSettingsSiteAccessMutationAdmission.shouldPersist(
                oldValue: SafariExtensionSiteAccessLevel.ask,
                newValue: .allow,
                persistedValue: .ask
            )
        )
    }

    func testInstalledSectionCommandRouting() async throws {
        let recorder = InstalledSectionCommandRecorder()
        let commands = ExtensionSettingsInstalledCommands(
            setEnabled: { extensionID, isEnabled in
                recorder.events.append(.enabled(extensionID, isEnabled))
            },
            setDefaultSiteAccess: { extensionID, access in
                recorder.events.append(
                    .defaultAccess(extensionID, access.rawValue)
                )
            },
            setPrivateAccess: { extensionID, isAllowed in
                recorder.events.append(.privateAccess(extensionID, isAllowed))
            },
            setConfiguredSiteAccess: { extensionID, pattern, access in
                recorder.events.append(
                    .configuredAccess(extensionID, pattern, access.rawValue)
                )
            },
            openOptions: { extensionID in
                recorder.events.append(.openOptions(extensionID))
            }
        )

        try await commands.setEnabled(true, for: "extension-a")
        commands.setDefaultSiteAccess(.allow, for: "extension-b")
        commands.setPrivateAccess(false, for: "extension-c")
        commands.setConfiguredSiteAccess(
            .deny,
            for: "extension-d",
            matchPattern: "*://example.com/*"
        )
        await commands.openOptions(for: "extension-e")

        XCTAssertEqual(recorder.events, [
            .enabled("extension-a", true),
            .defaultAccess("extension-b", "allow"),
            .privateAccess("extension-c", false),
            .configuredAccess(
                "extension-d",
                "*://example.com/*",
                "deny"
            ),
            .openOptions("extension-e"),
        ])
    }

    func testContentBlockerSectionCommandRouting() async throws {
        let candidate = makeRoutingCandidate(id: "content-blocker")
        let enabledRecord = makeRoutingRecord(
            id: candidate.id,
            isEnabled: true
        )
        let disabledRecord = makeRoutingRecord(
            id: candidate.id,
            isEnabled: false
        )
        let recorder = ContentBlockerCommandRecorder(
            enabledRecord: enabledRecord,
            disabledRecord: disabledRecord
        )
        let commands = ExtensionSettingsContentBlockerCommands(
            enable: { candidate in
                recorder.enabledCandidateIDs.append(candidate.id)
                return recorder.enabledRecord
            },
            setEnabled: { bundleIdentifier, isEnabled in
                recorder.setEnabledCalls.append((bundleIdentifier, isEnabled))
                return recorder.disabledRecord
            }
        )

        let enabled = try await commands.setEnabled(true, for: candidate)
        let disabled = try await commands.setEnabled(false, for: candidate)

        XCTAssertEqual(enabled, enabledRecord)
        XCTAssertEqual(disabled, disabledRecord)
        XCTAssertEqual(recorder.enabledCandidateIDs, [candidate.id])
        XCTAssertEqual(recorder.setEnabledCalls.count, 1)
        XCTAssertEqual(recorder.setEnabledCalls.first?.0, candidate.id)
        XCTAssertEqual(recorder.setEnabledCalls.first?.1, false)
    }
}

@available(macOS 15.5, *)
@MainActor
private final class InstalledSectionCommandRecorder {
    enum Event: Equatable {
        case enabled(String, Bool)
        case defaultAccess(String, String)
        case privateAccess(String, Bool)
        case configuredAccess(String, String, String)
        case openOptions(String)
    }

    var events: [Event] = []
}

@available(macOS 15.5, *)
@MainActor
private final class ContentBlockerCommandRecorder {
    let enabledRecord: InstalledSafariContentBlockerRecord
    let disabledRecord: InstalledSafariContentBlockerRecord
    var enabledCandidateIDs: [String] = []
    var setEnabledCalls: [(String, Bool)] = []

    init(
        enabledRecord: InstalledSafariContentBlockerRecord,
        disabledRecord: InstalledSafariContentBlockerRecord
    ) {
        self.enabledRecord = enabledRecord
        self.disabledRecord = disabledRecord
    }
}

private func makeRoutingCandidate(
    id: String
) -> DiscoveredSafariExtensionCandidate {
    let appURL = URL(fileURLWithPath: "/Applications/\(id).app")
    return DiscoveredSafariExtensionCandidate(
        extensionBundleIdentifier: id,
        displayName: id,
        version: "1.0",
        extensionPointIdentifier: SafariExtensionScanner
            .safariContentBlockerExtensionPointIdentifier,
        bundleKind: .contentBlocker,
        runtimeStatus: .contentBlockerImportable,
        containingAppName: id,
        containingAppBundleIdentifier: "test.\(id)",
        containingAppURL: appURL,
        appexURL: appURL.appendingPathComponent("Contents/PlugIns/\(id).appex"),
        manifestURL: nil,
        isReadable: true
    )
}

private func makeRoutingRecord(
    id: String,
    isEnabled: Bool
) -> InstalledSafariContentBlockerRecord {
    InstalledSafariContentBlockerRecord(
        id: id,
        extensionBundleIdentifier: id,
        displayName: id,
        version: "1.0",
        containingAppName: id,
        containingAppBundleIdentifier: "test.\(id)",
        appexPath: "/Applications/\(id).app/Contents/PlugIns/\(id).appex",
        containingAppPath: "/Applications/\(id).app",
        resourceFingerprint: "fingerprint-\(id)",
        isEnabled: isEnabled,
        installDate: .distantPast,
        lastUpdateDate: .distantPast,
        compileStatus: .available,
        lastError: nil,
        ruleListCount: 1,
        ignoredEmptyRuleListCount: 0
    )
}
