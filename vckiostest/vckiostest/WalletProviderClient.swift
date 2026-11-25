import CryptoKit
import DeviceCheck
import Foundation
import Security
import VckIos

// Same wallet provider and wallet solution as Valera, see its attestation/Constants.kt.
let walletProviderHost = "https://wallet-provider.a-sit.plus"
private let walletSolutionOid = "2.25.210184084534939142470042512176304499012"
private let wiaKeyTag = Data("at.asitplus.wallet.vckios.wia".utf8)
private let iso18045Moderate = "iso_18045_moderate"
/// The purpose of Signum's App Attest client data, see `IosHomebrewAttestation.ClientData`.
private let appAttestPurpose = "ios app-attest: secure enclave protected key"

/// A Wallet Instance Attestation (WIA) and the Secure Enclave key it binds in `cnf.jwk`.
struct InstanceAttestation {
    let keyMaterial: KeyMaterial
    let jwt: JwsTyped<JwsCompact, JsonWebToken>
    let serialized: String
}

/// Loads a Wallet Instance Attestation and key attestations (WUA) from the wallet provider, as Valera does.
///
/// The WIA binds a fresh Secure Enclave key attested with App Attest, which needs a physical device, and the wallet
/// provider has to accept this app's App ID. Attests the key as Warden Supreme's client does, with signature data
/// authentication: the CSR carries Signum's `ios-appattest` statement and is signed with the attested key.
final class WalletProviderClient {
    private let host: String
    private let session: URLSession

    init(host: String = walletProviderHost, session: URLSession = .shared) {
        var host = host
        while host.hasSuffix("/") { host.removeLast() }
        self.host = host
        self.session = session
    }

    /// Creates a new attested key and returns it with the WIA binding it.
    /// - Parameter preferredClientStatusPeriod: the requested validity of the WIA, in seconds.
    func loadInstanceAttestation(preferredClientStatusPeriod: TimeInterval?) async throws -> InstanceAttestation {
        let challenge = try AttestationChallenge(json: try await get("\(host)/api/v1/challenge"))
        let privateKey = try createSecureEnclaveKey(userPresence: challenge.requiresUserPresence)
        let publicKey = try iosEncodedPublicKey(privateKey)
        var attributes = [
            CsrAttribute(
                oid: walletSolutionOid,
                value: Der.utf8String(try instanceAttestationRequest(preferredClientStatusPeriod))
            ),
            CsrAttribute(
                oid: challenge.proofOid,
                value: Der.utf8String(try await appAttestation(publicKey: publicKey, challenge: challenge.nonce))
            ),
        ]
        if let oid = challenge.genericDeviceNameOid {
            attributes.append(CsrAttribute(oid: oid, value: Der.utf8String(deviceName())))
        }
        let csr = try CertificationRequest.signed(
            serialNumber: challenge.nonce.map { String(format: "%02X", $0) }.joined(),
            publicKey: publicKey,
            attributes: attributes,
            privateKey: privateKey
        )
        let serialized = try await send("\(host)/api/v1/instanceAttestation", contentType: "application/octet-stream", body: csr)
        let keyMaterial = try kotlinValue(
            KeyMaterialAdapter.shared.fromSecKey(privateKey: Unmanaged.passUnretained(privateKey).toOpaque())
        )!
        let jwt = try VckSerializer.shared.joseDeserializeJsonWebTokenJws(serialized)
        guard jwt.payload?.confirmationClaim?.jsonWebKey?.jwkThumbprint == keyMaterial.jsonWebKey.jwkThumbprint else {
            throw WalletProviderError("Instance attestation does not bind the attested key")
        }
        return InstanceAttestation(keyMaterial: keyMaterial, jwt: jwt, serialized: serialized)
    }

