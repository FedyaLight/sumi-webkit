import Foundation

struct WebsiteDisplayState: Equatable {
    let splitGroup: SplitGroup?
    let currentId: UUID?
    let compositorVersion: Int
    let currentTabUnloaded: Bool
    let visibleTabIds: Set<UUID>
    let isSplitDropCaptureActive: Bool

    var activeSplitGroup: SplitGroup? {
        guard let splitGroup,
              let currentId,
              splitGroup.contains(currentId)
        else {
            return nil
        }
        return splitGroup
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.splitGroup == rhs.splitGroup
            && lhs.currentId == rhs.currentId
            && lhs.compositorVersion == rhs.compositorVersion
            && lhs.currentTabUnloaded == rhs.currentTabUnloaded
            && lhs.visibleTabIds == rhs.visibleTabIds
            && lhs.isSplitDropCaptureActive == rhs.isSplitDropCaptureActive
    }
}
