import XCTest

@testable import Sumi

final class SumiPermissionPolicyResolverTests: XCTestCase {
    func testHTTPSRequestingAndTopOriginsProceed() async {
        let result = await evaluate(.camera)

        XCTAssertTrue(result.isAllowedToProceed)
        XCTAssertTrue(result.mayAskUser)
        XCTAssertEqual(result.source, .defaultSetting)
        XCTAssertEqual(result.reason, SumiPermissionPolicyReason.allowed)
    }

    func testUnsupportedPermissionGroupsDoNotProceed() async {
        let combined = await evaluate(.cameraAndMicrophone)
        XCTAssertFalse(combined.isAllowedToProceed)
        XCTAssertEqual(combined.source, .unsupported)
        XCTAssertEqual(
            combined.reason,
            SumiPermissionPolicyReason.cameraAndMicrophoneRequiresCoordinatorExpansion
        )

        let storage = await evaluate(.storageAccess)
        XCTAssertFalse(storage.isAllowedToProceed)
        XCTAssertEqual(storage.source, .unsupported)
        XCTAssertEqual(storage.reason, SumiPermissionPolicyReason.storageAccessUnsupported)
    }

    func testZeroOrMultiplePermissionTypesAreUnsupported() async {
        let empty = await evaluate(permissionTypes: [])
        XCTAssertFalse(empty.isAllowedToProceed)
        XCTAssertEqual(empty.source, .unsupported)
        XCTAssertEqual(empty.reason, SumiPermissionPolicyReason.requiresSinglePermissionType)

        let multiple = await evaluate(permissionTypes: [.camera, .microphone])
        XCTAssertFalse(multiple.isAllowedToProceed)
        XCTAssertEqual(multiple.source, .unsupported)
        XCTAssertEqual(multiple.reason, SumiPermissionPolicyReason.requiresSinglePermissionType)
    }

    func testHTTPNonLocalhostCameraRequestIsDeniedWithInsecureOrigin() async {
        let result = await evaluate(
            .camera,
            requestingOrigin: SumiPermissionOrigin(string: "http://example.com"),
            topOrigin: SumiPermissionOrigin(string: "http://example.com")
        )

        XCTAssertFalse(result.isAllowedToProceed)
        XCTAssertEqual(result.source, .insecureOrigin)
        XCTAssertEqual(result.reason, SumiPermissionPolicyReason.insecureRequestingOrigin)
        XCTAssertEqual(result.deniedState, .deny)
    }

    func testLocalDevelopmentHTTPOriginsProceed() async {
        for origin in [
            "http://localhost",
            "http://127.0.0.1",
            "http://[::1]",
        ] {
            let result = await evaluate(
                .camera,
                requestingOrigin: SumiPermissionOrigin(string: origin),
                topOrigin: SumiPermissionOrigin(string: origin),
                committedURL: URL(string: origin),
                visibleURL: URL(string: origin)
            )

            XCTAssertTrue(result.isAllowedToProceed, origin)
        }
    }

    func testOpaqueDataAndFileSensitiveOriginsAreDeniedBeforeUI() async {
        for origin in [
            SumiPermissionOrigin(string: "about:blank"),
            SumiPermissionOrigin(string: "data:text/plain,hello"),
            SumiPermissionOrigin(url: URL(fileURLWithPath: "/tmp/permission-test.html")),
        ] {
            let result = await evaluate(
                .geolocation,
                requestingOrigin: origin,
                topOrigin: origin,
                committedURL: nil,
                visibleURL: nil
            )

            XCTAssertFalse(result.isAllowedToProceed, origin.identity)
            XCTAssertEqual(result.source, .invalidOrigin, origin.identity)
            XCTAssertFalse(result.mayAskUser)
        }
    }

    func testMalformedOriginIsDeniedWithInvalidOrigin() async {
        let result = await evaluate(
            .notifications,
            requestingOrigin: SumiPermissionOrigin.invalid(reason: "malformed"),
            topOrigin: SumiPermissionOrigin(string: "https://example.com")
        )

        XCTAssertFalse(result.isAllowedToProceed)
        XCTAssertEqual(result.source, .invalidOrigin)
        XCTAssertEqual(result.reason, SumiPermissionPolicyReason.invalidRequestingOrigin)
    }

