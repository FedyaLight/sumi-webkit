import AppKit
import Foundation

enum SumiDefaultBrowserStatus: Equatable {
    case isDefault
    case other(displayName: String)
    case sandboxed
    case unknown
}

enum SumiDefaultBrowserError: Error, Equatable {
    case sandboxed
    case systemError(String)
}

@MainActor
protocol SumiDefaultBrowserWorkspaceResolving {
    func urlForApplication(toOpen url: URL) -> URL?
    func setDefaultApplication(at applicationURL: URL, toOpenURLsWithScheme urlScheme: String) async throws
}

@MainActor
struct SumiNSWorkspaceDefaultBrowserResolver: SumiDefaultBrowserWorkspaceResolving {
    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func urlForApplication(toOpen url: URL) -> URL? {
        workspace.urlForApplication(toOpen: url)
    }

    func setDefaultApplication(at applicationURL: URL, toOpenURLsWithScheme urlScheme: String) async throws {
        try await workspace.setDefaultApplication(
            at: applicationURL,
            toOpenURLsWithScheme: urlScheme
        )
    }
}

@MainActor
final class SumiDefaultBrowserService {
    static let shared = SumiDefaultBrowserService()

    private let workspace: any SumiDefaultBrowserWorkspaceResolving
    private let bundleURL: URL
    private let isSandboxed: () -> Bool

    init(
        workspace: any SumiDefaultBrowserWorkspaceResolving = SumiNSWorkspaceDefaultBrowserResolver(),
        bundleURL: URL = Bundle.main.bundleURL,
        isSandboxed: @escaping () -> Bool = {
            ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        }
    ) {
        self.workspace = workspace
        self.bundleURL = bundleURL
        self.isSandboxed = isSandboxed
    }

    var canSetProgrammatically: Bool {
        !isSandboxed()
    }

    func currentStatus() -> SumiDefaultBrowserStatus {
        if isSandboxed() {
            return .sandboxed
        }

        guard let schemeURL = URL(string: "https:"),
              let defaultApplicationURL = workspace.urlForApplication(toOpen: schemeURL)
        else {
            return .unknown
        }

        if normalizedApplicationURL(defaultApplicationURL) == normalizedApplicationURL(bundleURL) {
            return .isDefault
        }

        return .other(displayName: displayName(for: defaultApplicationURL))
    }

    func requestBecomeDefault() async -> Result<Void, SumiDefaultBrowserError> {
        guard canSetProgrammatically else {
            return .failure(.sandboxed)
        }

        do {
            try await workspace.setDefaultApplication(
                at: bundleURL,
                toOpenURLsWithScheme: "http"
            )
            return .success(())
        } catch {
            return .failure(.systemError(error.localizedDescription))
        }
    }

    private func normalizedApplicationURL(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }

    private func displayName(for applicationURL: URL) -> String {
        guard let bundle = Bundle(url: applicationURL) else {
            return applicationURL.deletingPathExtension().lastPathComponent
        }

        if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !displayName.isEmpty {
            return displayName
        }

        if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !name.isEmpty {
            return name
        }

        return applicationURL.deletingPathExtension().lastPathComponent
    }
}
