import Foundation

@MainActor
protocol URLTabOpening: AnyObject {
    @discardableResult
    func openNewTab(url: String, context: BrowserTabOpenContext) -> Tab
}

extension BrowserTabOpeningOwner: URLTabOpening {}
