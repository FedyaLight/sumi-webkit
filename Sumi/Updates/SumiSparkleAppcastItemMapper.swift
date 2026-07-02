import Foundation

#if canImport(Sparkle)
import Sparkle

enum SumiSparkleAppcastItemMapper {
    static func availableUpdate(from item: SUAppcastItem) -> SumiAvailableUpdate {
        SumiAvailableUpdate(
            displayVersion: item.displayVersionString,
            buildVersion: item.versionString,
            title: item.title,
            subtitle: nil,
            releaseNotesURL: item.releaseNotesURL,
            isInformationOnly: item.isInformationOnlyUpdate
        )
    }
}
#endif
