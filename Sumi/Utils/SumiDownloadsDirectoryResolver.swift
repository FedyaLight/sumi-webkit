import Foundation

/// Central place for resolving where automatic downloads should land.
/// During XCTest / UI smoke runs, avoids touching the real `~/Downloads` so macOS does not prompt for TCC access on every run.
enum SumiDownloadsDirectoryResolver {
    static func resolvedDownloadsDirectory(fileManager: FileManager = .default) -> URL {
        if useIsolatedDirectory {
            let dir = isolatedRoot(fileManager: fileManager).appendingPathComponent("SumiDownloads", isDirectory: true)
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
        if let downloads = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            return downloads
        }
        return fileManager.temporaryDirectory
    }

    private static var useIsolatedDirectory: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["SUMI_TEST_DOWNLOADS_ISOLATION"] == "1" { return true }
        if ProcessInfo.processInfo.arguments.contains("--uitest-smoke") { return true }
        // Unit tests and other XCTest-hosted runs (not the UI-tested app process).
        if env["XCTestConfigurationFilePath"] != nil { return true }
        return false
    }

    private static func isolatedRoot(fileManager: FileManager) -> URL {
        let env = ProcessInfo.processInfo.environment
        if let override = env["SUMI_APP_SUPPORT_OVERRIDE"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true).appendingPathComponent("TestDownloads", isDirectory: true)
        }
        if let tmp = env["TMPDIR"], !tmp.isEmpty {
            return URL(fileURLWithPath: tmp, isDirectory: true)
        }
        return fileManager.temporaryDirectory
    }
}