    func testDifferentTopOriginsRemainAllowedWhenBothOriginsAreKeyable() async {
        let result = await evaluate(
            .camera,
            requestingOrigin: SumiPermissionOrigin(string: "https://widget.example"),
            topOrigin: SumiPermissionOrigin(string: "https://embedder.example"),
            committedURL: URL(string: "https://widget.example"),
            visibleURL: URL(string: "https://widget.example")
        )

        XCTAssertTrue(result.isAllowedToProceed)
    }

    func testMissingTopOriginForSensitivePermissionIsDenied() async {
        let result = await evaluate(
            .camera,
            requestingOrigin: SumiPermissionOrigin(string: "https://example.com"),
            topOrigin: SumiPermissionOrigin.invalid(reason: "missing-top-origin")
        )

        XCTAssertFalse(result.isAllowedToProceed)
        XCTAssertEqual(result.source, .invalidOrigin)
        XCTAssertEqual(result.reason, SumiPermissionPolicyReason.invalidTopOrigin)
    }

    func testDisplayDomainDoesNotInfluenceSecurityDecision() async {
        let result = await evaluate(
            .camera,
            requestingOrigin: SumiPermissionOrigin(string: "http://evil.example"),
            topOrigin: SumiPermissionOrigin(string: "http://evil.example"),
            displayDomain: "trusted.example"
        )

        XCTAssertFalse(result.isAllowedToProceed)
        XCTAssertEqual(result.source, .insecureOrigin)
    }

    func testVisibleURLMismatchForSensitivePermissionIsDenied() async {
        let result = await evaluate(
            .camera,
            committedURL: URL(string: "https://real.example/camera"),
            visibleURL: URL(string: "https://shown.example/camera")
        )

        XCTAssertFalse(result.isAllowedToProceed)
        XCTAssertEqual(result.source, .virtualURLMismatch)
        XCTAssertEqual(result.reason, SumiPermissionPolicyReason.virtualURLMismatch)
    }

    func testMissingVisibleURLDoesNotFailOrdinaryCommittedHTTPSPage() async {
        let result = await evaluate(
            .camera,
            committedURL: URL(string: "https://example.com/camera"),
            visibleURL: nil
        )

        XCTAssertTrue(result.isAllowedToProceed)
    }

    func testNormalTabHTTPSCameraProceedsWhenSystemAuthorized() async {
        let result = await evaluate(.camera, surface: .normalTab)

        XCTAssertTrue(result.isAllowedToProceed)
        XCTAssertEqual(result.systemAuthorizationSnapshot?.state, .authorized)
    }

    func testAuxiliaryAndUnsafeSurfacesDenySensitivePermissions() async {
        let miniWindow = await evaluate(.camera, surface: .miniWindow)
        XCTAssertFalse(miniWindow.isAllowedToProceed)
        XCTAssertEqual(miniWindow.source, .defaultSetting)
        XCTAssertEqual(miniWindow.reason, SumiPermissionPolicyReason.miniWindowSensitiveDenied)

        let peek = await evaluate(.camera, surface: .peek)
        XCTAssertFalse(peek.isAllowedToProceed)
        XCTAssertEqual(peek.source, .defaultSetting)
        XCTAssertEqual(peek.reason, SumiPermissionPolicyReason.peekSensitiveDenied)

        let unknown = await evaluate(.camera, surface: .unknown)
        XCTAssertFalse(unknown.isAllowedToProceed)
        XCTAssertEqual(unknown.source, .defaultSetting)
        XCTAssertEqual(unknown.reason, SumiPermissionPolicyReason.unknownSurfaceSensitiveDenied)
    }

    func testInternalAndExtensionSurfacesDoNotReceivePagePermissionTreatment() async {
        let internalPage = await evaluate(.camera, surface: .internalPage)
        XCTAssertFalse(internalPage.isAllowedToProceed)
        XCTAssertEqual(internalPage.source, .internalPage)
        XCTAssertEqual(internalPage.reason, SumiPermissionPolicyReason.internalPage)

        let extensionPage = await evaluate(.camera, surface: .extensionPage)
        XCTAssertFalse(extensionPage.isAllowedToProceed)
        XCTAssertEqual(extensionPage.source, .unsupported)
        XCTAssertEqual(extensionPage.reason, SumiPermissionPolicyReason.extensionPageUnsupported)
    }

    func testSumiInternalURLsAreDeniedAsInternalPages() async {
        let result = await evaluate(
            .camera,
            requestingOrigin: SumiPermissionOrigin(identity: "unsupported:sumi"),
            topOrigin: SumiPermissionOrigin(identity: "unsupported:sumi"),
            committedURL: URL(string: "sumi://settings?pane=privacy"),
            visibleURL: URL(string: "sumi://settings?pane=privacy")
        )

        XCTAssertFalse(result.isAllowedToProceed)
        XCTAssertEqual(result.source, .internalPage)
        XCTAssertEqual(result.reason, SumiPermissionPolicyReason.internalPage)
    }

