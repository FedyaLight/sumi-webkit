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
    let receivedAt: TimeInterval

    init(
        kind: SumiWebPageContextMenuTargetKind,
        selectedText: String? = nil,
        receivedAt: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        self.kind = kind
        self.selectedText = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
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
