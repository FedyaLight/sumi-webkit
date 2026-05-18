//
//  SumiNonPersistentURLSession.swift
//  Sumi
//

import Foundation

enum SumiNonPersistentURLSession {
    static let shared: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()
}
