import Foundation

@testable import Sumi

@MainActor
extension SumiBoostStore {
    convenience init(
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.init(
            rootDirectory: rootDirectory,
            fileManager: fileManager,
            profileReferenceAdmission: .testingAllowingReferences()
        )
    }
}
