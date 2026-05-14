import AppKit
import XCTest

@testable import Sumi

final class SidebarDragPasteboardPayloadTests: XCTestCase {
    func testPayloadRoundTripsThroughPasteboard() throws {
        let spaceId = UUID()
        let profileId = UUID()
        let windowId = UUID()
        let item = SumiDragItem(
            tabId: UUID(),
            title: "Example",
            urlString: "https://example.com"
        )
        let scope = SidebarDragScope(
            windowId: windowId,
            spaceId: spaceId,
            profileId: profileId,
            sourceContainer: .spaceRegular(spaceId),
            sourceItemId: item.tabId,
            sourceItemKind: item.kind
        )

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("SumiPayload-\(UUID().uuidString)"))
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([item.pasteboardItem(scope: scope)]))

        let payload = try XCTUnwrap(SidebarDragPasteboardPayload.fromPasteboard(pasteboard))
        XCTAssertEqual(payload.item, item)
        XCTAssertEqual(payload.scope, scope)
        XCTAssertEqual(SidebarDropCoordinator.draggedItem(from: pasteboard), item)
        XCTAssertEqual(SidebarDropCoordinator.dragOperation(for: pasteboard), .move)
    }

    func testInternalDragRequiresScopedPayload() throws {
        let item = SumiDragItem(
            tabId: UUID(),
            title: "Unscoped",
            urlString: "https://example.com/unscoped"
        )
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("SumiUnscopedPayload-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString(item.tabId.uuidString, forType: .string)

        XCTAssertNil(SidebarDragPasteboardPayload.fromPasteboard(pasteboard))
        XCTAssertNil(SidebarDropCoordinator.draggedItem(from: pasteboard))
        XCTAssertEqual(SidebarDropCoordinator.dragOperation(for: pasteboard), .copy)
    }

    func testDragContainerCodableRoundTrip() throws {
        let id = UUID()
        let containers: [TabDragManager.DragContainer] = [
            .none,
            .essentials,
            .spacePinned(id),
            .spaceRegular(id),
            .folder(id),
        ]

        for container in containers {
            let data = try JSONEncoder().encode(container)
            let decoded = try JSONDecoder().decode(TabDragManager.DragContainer.self, from: data)
            XCTAssertEqual(decoded, container)
        }
    }

    @MainActor
    func testValidPayloadScopeDoesNotRequireGlobalDragState() throws {
        let profileId = UUID()
        let spaceId = UUID()
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = spaceId
        windowState.currentProfileId = profileId
        let item = SumiDragItem(
            tabId: UUID(),
            title: "Scoped",
            urlString: "https://example.com/scoped"
        )
        let scope = SidebarDragScope(
            windowId: windowState.id,
            spaceId: spaceId,
            profileId: profileId,
            sourceContainer: .spaceRegular(spaceId),
            sourceItemId: item.tabId,
            sourceItemKind: item.kind
        )
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("SumiValidScope-\(UUID().uuidString)"))
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([item.pasteboardItem(scope: scope)]))

        let dragState = SidebarDragState.shared
        dragState.resetInteractionState()
        defer { dragState.resetInteractionState() }

        XCTAssertEqual(
            SidebarDropCoordinator.validatedScope(
                for: item,
                pasteboard: pasteboard,
                dragState: dragState,
                windowState: windowState
            ),
            scope
        )
    }

    @MainActor
    func testMismatchedPayloadDoesNotFallBackToGlobalDragState() throws {
        let profileId = UUID()
        let currentSpaceId = UUID()
        let staleSpaceId = UUID()
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = currentSpaceId
        windowState.currentProfileId = profileId
        let item = SumiDragItem(
            tabId: UUID(),
            title: "Stale",
            urlString: "https://example.com/stale"
        )
        let currentScope = SidebarDragScope(
            windowId: windowState.id,
            spaceId: currentSpaceId,
            profileId: profileId,
            sourceContainer: .spaceRegular(currentSpaceId),
            sourceItemId: item.tabId,
            sourceItemKind: item.kind
        )
        let staleScope = SidebarDragScope(
            windowId: windowState.id,
            spaceId: staleSpaceId,
            profileId: profileId,
            sourceContainer: .spaceRegular(staleSpaceId),
            sourceItemId: item.tabId,
            sourceItemKind: item.kind
        )
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("SumiStaleScope-\(UUID().uuidString)"))
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([item.pasteboardItem(scope: staleScope)]))

        let dragState = SidebarDragState.shared
        dragState.resetInteractionState()
        dragState.beginInternalDragSession(
            itemId: item.tabId,
            location: .zero,
            previewKind: .row,
            previewAssets: [:],
            scope: currentScope
        )
        defer { dragState.resetInteractionState() }

        XCTAssertNil(
            SidebarDropCoordinator.validatedScope(
                for: item,
                pasteboard: pasteboard,
                dragState: dragState,
                windowState: windowState
            )
        )
    }
}
