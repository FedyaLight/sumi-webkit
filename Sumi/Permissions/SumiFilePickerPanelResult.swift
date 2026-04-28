import Foundation

enum SumiFilePickerPanelResult: Equatable, Sendable {
    case selected([URL])
    case cancelled
    case failed(reason: String)

    var webKitURLs: [URL]? {
        switch self {
        case .selected(let urls):
            return urls.isEmpty ? nil : urls
        case .cancelled, .failed:
            return nil
        }
    }

    var reason: String {
        switch self {
        case .selected:
            return "file-picker-selected"
        case .cancelled:
            return "file-picker-cancelled"
        case .failed(let reason):
            return reason
        }
    }
}
