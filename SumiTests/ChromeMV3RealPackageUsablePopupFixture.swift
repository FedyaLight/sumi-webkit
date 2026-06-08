import Foundation
@testable import Sumi

enum ChromeMV3RealPackageUsablePopupFixtureLocation {
    static let packageDirectoryName = ChromeMV3LiveUsablePopupFixtureLocation.packageDirectoryName

    static func packageRoot(file: StaticString = #filePath) -> URL? {
        ChromeMV3LiveUsablePopupFixtureLocation.packageRoot(file: file)
    }
}
