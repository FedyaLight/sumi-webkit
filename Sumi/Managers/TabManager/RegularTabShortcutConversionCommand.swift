import Foundation
import SumiDomain

@MainActor
final class RegularTabShortcutConversionCommand {
    private let structuralLookup: TabStructuralLookupCoordinator
    private let runtimeConnection: TabRuntimePortConnection
    private let conversion: RegularTabShortcutConversionService

    init(
        structuralLookup: TabStructuralLookupCoordinator,
        runtimeConnection: TabRuntimePortConnection,
        conversion: RegularTabShortcutConversionService
    ) {
        self.structuralLookup = structuralLookup
        self.runtimeConnection = runtimeConnection
        self.conversion = conversion
    }

    func convert(
        _ tab: Tab,
        destination: TabShortcutPinDestination,
        preferredWindowId: UUID?
    ) -> ShortcutPin? {
        structuralLookup.withTransaction {
            if let folderID = destination.folderId,
               runtimeConnection.current?.isLiveFolder(folderID) == true {
                return nil
            }
            return conversion.convert(
                tab,
                destination: destination,
                preferredWindowId: preferredWindowId
            )
        }
    }

}
