import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionPermissionsOriginsCompatibilityPreludeInstallationOwnerTests:
    XCTestCase {
    func testInstallPreludesDeduplicatesPerControllerProfileExtensionAndBaseURL() {
        let profileId = UUID()
        let userContentController = WKUserContentController()
        var installCount = 0
        var traces: [String] = []
        let owner = ExtensionPermissionsOriginsCompatibilityPreludeInstallationOwner(
            dependencies: .init(
                isPrivateUserScriptSPIAvailable: { true },
                preludeTargets: { requestedProfileId in
                    XCTAssertEqual(requestedProfileId, profileId)
                    return [
                        .init(
                            extensionId: "extension-a",
                            isLoaded: true,
                            baseURL: URL(string: "webkit-extension://extension-a")!,
                            installPrelude: { _ in
                                installCount += 1
                                return true
                            }
                        ),
                    ]
                },
                trace: { traces.append($0) }
            )
        )

        owner.installPreludes(into: userContentController, profileId: profileId)
        owner.installPreludes(into: userContentController, profileId: profileId)

        XCTAssertEqual(installCount, 1)
        XCTAssertEqual(traces.count, 1)
    }

    func testClearInstallationsAllowsReinstallingSamePrelude() {
        let profileId = UUID()
        let userContentController = WKUserContentController()
        var installCount = 0
        let owner = ExtensionPermissionsOriginsCompatibilityPreludeInstallationOwner(
            dependencies: .init(
                isPrivateUserScriptSPIAvailable: { true },
                preludeTargets: { _ in
                    [
                        .init(
                            extensionId: "extension-a",
                            isLoaded: true,
                            baseURL: URL(string: "webkit-extension://extension-a")!,
                            installPrelude: { _ in
                                installCount += 1
                                return true
                            }
                        ),
                    ]
                },
                trace: { _ in }
            )
        )

        owner.installPreludes(into: userContentController, profileId: profileId)
        owner.clearInstallations()
        owner.installPreludes(into: userContentController, profileId: profileId)

        XCTAssertEqual(installCount, 2)
    }

    func testInstallPreludesSkipsUnavailableSPIAndUnloadedTargets() {
        let profileId = UUID()
        let userContentController = WKUserContentController()
        var installCount = 0
        let unavailableOwner = ExtensionPermissionsOriginsCompatibilityPreludeInstallationOwner(
            dependencies: .init(
                isPrivateUserScriptSPIAvailable: { false },
                preludeTargets: { _ in
                    [
                        .init(
                            extensionId: "extension-a",
                            isLoaded: true,
                            baseURL: URL(string: "webkit-extension://extension-a")!,
                            installPrelude: { _ in
                                installCount += 1
                                return true
                            }
                        ),
                    ]
                },
                trace: { _ in }
            )
        )
        unavailableOwner.installPreludes(
            into: userContentController,
            profileId: profileId
        )

        let unloadedOwner = ExtensionPermissionsOriginsCompatibilityPreludeInstallationOwner(
            dependencies: .init(
                isPrivateUserScriptSPIAvailable: { true },
                preludeTargets: { _ in
                    [
                        .init(
                            extensionId: "extension-a",
                            isLoaded: false,
                            baseURL: URL(string: "webkit-extension://extension-a")!,
                            installPrelude: { _ in
                                installCount += 1
                                return true
                            }
                        ),
                    ]
                },
                trace: { _ in }
            )
        )
        unloadedOwner.installPreludes(into: userContentController, profileId: profileId)

        XCTAssertEqual(installCount, 0)
    }
}
