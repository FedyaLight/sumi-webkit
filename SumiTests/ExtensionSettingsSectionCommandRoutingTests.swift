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
            },
            uninstall: { extensionID in
                recorder.events.append(.uninstall(extensionID))
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
        try await commands.uninstall("extension-f")

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
            .uninstall("extension-f"),
        ])
    }

    func testFindingsSectionAddCommandRouting() async throws {
        let candidate = makeRoutingCandidate(
            id: "web-extension",
            bundleKind: .webExtension,
            runtimeStatus: .webExtensionImportable
        )
        let expected = makeRoutingInstalledExtension(id: candidate.id)
        var addedCandidateIDs: [String] = []
        let commands = ExtensionSettingsFindingsCommands { candidate in
            addedCandidateIDs.append(candidate.id)
            return expected
        }

        let installed = try await commands.add(candidate)

        XCTAssertEqual(addedCandidateIDs, [candidate.id])
        XCTAssertEqual(installed.id, expected.id)
        XCTAssertFalse(installed.isEnabled)
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
        case uninstall(String)
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
    id: String,
    bundleKind: SafariExtensionBundleKind = .contentBlocker,
    runtimeStatus: SafariExtensionRuntimeStatus = .contentBlockerImportable
) -> DiscoveredSafariExtensionCandidate {
    let appURL = URL(fileURLWithPath: "/Applications/\(id).app")
    return DiscoveredSafariExtensionCandidate(
        extensionBundleIdentifier: id,
        displayName: id,
        version: "1.0",
        extensionPointIdentifier: bundleKind == .webExtension
            ? SafariExtensionScanner.safariWebExtensionPointIdentifier
            : SafariExtensionScanner.safariContentBlockerExtensionPointIdentifier,
        bundleKind: bundleKind,
        runtimeStatus: runtimeStatus,
        containingAppName: id,
        containingAppBundleIdentifier: "test.\(id)",
        containingAppURL: appURL,
        appexURL: appURL.appendingPathComponent("Contents/PlugIns/\(id).appex"),
        manifestURL: nil,
        isReadable: true
    )
}

private func makeRoutingInstalledExtension(id: String) -> InstalledExtension {
    InstalledExtension(
        id: id,
        name: id,
        version: "1.0",
        manifestVersion: 3,
        description: nil,
        isEnabled: false,
        installDate: .distantPast,
        lastUpdateDate: .distantPast,
        packagePath: "/Applications/\(id).app/Contents/PlugIns/\(id).appex",
        iconPath: nil,
        sourceKind: .safariAppExtension,
        backgroundModel: .serviceWorker,
        incognitoMode: .spanning,
        sourcePathFingerprint: "source-\(id)",
        manifestRootFingerprint: "manifest-\(id)",
        sourceBundlePath: "/Applications/\(id).app/Contents/PlugIns/\(id).appex",
        optionsPagePath: nil,
        defaultPopupPath: nil,
        hasBackground: true,
        hasAction: true,
        hasOptionsPage: false,
        hasContentScripts: true,
        hasExtensionPages: false,
        activationSummary: ExtensionActivationSummary(
            matchPatternStrings: [],
            broadScope: false,
            hasContentScripts: true,
            hasAction: true,
            hasOptionsPage: false,
            hasExtensionPages: false
        ),
        manifest: [:]
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
