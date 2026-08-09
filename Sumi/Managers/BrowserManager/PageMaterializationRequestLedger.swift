import Foundation

struct PageMaterializationRequest: Equatable {
    let id: UUID
    let pageID: UUID
    let windowID: UUID
    let selectionRevision: UInt64
    let residenceGeneration: UInt64
    let destination: URL
}

enum PageMaterializationRequestResult: Equatable {
    case liveExisting(webViewID: ObjectIdentifier)
    case transferred(TabMainFramePendingAttemptOwner)
    case empty
    case cancelled
    case failed(PageMaterializationFailureReason)
    case departed
    case superseded
}

enum PageMaterializationFailureReason: Equatable {
    case residenceUnavailable
    case initialSubmissionUnavailable
}

struct PageMaterializationRequestSettlement: Equatable {
    let request: PageMaterializationRequest
    let result: PageMaterializationRequestResult
}

struct PageMaterializationRequestAdmission: Equatable {
    let request: PageMaterializationRequest
    let superseded: PageMaterializationRequestSettlement?
}

struct PageMaterializationRequestSeed {
    let pageID: UUID
    let residenceGeneration: UInt64
    let destination: URL
}

struct PageMaterializationActivationAdmission {
    let requests: [PageMaterializationRequest]
    let superseded: [PageMaterializationRequestSettlement]
}

/// Window-local owner for Cold Page materialization. It has no timer or
/// observation source: selection starts a request and an exact event settles it.
@MainActor
final class PageMaterializationRequestLedger {
    private struct Key: Hashable {
        let windowID: UUID
        let pageID: UUID
    }

    private var revisionByWindowID: [UUID: UInt64] = [:]
    private var currentByKey: [Key: PageMaterializationRequest] = [:]

    func beginActivation(
        _ seeds: [PageMaterializationRequestSeed],
        windowID: UUID
    ) -> PageMaterializationActivationAdmission {
        let superseded = supersedeAll(in: windowID)
        guard seeds.isEmpty == false else {
            return PageMaterializationActivationAdmission(
                requests: [],
                superseded: superseded
            )
        }
        let revision = nextRevision(in: windowID)
        let requests = seeds.map { seed in
            makeRequest(
                pageID: seed.pageID,
                windowID: windowID,
                selectionRevision: revision,
                residenceGeneration: seed.residenceGeneration,
                destination: seed.destination
            )
        }
        return PageMaterializationActivationAdmission(
            requests: requests,
            superseded: superseded
        )
    }

    func begin(
        pageID: UUID,
        windowID: UUID,
        residenceGeneration: UInt64,
        destination: URL
    ) -> PageMaterializationRequestAdmission {
        let key = Key(windowID: windowID, pageID: pageID)
        let superseded = currentByKey.removeValue(forKey: key).map {
            PageMaterializationRequestSettlement(
                request: $0,
                result: .superseded
            )
        }
        let request = makeRequest(
            pageID: pageID,
            windowID: windowID,
            selectionRevision: nextRevision(in: windowID),
            residenceGeneration: residenceGeneration,
            destination: destination
        )
        return PageMaterializationRequestAdmission(
            request: request,
            superseded: superseded
        )
    }

    func owns(_ request: PageMaterializationRequest) -> Bool {
        currentByKey[Key(
            windowID: request.windowID,
            pageID: request.pageID
        )] == request
    }

    func currentRequest(in windowID: UUID) -> PageMaterializationRequest? {
        currentRequests(in: windowID).first
    }

    func currentRequest(
        for pageID: UUID,
        in windowID: UUID
    ) -> PageMaterializationRequest? {
        currentByKey[Key(windowID: windowID, pageID: pageID)]
    }

    func currentRequests(in windowID: UUID) -> [PageMaterializationRequest] {
        currentByKey.values
            .filter { $0.windowID == windowID }
            .sorted { lhs, rhs in
                if lhs.selectionRevision != rhs.selectionRevision {
                    return lhs.selectionRevision < rhs.selectionRevision
                }
                return lhs.pageID.uuidString < rhs.pageID.uuidString
            }
    }

    @discardableResult
    func settle(
        _ request: PageMaterializationRequest,
        as result: PageMaterializationRequestResult
    ) -> PageMaterializationRequestSettlement? {
        guard owns(request) else { return nil }
        currentByKey.removeValue(forKey: Key(
            windowID: request.windowID,
            pageID: request.pageID
        ))
        return PageMaterializationRequestSettlement(
            request: request,
            result: result
        )
    }

    @discardableResult
    func supersedeAll(
        in windowID: UUID
    ) -> [PageMaterializationRequestSettlement] {
        currentRequests(in: windowID).compactMap {
            settle($0, as: .superseded)
        }
    }

    private func nextRevision(in windowID: UUID) -> UInt64 {
        let revision = (revisionByWindowID[windowID] ?? 0) &+ 1
        revisionByWindowID[windowID] = revision
        return revision
    }

    private func makeRequest(
        pageID: UUID,
        windowID: UUID,
        selectionRevision: UInt64,
        residenceGeneration: UInt64,
        destination: URL
    ) -> PageMaterializationRequest {
        let request = PageMaterializationRequest(
            id: UUID(),
            pageID: pageID,
            windowID: windowID,
            selectionRevision: selectionRevision,
            residenceGeneration: residenceGeneration,
            destination: destination
        )
        currentByKey[Key(windowID: windowID, pageID: pageID)] = request
        return request
    }
}
