//
//  vckiostestTests.swift
//  vckiostestTests
//
//  Created by Bernd Prünster on 22.07.26.
//

import Testing
import Foundation
import vck_ios

struct vckiostestTests {

    @Test func byteArrayConversions() throws {
        let bytes = Array(UInt8.min...UInt8.max)
        let kotlin = try bytes.kotlinByteArray
        #expect(kotlin.bytes == bytes)
        #expect(kotlin.data == Data(bytes))
        #expect(try Data().kotlinByteArray.bytes.isEmpty)
        kotlin.set(index: 0, value: -1)
        #expect(bytes[0] == 0)
        #expect(kotlin.bytes[0] == 255)
    }

    @Test func swiftSuspendClosures() async throws {
        let zero = SwiftSuspendFunction0 { "zero" }
        #expect(try await zero() as? String == "zero")
        let one = SwiftSuspendFunction1 { (value: String) in value.uppercased() }
        #expect(try await one("one") as? String == "ONE")
        let two = SwiftSuspendFunction2 { (a: String, b: String) in a + b }
        #expect(try await two("a", "b") as? String == "ab")
        let optional = SwiftSuspendFunction1 { (value: String?) -> String? in value }
        #expect(try await optional(nil) == nil)
        await #expect(throws: (any Error).self) { try await one(KotlinInt(int: 42)) }
        let failing = SwiftSuspendFunction0<String> {
            throw NSError(domain: "test", code: 7)
        }
        await #expect(throws: (any Error).self) { try await failing() }
        let cancelled = SwiftSuspendFunction0<String> { throw CancellationError() }
        await #expect(throws: CancellationError.self) { try await cancelled() }
        let unit = SwiftSuspendFunction0 { () }
        #expect(try await unit() is KotlinUnit)
    }

    @Test func kotlinResultErrors() throws {
        let success = KmmResult<NSString>(value: "ok")
        #expect(try kotlinValue(success) == "ok")
        #expect(try success.swiftResult(as: String.self).get() == "ok")
        #expect(throws: (any Error).self) { try success.swiftResult(as: [String].self).get() }
        let array = KmmResult<NSArray>(value: ["ok"] as NSArray)
        #expect(try array.swiftResult(as: [String].self).get() == ["ok"])
        let empty = KmmResult<NSString>(value: nil)
        #expect(try empty.swiftResult(as: String?.self).get() == nil)
        #expect(throws: (any Error).self) { try empty.swiftResult(as: String.self).get() }
        let failure = KmmResult<NSString>(failure: KotlinIllegalArgumentException(message: "failed"))
        #expect(throws: (any Error).self) { try kotlinValue(failure) }
        #expect(throws: (any Error).self) { try failure.swiftResult(as: String.self).get() }
    }

    @Test func walletServiceDefaults() throws {
        let firstKey = WalletServiceDefaults.keyMaterial
        let secondKey = WalletServiceDefaults.keyMaterial
        #expect(firstKey !== secondKey)
        #expect(WalletServiceDefaults.encryptionService !== WalletServiceDefaults.encryptionService)
        let wallet = WalletServiceAdapter()
        #expect(wallet.service.clientId == "https://wallet.a-sit.at/app")
        let details = try #require(wallet.buildAuthorizationDetails(credentialConfigurationId: "pid").first)
        #expect(details.credentialConfigurationId == "pid")
        #expect(details.locations == nil)

        let custom = WalletServiceAdapter(clientId: "https://custom.example/wallet")
        #expect(custom.service.clientId == "https://custom.example/wallet")
        let servers: Set<String> = ["https://auth.example"]
        let multiple = custom.buildAuthorizationDetails(
            credentialConfigurationIds: ["pid", "mdl"], authorizationServers: servers
        )
        #expect(multiple.count == 2)
        #expect(multiple.allSatisfy { $0.locations == servers })

        let before = ClockAdapter.system.now()
        #expect(ClockAdapter.system.now().compareTo(other: before) >= 0)
    }

