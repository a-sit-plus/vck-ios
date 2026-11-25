//
//  vckiostestTests.swift
//  vckiostestTests
//
//  Created by Bernd Prünster on 22.07.26.
//

import Testing
import Foundation
import VckIos

private let issuerMetadataCodec = JoseCodec<IssuerMetadata>(serializer: IssuerMetadata.companion.serializer())

struct vckiostestTests {

    @Test func tokenResponseDefaults() {
        let token = TokenResponseParameters(accessToken: "token", tokenType: "Bearer")
        #expect(token.accessToken == "token")
        #expect(token.tokenType == "Bearer")
        #expect(token.refreshToken == nil)
        #expect(token.expires == nil)
        #expect(token.scope == nil)
        #expect(token.authorizationPending == nil)
        #expect(token.interval == nil)
        #expect(token.authorizationDetails == nil)
        #expect(token.credentialId == nil)

        let custom = TokenResponseParameters(
            accessToken: "custom", tokenType: "DPoP", refreshToken: "refresh",
            scope: "pid", authorizationPending: KotlinBoolean(bool: false),
            authorizationDetails: [], credentialId: "credential"
        )
        #expect(custom.accessToken == "custom")
        #expect(custom.tokenType == "DPoP")
        #expect(custom.refreshToken == "refresh")
        #expect(custom.scope == "pid")
        #expect(custom.authorizationPending?.boolValue == false)
        #expect(custom.authorizationDetails?.isEmpty == true)
        #expect(custom.credentialId == "credential")
    }

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

    @Test func oauth2ExceptionFromError() throws {
        let nonce = OAuth2Exception.InvalidNonce(description: "stale nonce", cause: nil)
        do {
            _ = try kotlinValue(KmmResult<NSString>(failure: nonce))
            Issue.record("Expected an error")
        } catch {
            let exception = try #require(error.oauth2Exception)
            #expect(exception is OAuth2Exception.InvalidNonce)
            #expect(exception.error == "invalid_nonce")
            #expect(exception.errorDescription == "stale nonce")
        }
        do {
            _ = try kotlinValue(KmmResult<NSString>(failure: KotlinIllegalStateException(message: "wrapped", cause: nonce)))
            Issue.record("Expected an error")
        } catch {
            #expect(error.kotlinThrowable is KotlinIllegalStateException)
            #expect(error.oauth2Exception?.error == "invalid_nonce")
        }
        #expect(NSError(domain: "test", code: 1).oauth2Exception == nil)
    }

