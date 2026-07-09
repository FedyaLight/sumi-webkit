//
//  SumiNonPersistentURLSession.swift
//  Sumi
//

import Foundation

enum SumiNonPersistentURLSession {
    static func make() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }
}
