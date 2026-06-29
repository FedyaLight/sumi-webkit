import AppKit
import Foundation
import UniformTypeIdentifiers

enum SumiDownloadOrigin: Equatable, Sendable {
    case normalNavigation
    case responseForcedDownload
    case unshowableResponse
    case actionRequestedDownload
    case explicitUserSave

    var isEligibleForApplicationsHandling: Bool {
        switch self {
        case .responseForcedDownload, .unshowableResponse, .actionRequestedDownload:
            return true
        case .normalNavigation, .explicitUserSave:
            return false
        }
    }
}

enum SumiDownloadFallbackAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case saveFile
    case ask

    var id: String { rawValue }

    var title: String {
        switch self {
        case .saveFile: return "Save files"
        case .ask: return "Ask whether to open or save files"
        }
    }
}

enum SumiContentHandlerKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case openInSumi
    case saveFile
    case alwaysAsk
    case useSystemDefault
    case useOtherApplication

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openInSumi: return "Open in Sumi"
        case .saveFile: return "Save File"
        case .alwaysAsk: return "Always Ask"
        case .useSystemDefault: return "Use system default app"
        case .useOtherApplication: return "Use other app..."
        }
    }
}

struct SumiContentHandlerRecord: Codable, Equatable, Identifiable, Sendable {
    var id: String { contentType }
    var contentType: String
    var displayName: String
    var handler: SumiContentHandlerKind
    var applicationURL: URL?
}

enum SumiDownloadResolvedAction: Equatable, Sendable {
    case navigate
    case saveFile
    case prompt(canPersistChoice: Bool)
    case downloadThenOpen(SumiDownloadOpenIntent)
    case cancel
}

enum SumiDownloadOpenIntent: Equatable, Sendable {
    case systemDefault
    case application(URL)
}

struct SumiDownloadPromptRequest: Equatable, Sendable {
    let identity: SumiDownloadContentIdentity
    let canPersistChoice: Bool
}

struct SumiDownloadContentIdentity: Equatable, Sendable {
    let contentType: String?
    let displayName: String
    let isCoreWebDocument: Bool
    let requiresOpeningConfirmation: Bool

    static func resolve(mimeType: String?, filename: String?) -> SumiDownloadContentIdentity {
        let normalizedMIME = mimeType?.split(separator: ";", maxSplits: 1).first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let extensionType = filename.flatMap { URL(fileURLWithPath: $0).pathExtension.isEmpty ? nil : UTType(filenameExtension: URL(fileURLWithPath: $0).pathExtension) }
        let type = normalizedMIME.flatMap(Self.typeForMIMEType) ?? extensionType
        let contentType = normalizedMIME ?? type?.identifier
        let displayName = type?.localizedDescription
            ?? normalizedMIME
            ?? filename.map { URL(fileURLWithPath: $0).pathExtension }.flatMap { $0.isEmpty ? nil : ".\($0)" }
            ?? "File"
        return SumiDownloadContentIdentity(
            contentType: contentType,
            displayName: displayName,
            isCoreWebDocument: Self.isCoreWebDocument(mimeType: normalizedMIME, type: type),
            requiresOpeningConfirmation: SumiDownloadSafety.requiresOpeningConfirmation(
                filename: filename,
                mimeType: normalizedMIME
            )
        )
    }

    static func isCoreWebDocument(mimeType: String?, type: UTType?) -> Bool {
        if mimeType == "text/html" || mimeType == "application/xhtml+xml" {
            return true
        }
        guard let type else { return false }
        return type.conforms(to: .html)
    }

    private static func typeForMIMEType(_ mimeType: String) -> UTType? {
        UTType.types(tag: mimeType, tagClass: .mimeType, conformingTo: nil).first
    }
}