    /// Loads a key attestation for `holderKey`, authenticated with the WIA and a proof of possession of its key.
    func loadKeyAttestation(
        instance: InstanceAttestation,
        holderKey: KeyMaterial,
        input: OpenId4VciClient.KeyAttestationInput
    ) async throws -> JwsTyped<JwsCompact, KeyAttestationJwt> {
        let nonceResponse = try JSONSerialization.jsonObject(with: Data(try await get("\(host)/api/v1/nonce").utf8))
        guard let providerNonce = (nonceResponse as? [String: Any])?["c_nonce"] as? String else {
            throw WalletProviderError("Wallet provider sent no c_nonce")
        }
        let pop = try await BuildClientAttestationPoPJwt.shared.invoke(
            signJwt: SignJwt<JsonWebToken>(keyMaterial: instance.keyMaterial, headerModifier: JwsHeaderNone()),
            audience: host,
            nonce: providerNonce,
            randomSource: RandomSource.Secure.shared,
            issuedAt: ClockAdapter.system.now()
        )
        let holderJwk = holderKey.jsonWebKey
        let jwk = try JoseCodec<JsonWebKey>(serializer: JsonWebKey.companion.serializer()).encode(value: holderJwk)
        var request: [String: Any] = [
            "token": instance.serialized,
            "proof": String(describing: pop.jws),
            "keys": [try JSONSerialization.jsonObject(with: jwk)],
            "key_storage": [iso18045Moderate],
            "user_authentication": [iso18045Moderate],
        ]
        if let nonce = input.clientNonce { request["nonce"] = nonce }
        if let period = input.requirements?.preferredTtlSeconds {
            request["preferred_key_storage_status_period"] = period.int64Value
        }
        if let algorithms = input.supportedAlgorithms { request["supported_algorithms"] = algorithms }
        let body = try await send(
            "\(host)/api/v1/keyAttestation",
            contentType: "application/json",
            body: try JSONSerialization.data(withJSONObject: request)
        )
        let keyAttestation = try VckSerializer.shared.joseDeserializeKeyAttestationJwt(body)
        let attestedKeys = try kotlinCollection(keyAttestation.payload?.attestedKeys)?.compactMap { $0 as? JsonWebKey }
        guard attestedKeys?.first?.jwkThumbprint == holderJwk.jwkThumbprint else {
            throw WalletProviderError("Key attestation does not attest the holder key")
        }
        return keyAttestation
    }

    /// Replaces the key of a previous WIA, if any.
    private func createSecureEnclaveKey(userPresence: Bool) throws -> SecKey {
        SecItemDelete([kSecClass: kSecClassKey, kSecAttrApplicationTag: wiaKeyTag] as CFDictionary)
        var flags: SecAccessControlCreateFlags = .privateKeyUsage
        if userPresence { flags.insert(.userPresence) }
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, flags, &error
        ) else { throw error!.takeRetainedValue() }
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256,
            kSecAttrTokenID: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs: [
                kSecAttrIsPermanent: true,
                kSecAttrApplicationTag: wiaKeyTag,
                kSecAttrAccessControl: access,
            ] as [CFString: Any],
        ]
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw error!.takeRetainedValue()
        }
        return key
    }

    /// The uncompressed point (ANSI X9.63), as `CryptoPublicKey.iosEncoded` in Signum.
    private func iosEncodedPublicKey(_ privateKey: SecKey) throws -> Data {
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw WalletProviderError("Secure Enclave key has no public key")
        }
        var error: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw error!.takeRetainedValue()
        }
        return data
    }

    /// Signum's `IosHomebrewAttestation` as JSON: an App Attest attestation over the hash of client data that binds the
    /// Secure Enclave key to the challenge. Warden hashes the client data as sent, so its formatting is free.
    private func appAttestation(publicKey: Data, challenge: Data) async throws -> String {
        let service = DCAppAttestService.shared
        guard service.isSupported else {
            throw WalletProviderError("App Attest is not supported on this device, e.g. in the Simulator")
        }
        let clientData = Data("""
            {"purpose":"\(appAttestPurpose)","publicKey":"\(publicKey.base64Url)","challenge":"\(challenge.base64Url)"}
            """.utf8)
        let keyId = try await service.generateKey()
        let attestation = try await service.attestKey(keyId, clientDataHash: Data(SHA256.hash(data: clientData)))
        // The class discriminator comes first, as kotlinx.serialization writes it.
        return """
            {"typ":"ios-appattest","attestation":"\(attestation.base64Url)","clientDataJSON":"\(clientData.base64Url)"}
            """
    }

    /// The WIA request the wallet provider reads from the CSR, as Valera's `InstanceAttestationRequest`.
    private func instanceAttestationRequest(_ preferredClientStatusPeriod: TimeInterval?) throws -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        var request: [String: Any] = ["versionName": version]
        if let period = preferredClientStatusPeriod {
            // kotlin.time.Duration as ISO 8601, as kotlinx.serialization encodes it
            request["preferredClientStatusPeriod"] = "PT\(Int64(period))S"
        }
        return String(decoding: try JSONSerialization.data(withJSONObject: request), as: UTF8.self)
    }

    /// The model identifier, e.g. `iPhone15,3`, as Warden Supreme's client sends it.
    private func deviceName() -> String {
        var info = utsname()
        guard uname(&info) == 0 else { return "iPhone" }
        return withUnsafeBytes(of: info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }

    private func get(_ url: String) async throws -> String {
        try await send(url, contentType: nil, body: nil)
    }

    private func send(_ urlString: String, contentType: String?, body: Data?) async throws -> String {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = body == nil ? "GET" : "POST"
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(decoding: data, as: UTF8.self)
        guard status == 200 else { throw WalletProviderError("Wallet provider answered \(status) for \(urlString): \(text)") }
        return text
    }
}

