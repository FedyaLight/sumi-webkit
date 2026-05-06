import Common
import Foundation

protocol SumiRegistrableDomainResolving {
    func registrableDomain(forHost host: String?) -> String?
}

struct SumiRegistrableDomainResolver: SumiRegistrableDomainResolving {
    private let tld: TLD

    init(tld: TLD = TLD()) {
        self.tld = tld
    }

    func registrableDomain(forHost host: String?) -> String? {
        tld.eTLDplus1(host)
    }
}
