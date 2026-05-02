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
}
