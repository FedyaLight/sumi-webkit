import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers
import WebKit

enum DownloadState: String, Codable, Equatable {
    case pending
    case downloading
    case completed
    case failed
    case cancelled

    var isActive: Bool {
        self == .pending || self == .downloading
    }
}

enum DownloadError: Error, Equatable, Codable, LocalizedError {
    case cancelled
    case failed(message: String, resumeData: Data?, isRetryable: Bool)
    case moveFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Canceled"
        case .failed(let message, _, _):
            return message.isEmpty ? "Error" : message
        case .moveFailed(let message):
            return message.isEmpty ? "Could not move file to Downloads" : message
        }
    }

    var resumeData: Data? {
        guard case .failed(_, let data, _) = self else { return nil }
        return data
    }

    var isRetryable: Bool {
        guard case .failed(_, _, let retryable) = self else { return false }
        return retryable
    }
}

enum DownloadDestination: Equatable {
    case automatic
    case preset(URL)
}

@MainActor
final class DownloadItem: ObservableObject, Identifiable {
    let id: UUID
    let added: Date
    @Published var modified: Date
    let downloadURL: URL
    let websiteURL: URL?

    @Published var fileName: String {
        didSet { touchIfChanged(fileName, oldValue) }
    }

    @Published var destinationURL: URL? {
        didSet { touchIfChanged(destinationURL, oldValue) }
    }

    @Published var tempURL: URL? {
        didSet { touchIfChanged(tempURL, oldValue) }
    }

    @Published var state: DownloadState {
        didSet { touchIfChanged(state, oldValue) }
    }

    @Published var error: DownloadError? {
        didSet {
            if error != oldValue {
                modified = Date()
            }
        }
    }

    @Published var progress: DownloadProgress?

    @Published var completedUnitCount: Int64 {
        didSet { touchIfChanged(completedUnitCount, oldValue) }
    }

    @Published var totalUnitCount: Int64 {
        didSet { touchIfChanged(totalUnitCount, oldValue) }
    }

    @Published var throughput: Int? {
        didSet { touchIfChanged(throughput, oldValue) }
    }

    @Published var estimatedTimeRemaining: TimeInterval? {
        didSet { touchIfChanged(estimatedTimeRemaining, oldValue) }
    }

    init(
        id: UUID = UUID(),
        added: Date = Date(),
        modified: Date = Date(),
        downloadURL: URL,
        websiteURL: URL?,
        fileName: String,
        destinationURL: URL? = nil,
        tempURL: URL? = nil,
        state: DownloadState = .pending,
        error: DownloadError? = nil,
        progress: DownloadProgress? = nil,
        completedUnitCount: Int64 = 0,
        totalUnitCount: Int64 = -1,
        throughput: Int? = nil,
        estimatedTimeRemaining: TimeInterval? = nil
    ) {
        self.id = id
        self.added = added
        self.modified = modified
        self.downloadURL = downloadURL
        self.websiteURL = websiteURL
        self.fileName = fileName
        self.destinationURL = destinationURL
        self.tempURL = tempURL
        self.state = state
        self.error = error
        self.progress = progress
        self.completedUnitCount = completedUnitCount
        self.totalUnitCount = totalUnitCount
        self.throughput = throughput
        self.estimatedTimeRemaining = estimatedTimeRemaining
    }

    var isActive: Bool {
        state.isActive
    }

    var localURL: URL? {
        guard state == .completed else { return nil }
        return destinationURL
    }

    var progressFraction: Double? {
        guard state.isActive else { return nil }
        guard totalUnitCount > 0 else { return -1 }
        return min(max(Double(completedUnitCount) / Double(totalUnitCount), 0), 1)
    }

    var isFinishing: Bool {
        guard state == .downloading else { return false }
        guard totalUnitCount > 0 else { return false }
        return completedUnitCount >= totalUnitCount
    }

    var canRetry: Bool {
        guard state == .failed else { return false }
        return error?.isRetryable == true
    }

    var statusText: String {
        switch state {
        case .pending:
            return "Starting download…"
        case .downloading:
            return activeStatusText
        case .completed:
            return completedSizeText
        case .failed:
            return error?.localizedDescription ?? "Error"
        case .cancelled:
            return "Canceled"
        }
    }

    var activeStatusText: String {
        if isFinishing {
            return "Finishing download…"
        }

        if completedUnitCount == 0 {
            return "Starting download…"
        }

        if totalUnitCount > 0 {
            var text = Self.compactByteProgressText(
                completedUnitCount: completedUnitCount,
                totalUnitCount: totalUnitCount
            )
            if let throughput, throughput > 0 {
                let speed = ByteCountFormatter.string(fromByteCount: Int64(throughput), countStyle: .file)
                text += " - \(speed)/s"
            }
            if let eta = estimatedTimeRemaining, eta > 1,
               let etaText = Self.remainingTimeFormatter.string(from: eta) {
                text += " - \(etaText)"
            }
            return text
        }

        let completed = ByteCountFormatter.string(fromByteCount: completedUnitCount, countStyle: .file)
        return completed
    }

    private var completedSizeText: String {
        guard let url = destinationURL,
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        else {
            return "Completed"
        }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    func icon(size: NSSize = NSSize(width: 32, height: 32)) -> NSImage {
        if let localURL, FileManager.default.fileExists(atPath: localURL.path) {
            let icon = NSWorkspace.shared.icon(forFile: localURL.path)
            icon.size = size
            return icon
        }

        let ext = (fileName as NSString).pathExtension
        if !ext.isEmpty, let type = UTType(filenameExtension: ext) {
            let icon = NSWorkspace.shared.icon(for: type)
            icon.size = size
            return icon
        }

        let icon = NSWorkspace.shared.icon(for: .item)
        icon.size = size
        return icon
    }

    private func touchIfChanged<T: Equatable>(_ value: T, _ oldValue: T) {
        if value != oldValue {
            modified = Date()
        }
    }

    private static func compactByteProgressText(
        completedUnitCount: Int64,
        totalUnitCount: Int64
    ) -> String {
        let completed = ByteCountFormatter.string(fromByteCount: completedUnitCount, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: totalUnitCount, countStyle: .file)

        guard let completedParts = splitByteText(completed),
              let totalParts = splitByteText(total),
              completedParts.unit == totalParts.unit
        else {
            return "\(completed)/\(total)"
        }

        return "\(completedParts.value)/\(totalParts.value) \(totalParts.unit)"
    }

    private static func splitByteText(_ text: String) -> (value: String, unit: String)? {
        let normalized = text
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "\u{202f}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separatorIndex = normalized.lastIndex(of: " ") else { return nil }

        let value = String(normalized[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
        let unitStart = normalized.index(after: separatorIndex)
        let unit = String(normalized[unitStart...]).trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, !unit.isEmpty else { return nil }

        return (value, unit)
    }

    private static let remainingTimeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.includesTimeRemainingPhrase = true
        return formatter
    }()
}
