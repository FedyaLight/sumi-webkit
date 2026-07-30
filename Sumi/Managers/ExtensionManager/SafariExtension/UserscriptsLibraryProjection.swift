import Foundation

/// Projects a durable userscript catalog into extension-facing read models.
struct UserscriptsLibraryProjection {
    private let repository: UserscriptsLibraryRepository
    private let metadata: UserscriptsMetadataPolicy

    init(
        repository: UserscriptsLibraryRepository,
        metadata: UserscriptsMetadataPolicy
    ) {
        self.repository = repository
        self.metadata = metadata
    }

    func injectionPayload(
        for url: String,
        isTop: Bool,
        scriptsURL: URL,
        stateRootURL: URL,
        extensionVersion: String
    ) throws -> [String: Any] {
        let manifest = repository.manifest(at: stateRootURL)
        let files = metadata.matchingFiles(
            url: url,
            files: try repository.files(in: scriptsURL),
            manifest: manifest
        )
        var css: [[String: Any]] = []
        var js: [[String: Any]] = []
        var menu: [[String: Any]] = []

        for file in files where isTop || file.noframes == false {
            guard file.runAt != "request" else { continue }
            var code = file.code
            for requiredURL in (file.metadata["require"] ?? []).reversed() {
                let localURL = repository.requiredResourceURL(
                    named: metadata.sanitizeResourceName(requiredURL),
                    for: file.filename,
                    stateRootURL: stateRootURL
                )
                if let requiredCode = repository.stringIfPresent(at: localURL) {
                    code = requiredCode + "\n" + code
                }
            }

            let weight = metadata.normalizedWeight(
                file.metadata["weight"]?.first
            )
            if file.type == "css" {
                css.append([
                    "code": code,
                    "filename": file.filename,
                    "name": file.name,
                    "type": "css",
                    "weight": weight,
                ])
                continue
            }
            let item: [String: Any] = [
                "code": code,
                "scriptMetaStr": file.metablock,
                "scriptObject": metadata.scriptObject(for: file),
                "type": "js",
                "weight": weight,
            ]
            if file.runAt == "context-menu" {
                menu.append(item)
            } else {
                js.append(item)
            }
        }
        return [
            "files": ["css": css, "js": js, "menu": menu],
            "scriptHandler": "Userscripts",
            "scriptHandlerVersion": extensionVersion,
        ]
    }

    func requestScripts(
        scriptsURL: URL,
        stateRootURL: URL
    ) throws -> [[String: String]] {
        let manifest = repository.manifest(at: stateRootURL)
        guard manifest.settings["active"] == "true" else { return [] }
        return try repository.files(in: scriptsURL).compactMap { file in
            guard file.runAt == "request",
                  manifest.disabled.contains(file.filename) == false else {
                return nil
            }
            return ["name": file.name, "code": file.code]
        }
    }

    func contextMenuScripts(
        scriptsURL: URL,
        stateRootURL: URL,
        extensionVersion: String
    ) throws -> [String: Any] {
        let manifest = repository.manifest(at: stateRootURL)
        guard manifest.settings["active"] == "true" else {
            return ["files": ["menu": []]]
        }
        let files = try repository.files(in: scriptsURL).filter {
            $0.runAt == "context-menu"
                && manifest.disabled.contains($0.filename) == false
        }
        var payload = try injectionPayload(
            for: "https://userscripts.invalid/",
            isTop: true,
            scriptsURL: scriptsURL,
            stateRootURL: stateRootURL,
            extensionVersion: extensionVersion
        )
        payload["files"] = [
            "menu": files.map { file in
                [
                    "code": file.code,
                    "scriptMetaStr": file.metablock,
                    "scriptObject": metadata.scriptObject(for: file),
                    "type": "js",
                    "weight": metadata.normalizedWeight(
                        file.metadata["weight"]?.first
                    ),
                ] as [String: Any]
            },
        ]
        return payload
    }

    func popupMatches(
        url: String,
        frameURLs: [String],
        scriptsURL: URL,
        stateRootURL: URL
    ) throws -> [[String: Any]] {
        guard url.hasPrefix("http://") || url.hasPrefix("https://") else {
            return []
        }
        let manifest = repository.manifest(at: stateRootURL)
        let files = try repository.files(in: scriptsURL)
        let disabled = Set(manifest.disabled)
        var result = metadata.matchingFiles(
            url: url,
            files: files,
            manifest: manifest,
            includeDisabled: true,
            respectsActivation: false,
            respectsBlacklist: false
        ).map {
            metadata.fileDictionary($0, disabledFilenames: disabled)
        }
        let topFilenames = Set(result.compactMap {
            $0["filename"] as? String
        })
        var frameFilenames: Set<String> = []
        for frameURL in Set(frameURLs) where frameURL != url {
            for file in metadata.matchingFiles(
                url: frameURL,
                files: files,
                manifest: manifest,
                includeDisabled: true,
                respectsActivation: false,
                respectsBlacklist: false
            ) where file.noframes == false
                && topFilenames.contains(file.filename) == false {
                frameFilenames.insert(file.filename)
            }
        }
        for file in files where frameFilenames.contains(file.filename) {
            var item = metadata.fileDictionary(
                file,
                disabledFilenames: disabled
            )
            item["subframe"] = true
            result.append(item)
        }
        return result
    }
}
