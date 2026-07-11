import Foundation

struct WebsiteDisplayState: Equatable {
    let splitPresentation: WindowSplitPresentation?
    let currentId: UUID?
    let compositorVersion: Int
    let currentTabUnloaded: Bool
    let isSplitDropCaptureActive: Bool

    var activeSplitPresentation: WindowSplitPresentation? {
        guard let splitPresentation,
              let currentId,
              splitPresentation.activeTabID == currentId
        else {
            return nil
        }
        return splitPresentation
    }

    var visibleTabIDs: Set<UUID> {
        if let activeSplitPresentation {
            return Set(activeSplitPresentation.visibleTabIDs)
        }
        return currentId.map { Set([$0]) } ?? []
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.splitPresentation == rhs.splitPresentation
            && lhs.currentId == rhs.currentId
            && lhs.compositorVersion == rhs.compositorVersion
            && lhs.currentTabUnloaded == rhs.currentTabUnloaded
            && lhs.isSplitDropCaptureActive == rhs.isSplitDropCaptureActive
    }
}
