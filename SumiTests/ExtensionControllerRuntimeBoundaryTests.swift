import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionControllerRuntimeBoundaryTests: XCTestCase {
    func testExistingControllerQueryCannotProvisionMissingController() {
        let profileID = UUID()
        let tab = makeTab(id: UUID(), profileID: profileID)
        let profileRuntime = ExtensionProfileRuntime(initialProfileId: profileID)
        let profiles = ControllerRuntimeProfileQuery(profileID: profileID)
        let tabs = ControllerRuntimeTabQuery(canonical: tab)
        let query = ExtensionExistingExactTabControllerQuery(
            tabs: tabs,
            profileRuntime: profileRuntime,
            profiles: profiles
        )

        XCTAssertNil(query.existingController(for: tab))
        XCTAssertTrue(profileRuntime.controllersByProfile.isEmpty)
    }

    func testExistingExactControllerQueryAllowsCanonicalAndRejectsSameIDReplacement() {
        let profileID = UUID()
        let tabID = UUID()
        let canonical = makeTab(id: tabID, profileID: profileID)
        let replacement = makeTab(id: tabID, profileID: profileID)
        let tabs = ControllerRuntimeTabQuery(canonical: canonical)
        let profileRuntime = ExtensionProfileRuntime(initialProfileId: profileID)
        let controller = makeController()
        profileRuntime.setController(controller, for: profileID)
        let profiles = ControllerRuntimeProfileQuery(profileID: profileID)
        let query = ExtensionExistingExactTabControllerQuery(
            tabs: tabs,
            profileRuntime: profileRuntime,
            profiles: profiles
        )

        XCTAssertIdentical(query.existingController(for: canonical), controller)
        XCTAssertNil(query.existingController(for: replacement))
        withExtendedLifetime(profiles) {}
    }

    func testExistingExactControllerQueryAllowsCanonicalEphemeralAuxiliaryTab() {
        let profile = Profile.createEphemeral()
        let browserManager = makeSafariExtensionTestBrowserManager(
            profile: profile
        )
        let tab = browserManager.tabFactory.makeTab(
            id: UUID(),
            url: URL(string: "about:blank")!,
            name: "Auxiliary controller query"
        )
        tab.profileId = profile.id
        tab.attachBrowserRuntime(
            TabBrowserRuntimeFactory.make(for: browserManager)
        )
        let tabs = ControllerRuntimeTabQuery(
            canonical: tab,
            isAuxiliary: true
        )
        let profileRuntime = ExtensionProfileRuntime(
            initialProfileId: profile.id
        )
        let controller = makeController()
        profileRuntime.setController(controller, for: profile.id)
        let profiles = ControllerRuntimeProfileQuery(profileID: profile.id)
        let query = ExtensionExistingExactTabControllerQuery(
            tabs: tabs,
            profileRuntime: profileRuntime,
            profiles: profiles
        )

        XCTAssertTrue(tab.isEphemeral)
        XCTAssertTrue(tabs.isAuxiliaryMiniWindowTab(tab))
        XCTAssertIdentical(query.existingController(for: tab), controller)
        withExtendedLifetime((browserManager, profiles)) {}
    }

    func testExistingExactControllerQueryRejectsStaleSameIDEphemeralTab() {
        let profile = Profile.createEphemeral()
        let browserManager = makeSafariExtensionTestBrowserManager(
            profile: profile
        )
        let tabID = UUID()
        let canonical = browserManager.tabFactory.makeTab(
            id: tabID,
            url: URL(string: "about:blank")!,
            name: "Canonical auxiliary controller query"
        )
        let stale = browserManager.tabFactory.makeTab(
            id: tabID,
            url: URL(string: "about:blank")!,
            name: "Stale auxiliary controller query"
        )
        canonical.profileId = profile.id
        stale.profileId = profile.id
        canonical.attachBrowserRuntime(
            TabBrowserRuntimeFactory.make(for: browserManager)
        )
        stale.attachBrowserRuntime(
            TabBrowserRuntimeFactory.make(for: browserManager)
        )
        let profileRuntime = ExtensionProfileRuntime(
            initialProfileId: profile.id
        )
        let controller = makeController()
        profileRuntime.setController(controller, for: profile.id)
        let profiles = ControllerRuntimeProfileQuery(profileID: profile.id)
        let tabs = ControllerRuntimeTabQuery(
            canonical: canonical,
            isAuxiliary: true
        )
        let query = ExtensionExistingExactTabControllerQuery(
            tabs: tabs,
            profileRuntime: profileRuntime,
            profiles: profiles
        )

        XCTAssertTrue(canonical.isEphemeral)
        XCTAssertTrue(stale.isEphemeral)
        XCTAssertIdentical(
            query.existingController(for: canonical),
            controller
        )
        XCTAssertNil(query.existingController(for: stale))
        withExtendedLifetime((browserManager, profiles, tabs)) {}
    }

    func testExactWebViewQueryRejectsStaleSameUUIDBeforeConsultingResidence() {
        let tabID = UUID()
        let canonical = makeTab(id: tabID, profileID: UUID())
        let stale = makeTab(id: tabID, profileID: canonical.profileId!)
        let webView = FocusableWKWebView()
        webView.owningTab = canonical
        let tabs = ControllerRuntimeTabQuery(canonical: canonical)
        let residence = ControllerRuntimeWebViewResidence(webView: webView)
        let query = ExtensionExactTabWebViewQuery(
            tabs: tabs,
            residences: residence,
            selected: residence
        )

        XCTAssertNil(query.liveWebView(for: stale))
        XCTAssertNil(query.untrackedWebView(for: stale))
        XCTAssertTrue(query.currentLiveWebViews(for: stale).isEmpty)
        XCTAssertEqual(residence.liveLookupCount, 0)
        XCTAssertEqual(residence.untrackedLookupCount, 0)
        XCTAssertEqual(residence.inventoryLookupCount, 0)
    }

    func testExactWebViewQueryRejectsForeignPhysicalOwnership() {
        let canonical = makeTab(id: UUID(), profileID: UUID())
        let foreign = makeTab(id: UUID(), profileID: canonical.profileId!)
        let webView = FocusableWKWebView()
        webView.owningTab = foreign
        let tabs = ControllerRuntimeTabQuery(canonical: canonical)
        let residence = ControllerRuntimeWebViewResidence(webView: webView)
        let query = ExtensionExactTabWebViewQuery(
            tabs: tabs,
            residences: residence,
            selected: residence
        )

        XCTAssertNil(query.liveWebView(for: canonical))
        XCTAssertNil(query.untrackedWebView(for: canonical))
        XCTAssertTrue(query.currentLiveWebViews(for: canonical).isEmpty)
    }

    func testExactWebViewQueryRejectsResidenceRemovedDuringResolution() {
        let canonical = makeTab(id: UUID(), profileID: UUID())
        let webView = FocusableWKWebView()
        webView.owningTab = canonical
        let tabs = ControllerRuntimeTabQuery(canonical: canonical)

        let selected = RemovingControllerRuntimeWebViewResidence(
            webView: webView
        )
        XCTAssertNil(
            ExtensionExactTabWebViewQuery(
                tabs: tabs,
                residences: selected,
                selected: selected
            ).liveWebView(for: canonical)
        )

        let untracked = RemovingControllerRuntimeWebViewResidence(
            webView: webView
        )
        XCTAssertNil(
            ExtensionExactTabWebViewQuery(
                tabs: tabs,
                residences: untracked,
                selected: untracked
            ).untrackedWebView(for: canonical)
        )

        let inventory = RemovingControllerRuntimeWebViewResidence(
            webView: webView
        )
        XCTAssertTrue(
            ExtensionExactTabWebViewQuery(
                tabs: tabs,
                residences: inventory,
                selected: inventory
            ).currentLiveWebViews(for: canonical).isEmpty
        )
    }

    func testControllerAdmissionRejectsStaleSameUUID() {
        let profileID = UUID()
        let tabID = UUID()
        let canonical = makeTab(id: tabID, profileID: profileID)
        let stale = makeTab(id: tabID, profileID: profileID)
        let tabs = ControllerRuntimeTabQuery(canonical: canonical)
        let profiles = ControllerRuntimeProfileQuery(profileID: profileID)
        let profileRuntime = ExtensionProfileRuntime(initialProfileId: profileID)
        let controller = makeController()
        profileRuntime.setController(controller, for: profileID)
        let webView = FocusableWKWebView()
        webView.owningTab = stale
        let residence = ControllerRuntimeWebViewResidence(webView: webView)
        let exactWebViews = ExtensionExactTabWebViewQuery(
            tabs: tabs,
            residences: residence,
            selected: residence
        )
        let admission = makeAdmission(
            tabs: tabs,
            profiles: profiles,
            profileRuntime: profileRuntime,
            webViews: exactWebViews
        )

        XCTAssertEqual(
            admission.admit(
                controller,
                profileID: profileID,
                to: webView,
                for: stale
            ),
            .rejected
        )
        XCTAssertNil(webView.configuration.webExtensionController)
    }

    func testControllerAdmissionRequiresExactOwningTab() {
        let profileID = UUID()
        let canonical = makeTab(id: UUID(), profileID: profileID)
        let foreign = makeTab(id: UUID(), profileID: profileID)
        let tabs = ControllerRuntimeTabQuery(canonical: canonical)
        let profiles = ControllerRuntimeProfileQuery(profileID: profileID)
        let profileRuntime = ExtensionProfileRuntime(initialProfileId: profileID)
        let controller = makeController()
        profileRuntime.setController(controller, for: profileID)
        let webView = FocusableWKWebView()
        webView.owningTab = foreign
        let residence = ControllerRuntimeWebViewResidence(webView: webView)
        let exactWebViews = ExtensionExactTabWebViewQuery(
            tabs: tabs,
            residences: residence,
            selected: residence
        )
        let admission = makeAdmission(
            tabs: tabs,
            profiles: profiles,
            profileRuntime: profileRuntime,
            webViews: exactWebViews
        )

        XCTAssertEqual(
            admission.admit(
                controller,
                profileID: profileID,
                to: webView,
                for: canonical
            ),
            .rejected
        )
        XCTAssertNil(webView.configuration.webExtensionController)
    }

    func testControllerAdmissionAcceptsOnlyRegisteredController() {
        let profileID = UUID()
        let canonical = makeTab(id: UUID(), profileID: profileID)
        let tabs = ControllerRuntimeTabQuery(canonical: canonical)
        let profiles = ControllerRuntimeProfileQuery(profileID: profileID)
        let profileRuntime = ExtensionProfileRuntime(initialProfileId: profileID)
        let controller = makeController()
        profileRuntime.setController(controller, for: profileID)
        let configuration = WKWebViewConfiguration()
        configuration.webExtensionController = controller
        let webView = FocusableWKWebView(
            frame: .zero,
            configuration: configuration
        )
        webView.owningTab = canonical
        let residence = ControllerRuntimeWebViewResidence(webView: webView)
        let exactWebViews = ExtensionExactTabWebViewQuery(
            tabs: tabs,
            residences: residence,
            selected: residence
        )
        let admission = makeAdmission(
            tabs: tabs,
            profiles: profiles,
            profileRuntime: profileRuntime,
            webViews: exactWebViews
        )

        XCTAssertEqual(
            admission.admit(
                controller,
                profileID: profileID,
                to: webView,
                for: canonical
            ),
            .alreadyBound
        )
        XCTAssertIdentical(
            webView.configuration.webExtensionController,
            controller
        )
        XCTAssertEqual(profileRuntime.controllersByProfile.count, 1)
    }

    func testControllerAdmissionRequiresRebuildWhenControllerWasMissingAtCreation() {
        let profileID = UUID()
        let canonical = makeTab(id: UUID(), profileID: profileID)
        let tabs = ControllerRuntimeTabQuery(canonical: canonical)
        let profiles = ControllerRuntimeProfileQuery(profileID: profileID)
        let profileRuntime = ExtensionProfileRuntime(initialProfileId: profileID)
        let controller = makeController()
        profileRuntime.setController(controller, for: profileID)
        let webView = FocusableWKWebView()
        webView.owningTab = canonical
        let residence = ControllerRuntimeWebViewResidence(webView: webView)
        let exactWebViews = ExtensionExactTabWebViewQuery(
            tabs: tabs,
            residences: residence,
            selected: residence
        )
        let admission = makeAdmission(
            tabs: tabs,
            profiles: profiles,
            profileRuntime: profileRuntime,
            webViews: exactWebViews
        )

        XCTAssertEqual(
            admission.admit(
                controller,
                profileID: profileID,
                to: webView,
                for: canonical
            ),
            .requiresRebuild
        )
        XCTAssertNil(webView.configuration.webExtensionController)
    }

    func testMismatchQueryRejectsStaleAndForeignResidence() {
        let profileID = UUID()
        let tabID = UUID()
        let canonical = makeTab(id: tabID, profileID: profileID)
        let stale = makeTab(id: tabID, profileID: profileID)
        let foreign = makeTab(id: UUID(), profileID: profileID)
        let tabs = ControllerRuntimeTabQuery(canonical: canonical)
        let profiles = ControllerRuntimeProfileQuery(profileID: profileID)
        let profileRuntime = ExtensionProfileRuntime(initialProfileId: profileID)
        let query = ExtensionWebViewControllerMismatchQuery(
            tabs: tabs,
            profiles: profiles,
            profileRuntime: profileRuntime
        )
        let webView = FocusableWKWebView()
        webView.owningTab = canonical

        XCTAssertFalse(
            query.webViewNeedsExtensionRuntimeRebuild(webView, for: stale)
        )
        webView.owningTab = foreign
        XCTAssertFalse(
            query.webViewNeedsExtensionRuntimeRebuild(webView, for: canonical)
        )
    }

    func testRuntimeRepairCannotRebuildAfterSameUUIDReplacement() {
        let profileID = UUID()
        let tabID = UUID()
        let canonical = makeTab(id: tabID, profileID: profileID)
        let replacement = makeTab(id: tabID, profileID: profileID)
        let tabs = ControllerRuntimeTabQuery(canonical: canonical)
        let profiles = ControllerRuntimeProfileQuery(profileID: profileID)
        let profileRuntime = ExtensionProfileRuntime(initialProfileId: profileID)
        profileRuntime.setController(makeController(), for: profileID)
        let webView = FocusableWKWebView()
        webView.owningTab = canonical
        let residence = ControllerRuntimeWebViewResidence(webView: webView)
        let exactWebViews = ExtensionExactTabWebViewQuery(
            tabs: tabs,
            residences: residence,
            selected: residence
        )
        let admission = ReplacingControllerAdmission {
            tabs.canonical = replacement
        }
        let mismatch = ControllerRuntimeMismatchQuery(result: false)
        let rebuilder = ControllerRuntimeRebuilder()
        let runtimeLoadStatus = ExtensionRuntimeLoadStatusAuthority()
        let repair = ExtensionTabWebViewRuntimeRepair(
            runtimeLoadStatus: runtimeLoadStatus,
            tabs: tabs,
            profiles: profiles,
            profileRuntime: profileRuntime,
            webViews: exactWebViews,
            admission: admission,
            mismatch: mismatch,
            rebuilder: rebuilder,
            diagnostics: ExtensionRuntimeDiagnostics()
        )

        repair.repair(
            canonical,
            reason: #function,
            publicationStage: .loadFinalization
        )

        XCTAssertIdentical(tabs.canonical, replacement)
        XCTAssertEqual(admission.callCount, 1)
        XCTAssertEqual(rebuilder.callCount, 0)
        withExtendedLifetime(runtimeLoadStatus) {}
    }

    func testRuntimeRepairPreservesCommittedSubmissionOutcome() {
        assertRepairInvalidatesPublication(for: .committed)
    }

    func testRuntimeRepairPreservesDeferredSubmissionOutcome() {
        assertRepairInvalidatesPublication(for: .deferred)
    }

    func testRuntimeRepairPreservesNoLiveWindowsSubmissionOutcome() {
        assertRepairInvalidatesPublication(for: .noLiveWindows)
    }

    func testRuntimeRepairPreservesFailedSubmissionOutcome() {
        assertRepairInvalidatesPublication(for: .failed)
    }

    func testRuntimeRepairDoesNotClearSameIDReplacementAfterSubmission() {
        let profileID = UUID()
        let tabID = UUID()
        let canonical = makeTab(id: tabID, profileID: profileID)
        let replacement = makeTab(id: tabID, profileID: profileID)
        let tabPublicationRevisions =
            ExtensionTabPublicationRevisionAuthority()
        let runtimeLoadStatus = ExtensionRuntimeLoadStatusAuthority()
        runtimeLoadStatus.markExtensionsLoaded()
        establishSettledOpen(
            on: replacement,
            generation: tabPublicationRevisions.issue()
        )
        let tabs = ControllerRuntimeTabQuery(canonical: canonical)
        let profiles = ControllerRuntimeProfileQuery(profileID: profileID)
        let profileRuntime = ExtensionProfileRuntime(initialProfileId: profileID)
        let controller = makeController()
        profileRuntime.setController(controller, for: profileID)
        let webView = FocusableWKWebView()
        webView.owningTab = canonical
        let residence = ControllerRuntimeWebViewResidence(webView: webView)
        let exactWebViews = ExtensionExactTabWebViewQuery(
            tabs: tabs,
            residences: residence,
            selected: residence
        )
        let rebuilder = ControllerRuntimeRebuilder(
            outcome: .deferred,
            onSubmit: { tabs.canonical = replacement }
        )
        let admission = makeAdmission(
            tabs: tabs,
            profiles: profiles,
            profileRuntime: profileRuntime,
            webViews: exactWebViews
        )
        let mismatch = ControllerRuntimeMismatchQuery(result: true)
        let repair = ExtensionTabWebViewRuntimeRepair(
            runtimeLoadStatus: runtimeLoadStatus,
            tabs: tabs,
            profiles: profiles,
            profileRuntime: profileRuntime,
            webViews: exactWebViews,
            admission: admission,
            mismatch: mismatch,
            rebuilder: rebuilder,
            diagnostics: ExtensionRuntimeDiagnostics()
        )

        XCTAssertEqual(
            repair.repair(
                canonical,
                reason: #function
            ),
            .notApplicable
        )
        XCTAssertIdentical(tabs.canonical, replacement)
        XCTAssertEqual(rebuilder.callCount, 1)
        XCTAssertEqual(
            replacement.extensionPageRuntimeOwner
                .currentOpenNotificationGeneration(),
            tabPublicationRevisions.issue()
        )
        withExtendedLifetime((admission, mismatch, runtimeLoadStatus)) {}
    }

    func testRuntimeRepairPreservesReentrantNewerOpenOnSameTab() {
        let profileID = UUID()
        let tab = makeTab(id: UUID(), profileID: profileID)
        let tabPublicationRevisions =
            ExtensionTabPublicationRevisionAuthority()
        let runtimeLoadStatus = ExtensionRuntimeLoadStatusAuthority()
        runtimeLoadStatus.markExtensionsLoaded()
        establishSettledOpen(
            on: tab,
            generation: tabPublicationRevisions.issue()
        )
        let tabs = ControllerRuntimeTabQuery(canonical: tab)
        let profiles = ControllerRuntimeProfileQuery(profileID: profileID)
        let profileRuntime = ExtensionProfileRuntime(initialProfileId: profileID)
        let controller = makeController()
        profileRuntime.setController(controller, for: profileID)
        let webView = FocusableWKWebView()
        webView.owningTab = tab
        let residence = ControllerRuntimeWebViewResidence(webView: webView)
        let exactWebViews = ExtensionExactTabWebViewQuery(
            tabs: tabs,
            residences: residence,
            selected: residence
        )
        let rebuilder = ControllerRuntimeRebuilder(
            outcome: .deferred,
            onSubmit: {
                let generation = tabPublicationRevisions.advance(
                    ifCurrent: tabPublicationRevisions.issue()
                )!
                self.establishSettledOpen(on: tab, generation: generation)
            }
        )
        let admission = makeAdmission(
            tabs: tabs,
            profiles: profiles,
            profileRuntime: profileRuntime,
            webViews: exactWebViews
        )
        let mismatch = ControllerRuntimeMismatchQuery(result: true)
        let repair = ExtensionTabWebViewRuntimeRepair(
            runtimeLoadStatus: runtimeLoadStatus,
            tabs: tabs,
            profiles: profiles,
            profileRuntime: profileRuntime,
            webViews: exactWebViews,
            admission: admission,
            mismatch: mismatch,
            rebuilder: rebuilder,
            diagnostics: ExtensionRuntimeDiagnostics()
        )

        XCTAssertEqual(
            repair.repair(tab, reason: #function),
            .publicationSuperseded(.deferred)
        )
        XCTAssertEqual(rebuilder.callCount, 1)
        XCTAssertEqual(
            tab.extensionPageRuntimeOwner.currentOpenNotificationGeneration(),
            tabPublicationRevisions.issue()
        )
        XCTAssertTrue(
            tab.extensionPageRuntimeOwner
                .hasSettledDidOpenTabNotification(
                    for: tabPublicationRevisions.issue()
                )
        )
        withExtendedLifetime((admission, mismatch)) {}
    }

    func testRuntimeRepairPreservesReentrantWindowPrepublicationOnSameTab()
        throws {
        let profileID = UUID()
        let tab = makeTab(id: UUID(), profileID: profileID)
        let tabPublicationRevisions =
            ExtensionTabPublicationRevisionAuthority()
        let runtimeLoadStatus = ExtensionRuntimeLoadStatusAuthority()
        runtimeLoadStatus.markExtensionsLoaded()
        let tabs = ControllerRuntimeTabQuery(canonical: tab)
        let profiles = ControllerRuntimeProfileQuery(profileID: profileID)
        let profileRuntime = ExtensionProfileRuntime(initialProfileId: profileID)
        let controller = makeController()
        profileRuntime.setController(controller, for: profileID)
        let webView = FocusableWKWebView()
        webView.owningTab = tab
        let residence = ControllerRuntimeWebViewResidence(webView: webView)
        let exactWebViews = ExtensionExactTabWebViewQuery(
            tabs: tabs,
            residences: residence,
            selected: residence
        )
        var newerPreparation: TabExtensionPrepublicationToken?
        let rebuilder = ControllerRuntimeRebuilder(
            outcome: .deferred,
            onSubmit: {
                let generation = tabPublicationRevisions.advance(
                    ifCurrent: tabPublicationRevisions.issue()
                )!
                newerPreparation = tab.extensionPageRuntimeOwner
                    .prepareForWindowPrepublication(
                        generation: generation
                    )
            }
        )
        let admission = makeAdmission(
            tabs: tabs,
            profiles: profiles,
            profileRuntime: profileRuntime,
            webViews: exactWebViews
        )
        let mismatch = ControllerRuntimeMismatchQuery(result: true)
        let repair = ExtensionTabWebViewRuntimeRepair(
            runtimeLoadStatus: runtimeLoadStatus,
            tabs: tabs,
            profiles: profiles,
            profileRuntime: profileRuntime,
            webViews: exactWebViews,
            admission: admission,
            mismatch: mismatch,
            rebuilder: rebuilder,
            diagnostics: ExtensionRuntimeDiagnostics()
        )

        XCTAssertEqual(
            repair.repair(tab, reason: #function),
            .publicationSuperseded(.deferred)
        )
        let preparation = try XCTUnwrap(newerPreparation)
        XCTAssertTrue(
            tab.extensionPageRuntimeOwner.canCommitWindowPrepublication(
                preparation
            )
        )
        XCTAssertEqual(rebuilder.callCount, 1)
        withExtendedLifetime((admission, mismatch)) {}
    }

    func testLivePreparationSubmitsOneRepairThroughBoundRegistration() {
        let profileID = UUID()
        let tab = makeTab(id: UUID(), profileID: profileID)
        let tabs = ControllerRuntimeTabQuery(canonical: tab)
        let profileRuntime = ExtensionProfileRuntime(initialProfileId: profileID)
        profileRuntime.setController(makeController(), for: profileID)
        let profiles = ControllerRuntimeProfileQuery(profileID: profileID)
        let controllers = ExtensionExistingExactTabControllerQuery(
            tabs: tabs,
            profileRuntime: profileRuntime,
            profiles: profiles
        )
        let repair = ControllerRuntimeRepairCounter()
        let tabPublicationRevisions =
            ExtensionTabPublicationRevisionAuthority()
        let runtimeLoadStatus = ExtensionRuntimeLoadStatusAuthority()
        runtimeLoadStatus.markExtensionsLoaded()
        let preparedTabs = NeverPreparedControllerRuntimeTabQuery()
        let opening = RejectingControllerRuntimeOpening()
        let registration = ExtensionNormalTabRegistration(
            tabPublicationRevisions: tabPublicationRevisions,
            runtimeLoadStatus: runtimeLoadStatus,
            tabs: tabs,
            preparedTabs: preparedTabs,
            controllers: repair,
            opening: opening,
            diagnostics: ExtensionRuntimeDiagnostics()
        )
        let admission = AlwaysRebuildControllerAdmission()
        let preparation = ExtensionLiveWebViewRuntimePreparation(
            profiles: profiles,
            controllers: controllers,
            admission: admission,
            tabRegistration: registration,
            diagnostics: ExtensionRuntimeDiagnostics()
        )
        let webView = FocusableWKWebView()
        webView.owningTab = tab

        preparation.prepareWebViewForExtensionRuntime(
            webView,
            currentURL: tab.url,
            reason: #function
        )

        XCTAssertEqual(repair.callCount, 1)
        withExtendedLifetime((preparedTabs, opening, admission)) {}
    }

    func testControllerRuntimeLeavesDoNotRetainAuthorities() {
        let profileID = UUID()
        var tabs: ControllerRuntimeTabQuery? = ControllerRuntimeTabQuery(
            canonical: makeTab(id: UUID(), profileID: profileID)
        )
        var profiles: ControllerRuntimeProfileQuery? =
            ControllerRuntimeProfileQuery(profileID: profileID)
        var profileRuntime: ExtensionProfileRuntime? =
            ExtensionProfileRuntime(initialProfileId: profileID)
        var residence: ControllerRuntimeWebViewResidence? =
            ControllerRuntimeWebViewResidence(webView: FocusableWKWebView())
        let exact = ExtensionExactTabWebViewQuery(
            tabs: tabs!,
            residences: residence!,
            selected: residence!
        )
        let admission = makeAdmission(
            tabs: tabs!,
            profiles: profiles!,
            profileRuntime: profileRuntime!,
            webViews: exact
        )
        let mismatch = ExtensionWebViewControllerMismatchQuery(
            tabs: tabs!,
            profiles: profiles!,
            profileRuntime: profileRuntime!
        )
        weak let releasedTabs = tabs
        weak let releasedProfiles = profiles
        weak let releasedProfileRuntime = profileRuntime
        weak let releasedResidence = residence

        tabs = nil
        profiles = nil
        profileRuntime = nil
        residence = nil

        XCTAssertNil(releasedTabs)
        XCTAssertNil(releasedProfiles)
        XCTAssertNil(releasedProfileRuntime)
        XCTAssertNil(releasedResidence)
        withExtendedLifetime((exact, admission, mismatch)) {}
    }

    func testRetainedControllerCompositionDoesNotRetainRuntimeAuthorities() {
        let profileID = UUID()
        var tabs: ControllerRuntimeTabQuery? = ControllerRuntimeTabQuery(
            canonical: makeTab(id: UUID(), profileID: profileID)
        )
        var profileRuntime: ExtensionProfileRuntime? =
            ExtensionProfileRuntime(initialProfileId: profileID)
        var runtimeLoadStatus: ExtensionRuntimeLoadStatusAuthority? =
            ExtensionRuntimeLoadStatusAuthority()
        var contexts: ExtensionContextPublicationQuery? =
            ExtensionContextPublicationQuery(profileRuntime: profileRuntime!)
        var residence: ControllerRuntimeWebViewResidence? =
            ControllerRuntimeWebViewResidence(webView: FocusableWKWebView())
        var rebuilder: ControllerRuntimeRebuilder? = ControllerRuntimeRebuilder()
        var preludeInstaller:
            ExtensionPermissionsOriginsCompatibilityPreludeInstallationOwner? =
            ExtensionPermissionsOriginsCompatibilityPreludeInstallationOwner(
                isPrivateUserScriptSPIAvailable: { false },
                preludeTargets: { _ in [] },
                trace: { _ in }
            )
        let composition = ExtensionControllerRuntimeAssembler.assemble(
            tabs: tabs!,
            inventory: tabs!,
            selectedWebViews: residence!,
            residences: residence!,
            rebuilder: rebuilder!,
            windowProfiles: nil,
            runtimeLoadStatus: runtimeLoadStatus!,
            profileRuntime: profileRuntime!,
            contexts: contexts!,
            preludeInstaller: preludeInstaller!,
            diagnostics: ExtensionRuntimeDiagnostics()
        )
        weak let releasedTabs = tabs
        weak let releasedProfileRuntime = profileRuntime
        weak let releasedRuntimeLoadStatus = runtimeLoadStatus
        weak let releasedContexts = contexts
        weak let releasedResidence = residence
        weak let releasedRebuilder = rebuilder
        weak let releasedPreludeInstaller = preludeInstaller

        tabs = nil
        profileRuntime = nil
        runtimeLoadStatus = nil
        contexts = nil
        residence = nil
        rebuilder = nil
        preludeInstaller = nil

        XCTAssertNil(releasedTabs)
        XCTAssertNil(releasedProfileRuntime)
        XCTAssertNil(releasedRuntimeLoadStatus)
        XCTAssertNil(releasedContexts)
        XCTAssertNil(releasedResidence)
        XCTAssertNil(releasedRebuilder)
        XCTAssertNil(releasedPreludeInstaller)
        withExtendedLifetime(composition) {}
    }

    private func makeTab(id: UUID, profileID: UUID) -> Tab {
        let tab = Tab(
            id: id,
            url: URL(string: "about:blank")!,
            name: "Controller runtime boundary"
        )
        tab.profileId = profileID
        return tab
    }

    private func makeController() -> WKWebExtensionController {
        WKWebExtensionController(
            configuration: .init(identifier: UUID())
        )
    }

    private func makeAdmission(
        tabs: any ExtensionTabQuery,
        profiles: any ExtensionTabProfileResolving,
        profileRuntime: ExtensionProfileRuntime,
        webViews: ExtensionExactTabWebViewQuery
    ) -> ExtensionWebViewControllerAdmission {
        ExtensionWebViewControllerAdmission(
            tabs: tabs,
            profiles: profiles,
            profileRuntime: profileRuntime,
            webViews: webViews,
            preludeInstaller:
                ExtensionPermissionsOriginsCompatibilityPreludeInstallationOwner(
                    isPrivateUserScriptSPIAvailable: { false },
                    preludeTargets: { _ in [] },
                    trace: { _ in }
                )
        )
    }

    private func assertRepairInvalidatesPublication(
        for submission: ExtensionTabWebViewRebuildSubmissionOutcome,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let profileID = UUID()
        let tab = makeTab(id: UUID(), profileID: profileID)
        let tabPublicationRevisions =
            ExtensionTabPublicationRevisionAuthority()
        let runtimeLoadStatus = ExtensionRuntimeLoadStatusAuthority()
        runtimeLoadStatus.markExtensionsLoaded()
        establishSettledOpen(
            on: tab,
            generation: tabPublicationRevisions.issue(),
            file: file,
            line: line
        )
        let tabs = ControllerRuntimeTabQuery(canonical: tab)
        let profiles = ControllerRuntimeProfileQuery(profileID: profileID)
        let profileRuntime = ExtensionProfileRuntime(initialProfileId: profileID)
        let controller = makeController()
        profileRuntime.setController(controller, for: profileID)
        let webView = FocusableWKWebView()
        webView.owningTab = tab
        let residence = ControllerRuntimeWebViewResidence(webView: webView)
        let exactWebViews = ExtensionExactTabWebViewQuery(
            tabs: tabs,
            residences: residence,
            selected: residence
        )
        let rebuilder = ControllerRuntimeRebuilder(outcome: submission)
        let admission = makeAdmission(
            tabs: tabs,
            profiles: profiles,
            profileRuntime: profileRuntime,
            webViews: exactWebViews
        )
        let mismatch = ControllerRuntimeMismatchQuery(result: true)
        let repair = ExtensionTabWebViewRuntimeRepair(
            runtimeLoadStatus: runtimeLoadStatus,
            tabs: tabs,
            profiles: profiles,
            profileRuntime: profileRuntime,
            webViews: exactWebViews,
            admission: admission,
            mismatch: mismatch,
            rebuilder: rebuilder,
            diagnostics: ExtensionRuntimeDiagnostics()
        )

        XCTAssertEqual(
            repair.repair(
                tab,
                reason: #function
            ),
            .publicationInvalidated(submission),
            file: file,
            line: line
        )
        withExtendedLifetime((admission, mismatch, runtimeLoadStatus)) {}
        XCTAssertEqual(rebuilder.callCount, 1, file: file, line: line)
        XCTAssertEqual(
            tab.extensionPageRuntimeOwner.currentOpenNotificationGeneration(),
            nil,
            file: file,
            line: line
        )
    }

    private func establishSettledOpen(
        on tab: Tab,
        generation: ExtensionTabPublicationRevision,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let owner = tab.extensionPageRuntimeOwner
        owner.prepareGeneration(generation)
        owner.markEligible(for: generation)
        guard let claim = owner.reserveDidOpenTab(generation: generation)
        else {
            XCTFail("failed to reserve didOpen claim", file: file, line: line)
            return
        }
        XCTAssertTrue(
            owner.settleDidOpenTabNotification(
                claim,
                generation: generation
            ),
            file: file,
            line: line
        )
        XCTAssertEqual(
            owner.currentOpenNotificationGeneration(),
            generation,
            file: file,
            line: line
        )
    }
}

@available(macOS 15.5, *)
@MainActor
private final class ControllerRuntimeTabQuery:
    ExtensionTabQuery,
    ExtensionTabInventory {
    var canonical: Tab?
    private let isAuxiliary: Bool

    init(canonical: Tab?, isAuxiliary: Bool = false) {
        self.canonical = canonical
        self.isAuxiliary = isAuxiliary
    }

    var allExtensionTabs: [Tab] {
        canonical.map { [$0] } ?? []
    }

    func extensionTab(for tabId: UUID) -> Tab? {
        canonical?.id == tabId ? canonical : nil
    }

    func isTransientExtensionTab(_: Tab) -> Bool { false }
    func isAuxiliaryMiniWindowTab(_ tab: Tab) -> Bool {
        isAuxiliary && canonical === tab
    }
    func isPinnedExtensionTab(_: Tab) -> Bool { false }
}

@available(macOS 15.5, *)
@MainActor
private final class ControllerRuntimeProfileQuery:
    ExtensionTabProfileResolving {
    let profileID: UUID

    init(profileID: UUID) {
        self.profileID = profileID
    }

    func profileID(for _: Tab) -> UUID? { profileID }
}

@available(macOS 15.5, *)
@MainActor
private final class ControllerRuntimeWebViewResidence:
    ExtensionTabWebViewResidenceQuery,
    ExtensionTabLiveWebViewQuery {
    var webView: WKWebView?
    private(set) var liveLookupCount = 0
    private(set) var untrackedLookupCount = 0
    private(set) var inventoryLookupCount = 0

    init(webView: WKWebView?) {
        self.webView = webView
    }

    func extensionLiveWebView(for _: Tab) -> WKWebView? {
        liveLookupCount += 1
        return webView
    }

    func extensionLiveWebViews(for _: Tab) -> [WKWebView] {
        inventoryLookupCount += 1
        return webView.map { [$0] } ?? []
    }

    func extensionUntrackedWebView(for _: Tab) -> WKWebView? {
        untrackedLookupCount += 1
        return webView
    }
}

@available(macOS 15.5, *)
@MainActor
private final class RemovingControllerRuntimeWebViewResidence:
    ExtensionTabWebViewResidenceQuery,
    ExtensionTabLiveWebViewQuery {
    private let webView: WKWebView
    private var selectedReads = 0
    private var untrackedReads = 0
    private var inventoryReads = 0

    init(webView: WKWebView) {
        self.webView = webView
    }

    func extensionLiveWebView(for _: Tab) -> WKWebView? {
        defer { selectedReads += 1 }
        return selectedReads == 0 ? webView : nil
    }

    func extensionLiveWebViews(for _: Tab) -> [WKWebView] {
        defer { inventoryReads += 1 }
        return inventoryReads == 0 ? [webView] : []
    }

    func extensionUntrackedWebView(for _: Tab) -> WKWebView? {
        defer { untrackedReads += 1 }
        return untrackedReads == 0 ? webView : nil
    }
}

@available(macOS 15.5, *)
@MainActor
private final class ReplacingControllerAdmission:
    ExtensionWebViewControllerAdmitting {
    private let replace: () -> Void
    private(set) var callCount = 0

    init(replace: @escaping () -> Void) {
        self.replace = replace
    }

    func admit(
        _: WKWebExtensionController,
        profileID _: UUID,
        to _: WKWebView,
        for _: Tab
    ) -> ExtensionWebViewControllerAdmissionOutcome {
        callCount += 1
        replace()
        return .requiresRebuild
    }
}

@available(macOS 15.5, *)
@MainActor
private final class ControllerRuntimeMismatchQuery:
    ExtensionControllerRuntimeRebuildQuery {
    private let result: Bool

    init(result: Bool) {
        self.result = result
    }

    func webViewNeedsExtensionRuntimeRebuild(
        _: WKWebView,
        for _: Tab
    ) -> Bool {
        result
    }
}

@available(macOS 15.5, *)
@MainActor
private final class ControllerRuntimeRebuilder:
    ExtensionTabWebViewRebuilding {
    private let outcome: ExtensionTabWebViewRebuildSubmissionOutcome
    private let onSubmit: () -> Void
    private(set) var callCount = 0

    init(
        outcome: ExtensionTabWebViewRebuildSubmissionOutcome = .committed,
        onSubmit: @escaping () -> Void = {}
    ) {
        self.outcome = outcome
        self.onSubmit = onSubmit
    }

    func rebuildExtensionLiveWebViews(
        for _: Tab,
        reason _: String
    ) -> ExtensionTabWebViewRebuildSubmissionOutcome {
        callCount += 1
        onSubmit()
        return outcome
    }
}

@available(macOS 15.5, *)
@MainActor
private final class ControllerRuntimeRepairCounter:
    ExtensionTabWebViewRuntimeRepairing,
    ExtensionTabControllerPreparing {
    private(set) var callCount = 0

    func repair(
        _: Tab,
        reason _: String,
        publicationStage _: ExtensionRuntimePublicationStage
    ) -> ExtensionTabWebViewRuntimeRepairOutcome {
        callCount += 1
        return .publicationInvalidated(.deferred)
    }
}

@available(macOS 15.5, *)
@MainActor
private final class AlwaysRebuildControllerAdmission:
    ExtensionWebViewControllerAdmitting {
    func admit(
        _: WKWebExtensionController,
        profileID _: UUID,
        to _: WKWebView,
        for _: Tab
    ) -> ExtensionWebViewControllerAdmissionOutcome {
        .requiresRebuild
    }
}

@available(macOS 15.5, *)
@MainActor
private final class NeverPreparedControllerRuntimeTabQuery:
    ExtensionPreparedTabQuery {
    func containsPreparedTab(_: Tab) -> Bool { false }
}

@available(macOS 15.5, *)
@MainActor
private final class RejectingControllerRuntimeOpening:
    ExtensionNormalTabOpening {
    func publishOpen(_: Tab) -> Bool { false }

    func publishOpen(
        _: Tab,
        during _: ExtensionRuntimePublicationGate.ReloadClaim
    ) -> Bool { false }
}
