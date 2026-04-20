//
//  UserScriptZipUtil.swift
//  Sumi
//
//  Zip / unzip via `/usr/bin/ditto` (available on macOS).
//

import Foundation

enum UserScriptZipUtilError: LocalizedError {
    case dittoFailed(Int32, String)
    case missingDitto

    var errorDescription: String? {
        switch self {
        case .dittoFailed(let code, let msg):
            return "ditto exited \(code): \(msg)"
        case .missingDitto:
            return "ditto not found at /usr/bin/ditto"
        }
    }
}

enum UserScriptZipUtil {
    private static let ditto = "/usr/bin/ditto"

    static func zipFolder(_ sourceFolder: URL, to zipURL: URL) throws {
        guard FileManager.default.fileExists(atPath: ditto) else {
            throw UserScriptZipUtilError.missingDitto
        }
        try? FileManager.default.removeItem(at: zipURL)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ditto)
        p.arguments = ["-c", "-k", "--sequesterRsrc", sourceFolder.path, zipURL.path]
        let pipe = Pipe()
        p.standardError = pipe
        p.standardOutput = pipe
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let err = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw UserScriptZipUtilError.dittoFailed(p.terminationStatus, err)
        }
    }

    static func unzip(_ zipURL: URL, to destinationFolder: URL) throws {
        guard FileManager.default.fileExists(atPath: ditto) else {
            throw UserScriptZipUtilError.missingDitto
        }
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ditto)
        p.arguments = ["-x", "-k", zipURL.path, destinationFolder.path]
        let pipe = Pipe()
        p.standardError = pipe
        p.standardOutput = pipe
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let err = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw UserScriptZipUtilError.dittoFailed(p.terminationStatus, err)
        }
    }
}
