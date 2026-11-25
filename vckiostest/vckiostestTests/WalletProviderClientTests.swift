import Foundation
import Security
import Testing
import VckIos
@testable import vckiostest

/// App Attest needs a physical device, so these cover what the wallet provider checks without it: the CSR, and the
/// challenge the client accepts.
struct WalletProviderClientTests {

    @Test func encodesObjectIdentifiers() throws {
        let expected = [
            "1.2.840.10045.4.3.2": "06082a8648ce3d040302",
            "2.5.4.5": "0603550405",
            "2.999.0": "0603883700",
            "2.25.210184084534939142470042512176304499012": "06146982bc9ffddce0f4e2bea3aaed8080eac4e8d244",
        ]

        let encoded = Dictionary(uniqueKeysWithValues: try expected.keys.map { oid in
            (oid, try Der.oid(oid).map { String(format: "%02x", $0) }.joined())
        })

        #expect(encoded == expected)
        #expect(throws: DerError.self) { try Der.oid("1.x") }
    }

    @Test func certificationRequestDecodesWithSignum() throws {
        var error: Unmanaged<CFError>?
        let privateKey = try #require(SecKeyCreateRandomKey([
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256,
        ] as CFDictionary, &error))
        let publicKey = try #require(SecKeyCopyPublicKey(privateKey))
        let publicKeyData = try #require(SecKeyCopyExternalRepresentation(publicKey, &error) as Data?)
        let attributes = [
            CsrAttribute(oid: "2.25.210184084534939142470042512176304499012", value: Der.utf8String(#"{"versionName":"1"}"#)),
            CsrAttribute(oid: "1.3.6.1.4.1.0", value: Der.utf8String("statement")),
            CsrAttribute(oid: "1.3.6.1.4.1.1", value: Der.utf8String("iPhone15,3")),
        ]

        let csr = try CertificationRequest.signed(
            serialNumber: "00FF", publicKey: publicKeyData, attributes: attributes, privateKey: privateKey
        )

        // The generic Kotlin interface erases the result type in Objective-C
        let decoded = try #require(
            try Pkcs10CertificationRequest.companion.decodeFromDer(src: try csr.kotlinByteArray, assertTag: nil)
                as? Pkcs10CertificationRequest
        )
        #expect(try decoded.encodeToDer().data == csr, "Signum re-encodes the CSR to the same DER")
        #expect(decoded.tbsCsr.attributes.count == 3)
        let tbs = try decoded.tbsCsr.encodeToDer().data
        let signature = try #require(try kotlinValue(decoded.decodedSignature)).encodeToDer().data
        #expect(SecKeyVerifySignature(
            publicKey, .ecdsaSignatureMessageX962SHA256, tbs as CFData, signature as CFData, &error
        ))
    }

    /// As sent by Warden: `issuedAt` in epoch milliseconds, `validity` in seconds.
    private let issuedAt = Date(timeIntervalSince1970: 1_795_695_296.254)

    @Test func acceptsChallengeWithSignatureAuthentication() throws {
        let now = issuedAt.addingTimeInterval(60)

        let challenge = try AttestationChallenge(json: challengeJson(), now: now)

        #expect(challenge.nonce == Data([0, 1, 2, 255]))
        #expect(challenge.proofOid == "1.3.6.1.4.1.0")
        #expect(challenge.genericDeviceNameOid == nil)
        #expect(challenge.requiresUserPresence)
    }

    @Test func rejectsUnsupportedChallenges() throws {
        let now = issuedAt.addingTimeInterval(60)

        #expect(throws: WalletProviderError.self) {
            try AttestationChallenge(json: challengeJson(), now: issuedAt.addingTimeInterval(-60))
        }
        #expect(throws: WalletProviderError.self) {
            try AttestationChallenge(json: challengeJson(), now: issuedAt.addingTimeInterval(601))
        }
        #expect(throws: WalletProviderError.self) {
            try AttestationChallenge(json: challengeJson(extra: #""dataAuth":{"type":"HASH","algorithm":"SHA256"}"#), now: now)
        }
        #expect(throws: WalletProviderError.self) {
            try AttestationChallenge(json: challengeJson(algorithm: #"{"type":"RSA","keySize":2048}"#), now: now)
        }
    }

    private func challengeJson(
        algorithm: String = #"{"type":"EC","curve":"P-256"}"#,
        extra: String? = nil
    ) -> String {
        """
        {"issuedAt":1795695296254,"validity":600,"nonce":"\(Data([0, 1, 2, 255]).base64Url)",
         "attestationEndpoint":"https://wallet-provider.example/attest","proofOID":"1.3.6.1.4.1.0",
         "keyConstraints":{"algorithmParameters":\(algorithm),"keyProtection":{"deviceLock":true}}\(extra.map { ",\($0)" } ?? "")}
        """
    }
}