    @Test func keyAttestationCallback() async throws {
        func base64url(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let keyMaterial = WalletServiceDefaults.keyMaterial
        let header = base64url(Data(#"{"alg":"ES256"}"#.utf8))
        let payload = base64url(Data("""
            {"iat":0,"nonce":"nonce","attested_keys":[\(keyMaterial.jsonWebKey.serialize())]}
            """.utf8))
        // Parsing fixture only: signature verification belongs to the attestation verifier.
        let signature = base64url(Data(repeating: 1, count: 64))
        let proof = "\(header).\(payload).\(signature)"
        let parsed = try VckSerializer.shared.joseDeserializeKeyAttestationJwt(proof)
        #expect(parsed.payload?.nonce == "nonce")
        #expect(throws: (any Error).self) {
            try VckSerializer.shared.joseDeserializeKeyAttestationJwt("invalid")
        }
        #expect(throws: (any Error).self) {
            try VckSerializer.shared.joseDeserializeKeyAttestationJwt(
                "\(header).\(base64url(Data("{}".utf8))).\(signature)"
            )
        }

        let metadata = try VckSerializer.shared.joseDeserializeIssuerMetadata(Data(#"""
            {"credential_issuer":"https://issuer.example","credential_endpoint":"https://issuer.example/credential",
             "credential_configurations_supported":{"pid":{"format":"dc+sd-jwt","vct":"urn:example:pid",
                "scope":"pid","proof_types_supported":{"attestation":{"proof_signing_alg_values_supported":["ES256"]}}}}}
            """#.utf8))
        let format = try #require(metadata.supportedCredentialConfigurations?["pid"])
        let token = TokenResponseParameters(
            accessToken: "token", refreshToken: nil, tokenType: "Bearer", expires: nil,
            scope: "pid", authorizationPending: nil, interval: nil, authorizationDetails: nil, credentialId: nil
        )
        var calls = 0
        let callback = SwiftSuspendFunction1 { (input: WalletService.KeyAttestationInput) in
            #expect(input.credentialIssuer == "https://issuer.example")
            #expect(input.clientNonce == "nonce")
            calls += 1
            return KmmResult(value: try VckSerializer.shared.joseDeserializeKeyAttestationJwt(proof))
        }
        let wallet = WalletServiceAdapter(keyMaterial: keyMaterial, loadKeyAttestation: callback)
        let requests = try await wallet.createCredential(
            tokenResponse: token, metadata: metadata, credentialFormat: format, clientNonce: "nonce"
        )
        #expect(calls == 1)
        let request = try #require(requests.first as? WalletServiceCredentialRequestPlain)
        #expect(request.request.proofs?.attestation?.first?.description() == proof)
        let invalidCallback = SwiftSuspendFunction1 { (_: WalletService.KeyAttestationInput) in
            KmmResult(value: try VckSerializer.shared.joseDeserializeKeyAttestationJwt("invalid"))
        }
        let invalidWallet = WalletServiceAdapter(loadKeyAttestation: invalidCallback)
        await #expect(throws: (any Error).self) {
            try await invalidWallet.createCredential(tokenResponse: token, metadata: metadata, credentialFormat: format)
        }
    }

    @Test func walletCredentialRequests() async throws {
        let metadata = try VckSerializer.shared.joseDeserializeIssuerMetadata(Data(#"""
            {"credential_issuer":"https://issuer.example","credential_endpoint":"https://issuer.example/credential",
             "credential_configurations_supported":{
                "pid":{"format":"dc+sd-jwt","vct":"urn:example:pid","scope":"pid"},
                "address":{"format":"dc+sd-jwt","vct":"urn:example:address","scope":"address"}}}
            """#.utf8))
        let format = try #require(metadata.supportedCredentialConfigurations?["pid"])
        let token = TokenResponseParameters(
            accessToken: "token", refreshToken: nil, tokenType: "Bearer", expires: nil,
            scope: nil, authorizationPending: nil, interval: nil, authorizationDetails: nil, credentialId: nil
        )
        let wallet = WalletServiceAdapter()
        let requests: [WalletServiceCredentialRequest] = try await wallet.createCredential(
            tokenResponse: token, metadata: metadata, credentialFormat: format,
            previouslyRequestedScope: "pid address"
        )
        #expect(Set(requests.compactMap {
            ($0 as? WalletServiceCredentialRequestPlain)?.request.credentialConfigurationId
        }) == ["pid", "address"])
        await #expect(throws: (any Error).self) {
            try await wallet.createCredential(tokenResponse: token, metadata: metadata, credentialFormat: format)
        }
    }

}