    func testUserActivationRequiredPermissionsProceedWithGesture() async {
        let popups = await evaluate(.popups, hasUserGesture: true)
        XCTAssertTrue(popups.isAllowedToProceed)

        let externalScheme = await evaluate(.externalScheme("mailto"), hasUserGesture: true)
        XCTAssertTrue(externalScheme.isAllowedToProceed)

        let filePicker = await evaluate(.filePicker, hasUserGesture: true)
        XCTAssertTrue(filePicker.isAllowedToProceed)
        XCTAssertEqual(filePicker.allowedPersistences, [.oneTime])
    }

    func testUserActivationRequiredPermissionsDenyWithoutGesture() async {
        for permissionType in [
            SumiPermissionType.popups,
            .externalScheme("mailto"),
            .filePicker,
        ] {
            let result = await evaluate(permissionType, hasUserGesture: false)
            XCTAssertFalse(result.isAllowedToProceed, permissionType.identity)
            XCTAssertEqual(result.source, .runtime, permissionType.identity)
            XCTAssertEqual(result.reason, SumiPermissionPolicyReason.requiresUserActivation)
            XCTAssertEqual(result.deniedState, .deny)
        }
    }

    func testUnknownUserActivationIsConservativeForActivationRequiredPermissions() async {
        let result = await evaluate(.filePicker, usesUnknownUserGesture: true)

        XCTAssertFalse(result.isAllowedToProceed)
        XCTAssertEqual(result.source, .runtime)
        XCTAssertEqual(result.reason, SumiPermissionPolicyReason.requiresUserActivation)
    }

    func testCameraDoesNotRequireUserGesture() async {
        let result = await evaluate(.camera, hasUserGesture: false)

        XCTAssertTrue(result.isAllowedToProceed)
    }

    func testEphemeralProfileProceedResultExcludesPersistentChoices() async {
        let result = await evaluate(.camera, isEphemeralProfile: true)

        XCTAssertTrue(result.isAllowedToProceed)
        XCTAssertEqual(result.allowedPersistences, [.oneTime, .session])
        XCTAssertFalse(result.allowedPersistences.contains(.persistent))
    }

    func testFilePickerRemainsOneTimeOnlyInEphemeralProfile() async {
        let result = await evaluate(.filePicker, hasUserGesture: true, isEphemeralProfile: true)

        XCTAssertTrue(result.isAllowedToProceed)
        XCTAssertEqual(result.allowedPersistences, [.oneTime])
    }

    func testSystemAuthorizedCameraProceeds() async {
        let result = await evaluate(.camera, systemStates: [.camera: .authorized])

        XCTAssertTrue(result.isAllowedToProceed)
        XCTAssertFalse(result.requiresSystemAuthorizationPrompt)
        XCTAssertEqual(result.systemAuthorizationSnapshot?.state, .authorized)
    }

    func testSystemNotDeterminedProceedsWithSystemPromptHintAndDoesNotRequestAuthorization() async {
        let service = FakeSumiSystemPermissionService(states: [.camera: .notDetermined])
        let result = await evaluate(.camera, systemPermissionService: service)

        XCTAssertTrue(result.isAllowedToProceed)
        XCTAssertEqual(result.source, .system)
        XCTAssertTrue(result.requiresSystemAuthorizationPrompt)
        XCTAssertEqual(result.systemAuthorizationSnapshot?.state, .notDetermined)
        let requestAuthorizationCallCount = await service.requestAuthorizationCallCount()
        XCTAssertEqual(requestAuthorizationCallCount, 0)
    }

