import AppKit
import Foundation

extension Progress {
    convenience init(copy progress: Progress) {
        self.init(totalUnitCount: progress.totalUnitCount)
        completedUnitCount = progress.completedUnitCount
        fileOperationKind = progress.fileOperationKind
        kind = progress.kind
        isPausable = progress.isPausable
        isCancellable = progress.isCancellable
        fileURL = progress.fileURL
        fileDownloadingSourceURL = progress.fileDownloadingSourceURL
    }

    var fileDownloadingSourceURL: URL? {
        get { userInfo[.fileDownloadingSourceURLKey] as? URL }
        set { setUserInfoObject(newValue, forKey: .fileDownloadingSourceURLKey) }
    }

    var flyToImage: NSImage? {
        get { userInfo[.flyToImageKey] as? NSImage }
        set { setUserInfoObject(newValue, forKey: .flyToImageKey) }
    }

    var fileIcon: NSImage? {
        get { userInfo[.fileIconKey] as? NSImage }
        set { setUserInfoObject(newValue, forKey: .fileIconKey) }
    }

    var fileIconOriginalRect: NSRect? {
        get { (userInfo[.fileIconOriginalRectKey] as? NSValue)?.rectValue }
        set { setUserInfoObject(newValue.map(NSValue.init(rect:)), forKey: .fileIconOriginalRectKey) }
    }
}

extension ProgressUserInfoKey {
    static let fileDownloadingSourceURLKey = ProgressUserInfoKey(rawValue: "NSProgressFileDownloadingSourceURL")
    static let flyToImageKey = ProgressUserInfoKey(rawValue: "NSProgressFlyToImageKey")
    static let fileIconKey = ProgressUserInfoKey(rawValue: "NSProgressFileIconKey")
    static let fileIconOriginalRectKey = ProgressUserInfoKey(rawValue: "NSProgressFileAnimationImageOriginalRectKey")
}

extension NSScreen {
    static var dockScreen: NSScreen? {
        screens.min { lhs, rhs in
            lhs.frame.height - lhs.visibleFrame.height > rhs.frame.height - rhs.visibleFrame.height
        }
    }

    func convertFromGlobalScreenCoordinates(_ rect: NSRect) -> NSRect {
        NSRect(
            x: rect.origin.x - frame.origin.x,
            y: rect.origin.y - frame.origin.y,
            width: rect.width,
            height: rect.height
        )
    }
}
