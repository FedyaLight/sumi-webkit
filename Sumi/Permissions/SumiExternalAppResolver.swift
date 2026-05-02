import AppKit
import Foundation

struct SumiExternalAppInfo: Equatable, Sendable {
    let appDisplayName: String?
}

@MainActor
protocol SumiExternalAppResolving {
    func appInfo(for url: URL) -> SumiExternalAppInfo?
    func open(_ url: URL) -> Bool
}

@MainActor
final class SumiNSWorkspaceExternalAppResolver: SumiExternalAppResolving {
    static let shared = SumiNSWorkspaceExternalAppResolver()

    private let workspace: NSWorkspace
    private let fileManager: FileManager

    init(
        workspace: NSWorkspace = .shared,
        fileManager: FileManager = .default
    ) {
        self.workspace = workspace
        self.fileManager = fileManager
    }

    func appInfo(for url: URL) -> SumiExternalAppInfo? {
        guard SumiExternalSchemePermissionRequest.isValidExternalSchemeURL(url),
              let appURL = workspace.urlForApplication(toOpen: url)
        else {
            return nil
        }
        return SumiExternalAppInfo(
            appDisplayName: displayName(forApplicationAt: appURL)
        )
    }

    func open(_ url: URL) -> Bool {
        guard SumiExternalSchemePermissionRequest.isValidExternalSchemeURL(url) else {
            return false
        }
        return workspace.open(url)
    }

    private func displayName(forApplicationAt appURL: URL) -> String? {
        let bundle = Bundle(url: appURL)
        let bundleDisplayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
        let displayName = bundleDisplayName ?? bundleName ?? fileManager.displayName(atPath: appURL.path)
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
