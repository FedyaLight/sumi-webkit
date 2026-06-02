import Foundation
import XCTest
import zlib

@testable import Sumi

final class ChromeMV3PackageIntakeTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    @MainActor
    func testDisabledModuleBlocksPackageIntakeWithoutArtifacts() throws {
        let root = try makeTemporaryDirectory()
        let zip = try writeZIP(
            entries: minimalMV3ZIPEntries(),
            named: "disabled.zip"
        )
        let module = try makeModule(enabled: false)

        XCTAssertNil(
            module.chromeMV3PreflightLocalZipArchiveIfEnabled(
                rootURL: root,
                sourceURL: zip
            )
        )
        XCTAssertNil(
            module.chromeMV3PreflightLocalCRXArchiveIfEnabled(
                rootURL: root,
                sourceURL: zip
            )
        )
        XCTAssertNil(
            module.chromeMV3DiagnoseChromeWebStoreInputIfEnabled(
                rootURL: root,
                input: validExtensionID()
            )
        )
        XCTAssertNil(module.chromeMV3LatestPackageIntakeReportIfEnabled(rootURL: root))

        let result = module.chromeMV3ImportLocalArchiveThroughManager(
            rootURL: root,
            sourceURL: zip
        )

        XCTAssertEqual(result.status, .blocked)
        XCTAssertTrue(result.blockedDiagnostics.contains {
            $0.code == .moduleDisabled
        })
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("package-intake").path
            )
        )
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testZIPPreflightAcceptsSafeMinimalMV3Archive() throws {
        let root = try makeTemporaryDirectory()
        let zip = try writeZIP(
            entries: minimalMV3ZIPEntries(),
            named: "minimal.zip"
        )

        let report = ChromeMV3PackageIntakeService(rootURL: root)
            .preflightLocalZIPArchive(sourceURL: zip)

        XCTAssertEqual(report.sourceKind, .localZip)
        XCTAssertEqual(report.preflightResult.status, .passed)
        XCTAssertEqual(report.zipPreflight?.manifestCandidatePaths, ["manifest.json"])
        XCTAssertEqual(report.manifestRootResult.candidateCount, 1)
        XCTAssertTrue(report.productFlags.zipImportAvailable)
        XCTAssertFalse(report.productFlags.runtimeLoadable)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: ChromeMV3PackageIntakeService
                    .packageIntakeReportURL(rootURL: root)
                    .path
            )
        )
    }

    func testZIPPreflightRejectsUnsafeArchiveShapes() throws {
        try assertZIPPreflightFails(
            entries: [
                ZIPFixtureEntry(
                    path: "../manifest.json",
                    data: manifestData(version: 3)
                ),
            ],
            contains: "Unsafe ZIP archive entry"
        )
        try assertZIPPreflightFails(
            entries: [
                ZIPFixtureEntry(
                    path: "/manifest.json",
                    data: manifestData(version: 3)
                ),
            ],
            contains: "Unsafe ZIP archive entry"
        )
        try assertZIPPreflightFails(
            entries: minimalMV3ZIPEntries()
                + [
                    ZIPFixtureEntry(
                        path: "link.js",
                        data: Data(),
                        versionMadeBy: 3 << 8,
                        externalAttributes: 0o120777 << 16
                    ),
                ],
            contains: "symbolic link"
        )
        try assertZIPPreflightFails(
            entries: [
                ZIPFixtureEntry(path: "manifest.json", data: manifestData(version: 3)),
                ZIPFixtureEntry(path: "manifest.json", data: manifestData(version: 3)),
            ],
            contains: "duplicated"
        )
        try assertZIPPreflightFails(
            entries: [
                ZIPFixtureEntry(path: "background.js", data: Data()),
            ],
            contains: "manifest.json"
        )
        try assertZIPPreflightFails(
            entries: [
                ZIPFixtureEntry(path: "manifest.json", data: manifestData(version: 2)),
            ],
            contains: "manifest_version 2"
        )
    }

    @MainActor
    func testZIPImportExtractsInsideControlledRootAndCreatesLifecycleRecord()
        throws
    {
        let root = try makeTemporaryDirectory()
        let zip = try writeZIP(
            entries: [
                ZIPFixtureEntry(path: "extension/manifest.json", data: manifestData(version: 3)),
                ZIPFixtureEntry(path: "extension/background.js", data: Data()),
            ],
            named: "safe.zip"
        )
        let module = try makeModule(enabled: true)

        let result = module.chromeMV3ImportLocalArchiveThroughManager(
            rootURL: root,
            sourceURL: zip,
            profileID: "profile-zip"
        )
        let record = try XCTUnwrap(result.lifecycleOperationResult?.record)
        let report = try XCTUnwrap(result.packageIntakeReport)

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.action, .importZipArchive)
        XCTAssertEqual(record.profileID, "profile-zip")
        XCTAssertEqual(record.lifecycleState, .diagnosticsReady)
        XCTAssertEqual(record.sourceKind, .zipArchive)
        XCTAssertEqual(record.sourcePath, zip.standardizedFileURL.path)
        XCTAssertEqual(record.sourceLastPathComponent, "safe.zip")
        XCTAssertTrue(record.originalBundleRootPath.hasPrefix(root.path))
        let installedState = try XCTUnwrap(
            ChromeMV3ExtensionLifecycleRegistry(rootURL: root)
                .installedExtensionState(
                    profileID: record.profileID,
                    extensionID: record.extensionID
                )
        )
        XCTAssertEqual(installedState.sourceType, .localArchive)
        XCTAssertEqual(installedState.sourceKind, .zipArchive)
        XCTAssertEqual(installedState.sourcePath, zip.standardizedFileURL.path)
        XCTAssertTrue(installedState.generatedBundleState.generatedBundleAvailable)
        XCTAssertFalse(installedState.productSupportClaim)
        XCTAssertEqual(report.extractionResult?.stage.status, .passed)
        XCTAssertEqual(report.lifecycleImportResult.stage.status, .passed)
        XCTAssertFalse(result.runtimeAttachmentAttempted)
        XCTAssertFalse(result.runtimeObjectsCreated)
        XCTAssertFalse(result.serviceWorkerWakeAttempted)
        XCTAssertFalse(result.nativeHostLaunchAttempted)
        XCTAssertFalse(result.productFlags.runtimeLoadable)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    @MainActor
    func testFailedZIPImportCleansAcceptedCandidate() throws {
        let root = try makeTemporaryDirectory()
        let zip = try writeZIP(
            entries: [
                ZIPFixtureEntry(
                    path: "manifest.json",
                    data: manifestData(
                        version: 3,
                        backgroundServiceWorker: "missing.js"
                    )
                ),
            ],
            named: "missing-resource.zip"
        )
        let module = try makeModule(enabled: true)

        let result = module.chromeMV3ImportLocalArchiveThroughManager(
            rootURL: root,
            sourceURL: zip,
            profileID: "profile-failed-zip"
        )
        let extractedRoot = try XCTUnwrap(
            result.packageIntakeReport?.extractionResult?.extractedRootPath
        )

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.status, .failed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: extractedRoot))
        XCTAssertNil(result.lifecycleOperationResult?.record)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testCRX3ParserAndTrustFoundationStayBlocked() throws {
        let root = try makeTemporaryDirectory()
        let service = ChromeMV3PackageIntakeService(rootURL: root)
        let zipPayload = makeZIPData(entries: minimalMV3ZIPEntries())
        let crx = try writeData(makeCRX3(payload: zipPayload), named: "fixture.crx")

        let nonCRX = try writeData(Data("hello".utf8), named: "not.crx")
        let unsupported = try writeData(makeCRX(version: 2), named: "v2.crx")
        let oversized = try writeData(
            makeCRX(version: 3, headerLength: (1 << 18) + 1),
            named: "oversized.crx"
        )

        XCTAssertEqual(
            service.preflightLocalCRXArchive(sourceURL: nonCRX)
                .crxParserResult?.stage.code,
            "notCrx"
        )
        XCTAssertEqual(
            service.preflightLocalCRXArchive(sourceURL: unsupported)
                .crxParserResult?.version,
            nil
        )
        XCTAssertTrue(
            service.preflightLocalCRXArchive(sourceURL: oversized)
                .blockers
                .contains { $0.contains("header length") }
        )

        let report = service.preflightLocalCRXArchive(sourceURL: crx)
        let parser = try XCTUnwrap(report.crxParserResult)
        XCTAssertEqual(parser.stage.status, .passed)
        XCTAssertEqual(parser.version, 3)
        XCTAssertEqual(parser.payloadOffset, UInt64(12 + crxHeader().count))
        XCTAssertEqual(parser.payloadZIPPreflight?.stage.status, .passed)
        XCTAssertEqual(report.trustResult.importAllowed, false)
        XCTAssertTrue(report.trustResult.states.contains(.parsedButUnverified))
        XCTAssertTrue(report.trustResult.states.contains(.importBlocked))
        XCTAssertEqual(report.trustResult.extensionID?.count, 32)

        let importResult = service.importLocalCRXArchive(sourceURL: crx)
        XCTAssertEqual(importResult.actionStatus, .blocked)
        XCTAssertNil(importResult.lifecycleResult)
        XCTAssertEqual(
            importResult.report.lifecycleImportResult.stage.status,
            .blocked
        )
    }

    func testChromeWebStoreURLAndIDDiagnosticsAreDeferredOnly() throws {
        let root = try makeTemporaryDirectory()
        let service = ChromeMV3PackageIntakeService(rootURL: root)
        let id = validExtensionID()
        let url = "https://chromewebstore.google.com/detail/example/\(id)"

        let urlReport = service.diagnoseChromeWebStoreInput(url)
        let idReport = service.diagnoseChromeWebStoreInput(id)
        let invalid = service.diagnoseChromeWebStoreInput("not-a-valid-id")

        XCTAssertEqual(
            urlReport.webStoreDiagnostic?.parsedExtensionID,
            id
        )
        XCTAssertEqual(
            idReport.webStoreDiagnostic?.parsedExtensionID,
            id
        )
        XCTAssertEqual(invalid.webStoreDiagnostic?.stage.status, .failed)
        XCTAssertTrue(
            urlReport.webStoreDiagnostic?.remoteCRXDownloadUnavailable == true
        )
        XCTAssertTrue(
            urlReport.webStoreDiagnostic?.addToChromeInterceptionUnsupported == true
        )
        XCTAssertTrue(urlReport.webStoreDiagnostic?.pageInjectionForbidden == true)
        XCTAssertEqual(urlReport.lifecycleImportResult.stage.status, .deferred)
        XCTAssertFalse(urlReport.productFlags.chromeWebStoreInstallAvailable)
        XCTAssertFalse(urlReport.productFlags.runtimeLoadable)
    }

    func testPackageIntakeSourceGuardsRemainLocalAndNonRuntime() throws {
        let source = try String(
            contentsOf: projectRoot()
                .appendingPathComponent(
                    "Sumi/Models/Extension/ChromeMV3/ChromeMV3PackageIntake.swift"
                ),
            encoding: .utf8
        )
        let positiveBoolean = "tr" + "ue"

        XCTAssertFalse(source.contains("URL" + "Session"))
        XCTAssertFalse(source.contains("Process" + "("))
        XCTAssertFalse(source.contains("DispatchSource" + "Ti" + "mer"))
        XCTAssertFalse(source.contains("addUser" + "Script"))
        XCTAssertFalse(source.contains("addScript" + "MessageHandler"))
        XCTAssertFalse(source.contains("userAgent"))
        XCTAssertFalse(source.contains("chrome.webstore" + ".install"))
        XCTAssertFalse(source.contains("productRuntimeAvailable: " + positiveBoolean))
        XCTAssertFalse(
            source.contains(
                "normalTabRuntimeBridgeAvailable: " + positiveBoolean
            )
        )
        XCTAssertFalse(source.contains("runtimeLoadable: " + positiveBoolean))
    }

    private func assertZIPPreflightFails(
        entries: [ZIPFixtureEntry],
        contains expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let root = try makeTemporaryDirectory()
        let zip = try writeZIP(entries: entries, named: UUID().uuidString + ".zip")
        let report = ChromeMV3PackageIntakeService(rootURL: root)
            .preflightLocalZIPArchive(sourceURL: zip)

        XCTAssertEqual(report.preflightResult.status, .failed, file: file, line: line)
        XCTAssertTrue(
            report.blockers.contains { $0.contains(expected) },
            "Expected blocker containing \(expected), got \(report.blockers)",
            file: file,
            line: line
        )
    }

    private func minimalMV3ZIPEntries() -> [ZIPFixtureEntry] {
        [
            ZIPFixtureEntry(path: "manifest.json", data: manifestData(version: 3)),
            ZIPFixtureEntry(path: "background.js", data: Data()),
        ]
    }

    private func manifestData(
        version: Int,
        backgroundServiceWorker: String = "background.js"
    ) -> Data {
        let object: [String: Any] = [
            "manifest_version": version,
            "name": "ZIP Intake Minimal",
            "version": "1.0.0",
            "background": [
                "service_worker": backgroundServiceWorker,
            ],
        ]
        return try! JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
    }

    private func validExtensionID() -> String {
        "abcdefghijklmnopabcdefghijklmnop"
    }

    @MainActor
    private func makeModule(enabled: Bool) throws -> SumiExtensionsModule {
        let harness = TestDefaultsHarness()
        let registry = SumiModuleRegistry(
            settingsStore:
                SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.setEnabled(enabled, for: .extensions)
        return SumiExtensionsModule(moduleRegistry: registry)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(directory)
        return directory
    }

    private func writeZIP(
        entries: [ZIPFixtureEntry],
        named name: String
    ) throws -> URL {
        try writeData(makeZIPData(entries: entries), named: name)
    }

    private func writeData(_ data: Data, named name: String) throws -> URL {
        let directory = try makeTemporaryDirectory()
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: [.atomic])
        return url
    }

    private func makeZIPData(entries: [ZIPFixtureEntry]) -> Data {
        var archive = Data()
        var central = Data()
        var centralRecords: [(entry: ZIPFixtureEntry, offset: UInt32, crc: UInt32)] = []

        for entry in entries {
            let offset = UInt32(archive.count)
            let nameData = Data(entry.path.utf8)
            let crc = checksum(entry.data)
            appendUInt32(0x0403_4b50, to: &archive)
            appendUInt16(20, to: &archive)
            appendUInt16(0, to: &archive)
            appendUInt16(0, to: &archive)
            appendUInt16(0, to: &archive)
            appendUInt16(0, to: &archive)
            appendUInt32(crc, to: &archive)
            appendUInt32(UInt32(entry.data.count), to: &archive)
            appendUInt32(UInt32(entry.data.count), to: &archive)
            appendUInt16(UInt16(nameData.count), to: &archive)
            appendUInt16(0, to: &archive)
            archive.append(nameData)
            archive.append(entry.data)
            centralRecords.append((entry, offset, crc))
        }

        let centralOffset = UInt32(archive.count)
        for record in centralRecords {
            let nameData = Data(record.entry.path.utf8)
            appendUInt32(0x0201_4b50, to: &central)
            appendUInt16(record.entry.versionMadeBy, to: &central)
            appendUInt16(20, to: &central)
            appendUInt16(0, to: &central)
            appendUInt16(0, to: &central)
            appendUInt16(0, to: &central)
            appendUInt16(0, to: &central)
            appendUInt32(record.crc, to: &central)
            appendUInt32(UInt32(record.entry.data.count), to: &central)
            appendUInt32(UInt32(record.entry.data.count), to: &central)
            appendUInt16(UInt16(nameData.count), to: &central)
            appendUInt16(0, to: &central)
            appendUInt16(0, to: &central)
            appendUInt16(0, to: &central)
            appendUInt16(0, to: &central)
            appendUInt32(record.entry.externalAttributes, to: &central)
            appendUInt32(record.offset, to: &central)
            central.append(nameData)
        }
        archive.append(central)
        appendUInt32(0x0605_4b50, to: &archive)
        appendUInt16(0, to: &archive)
        appendUInt16(0, to: &archive)
        appendUInt16(UInt16(entries.count), to: &archive)
        appendUInt16(UInt16(entries.count), to: &archive)
        appendUInt32(UInt32(central.count), to: &archive)
        appendUInt32(centralOffset, to: &archive)
        appendUInt16(0, to: &archive)
        return archive
    }

    private func makeCRX3(payload: Data) -> Data {
        makeCRX(version: 3, header: crxHeader(), payload: payload)
    }

    private func makeCRX(
        version: UInt32,
        header: Data = Data(),
        headerLength: UInt32? = nil,
        payload: Data = Data()
    ) -> Data {
        var data = Data("Cr24".utf8)
        appendUInt32(version, to: &data)
        appendUInt32(headerLength ?? UInt32(header.count), to: &data)
        data.append(header)
        data.append(payload)
        return data
    }

    private func crxHeader() -> Data {
        let crxID = Data((0..<16).map(UInt8.init))
        let signedData = protobufLengthDelimited(field: 1, data: crxID)
        return protobufLengthDelimited(field: 10000, data: signedData)
    }

    private func protobufLengthDelimited(field: Int, data: Data) -> Data {
        var result = protobufVarint(UInt64(field << 3 | 2))
        result.append(protobufVarint(UInt64(data.count)))
        result.append(data)
        return result
    }

    private func protobufVarint(_ value: UInt64) -> Data {
        var value = value
        var data = Data()
        while value >= 0x80 {
            data.append(UInt8(value & 0x7f) | 0x80)
            value >>= 7
        }
        data.append(UInt8(value))
        return data
    }

    private func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0x00ff))
        data.append(UInt8((value >> 8) & 0x00ff))
    }

    private func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0x0000_00ff))
        data.append(UInt8((value >> 8) & 0x0000_00ff))
        data.append(UInt8((value >> 16) & 0x0000_00ff))
        data.append(UInt8((value >> 24) & 0x0000_00ff))
    }

    private func checksum(_ data: Data) -> UInt32 {
        var value = crc32(0, nil, 0)
        data.withUnsafeBytes { raw in
            value = crc32(
                value,
                raw.bindMemory(to: Bytef.self).baseAddress,
                uInt(data.count)
            )
        }
        return UInt32(value)
    }

    private func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private struct ZIPFixtureEntry {
    var path: String
    var data: Data
    var versionMadeBy: UInt16 = 20
    var externalAttributes: UInt32 = 0
}
