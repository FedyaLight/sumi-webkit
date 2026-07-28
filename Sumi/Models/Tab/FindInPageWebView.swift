import Foundation
import UniformTypeIdentifiers

enum FindInPageDocumentKind: Equatable, Sendable {
    case html
    case pdf
}

enum FindInPageSearchDirection: Equatable, Sendable {
    case forward
    case backward
}

struct FindInPageSearchRequest: Equatable, Sendable {
    let query: String
    var direction: FindInPageSearchDirection = .forward
    var preservesSelection = false
    var showsOverlay = false
    var determinesMatchIndex = false
}

enum FindInPageSearchResult: Equatable, Sendable {
    case found(matches: UInt?)
    case notFound
    case cancelled
}

@MainActor
protocol FindInPageWebView: AnyObject {
    func prepareFindSession() async -> FindInPageDocumentKind
    func search(_ request: FindInPageSearchRequest) async -> FindInPageSearchResult
    func dismissFindSession()
}

extension FocusableWKWebView: FindInPageWebView {
    private static var findInPageMaximumMatchCount: UInt { 1000 }

    func prepareFindSession() async -> FindInPageDocumentKind {
        clearFindInPageState()
        try? await deselectAll()
        return await mimeType == UTType.pdf.preferredMIMEType ? .pdf : .html
    }

    func search(_ request: FindInPageSearchRequest) async -> FindInPageSearchResult {
        guard !request.query.isEmpty else { return .notFound }

        if request.preservesSelection {
            try? await collapseSelectionToStart()
        }

        var options: _WKFindOptions = [.caseInsensitive, .wrapAround, .showFindIndicator]
        if request.direction == .backward {
            options.insert(.backwards)
        }
        if request.preservesSelection {
            options.insert(.noIndexChange)
        }
        if request.showsOverlay {
            options.insert(.showOverlay)
        }
        if request.determinesMatchIndex {
            options.insert(.determineMatchIndex)
        }

        switch await find(
            request.query,
            with: options,
            maxCount: Self.findInPageMaximumMatchCount
        ) {
        case .found(let matches):
            return .found(matches: matches)
        case .notFound:
            return .notFound
        case .cancelled:
            return .cancelled
        }
    }

    func dismissFindSession() {
        clearFindInPageState()
    }
}
