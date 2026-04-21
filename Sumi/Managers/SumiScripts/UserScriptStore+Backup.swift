//
//  UserScriptStore+Backup.swift
//  Sumi
//
//  Zip export/import and Violentmonkey-style archive import for userscripts.
//

import Foundation

// MARK: - Backup (zip export / import)

private struct SumiUserscriptsBackupEnvelope: Codable {
    let format: String
    let version: Int
    let exportedAt: Date
    let runMode: UserScriptRunMode?
    let originAllow: [String: [String]]?
    let originDeny: [String: [String]]?
    let disabled: [String]
}

extension UserScriptStore {

    /// Writes a zip containing script sources and `sumi-backup.json` (policy fields when requested).
    func exportBackupArchive(to zipURL: URL, includeOriginRules: Bool) throws {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("sumi-export-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }

        let urls = try fm.contentsOfDirectory(at: scriptsDirectory, includingPropertiesForKeys: nil)
        for u in urls {
            let name = u.lastPathComponent
            guard name.hasSuffix(".user.js") || name.hasSuffix(".user.css") || name.hasSuffix(".js") || name.hasSuffix(".css"),
                  name != "manifest.json"
            else { continue }
            let dest = temp.appendingPathComponent(name)
            try? fm.removeItem(at: dest)
            try fm.copyItem(at: u, to: dest)
        }

        let envelope = SumiUserscriptsBackupEnvelope(
            format: "sumi-userscripts",
            version: 1,
            exportedAt: Date(),
            runMode: includeOriginRules ? manifest.runMode : nil,
            originAllow: includeOriginRules ? manifest.originAllow : nil,
            originDeny: includeOriginRules ? manifest.originDeny : nil,
            disabled: includeOriginRules ? manifest.disabled : []
        )
        let encData = try JSONEncoder().encode(envelope)
        try encData.write(to: temp.appendingPathComponent("sumi-backup.json"), options: .atomic)

        try UserScriptZipUtil.zipFolder(temp, to: zipURL)
    }

    /// Unzips and copies `.user.js` / `.user.css` into the scripts directory. Merges `sumi-backup.json` when present.
    /// Best-effort: if `violentmonkey` JSON exists, imports script bodies from its `scripts` array.
    @discardableResult
    func importBackupArchive(from zipURL: URL) throws -> Int {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("sumi-import-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }

        try UserScriptZipUtil.unzip(zipURL, to: temp)

        var imported = 0

        if let backupURL = Self.findBackupJSONFile(named: "sumi-backup.json", under: temp),
           let data = try? Data(contentsOf: backupURL),
           let env = try? JSONDecoder().decode(SumiUserscriptsBackupEnvelope.self, from: data)
        {
            mergeImportedSumiEnvelope(env)
        }

        imported += try importViolentmonkeyIfPresent(root: temp)

        let scriptFiles = try fm.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil)
            .filter { u in
                let n = u.lastPathComponent
                return (n.hasSuffix(".user.js") || n.hasSuffix(".user.css")) && n != "manifest.json"
            }
        for src in scriptFiles {
            let name = src.lastPathComponent
            var dest = scriptsDirectory.appendingPathComponent(name)
            if fm.fileExists(atPath: dest.path) {
                let base = (name as NSString).deletingPathExtension
                let ext = (name as NSString).pathExtension
                dest = scriptsDirectory.appendingPathComponent("\(base)-imported-\(Int(Date().timeIntervalSince1970)).\(ext)")
            }
            try fm.copyItem(at: src, to: dest)
            imported += 1
        }

        saveManifest()
        reload()
        onScriptsChanged?()
        return imported
    }

    private func mergeImportedSumiEnvelope(_ env: SumiUserscriptsBackupEnvelope) {
        if let rm = env.runMode {
            manifest.runMode = rm
        }
        if let oa = env.originAllow {
            if manifest.originAllow == nil { manifest.originAllow = [:] }
            for (k, v) in oa {
                let merged = Set(manifest.originAllow![k] ?? []).union(v)
                if merged.isEmpty {
                    manifest.originAllow!.removeValue(forKey: k)
                } else {
                    manifest.originAllow![k] = Array(merged)
                }
            }
        }
        if let od = env.originDeny {
            if manifest.originDeny == nil { manifest.originDeny = [:] }
            for (k, v) in od {
                let merged = Set(manifest.originDeny![k] ?? []).union(v)
                if merged.isEmpty {
                    manifest.originDeny!.removeValue(forKey: k)
                } else {
                    manifest.originDeny![k] = Array(merged)
                }
            }
        }
        for fn in env.disabled where manifest.disabled.contains(fn) == false {
            manifest.disabled.append(fn)
        }
        pruneEmptyOriginMaps()
    }

    private func importViolentmonkeyIfPresent(root: URL) throws -> Int {
        guard let vmURL = Self.findViolentmonkeyJSON(under: root),
              let data = try? Data(contentsOf: vmURL),
              let rootObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scripts = rootObj["scripts"] as? [[String: Any]]
        else {
            return 0
        }
        var count = 0
        for (idx, obj) in scripts.enumerated() {
            guard let code = obj["code"] as? String ?? obj["source"] as? String,
                  UserScriptMetadataParser.parse(code) != nil
            else { continue }
            let name = "vm-import-\(idx)-\(UUID().uuidString.prefix(6)).user.js"
            let dest = scriptsDirectory.appendingPathComponent(name)
            try code.write(to: dest, atomically: true, encoding: .utf8)
            count += 1
        }
        return count
    }

    private static func findBackupJSONFile(named: String, under root: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { return nil }
        for case let u as URL in enumerator {
            if u.lastPathComponent == named { return u }
        }
        return nil
    }

    private static func findViolentmonkeyJSON(under root: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { return nil }
        for case let u as URL in enumerator {
            let n = u.lastPathComponent.lowercased()
            if n == "violentmonkey" || n == "violentmonkey.json" { return u }
        }
        return nil
    }
}
