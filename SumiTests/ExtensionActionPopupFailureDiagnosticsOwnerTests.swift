import Foundation
@testable import Sumi
import XCTest

@available(macOS 15.5, *)
@MainActor
final class ExtensionActionPopupFailureDiagnosticsOwnerTests: XCTestCase {
    func testClassifyReportsSourceResourcesMissingWhenResourceRootResolutionThrows() {
        let profileId = UUID()
        let installedExtension = makeInstalledExtension()
        let owner = makeOwner(
            installedExtension: installedExtension,
            profileId: profileId,
            resourcesError: resourcesError()
        )

        let bucket = owner.classifyActionPopupRuntimeFailure(
            extensionId: installedExtension.id,
            profileId: profileId,
            installedExtension: installedExtension
        )

        XCTAssertEqual(bucket, .sourceResourcesMissing)
    }

    func testDiagnosticLinesIncludeResourceRootResolutionError() {
        let profileId = UUID()
        let installedExtension = makeInstalledExtension()
        let error = resourcesError()
        let owner = makeOwner(
            installedExtension: installedExtension,
            profileId: profileId,
            resourcesError: error,
            snapshot: makeSnapshot(
                extensionId: installedExtension.id,
                profileId: profileId
            )
        )

        let lines = owner.actionPopupRuntimeDiagnosticLines(
            extensionId: installedExtension.id,
            profileId: profileId,
            installedExtension: installedExtension,
            failureBucket: .sourceResourcesMissing
        )

        XCTAssertTrue(lines.contains("sourceResourcesPresent=false"))
        XCTAssertTrue(lines.contains("sourceResourcesErrorDomain=\(error.domain)"))
        XCTAssertTrue(lines.contains("sourceResourcesErrorCode=\(error.code)"))
        XCTAssertTrue(lines.contains("sourceResourcesErrorDescription=\(error.localizedDescription)"))
    }

    private func makeOwner(
        installedExtension: InstalledExtension,
        profileId: UUID,
        resourcesError: NSError,
        snapshot: ExtensionProfileRuntimeStateOwner.ExtensionSnapshot? = nil
    ) -> ExtensionActionPopupFailureDiagnosticsOwner {
        ExtensionActionPopupFailureDiagnosticsOwner(
            installedExtensions: { [installedExtension] in
                [installedExtension]
            },
            controllerExists: { candidateProfileId in
                candidateProfileId == profileId
            },
            extensionResourcesRoot: { _, _, _ in
                throw resourcesError
            },
            lastExtensionLoadError: { _, _ in nil },
            extensionSnapshot: { _, candidateProfileId in
                candidateProfileId == profileId ? snapshot : nil
            },
            profileIdForContext: { _ in nil },
            currentProfileId: { profileId },
            runtimeState: { .ready }
        )
    }

    private func makeSnapshot(
        extensionId: String,
        profileId: UUID
    ) -> ExtensionProfileRuntimeStateOwner.ExtensionSnapshot {
        ExtensionProfileRuntimeStateOwner.ExtensionSnapshot(
            extensionId: extensionId,
            profileId: profileId,
            controller: nil,
            context: nil,
            readiness: ExtensionRuntimeReadinessContext(
                hasEnabledExtensionDemand: true,
                enabledExtensionIDs: [extensionId],
                loadedExtensionStatesByID: [:],
                controllerExists: true,
                globalRuntimeReady: true
            )
        )
    }

    private func makeInstalledExtension() -> InstalledExtension {
        InstalledExtension(
            id: "extension-a",
            name: "Extension A",
            version: "1.0.0",
            manifestVersion: 3,
            description: nil,
            isEnabled: true,
            installDate: Date(),
            lastUpdateDate: Date(),
            packagePath: "/tmp/extension-a",
            iconPath: nil,
            sourceKind: .directory,
            backgroundModel: .none,
            incognitoMode: .spanning,
            sourcePathFingerprint: "extension-a",
            manifestRootFingerprint: "extension-a",
            sourceBundlePath: "/tmp/extension-a",
            optionsPagePath: nil,
            defaultPopupPath: nil,
            hasBackground: false,
            hasAction: true,
            hasOptionsPage: false,
            hasContentScripts: false,
            hasExtensionPages: false,
            activationSummary: ExtensionActivationSummary(
                matchPatternStrings: [],
                broadScope: false,
                hasContentScripts: false,
                hasAction: true,
                hasOptionsPage: false,
                hasExtensionPages: false
            ),
            manifest: [
                "manifest_version": 3,
                "name": "Extension A",
                "version": "1.0.0",
                "action": [:],
            ]
        )
    }

    private func resourcesError() -> NSError {
        NSError(
            domain: "ExtensionResourcesTest",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "resources unavailable"]
        )
    }
}
