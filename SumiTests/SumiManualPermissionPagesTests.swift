import XCTest

final class SumiManualPermissionPagesTests: XCTestCase {
    private let requiredPages = [
        "index.html",
        "media.html",
        "geolocation.html",
        "notifications.html",
        "popups.html",
        "external-schemes.html",
        "autoplay.html",
        "file-picker.html",
        "storage-access.html",
        "storage-access-embedder.html",
        "storage-access-frame.html",
        "screen-capture.html",
        "site-settings-checklist.html",
        "anti-abuse-cleanup-checklist.html",
    ]

    func testRequiredManualPagesAndSharedResourcesExist() throws {
        for page in requiredPages {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: permissionsURL.appendingPathComponent(page).path),
                "\(page) should exist"
            )
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: permissionsURL.appendingPathComponent("README.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: permissionsURL.appendingPathComponent("shared/permissions-test.css").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: permissionsURL.appendingPathComponent("shared/permissions-test.js").path))
    }

    func testIndexLinksToEveryRequiredPage() throws {
        let index = try source("index.html")
        XCTAssertTrue(index.contains("<title>Sumi Permission Manual Tests</title>"))
        for page in requiredPages where page != "index.html" {
            XCTAssertTrue(index.contains("href=\"\(page)\""), "index.html should link to \(page)")
        }
    }

    func testReadmeContainsLocalhostServingAndStorageAccessSetup() throws {
        let readme = try String(contentsOf: permissionsURL.appendingPathComponent("README.md"), encoding: .utf8)
        XCTAssertTrue(readme.contains("cd ManualTests/permissions"))
        XCTAssertTrue(readme.contains("python3 -m http.server 8000"))
        XCTAssertTrue(readme.contains("http://localhost:8000/index.html"))
        XCTAssertTrue(readme.contains("python3 -m http.server 8001"))
        XCTAssertTrue(readme.contains("storage-access-embedder.html"))
        XCTAssertTrue(readme.contains("storage-access-frame.html"))
    }

    func testPagesUseSharedAssetsRuntimeInfoIndexLinkAndManualSections() throws {
        for page in requiredPages {
            let html = try source(page)
            XCTAssertTrue(html.contains("shared/permissions-test.css"), "\(page) should use shared CSS")
            XCTAssertTrue(html.contains("shared/permissions-test.js"), "\(page) should use shared JS")
            XCTAssertTrue(html.contains("data-runtime-info"), "\(page) should display runtime secure-context/origin info")

            if page != "index.html" {
                XCTAssertTrue(html.contains("href=\"index.html\""), "\(page) should link back to index")
                XCTAssertTrue(html.contains("Browser UI Expectations"), "\(page) should document browser UI expectations")
                XCTAssertTrue(html.contains("Manual Checklist"), "\(page) should include a manual checklist")
                XCTAssertTrue(html.contains("<h2>Notes</h2>"), "\(page) should include notes")
            }
        }
    }

    func testPagesDoNotReferenceExternalHttpResources() throws {
        for page in requiredPages {
            let html = try source(page)
            let urls = try detectedHTTPURLs(in: html)
            let externalURLs = urls.filter { url in
                guard let host = url.host?.lowercased() else { return true }
                return host != "localhost" && host != "127.0.0.1" && host != "::1"
            }
            XCTAssertTrue(externalURLs.isEmpty, "\(page) has external HTTP(S) URLs: \(externalURLs)")
        }
    }

    func testStorageAccessPagesDocumentTwoOriginTwoPortSetup() throws {
        for page in ["storage-access.html", "storage-access-embedder.html", "storage-access-frame.html"] {
            let html = try source(page).lowercased()
            XCTAssertTrue(html.contains("two-origin"), "\(page) should mention two-origin setup")
            XCTAssertTrue(html.contains("two-port"), "\(page) should mention two-port setup")
        }
    }

    func testPermissionSpecificManualExpectationsStayDocumented() throws {
        let notifications = try source("notifications.html").lowercased()
        XCTAssertTrue(notifications.contains("dismiss resolves") && notifications.contains("default"))

        let filePicker = try source("file-picker.html").lowercased()
        XCTAssertFalse(filePicker.contains("persistent allow"))
        XCTAssertTrue(filePicker.contains("no stored site permission is written"))

        let screenCapture = try source("screen-capture.html").lowercased()
        XCTAssertTrue(screenCapture.contains("runtime stop controls are unsupported"))
        XCTAssertTrue(screenCapture.contains("no fake stop control"))
    }

    func testSensitivePagesDoNotAutoRequestOnLoad() throws {
        let sensitivePages = [
            "media.html": ["getUserMedia"],
            "geolocation.html": ["getCurrentPosition", "watchPosition"],
            "screen-capture.html": ["getDisplayMedia"],
        ]

        for (page, apis) in sensitivePages {
            let html = try source(page)
            XCTAssertFalse(html.contains("window.addEventListener(\"load\""), "\(page) should not run sensitive APIs on load")
            XCTAssertFalse(html.contains("onload="), "\(page) should not run sensitive APIs from onload")
            for api in apis {
                XCTAssertTrue(html.contains(api), "\(page) should still include \(api) controls")
            }
        }
    }

    private var permissionsURL: URL {
        repoRoot.appendingPathComponent("ManualTests/permissions", isDirectory: true)
    }

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ page: String) throws -> String {
        try String(contentsOf: permissionsURL.appendingPathComponent(page), encoding: .utf8)
    }

    private func detectedHTTPURLs(in source: String) throws -> [URL] {
        let regex = try NSRegularExpression(pattern: #"https?://[A-Za-z0-9.\-\[\]:/_?=&%#]+"#)
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return regex.matches(in: source, options: [], range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: source) else { return nil }
            return URL(string: String(source[matchRange]))
        }
    }
}