    func testSystemBlockedStatesDoNotProceedOrAskOrdinarySiteUI() async throws {
        let cases: [(SumiPermissionType, SumiSystemPermissionKind, SumiSystemPermissionAuthorizationState)] = [
            (.camera, .camera, .denied),
            (.microphone, .microphone, .restricted),
            (.geolocation, .geolocation, .systemDisabled),
            (.notifications, .notifications, .denied),
            (.camera, .camera, .missingUsageDescription),
            (.microphone, .microphone, .missingEntitlement),
            (.geolocation, .geolocation, .unavailable),
        ]

        for (permissionType, kind, state) in cases {
            let service = FakeSumiSystemPermissionService(states: [kind: state])
            let result = await evaluate(permissionType, systemPermissionService: service)

            XCTAssertFalse(result.isAllowedToProceed, "\(kind.rawValue):\(state.rawValue)")
            XCTAssertFalse(result.mayAskUser, "\(kind.rawValue):\(state.rawValue)")
            XCTAssertEqual(result.source, .system, "\(kind.rawValue):\(state.rawValue)")
            XCTAssertEqual(result.systemAuthorizationSnapshot?.state, state)
            XCTAssertEqual(
                result.reason,
                "\(SumiPermissionPolicyReason.systemAuthorizationBlocked):\(state.rawValue)"
            )
            let requestAuthorizationCallCount = await service.requestAuthorizationCallCount()
            XCTAssertEqual(requestAuthorizationCallCount, 0)

            let snapshotString = try XCTUnwrap(result.decision?.systemAuthorizationSnapshot)
            let decoded = try JSONDecoder().decode(
                SumiSystemPermissionSnapshot.self,
                from: Data(snapshotString.utf8)
            )
            XCTAssertEqual(decoded.state, state)
        }
    }

    func testSystemSettingsHintOnlyForSettingsResolvableSystemBlocks() async {
        let denied = await evaluate(.camera, systemStates: [.camera: .denied])
        XCTAssertTrue(denied.mayOpenSystemSettings)

        let missingEntitlement = await evaluate(.camera, systemStates: [.camera: .missingEntitlement])
        XCTAssertFalse(missingEntitlement.mayOpenSystemSettings)
    }

    func testNoOpPolicyAllowsNormalEvaluation() async {
        let result = await evaluate(.camera, policyProvider: NoOpSumiPermissionPolicyProvider())

        XCTAssertTrue(result.isAllowedToProceed)
        XCTAssertEqual(result.source, .defaultSetting)
    }

    func testDenyPolicyOverrideBlocksBeforeStoredDecisionLookup() async {
        let result = await evaluate(
            .camera,
            policyProvider: StaticSumiPermissionPolicyProvider(
                override: .deny(reason: "enterprise-policy-denied")
            ),
            systemStates: [.camera: .authorized]
        )

        XCTAssertFalse(result.isAllowedToProceed)
        XCTAssertEqual(result.source, .policy)
        XCTAssertEqual(result.reason, "enterprise-policy-denied")
    }

    func testDefaultSettingDenyPolicyUsesDefaultSettingSource() async {
        let result = await evaluate(
            .camera,
            policyProvider: StaticSumiPermissionPolicyProvider(
                override: .deny(source: .defaultSetting, reason: "default-camera-block")
            )
        )

        XCTAssertFalse(result.isAllowedToProceed)
        XCTAssertEqual(result.source, .defaultSetting)
        XCTAssertEqual(result.reason, "default-camera-block")
    }

    func testAllowPolicyOverrideCanProceedOnlyAfterHardGatesPass() async {
        let allowProvider = StaticSumiPermissionPolicyProvider(
            override: .allow(reason: "enterprise-policy-allowed")
        )

        let allowed = await evaluate(
            .camera,
            policyProvider: allowProvider,
            systemStates: [.camera: .authorized]
        )
        XCTAssertTrue(allowed.isAllowedToProceed)
        XCTAssertEqual(allowed.source, .policy)
        XCTAssertEqual(allowed.reason, "enterprise-policy-allowed")

        let invalidOrigin = await evaluate(
            .camera,
            requestingOrigin: SumiPermissionOrigin.invalid(reason: "malformed"),
            topOrigin: SumiPermissionOrigin(string: "https://example.com"),
            policyProvider: allowProvider,
            systemStates: [.camera: .authorized]
        )
        XCTAssertFalse(invalidOrigin.isAllowedToProceed)
        XCTAssertEqual(invalidOrigin.source, .invalidOrigin)

        let missingEntitlement = await evaluate(
            .camera,
            policyProvider: allowProvider,
            systemStates: [.camera: .missingEntitlement]
        )
        XCTAssertFalse(missingEntitlement.isAllowedToProceed)
        XCTAssertEqual(missingEntitlement.source, .system)
        XCTAssertEqual(missingEntitlement.systemAuthorizationSnapshot?.state, .missingEntitlement)
    }

