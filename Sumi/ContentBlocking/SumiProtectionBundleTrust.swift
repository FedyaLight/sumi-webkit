import CryptoKit
import Foundation

struct SumiProtectionBundleSigningKey: Equatable, Sendable {
    let id: String
    let version: Int
    let publicKeyBase64: String

    func publicKey() throws -> Curve25519.Signing.PublicKey {
        guard let data = Data(base64Encoded: publicKeyBase64), data.count == 32 else {
            throw SumiProtectionBundleRemoteUpdateError.signaturePublicKeyInvalid(id)
        }
        return try Curve25519.Signing.PublicKey(rawRepresentation: data)
    }
}

struct SumiProtectionBundleSignatureVerification: Equatable, Sendable {
    let keyId: String
    let keyVersion: Int
}

protocol SumiProtectionBundleManifestVerifying: Sendable {
    func verify(
        manifestData: Data,
        signatureData: Data,
        expectedSignedAsset: String
    ) throws -> SumiProtectionBundleSignatureVerification
}

enum SumiProtectionBundleTrust {
    static let remoteManifestSignatureRequired = true

    static let pinnedSigningKeys: [SumiProtectionBundleSigningKey] = [
        SumiProtectionBundleSigningKey(
            id: "sumi-protection-bundles-ed25519-v1",
            version: 1,
            publicKeyBase64: "Y0hVG5cU1XYFdgLKLff+Ka+dc95Fu/JPC1ISGLEKJfU="
        ),
    ]
}

struct SumiProtectionBundleSignatureVerifier: SumiProtectionBundleManifestVerifying {
    private struct SignatureEnvelope: Decodable {
        let schemaVersion: Int
        let algorithm: String
        let keyId: String
        let signedAsset: String
        let signature: String
    }

    private let keysById: [String: SumiProtectionBundleSigningKey]

    init(keys: [SumiProtectionBundleSigningKey] = SumiProtectionBundleTrust.pinnedSigningKeys) {
        keysById = Dictionary(uniqueKeysWithValues: keys.map { ($0.id, $0) })
    }

    func verify(
        manifestData: Data,
        signatureData: Data,
        expectedSignedAsset: String = SumiProtectionBundleRemoteUpdateConstants.releaseManifestAssetName
    ) throws -> SumiProtectionBundleSignatureVerification {
        let envelope: SignatureEnvelope
        do {
            envelope = try JSONDecoder().decode(SignatureEnvelope.self, from: signatureData)
        } catch {
            throw SumiProtectionBundleRemoteUpdateError.signatureMetadataMalformed(error.localizedDescription)
        }

        guard envelope.schemaVersion == 1 else {
            throw SumiProtectionBundleRemoteUpdateError.signatureMetadataMalformed(
                "unsupported schemaVersion \(envelope.schemaVersion)"
            )
        }
        guard envelope.algorithm == "Ed25519" else {
            throw SumiProtectionBundleRemoteUpdateError.signatureAlgorithmUnsupported(envelope.algorithm)
        }
        guard envelope.signedAsset == expectedSignedAsset else {
            throw SumiProtectionBundleRemoteUpdateError.signatureMetadataMalformed(
                "signature covers \(envelope.signedAsset), expected \(expectedSignedAsset)"
            )
        }
        guard let key = keysById[envelope.keyId] else {
            throw SumiProtectionBundleRemoteUpdateError.signatureKeyUnknown(envelope.keyId)
        }
        guard let signature = Data(base64Encoded: envelope.signature), signature.count == 64 else {
            throw SumiProtectionBundleRemoteUpdateError.signatureMetadataMalformed("signature is not a 64-byte base64 Ed25519 signature")
        }

        let publicKey = try key.publicKey()
        guard publicKey.isValidSignature(signature, for: manifestData) else {
            throw SumiProtectionBundleRemoteUpdateError.signatureInvalid(envelope.keyId)
        }
        return SumiProtectionBundleSignatureVerification(
            keyId: envelope.keyId,
            keyVersion: key.version
        )
    }
}
