import Common

extension SumiSecurityOrigin {
    init(_ origin: SecurityOrigin) {
        self.init(protocol: origin.`protocol`, host: origin.host, port: origin.port)
    }

    var browserServicesKitSecurityOrigin: SecurityOrigin {
        SecurityOrigin(protocol: self.`protocol`, host: host, port: port)
    }
}