    private func evaluate(
        _ permissionType: SumiPermissionType,
        requestingOrigin: SumiPermissionOrigin = SumiPermissionOrigin(string: "https://example.com"),
        topOrigin: SumiPermissionOrigin? = nil,
        displayDomain: String? = nil,
        committedURL: URL? = URL(string: "https://example.com"),
        visibleURL: URL? = URL(string: "https://example.com"),
        surface: SumiPermissionSecurityContext.Surface = .normalTab,
        hasUserGesture: Bool = true,
        hasUserGestureOverride: Bool? = nil,
        usesUnknownUserGesture: Bool = false,
        isEphemeralProfile: Bool = false,
        policyProvider: any SumiPermissionPolicyProvider = NoOpSumiPermissionPolicyProvider(),
        systemStates: [SumiSystemPermissionKind: SumiSystemPermissionAuthorizationState] = [.camera: .authorized, .microphone: .authorized, .geolocation: .authorized, .notifications: .authorized],
        systemPermissionService: (any SumiSystemPermissionService)? = nil
    ) async -> SumiPermissionPolicyResult {
        await evaluate(
            permissionTypes: [permissionType],
            requestingOrigin: requestingOrigin,
            topOrigin: topOrigin,
            displayDomain: displayDomain,
            committedURL: committedURL,
            visibleURL: visibleURL,
            surface: surface,
            hasUserGesture: hasUserGesture,
            hasUserGestureOverride: hasUserGestureOverride,
            usesUnknownUserGesture: usesUnknownUserGesture,
            isEphemeralProfile: isEphemeralProfile,
            policyProvider: policyProvider,
            systemStates: systemStates,
            systemPermissionService: systemPermissionService
        )
    }

    private func evaluate(
        permissionTypes: [SumiPermissionType],
        requestingOrigin: SumiPermissionOrigin = SumiPermissionOrigin(string: "https://example.com"),
        topOrigin: SumiPermissionOrigin? = nil,
        displayDomain: String? = nil,
        committedURL: URL? = URL(string: "https://example.com"),
        visibleURL: URL? = URL(string: "https://example.com"),
        surface: SumiPermissionSecurityContext.Surface = .normalTab,
        hasUserGesture: Bool = true,
        hasUserGestureOverride: Bool? = nil,
        usesUnknownUserGesture: Bool = false,
        isEphemeralProfile: Bool = false,
        policyProvider: any SumiPermissionPolicyProvider = NoOpSumiPermissionPolicyProvider(),
        systemStates: [SumiSystemPermissionKind: SumiSystemPermissionAuthorizationState] = [.camera: .authorized, .microphone: .authorized, .geolocation: .authorized, .notifications: .authorized],
        systemPermissionService: (any SumiSystemPermissionService)? = nil
    ) async -> SumiPermissionPolicyResult {
        let resolvedTopOrigin = topOrigin ?? requestingOrigin
        let request = SumiPermissionRequest(
            tabId: "tab-a",
            pageId: "page-a",
            requestingOrigin: requestingOrigin,
            topOrigin: resolvedTopOrigin,
            displayDomain: displayDomain,
            permissionTypes: permissionTypes,
            hasUserGesture: hasUserGesture,
            requestedAt: date("2026-04-28T08:00:00Z"),
            isEphemeralProfile: isEphemeralProfile,
            profilePartitionId: "profile-a"
        )
        let context = SumiPermissionSecurityContext(
            request: request,
            requestingOrigin: requestingOrigin,
            topOrigin: resolvedTopOrigin,
            committedURL: committedURL,
            visibleURL: visibleURL,
            mainFrameURL: committedURL,
            isMainFrame: true,
            isActiveTab: true,
            isVisibleTab: true,
            hasUserGesture: usesUnknownUserGesture ? nil : (hasUserGestureOverride ?? hasUserGesture),
            isEphemeralProfile: isEphemeralProfile,
            profilePartitionId: "profile-a",
            transientPageId: "page-a",
            surface: surface,
            navigationOrPageGeneration: "generation-a",
            now: date("2026-04-28T08:00:01Z")
        )
        let service = systemPermissionService ?? FakeSumiSystemPermissionService(states: systemStates)
        let resolver = DefaultSumiPermissionPolicyResolver(
            systemPermissionService: service,
            policyProvider: policyProvider
        )
        return await resolver.evaluate(context)
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}

private struct StaticSumiPermissionPolicyProvider: SumiPermissionPolicyProvider {
    let override: SumiPermissionPolicyOverride?

    func override(
        for context: SumiPermissionSecurityContext,
        permissionType: SumiPermissionType
    ) async -> SumiPermissionPolicyOverride? {
        override
    }
}
