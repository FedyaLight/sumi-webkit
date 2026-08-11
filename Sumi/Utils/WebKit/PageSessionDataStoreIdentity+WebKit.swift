import WebKit

extension PageSessionDataStoreIdentity {
    @MainActor
    init(_ dataStore: WKWebsiteDataStore) {
        if let identifier = dataStore.identifier {
            self = .persistent(identifier)
        } else {
            self = .runtime(ObjectIdentifier(dataStore))
        }
    }
}
