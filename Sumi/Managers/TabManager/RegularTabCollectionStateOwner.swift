import Combine
import Foundation

@MainActor
final class RegularTabCollectionStateOwner {
    private(set) var tabsBySpace: [UUID: [Tab]] = [:]
    private let tabsBySpaceSubject = PassthroughSubject<[UUID: [Tab]], Never>()

    var tabsBySpacePublisher: AnyPublisher<[UUID: [Tab]], Never> {
        tabsBySpaceSubject.eraseToAnyPublisher()
    }

    func replaceTabsBySpace(_ tabsBySpace: [UUID: [Tab]]) {
        self.tabsBySpace = tabsBySpace
        tabsBySpaceSubject.send(tabsBySpace)
    }

    func removeAll() {
        tabsBySpace.removeAll()
        tabsBySpaceSubject.send(tabsBySpace)
    }

    func tabs(in space: Space) -> [Tab] {
        tabs(in: space.id)
    }

    func tabs(in spaceId: UUID) -> [Tab] {
        Array(tabsBySpace[spaceId] ?? [])
    }

    func allTabs(in spaces: [Space]) -> [Tab] {
        spaces.flatMap { tabsBySpace[$0.id] ?? [] }
    }

    func allTabs() -> [Tab] {
        tabsBySpace.values.flatMap(\.self)
    }

    func contains(_ tab: Tab) -> Bool {
        guard let spaceId = tab.spaceId else { return false }
        return (tabsBySpace[spaceId] ?? []).contains { $0.id == tab.id }
    }

    func firstIndex(of tab: Tab, in spaceId: UUID) -> Int? {
        tabsBySpace[spaceId]?.firstIndex { $0.id == tab.id }
    }

    func appendIndex(in spaceId: UUID) -> Int {
        (tabsBySpace[spaceId]?.map(\.index).max() ?? -1) + 1
    }

    func clampedInsertionIndex(_ index: Int, in spaceId: UUID) -> Int {
        let count = tabsBySpace[spaceId]?.count ?? 0
        return max(0, min(index, count))
    }

    func findSpace(for tabId: UUID) -> UUID? {
        for (spaceId, tabs) in tabsBySpace where tabs.contains(where: { $0.id == tabId }) {
            return spaceId
        }
        return nil
    }

    func tabsBelow(_ tab: Tab) -> [Tab]? {
        guard let spaceId = tab.spaceId,
              let tabs = tabsBySpace[spaceId],
              tabs.contains(where: { $0.id == tab.id }) else {
            return nil
        }
        return tabs.filter { $0.index > tab.index }
    }

    func hasTabs(in spaceId: UUID) -> Bool {
        tabsBySpace[spaceId]?.isEmpty == false
    }
}
