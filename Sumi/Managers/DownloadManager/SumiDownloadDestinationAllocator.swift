import AppKit
import Foundation

@MainActor
final class SumiDownloadDestinationAllocator: DownloadDestinationAllocating {
    private let reservations: SumiDownloadDestinationReservationStore

    init(fileManager: FileManager) {
        reservations = SumiDownloadDestinationReservationStore(
            fileManager: fileManager
        )
    }

    func reserve(
        _ request: DownloadDestinationRequest
    ) async -> DownloadDestinationReservation? {
        let responseFilename = DownloadFileUtilities.suggestedFilename(
            response: request.response,
            requestURL: request.sourceURL,
            fallback: request.suggestedFilename
        )
        let filename = DownloadFileUtilities.sanitizedFilename(responseFilename)
        let defaultDirectory = await allocate { reservations in
            reservations.defaultDirectory(preference: request.preference)
        }
        let requestedURL: URL

        if request.preference.alwaysAskWhereToSave {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = filename
            panel.canCreateDirectories = true
            panel.directoryURL = defaultDirectory
            let response = await withCheckedContinuation { continuation in
                panel.begin { continuation.resume(returning: $0) }
            }
            guard response == .OK, let url = panel.url else { return nil }
            requestedURL = url
        } else {
            requestedURL = defaultDirectory.appendingPathComponent(filename)
        }

        return await allocate { reservations in
            reservations.reserve(requestedURL: requestedURL)
        }
    }

    func release(_ reservation: DownloadDestinationReservation) {
        reservations.release(reservation)
    }

    func renewTemporaryDestination(
        for reservation: DownloadDestinationReservation
    ) async -> DownloadDestinationReservation? {
        await allocate { reservations in
            reservations.renewTemporaryDestination(for: reservation)
        }
    }

    private func allocate<T: Sendable>(
        _ operation: @escaping @Sendable (
            SumiDownloadDestinationReservationStore
        ) -> T
    ) async -> T {
        let reservations = self.reservations
        return await Task.detached(priority: .utility) {
            operation(reservations)
        }.value
    }
}

private final class SumiDownloadDestinationReservationStore: @unchecked Sendable {
    private let fileManager: FileManager

    private let lock = NSLock()
    private var pathOwners: [String: UUID] = [:]

    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    func defaultDirectory(
        preference: SumiDownloadDestinationPreference
    ) -> URL {
        SumiDownloadDestinationResolver.defaultDirectory(
            preference: preference,
            fileManager: fileManager
        )
    }

    func reserve(requestedURL: URL) -> DownloadDestinationReservation {
        DownloadFileUtilities.ensureDirectoryExists(
            requestedURL.deletingLastPathComponent(),
            fileManager: fileManager,
            context: "download destination allocation"
        )

        while true {
            let reservedPaths = Set(snapshot().keys)
            let destinationURL = uniqueAvailableURL(
                for: requestedURL,
                reservedPaths: reservedPaths
            )
            let temporaryURL = uniqueAvailableTemporaryURL(
                for: destinationURL,
                reservedPaths: reservedPaths.union([destinationURL.path])
            )
            let allocationID = UUID()
            if commitNewReservation(
                allocationID: allocationID,
                destinationURL: destinationURL,
                temporaryURL: temporaryURL
            ) {
                return DownloadDestinationReservation(
                    allocationID: allocationID,
                    fileName: destinationURL.lastPathComponent,
                    destinationURL: destinationURL,
                    tempURL: temporaryURL
                )
            }
        }
    }

    func renewTemporaryDestination(
        for reservation: DownloadDestinationReservation
    ) -> DownloadDestinationReservation? {
        while true {
            let owners = snapshot()
            guard owners[reservation.destinationURL.path] == reservation.allocationID,
                  owners[reservation.tempURL.path] == reservation.allocationID
            else { return nil }

            let temporaryURL = uniqueAvailableTemporaryURL(
                for: reservation.destinationURL,
                reservedPaths: Set(owners.keys)
            )
            let renewedAllocationID = UUID()
            if commitRenewedReservation(
                reservation,
                renewedAllocationID: renewedAllocationID,
                temporaryURL: temporaryURL
            ) {
                return DownloadDestinationReservation(
                    allocationID: renewedAllocationID,
                    fileName: reservation.fileName,
                    destinationURL: reservation.destinationURL,
                    tempURL: temporaryURL
                )
            }
        }
    }

    func release(_ reservation: DownloadDestinationReservation) {
        lock.withLock {
            removePath(
                reservation.destinationURL.path,
                ownedBy: reservation.allocationID
            )
            removePath(
                reservation.tempURL.path,
                ownedBy: reservation.allocationID
            )
        }
    }

    private func snapshot() -> [String: UUID] {
        lock.withLock { pathOwners }
    }

    private func commitNewReservation(
        allocationID: UUID,
        destinationURL: URL,
        temporaryURL: URL
    ) -> Bool {
        lock.withLock {
            guard pathOwners[destinationURL.path] == nil,
                  pathOwners[temporaryURL.path] == nil
            else { return false }
            pathOwners[destinationURL.path] = allocationID
            pathOwners[temporaryURL.path] = allocationID
            return true
        }
    }

    private func commitRenewedReservation(
        _ reservation: DownloadDestinationReservation,
        renewedAllocationID: UUID,
        temporaryURL: URL
    ) -> Bool {
        lock.withLock {
            guard pathOwners[reservation.destinationURL.path]
                    == reservation.allocationID,
                  pathOwners[reservation.tempURL.path]
                    == reservation.allocationID,
                  pathOwners[temporaryURL.path] == nil
            else { return false }

            pathOwners[reservation.destinationURL.path] = renewedAllocationID
            pathOwners[reservation.tempURL.path] = nil
            pathOwners[temporaryURL.path] = renewedAllocationID
            return true
        }
    }

    private func removePath(_ path: String, ownedBy allocationID: UUID) {
        guard pathOwners[path] == allocationID else { return }
        pathOwners[path] = nil
    }

    private func uniqueAvailableURL(
        for desiredURL: URL,
        reservedPaths: Set<String>
    ) -> URL {
        guard isOnDiskOrReserved(desiredURL, reservedPaths: reservedPaths) else {
            return desiredURL
        }

        let directory = desiredURL.deletingLastPathComponent()
        let fileExtension = desiredURL.pathExtension
        let base = desiredURL.deletingPathExtension().lastPathComponent
        var counter = 1

        while true {
            let name = fileExtension.isEmpty
                ? "\(base) \(counter)"
                : "\(base) \(counter).\(fileExtension)"
            let candidate = directory.appendingPathComponent(name)
            if !isOnDiskOrReserved(candidate, reservedPaths: reservedPaths) {
                return candidate
            }
            counter += 1
        }
    }

    private func uniqueAvailableTemporaryURL(
        for destinationURL: URL,
        reservedPaths: Set<String>
    ) -> URL {
        let fileExtension = destinationURL.pathExtension
        let incompleteExtension = fileExtension.isEmpty
            ? DownloadFileUtilities.incompleteDownloadExtension
            : "\(fileExtension).\(DownloadFileUtilities.incompleteDownloadExtension)"
        let desired = destinationURL
            .deletingPathExtension()
            .appendingPathExtension(incompleteExtension)
        return uniqueAvailableURL(for: desired, reservedPaths: reservedPaths)
    }

    private func isOnDiskOrReserved(
        _ url: URL,
        reservedPaths: Set<String>
    ) -> Bool {
        reservedPaths.contains(url.path)
            || fileManager.fileExists(atPath: url.path)
    }
}
