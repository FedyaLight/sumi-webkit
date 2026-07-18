import Foundation

enum SumiWebPageContextMenuTargetKind: String, Sendable {
    case page
    case link
    case image
    case media
    case editable
    case interactiveElement
    case otherElement
}

struct SumiWebPageContextMenuTargetSnapshot: Sendable {
    let kind: SumiWebPageContextMenuTargetKind
    let selectedText: String?
    let linkHref: String?
    let linkText: String?
    let imageSrc: String?
    let mediaSrc: String?
    let receivedAt: TimeInterval

    init(
        kind: SumiWebPageContextMenuTargetKind,
        selectedText: String? = nil,
        linkHref: String? = nil,
        linkText: String? = nil,
        imageSrc: String? = nil,
        mediaSrc: String? = nil,
        receivedAt: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        self.kind = kind
        self.selectedText = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.linkHref = linkHref?.nilIfEmpty
        self.linkText = linkText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.imageSrc = imageSrc?.nilIfEmpty
        self.mediaSrc = mediaSrc?.nilIfEmpty
        self.receivedAt = receivedAt
    }

    func isRecent(maxAge: TimeInterval = 1.0) -> Bool {
        let age = ProcessInfo.processInfo.systemUptime - receivedAt
        return age >= 0 && age <= maxAge
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
