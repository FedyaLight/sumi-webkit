import XCTest
@testable import Sumi

@MainActor
final class BrowserSidebarFolderCommandOwnerTests: XCTestCase {
    func testCanCreateFolderRequiresSidebarActionSpace() {
        let windowState = BrowserWindowState()
        let availableSpy = Spy(resolvedSpace: Space(name: "Space"))
        let unavailableSpy = Spy(resolvedSpace: nil)

        XCTAssertTrue(makeOwner(spy: availableSpy).canCreateFolderInCurrentSpace(in: windowState))
        XCTAssertFalse(makeOwner(spy: unavailableSpy).canCreateFolderInCurrentSpace(in: windowState))
        XCTAssertEqual(availableSpy.events, [.spaceForSidebarActions(windowState.id)])
        XCTAssertEqual(unavailableSpy.events, [.spaceForSidebarActions(windowState.id)])
    }

    func testFolderCommandsRouteToDependencies() {
        let spy = Spy(resolvedSpace: nil)
        let owner = makeOwner(spy: spy)
        let windowState = BrowserWindowState()

        owner.createFolderInCurrentSpace(in: windowState)
        owner.createRSSLiveFolderInCurrentSpace(in: windowState)
        owner.createGitHubPullRequestsLiveFolderInCurrentSpace(in: windowState)
        owner.createGitHubIssuesLiveFolderInCurrentSpace(in: windowState)

        XCTAssertEqual(
            spy.events,
            [
                .createFolder(windowState.id),
                .createRSSLiveFolder(windowState.id),
                .createGitHubPullRequestsLiveFolder(windowState.id),
                .createGitHubIssuesLiveFolder(windowState.id),
            ]
        )
    }

    private func makeOwner(spy: Spy) -> BrowserSidebarFolderCommandOwner {
        BrowserSidebarFolderCommandOwner(
            dependencies: BrowserSidebarFolderCommandOwner.Dependencies(
                spaceForSidebarActions: { windowState in
                    spy.events.append(.spaceForSidebarActions(windowState.id))
                    return spy.resolvedSpace
                },
                createFolderInCurrentSpace: { windowState in
                    spy.events.append(.createFolder(windowState.id))
                },
                createRSSLiveFolderInCurrentSpace: { windowState in
                    spy.events.append(.createRSSLiveFolder(windowState.id))
                },
                createGitHubPullRequestsLiveFolderInCurrentSpace: { windowState in
                    spy.events.append(.createGitHubPullRequestsLiveFolder(windowState.id))
                },
                createGitHubIssuesLiveFolderInCurrentSpace: { windowState in
                    spy.events.append(.createGitHubIssuesLiveFolder(windowState.id))
                }
            )
        )
    }
}

private final class Spy {
    let resolvedSpace: Space?
    var events: [BrowserSidebarFolderCommandOwnerTests.Event] = []

    init(resolvedSpace: Space?) {
        self.resolvedSpace = resolvedSpace
    }
}

extension BrowserSidebarFolderCommandOwnerTests {
    enum Event: Equatable {
        case spaceForSidebarActions(UUID)
        case createFolder(UUID)
        case createRSSLiveFolder(UUID)
        case createGitHubPullRequestsLiveFolder(UUID)
        case createGitHubIssuesLiveFolder(UUID)
    }
}