    @Test func openId4VciClientDefaults() throws {
        let firstKey = OpenId4VciClientDefaults.keyMaterial
        let secondKey = OpenId4VciClientDefaults.keyMaterial
        #expect(firstKey !== secondKey)
        #expect(OpenId4VciClientDefaults.encryptionService !== OpenId4VciClientDefaults.encryptionService)
        let wallet = OpenId4VciClientAdapter(proofCreators: [JwtProofCreator(keyMaterial: firstKey)])
        #expect(wallet.clientId == "https://wallet.a-sit.at/app")
        let details = try #require(wallet.buildAuthorizationDetails(credentialConfigurationId: "pid").first)
        #expect(details.credentialConfigurationId == "pid")
        #expect(details.locations == nil)

        let custom = OpenId4VciClientAdapter(clientId: "https://custom.example/wallet", proofCreators: [])
        #expect(custom.clientId == "https://custom.example/wallet")
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
        let keyMaterial = OpenId4VciClientDefaults.keyMaterial
        let header = base64url(Data(#"{"alg":"ES256"}"#.utf8))
        let jwkCodec = JoseCodec<JsonWebKey>(serializer: JsonWebKey.companion.serializer())
        let jwk = try jwkCodec.encode(value: keyMaterial.jsonWebKey)
        #expect(try jwkCodec.decode(data: jwk) == keyMaterial.jsonWebKey)
        let payload = base64url(Data("""
            {"iat":0,"nonce":"nonce","attested_keys":[\(String(decoding: jwk, as: UTF8.self))]}
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

        let metadata = try issuerMetadataCodec.decode(data: Data(#"""
            {"credential_issuer":"https://issuer.example","credential_endpoint":"https://issuer.example/credential",
             "credential_configurations_supported":{"pid":{"format":"dc+sd-jwt","vct":"urn:example:pid",
                "scope":"pid","proof_types_supported":{"attestation":{"proof_signing_alg_values_supported":["ES256"]}}}}}
            """#.utf8))
        let format = try #require(metadata.supportedCredentialConfigurations["pid"])
        let token = TokenResponseParameters(
            accessToken: "token", refreshToken: nil, tokenType: "Bearer", expires: nil,
            scope: "pid", authorizationPending: nil, interval: nil, authorizationDetails: nil, credentialId: nil
        )
        var calls = 0
        let callback = SwiftSuspendFunction1 { (input: OpenId4VciClient.KeyAttestationInput) in
            #expect(input.credentialIssuer == "https://issuer.example")
            #expect(input.clientNonce == "nonce")
            calls += 1
            return KmmResult(value: try VckSerializer.shared.joseDeserializeKeyAttestationJwt(proof))
        }
        let wallet = OpenId4VciClientAdapter(proofCreators: [
            JwtProofCreator(keyMaterial: keyMaterial, loadKeyAttestation: callback),
            AttestationProofCreator(loadKeyAttestation: callback),
        ])
        let requests = try await wallet.createCredential(
            tokenResponse: token, metadata: metadata, credentialFormat: format, clientNonce: "nonce"
        )
        #expect(calls == 1)
        let request = try #require(requests.first as? OpenId4VciClientCredentialRequestPlain)
        #expect(request.request.proofs?.attestation?.first?.description() == proof)
        let invalidCallback = SwiftSuspendFunction1 { (_: OpenId4VciClient.KeyAttestationInput) in
            KmmResult(value: try VckSerializer.shared.joseDeserializeKeyAttestationJwt("invalid"))
        }
        let invalidWallet = OpenId4VciClientAdapter(proofCreators: [
            JwtProofCreator(keyMaterial: OpenId4VciClientDefaults.keyMaterial, loadKeyAttestation: invalidCallback),
            AttestationProofCreator(loadKeyAttestation: invalidCallback),
        ])
        await #expect(throws: (any Error).self) {
            try await invalidWallet.createCredential(tokenResponse: token, metadata: metadata, credentialFormat: format)
        }
    }

    @Test func walletCredentialRequests() async throws {
        let metadata = try issuerMetadataCodec.decode(data: Data(#"""
            {"credential_issuer":"https://issuer.example","credential_endpoint":"https://issuer.example/credential",
             "credential_configurations_supported":{
                "pid":{"format":"dc+sd-jwt","vct":"urn:example:pid","scope":"pid"},
                "address":{"format":"dc+sd-jwt","vct":"urn:example:address","scope":"address"}}}
            """#.utf8))
        let format = try #require(metadata.supportedCredentialConfigurations["pid"])
        let token = TokenResponseParameters(
            accessToken: "token", refreshToken: nil, tokenType: "Bearer", expires: nil,
            scope: nil, authorizationPending: nil, interval: nil, authorizationDetails: nil, credentialId: nil
        )
        let wallet = OpenId4VciClientAdapter(proofCreators: [JwtProofCreator(keyMaterial: OpenId4VciClientDefaults.keyMaterial)])
        let requests: [OpenId4VciClientCredentialRequest] = try await wallet.createCredential(
            tokenResponse: token, metadata: metadata, credentialFormat: format,
            previouslyRequestedScope: "pid address"
        )
        // Since VC-K 9, only the selected format is requested, even if the scope grants more.
        #expect(requests.compactMap {
            ($0 as? OpenId4VciClientCredentialRequestPlain)?.request.credentialConfigurationId
        } == ["pid"])
        await #expect(throws: (any Error).self) {
            try await wallet.createCredential(
                tokenResponse: token, metadata: metadata, credentialFormat: format,
                previouslyRequestedScope: "address"
            )
        }
        await #expect(throws: (any Error).self) {
            try await wallet.createCredential(tokenResponse: token, metadata: metadata, credentialFormat: format)
        }
    }

    @Test func preparedCredentialRequests() async throws {
        let metadata = try issuerMetadataCodec.decode(data: Data(#"""
            {"credential_issuer":"https://issuer.example","credential_endpoint":"https://issuer.example/credential",
             "credential_configurations_supported":{
                "pid":{"format":"dc+sd-jwt","vct":"urn:example:pid","scope":"pid",
                    "proof_types_supported":{"jwt":{"proof_signing_alg_values_supported":["ES256"]}}},
                "address":{"format":"dc+sd-jwt","vct":"urn:example:address","scope":"address"}}}
            """#.utf8))
        let pid = try #require(metadata.supportedCredentialConfigurations["pid"])
        let address = try #require(metadata.supportedCredentialConfigurations["address"])
        let token = TokenResponseParameters(accessToken: "token", tokenType: "Bearer", scope: "pid address")
        let wallet = OpenId4VciClientAdapter(
            clientId: "https://custom.example/wallet",
            proofCreators: [JwtProofCreator(keyMaterial: OpenId4VciClientDefaults.keyMaterial)]
        )

        let all = try wallet.prepareCredentialRequests(tokenResponse: token, metadata: metadata)
        #expect(Set(all.map(\.credentialConfigurationId)) == ["pid", "address"])
        let selected = try wallet.prepareCredentialRequests(
            tokenResponse: token, metadata: metadata, credentialFormats: [pid]
        )
        #expect(selected.map(\.credentialConfigurationId) == ["pid"])
        #expect(throws: (any Error).self) {
            try wallet.prepareCredentialRequests(
                tokenResponse: TokenResponseParameters(accessToken: "token", tokenType: "Bearer", scope: "pid"),
                metadata: metadata, credentialFormats: [address]
            )
        }
        let byId = try wallet.prepareCredentialRequests(credentialConfigurationIds: ["address"], metadata: metadata)
        #expect(byId.map(\.credentialConfigurationId) == ["address"])
        #expect(throws: (any Error).self) {
            try wallet.prepareCredentialRequests(credentialConfigurationIds: ["unknown"], metadata: metadata)
        }

        // Each prepared request gets its own nonce; the jwt proof comes from the proof creator.
        let prepared = try #require(selected.first)
        let request = try await wallet.createCredential(request: prepared, metadata: metadata, clientNonce: "nonce-1")
        let plain = try #require(request as? OpenId4VciClientCredentialRequestPlain)
        #expect(plain.request.credentialConfigurationId == "pid")
        #expect(plain.request.proofs?.jwt?.count == 1)

        // Every credential of a batch is reported, also one that can not be decoded; nothing is validated here,
        // so any string passes as an SD-JWT until its storage is prepared.
        let received = try await wallet.decodeCredentialResponse(
            response: #"{"credentials":[{"credential":"not-an-sd-jwt"},{"credential":{"not":"a string"}}]}"#,
            isEncrypted: false, request: request, representation: .sdJwt
        )
        #expect(received.count == 2)
        #expect(received.first is ReceivedCredentialDecoded)
        #expect(received.last is ReceivedCredentialUndecodable)
        // A plain request must not get an encrypted response.
        await #expect(throws: (any Error).self) {
            try await wallet.decodeCredentialResponse(
                response: "a.b.c.d.e", isEncrypted: true, request: request, representation: .sdJwt
            )
        }

        let withoutToken = try await wallet.createCredential(metadata: metadata, credentialConfigurationId: "address")
        let plainWithoutToken = try #require(withoutToken as? OpenId4VciClientCredentialRequestPlain)
        #expect(plainWithoutToken.request.credentialConfigurationId == "address")
        #expect(plainWithoutToken.request.proofs == nil)
        await #expect(throws: (any Error).self) {
            try await wallet.createCredential(metadata: metadata, credentialConfigurationId: "unknown")
        }

        // Without a matching proof creator, a credential that requires proofs can not be requested.
        let noProofs = OpenId4VciClientAdapter(proofCreators: [])
        await #expect(throws: (any Error).self) {
            try await noProofs.createCredential(metadata: metadata, credentialConfigurationId: "pid")
        }
    }

    @Test func protocolClientFactories() async throws {
        let oauth2 = OAuth2Client.create(clientId: "https://custom.example/wallet")
        #expect(oauth2.clientId == "https://custom.example/wallet")
        #expect(oauth2.redirectUrl == "https://custom.example/wallet/callback")
        #expect(oauth2.signPushedAuthorizationRequest != nil)
        let unsigned = OAuth2Client.create(redirectUrl: "app://callback", signPushedAuthorizationRequest: nil)
        #expect(unsigned.redirectUrl == "app://callback")
        #expect(unsigned.signPushedAuthorizationRequest == nil)
        #expect(OpenId4VciProtocolClientDefaults.dpopKeyMaterial !== OpenId4VciProtocolClientDefaults.dpopKeyMaterial)

        _ = try IssuerMetadataValidator.create()
        #expect(throws: (any Error).self) { try IssuerMetadataValidator.create(maxRegistrationValidity: .nan) }

        let wallet = OpenId4VciClientAdapter(
            clientId: "https://custom.example/wallet",
            proofCreators: [JwtProofCreator(keyMaterial: OpenId4VciClientDefaults.keyMaterial)]
        )
        let client = wallet.protocolClient()
        #expect(client.vciClient === wallet.client)
        #expect(client.oauth2Client.oAuth2Client.clientId == wallet.clientId)
        #expect(client.oauth2Client.oAuth2Client.redirectUrl == "https://custom.example/wallet/callback")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IssuerMetadataURLProtocol.self]
        let metadata = try await client.loadIssuerMetadata(credentialIssuer: "https://issuer.example")
            .run(as: IssuerMetadata.self, session: URLSession(configuration: configuration))
        #expect(metadata.credentialIssuer == "https://issuer.example")
        #expect(metadata.supportedCredentialConfigurations["pid"] != nil)
    }

    @Test func validationFactories() throws {
        let policy = try ValidationPolicy.create(
            trust: TrustPolicyIntegrityOnly.shared, status: StatusPolicySkip.shared,
            timeLeeway: 300, requireTimeliness: true
        )
        #expect(policy.timeLeewayMilliseconds == 300_000)
        #expect(policy.registration is RegistrationPolicyRequire)
        #expect(throws: (any Error).self) {
            try ValidationPolicy.create(
                trust: TrustPolicyIntegrityOnly.shared, status: StatusPolicySkip.shared,
                timeLeeway: -1, requireTimeliness: true
            )
        }
        _ = CredentialValidator.create()
        _ = CredentialValidator.create(
            statusValidator: .create(zlibService: DefaultZlibService()),
            clock: ClockAdapter.system, requiredClaimsResolver: RequiredClaimsResolverDefault.shared
        )
        _ = try RelyingPartyValidator.create(trust: .create(), statusValidator: .create())
        _ = try RelyingPartyValidator.create(clock: ClockAdapter.system)
        _ = try IssuerMetadataValidator.create(clock: ClockAdapter.system)
    }

    @Test func httpExchangeRunner() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = OpenId4VpProtocolClient(openId4VpHolder: OpenId4VpHolderBuilder().build())
        let post = AuthenticationResponseResult.Post(
            url: "https://verifier.example/response", params: ["vp_token": "token"]
        )

        StubURLProtocol.response = (200, Data(#"{"redirect_uri":"https://verifier.example/done"}"#.utf8))
        let redirect = try await client.sendAuthorizationResponse(response: post)
            .run(as: String?.self, session: session)
        #expect(redirect == "https://verifier.example/done")
        let request = try #require(StubURLProtocol.request)
        #expect(request.url?.absoluteString == "https://verifier.example/response")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        #expect(StubURLProtocol.body.map { String(decoding: $0, as: UTF8.self) } == "vp_token=token")

        StubURLProtocol.response = (302, Data())
        await #expect(throws: (any Error).self) {
            try await client.sendAuthorizationResponse(response: post).run(as: String?.self, session: session)
        }
    }
}

/// Answers every request with `response`; only used by `httpExchangeRunner`, which runs its cases in sequence.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var response: (status: Int, body: Data) = (200, Data())
    nonisolated(unsafe) static var request: URLRequest?
    nonisolated(unsafe) static var body: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.request = request
        Self.body = request.httpBodyStream.map { stream in
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            return data
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: Self.response.status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Serves issuer metadata for `protocolClientFactories`, separate from `StubURLProtocol` as tests run in parallel.
final class IssuerMetadataURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Data(#"""
            {"credential_issuer":"https://issuer.example","credential_endpoint":"https://issuer.example/credential",
             "credential_configurations_supported":{"pid":{"format":"dc+sd-jwt","vct":"urn:example:pid"}}}
            """#.utf8)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
