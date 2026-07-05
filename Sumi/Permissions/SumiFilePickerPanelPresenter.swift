import AppKit
import Foundation
import UniformTypeIdentifiers
import WebKit

struct SumiFilePickerPanelPresentationRequest: Equatable, Sendable {
    let allowsMultipleSelection: Bool
    let allowsDirectories: Bool
    let canChooseFiles: Bool
    let allowedContentTypeIdentifiers: [String]
    let allowedFileExtensions: [String]
    let title: String
    let prompt: String

    init(
        allowsMultipleSelection: Bool,
        allowsDirectories: Bool,
        canChooseFiles: Bool = true,
        allowedContentTypeIdentifiers: [String] = [],
        allowedFileExtensions: [String] = [],
        title: String = "Choose File",
        prompt: String = "Choose"
    ) {
        self.allowsMultipleSelection = allowsMultipleSelection
        self.allowsDirectories = allowsDirectories
        self.canChooseFiles = canChooseFiles
        self.allowedContentTypeIdentifiers = allowedContentTypeIdentifiers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.allowedFileExtensions = allowedFileExtensions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            .filter { !$0.isEmpty }
        self.title = title
        self.prompt = prompt
    }

    var allowedContentTypes: [UTType] {
        let contentTypes = allowedContentTypeIdentifiers.compactMap(UTType.init)
        let extensionTypes = allowedFileExtensions.compactMap { UTType(filenameExtension: $0) }
        return contentTypes + extensionTypes
    }
}

struct SumiFilePickerOpenPanelConfiguration: Equatable {
    let resolvesAliases: Bool
    let title: String
    let prompt: String
    let allowedContentTypes: [UTType]
    let canChooseDirectories: Bool
    let canChooseFiles: Bool
    let allowsMultipleSelection: Bool

    init(request: SumiFilePickerPanelPresentationRequest) {
        self.resolvesAliases = true
        self.title = request.title
        self.prompt = request.prompt
        self.allowedContentTypes = request.allowedContentTypes
        self.canChooseDirectories = request.allowsDirectories
        self.canChooseFiles = request.canChooseFiles
        self.allowsMultipleSelection = request.allowsMultipleSelection
    }

    @MainActor
    func apply(to openPanel: NSOpenPanel) {
        openPanel.resolvesAliases = resolvesAliases
        openPanel.title = title
        openPanel.prompt = prompt

        if !allowedContentTypes.isEmpty {
            openPanel.allowedContentTypes = allowedContentTypes
        }

        openPanel.canChooseDirectories = canChooseDirectories
        openPanel.canChooseFiles = canChooseFiles
        openPanel.allowsMultipleSelection = allowsMultipleSelection
    }
}

@MainActor
protocol SumiFilePickerPanelPresenting: AnyObject {
    func presentFilePicker(
        _ request: SumiFilePickerPanelPresentationRequest,
        for webView: WKWebView?,
        completion: @escaping @MainActor (SumiFilePickerPanelResult) -> Void
    )
}

@MainActor
final class SumiFilePickerPanelPresenter: SumiFilePickerPanelPresenting {
    func presentFilePicker(
        _ request: SumiFilePickerPanelPresentationRequest,
        for webView: WKWebView?,
        completion: @escaping @MainActor (SumiFilePickerPanelResult) -> Void
    ) {
        let openPanel = makeOpenPanel(for: request)
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            switch response {
            case .OK:
                completion(.selected(openPanel.urls))
            case .abort, .cancel:
                completion(.cancelled)
            default:
                completion(.failed(reason: "file-picker-panel-response-\(response.rawValue)"))
            }
        }

        if let window = webView?.window {
            openPanel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            openPanel.begin(completionHandler: handler)
        }
    }

    func makeOpenPanel(for request: SumiFilePickerPanelPresentationRequest) -> NSOpenPanel {
        let openPanel = NSOpenPanel()
        openPanelConfiguration(for: request).apply(to: openPanel)
        return openPanel
    }

    func openPanelConfiguration(
        for request: SumiFilePickerPanelPresentationRequest
    ) -> SumiFilePickerOpenPanelConfiguration {
        SumiFilePickerOpenPanelConfiguration(request: request)
    }
}
