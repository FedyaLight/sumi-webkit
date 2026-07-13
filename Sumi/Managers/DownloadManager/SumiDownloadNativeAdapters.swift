import AppKit
import Foundation

@MainActor
final class SumiDownloadPromptPresenter: DownloadPromptPresenting {
    func resolve(
        request: SumiDownloadPromptRequest,
        response: URLResponse,
        suggestedFilename: String,
        sourceURL: URL,
        window: NSWindow?
    ) async -> DownloadPromptDecision {
        let filename = DownloadFileUtilities.suggestedFilename(
            response: response,
            requestURL: sourceURL,
            fallback: suggestedFilename
        )
        let responseIdentity = SumiDownloadContentIdentity.resolve(
            mimeType: response.mimeType,
            filename: filename
        )
        let identity = responseIdentity.contentType == nil
            ? request.identity
            : responseIdentity
        guard let window else {
            return DownloadPromptDecision(
                action: .saveFile,
                shouldPersist: false,
                identity: identity
            )
        }

        let alert = NSAlert()
        alert.messageText = "What should Sumi do with this file?"
        if identity.requiresOpeningConfirmation {
            alert.informativeText = "\(filename)\nType: \(identity.displayName)\nThis file may run code or open active content. Sumi will save it instead of opening it automatically."
            alert.addButton(withTitle: "Save File")
            alert.addButton(withTitle: "Cancel")
        } else {
            alert.informativeText = "\(filename)\nType: \(identity.displayName)"
            alert.addButton(withTitle: "Open File")
            alert.addButton(withTitle: "Save File")
            alert.addButton(withTitle: "Cancel")
        }

        let checkbox = NSButton(
            checkboxWithTitle: "Do this automatically for files like this from now on",
            target: nil,
            action: nil
        )
        checkbox.isEnabled = request.canPersistChoice
            && !identity.requiresOpeningConfirmation
        alert.accessoryView = checkbox

        let response = await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) {
                continuation.resume(returning: $0)
            }
        }
        let action: SumiDownloadResolvedAction
        if identity.requiresOpeningConfirmation {
            action = response == .alertFirstButtonReturn ? .saveFile : .cancel
        } else {
            switch response {
            case .alertFirstButtonReturn:
                action = .downloadThenOpen(.systemDefault)
            case .alertSecondButtonReturn:
                action = .saveFile
            default:
                action = .cancel
            }
        }
        return DownloadPromptDecision(
            action: action,
            shouldPersist: checkbox.state == .on
                && request.canPersistChoice
                && !identity.requiresOpeningConfirmation,
            identity: identity
        )
    }
}

@MainActor
final class SumiDownloadWorkspace: DownloadWorkspaceOpening {
    private let workspace: NSWorkspace
    private let fileManager: FileManager

    init(workspace: NSWorkspace, fileManager: FileManager) {
        self.workspace = workspace
        self.fileManager = fileManager
    }

    func openDownloadedFile(at url: URL, sourceURL: URL?) {
        guard fileManager.fileExists(atPath: url.path),
              SumiDownloadSafety.confirmOpeningIfNeeded(
                url: url,
                sourceURL: sourceURL
              )
        else { return }
        workspace.open(url)
    }

    func openDownloadedFileIfSafe(
        at url: URL,
        intent: SumiDownloadOpenIntent
    ) {
        guard fileManager.fileExists(atPath: url.path),
              !isCurrentApplication(url),
              !SumiDownloadSafety.requiresOpeningConfirmation(forFileAt: url)
        else { return }

        switch intent {
        case .systemDefault:
            workspace.open(url)
        case .application(let applicationURL):
            guard !isCurrentApplication(applicationURL) else { return }
            workspace.open(
                [url],
                withApplicationAt: applicationURL,
                configuration: NSWorkspace.OpenConfiguration(),
                completionHandler: nil
            )
        }
    }

    func revealDownloadedFile(at url: URL) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        workspace.activateFileViewerSelecting([url])
    }

    func openDownloadsFolder(preference: SumiDownloadDestinationPreference) {
        let folder = SumiDownloadDestinationResolver.defaultDirectory(
            preference: preference,
            fileManager: fileManager
        )
        workspace.selectFile(nil, inFileViewerRootedAtPath: folder.path)
    }

    private func isCurrentApplication(_ url: URL) -> Bool {
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        let standardizedURL = url.standardizedFileURL
        return standardizedURL == bundleURL
            || standardizedURL.path.hasPrefix(bundleURL.path + "/")
    }
}

final class SumiDownloadOrphanCleaner: DownloadOrphanCleaning, @unchecked Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    func removeOrphanedDownloads(
        preference: SumiDownloadDestinationPreference
    ) async {
        let fileManager = self.fileManager
        await Task.detached(priority: .utility) {
            let directory = SumiDownloadDestinationResolver.defaultDirectory(
                preference: preference,
                fileManager: fileManager
            )
            let urls: [URL]
            do {
                urls = try fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                return
            } catch {
                DownloadFileUtilities.logFileOperationFailure(
                    "list incomplete downloads",
                    url: directory,
                    error: error
                )
                return
            }

            for url in urls where url.pathExtension == DownloadFileUtilities.incompleteDownloadExtension {
                do {
                    let isDirectory = try url.resourceValues(
                        forKeys: [.isDirectoryKey]
                    ).isDirectory ?? false
                    guard !isDirectory else { continue }
                    try fileManager.removeItem(at: url)
                } catch {
                    DownloadFileUtilities.logFileOperationFailure(
                        "remove orphaned incomplete download",
                        url: url,
                        error: error
                    )
                }
            }
        }.value
    }
}