/// The parts of Warden Supreme's `AttestationChallenge` this client uses. Fails for what it does not support, rather
/// than sending a CSR the wallet provider would reject.
struct AttestationChallenge {
    let nonce: Data
    let proofOid: String
    let genericDeviceNameOid: String?
    let requiresUserPresence: Bool

    init(json: String, now: Date = Date()) throws {
        guard let challenge = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let issuedAt = (challenge["issuedAt"] as? NSNumber)?.doubleValue,
              let validity = (challenge["validity"] as? NSNumber)?.doubleValue,
              let nonce = (challenge["nonce"] as? String).flatMap(Data.init(base64Url:)),
              let proofOid = challenge["proofOID"] as? String
        else { throw WalletProviderError("Malformed attestation challenge") }
        // Warden sends `issuedAt` in epoch milliseconds, but `validity` in seconds
        let validFrom = Date(timeIntervalSince1970: issuedAt / 1000)
        let validUntil = validFrom.addingTimeInterval(validity)
        guard validFrom <= now, now <= validUntil else {
            throw WalletProviderError("System time off: challenge valid \(validFrom)..\(validUntil), local time \(now)")
        }
        if let dataAuth = challenge["dataAuth"] as? [String: Any], dataAuth["type"] as? String != "SIGNATURE" {
            throw WalletProviderError("Unsupported data authentication \(dataAuth), only SIGNATURE is implemented")
        }
        if let attributes = challenge["toBeAttestedAttributes"], !(attributes is NSNull) {
            throw WalletProviderError("Attesting client-provided attributes is not implemented")
        }
        let constraints = challenge["keyConstraints"] as? [String: Any]
        if let algorithm = constraints?["algorithmParameters"] as? [String: Any] {
            guard algorithm["type"] as? String == "EC",
                  (algorithm["curve"] as? String).map({ $0 == "P-256" }) ?? true
            else { throw WalletProviderError("Unsupported key \(algorithm), the Secure Enclave only holds P-256 keys") }
        }
        let protection = constraints?["keyProtection"] as? [String: Any]
        self.nonce = nonce
        self.proofOid = proofOid
        genericDeviceNameOid = challenge["genericDeviceNameOID"] as? String
        requiresUserPresence = protection?["biometry"] as? Bool == true || protection?["deviceLock"] as? Bool == true
    }
}

struct WalletProviderError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

extension Data {
    /// Base64url without padding, as Signum's `Base64UrlStrict`.
    var base64Url: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64Url: String) {
        var base64 = base64Url.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}
