import XCTest

final class BrowserServicesKitNavigationBoundaryTests: XCTestCase {
    func testNavigationImportsStayInBrowserServicesKitAdapters() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sumiRoot = repoRoot.appendingPathComponent("Sumi", isDirectory: true)
        let allowedAdapterFiles: Set<String> = [
            "SumiNavigationResponderAdapter.swift",
            "SumiTabNavigationDelegateBundle.swift",
        ]
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: sumiRoot,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        )
        var violations: [String] = []

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            guard importsNavigation(contents) else { continue }

            let fileName = fileURL.lastPathComponent
            guard fileName.contains("+BrowserServicesKit") || allowedAdapterFiles.contains(fileName) else {
                violations.append(fileURL.path.replacingOccurrences(of: repoRoot.path + "/", with: ""))
                continue
            }
        }

        let violationList = violations.joined(separator: ", ")
        XCTAssertTrue(
            violations.isEmpty,
            "DDG Navigation imports must stay behind Sumi adapter files: \(violationList)"
        )
    }

    private func importsNavigation(_ contents: String) -> Bool {
        contents.split(separator: "\n").contains { line in
            let importLine = line.trimmingCharacters(in: .whitespaces)
            return importLine == "import Navigation"
                || importLine == "@preconcurrency import Navigation"
        }
    }
}