enum SumiDownloadPolicyResolver {
    static func resolve(
        origin: SumiDownloadOrigin,
        identity: SumiDownloadContentIdentity,
        handler: SumiContentHandlerRecord?,
        fallback: SumiDownloadFallbackAction
    ) -> SumiDownloadResolvedAction {
        if origin == .normalNavigation {
            return .navigate
        }
        if origin == .explicitUserSave {
            return .saveFile
        }
        if identity.isCoreWebDocument {
            return .saveFile
        }
        if identity.requiresOpeningConfirmation {
            return fallback == .ask ? .prompt(canPersistChoice: false) : .saveFile
        }
        guard origin.isEligibleForApplicationsHandling else {
            return .saveFile
        }
        if let handler {
            switch handler.handler {
            case .openInSumi:
                return identity.isCoreWebDocument ? .navigate : .saveFile
            case .saveFile:
                return .saveFile
            case .alwaysAsk:
                return .prompt(canPersistChoice: false)
            case .useSystemDefault:
                return .downloadThenOpen(.systemDefault)
            case .useOtherApplication:
                guard let applicationURL = handler.applicationURL else { return .saveFile }
                return .downloadThenOpen(.application(applicationURL))
            }
        }
        switch fallback {
        case .saveFile:
            return .saveFile
        case .ask:
            return .prompt(canPersistChoice: identity.contentType != nil && !identity.isCoreWebDocument)
        }
    }
}

struct SumiDownloadDestinationPreference: Equatable, Sendable {
    var alwaysAskWhereToSave: Bool
    var customDirectoryURL: URL?
}

enum SumiDownloadDestinationResolver {
    static func defaultDirectory(
        preference: SumiDownloadDestinationPreference,
        fileManager: FileManager = .default
    ) -> URL {
        preference.customDirectoryURL ?? DownloadsDirectoryResolver.resolvedDownloadsDirectory(fileManager: fileManager)
    }
}

@MainActor
final class SumiDownloadApplicationsStore {
    private let fileURL: URL
    private(set) var records: [SumiContentHandlerRecord] = []

    init(fileURL: URL? = nil) {
        let fileURL = fileURL ?? SumiDownloadApplicationsStore.defaultStoreURL()
        self.fileURL = fileURL
        load()
    }

    func record(for contentType: String?) -> SumiContentHandlerRecord? {
        guard let contentType else { return nil }
        return records.first { $0.contentType.caseInsensitiveCompare(contentType) == .orderedSame }
    }

    func upsert(_ record: SumiContentHandlerRecord) {
        guard !SumiDownloadContentIdentity.isCoreWebDocument(mimeType: record.contentType.lowercased(), type: UTType(record.contentType)) else {
            return
        }
        if let index = records.firstIndex(where: { $0.contentType.caseInsensitiveCompare(record.contentType) == .orderedSame }) {
            records[index] = record
        } else {
            records.append(record)
        }
        records.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        save()
    }

    func remove(contentType: String) {
        records.removeAll { $0.contentType.caseInsensitiveCompare(contentType) == .orderedSame }
        save()
    }

    func load() {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            records = []
            return
        } catch {
            RuntimeDiagnostics.debug(
                "Failed to read download applications store: \(String(describing: error))",
                category: "DownloadManager"
            )
            records = []
            return
        }

        let decoded: [SumiContentHandlerRecord]
        do {
            decoded = try JSONDecoder().decode([SumiContentHandlerRecord].self, from: data)
        } catch {
            RuntimeDiagnostics.debug(
                "Failed to decode download applications store: \(String(describing: error))",
                category: "DownloadManager"
            )
            records = []
            return
        }
        records = decoded.filter {
            !SumiDownloadContentIdentity.isCoreWebDocument(mimeType: $0.contentType.lowercased(), type: UTType($0.contentType))
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(records)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            RuntimeDiagnostics.debug(
                "Failed to save download applications store: \(String(describing: error))",
                category: "DownloadManager"
            )
        }
    }

    static func defaultStoreURL() -> URL {
        let base = ProcessInfo.processInfo.environment["SUMI_APP_SUPPORT_OVERRIDE"].flatMap {
            $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true)
        } ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Sumi", isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("Sumi", isDirectory: true)
        return base.appendingPathComponent("DownloadApplications.json")
    }
}
