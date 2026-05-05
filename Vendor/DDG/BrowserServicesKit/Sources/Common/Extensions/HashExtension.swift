//
//  HashExtension.swift
//

import CommonCrypto
import Foundation

extension Data {

    public var sha1: String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        let dataBytes = [UInt8](self)
        _ = CC_SHA1(dataBytes, CC_LONG(count), &hash)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

extension String {

    public var sha1: String {
        Data(utf8).sha1
    }
}
