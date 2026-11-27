import Foundation
import VckIos

// Same client as Valera, which the A-SIT Plus demo issuer and wallet provider know.
private let clientId = "https://wallet.a-sit.plus/app"
let issuanceCallback = "asitplus-wallet://wallet.a-sit.plus/app/callback/provisioning"
/// The PID in SD-JWT format, as the demo RP's remote presentation case 1 requests it.
let pidSdJwtConfigurationId = "urn:eudi:pid:1#dc+sd-jwt"
/// Requested validity of the WIA and of key attestations, as in Valera.
private let preferredStatusPeriod: TimeInterval = 31 * 24 * 60 * 60

/// Minimal stateful wallet for a single issue-then-present demo run, written against VC-K's Swift package only.
///
/// Issuance authenticates the client with a fresh Wallet Instance Attestation (OAuth 2.0 Attestation-Based Client
/// Authentication), whose key also binds DPoP, and proves possession of the holder key with key attestations from the
/// wallet provider, see `WalletProviderClient`.
@MainActor
final class DemoWallet {
    let keyMaterial: KeyMaterial
    let holder: HolderAgent
    private let session: URLSession
    private let walletProvider: WalletProviderClient

    /// The demo configures no trust anchors and no status list resolver.
    private let issuancePolicy: ValidationPolicy

    /// One issuance flow: its context, and the client that keeps the PKCE and DPoP state of the flow, so
    /// `finishIssuance` has to use the same instance. Persist `context` with
    /// `JoseCodec<ProvisioningContext>` to resume after the app was killed.
    private struct PendingIssuance {
        let context: ProvisioningContext
        let client: OpenId4VciProtocolClient
    }
    private var pending: PendingIssuance?

    init(keyMaterial: KeyMaterial, subjectCredentialStore: SubjectCredentialStore, session: URLSession = .shared) throws {
        self.keyMaterial = keyMaterial
        self.session = session
        walletProvider = WalletProviderClient(session: session)
        holder = HolderAgentBuilder(keyMaterial: keyMaterial, subjectCredentialStore: subjectCredentialStore).build()
        issuancePolicy = try ValidationPolicy.create(
            trust: TrustPolicyIntegrityOnly.shared, status: StatusPolicySkip.shared,
            timeLeeway: 5 * 60, requireTimeliness: true
        )
    }

    /// The client for one issuance flow, authenticated with a fresh WIA, which keeps the DPoP and attestation challenge
    /// state of the flow.
    private func protocolClient() async throws -> OpenId4VciProtocolClient {
        let walletProvider = self.walletProvider
        let holderKey = keyMaterial
        let instance = try await walletProvider.loadInstanceAttestation(
            preferredClientStatusPeriod: preferredStatusPeriod
        )
        let loadKeyAttestation = SwiftSuspendFunction1 { (input: OpenId4VciClient.KeyAttestationInput) in
            do {
                return KmmResult(value: try await walletProvider.loadKeyAttestation(
                    instance: instance, holderKey: holderKey, input: input
                ))
            } catch {
                return KmmResult(failure: SwiftErrorBridge.shared.fromError(error: error as NSError))
            }
        }
        let clientAttestation = ClientAttestation(
            keyMaterial: instance.keyMaterial,
            loadInstanceAttestation: SwiftSuspendFunction1 { (_: OAuth2ProtocolClient.LoadInstanceAttestationInput) in
                KmmResult(value: instance.jwt)
            }
        )
        return OpenId4VciClientAdapter(clientId: clientId, proofCreators: [
            JwtProofCreator(keyMaterial: holderKey, loadKeyAttestation: loadKeyAttestation),
            AttestationProofCreator(loadKeyAttestation: loadKeyAttestation),
        ]).protocolClient(redirectUrl: issuanceCallback, clientAttestation: clientAttestation)
    }

    /// Starts the authorization for the credential configuration `credentialConfigurationId`, by default the PID in
    /// SD-JWT format, and returns the URL to open in the browser.
    func startIssuance(issuer: String, credentialConfigurationId: String = pidSdJwtConfigurationId) async throws -> String {
        let normalized = issuer.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard normalized.hasPrefix("https://") else { throw DemoWalletError("Issuer must be an HTTPS URL") }
        let vci = try await protocolClient()
        let issuerMetadata = try await vci.loadIssuerMetadata(credentialIssuer: normalized)
            .run(as: IssuerMetadata.self, session: session)
        let credentials = try vci.parseCredentialMetadata(issuerMetadata: issuerMetadata, issuer: nil)
            .swiftResult(as: [CredentialIdentifierInfo].self).get()
        guard let credential = credentials.first(where: { $0.credentialIdentifier == credentialConfigurationId }) else {
            throw DemoWalletError("Issuer does not advertise \(credentialConfigurationId), only "
                + credentials.map(\.credentialIdentifier).joined(separator: ", "))
        }
        let authorizationServer = vci.selectAuthorizationServer(issuerMetadata: issuerMetadata, credentialIssuer: normalized)
        let oauthMetadata = try await vci.oauth2Client.loadAuthorizationServerMetadata(authorizationServer: authorizationServer)
            .run(as: OAuth2AuthorizationServerMetadata.self, session: session)
        let authorization = try await vci.oauth2Client.startAuthorization(
            oauthMetadata: oauthMetadata,
            authorizationServer: authorizationServer,
            state: UUID().uuidString.lowercased(),
            issuerState: nil,
            authorizationDetails: authorizationDetails(credential),
            scope: credential.supportedCredentialFormat.scope,
            issuerMetadata: issuerMetadata
        ).run(as: OAuth2ProtocolClient.OpenUrlForAuthnRequest.self, session: session)
        pending = PendingIssuance(
            context: ProvisioningContext(
                state: authorization.state,
                credential: credential,
                credentials: [credential],
                oauthMetadata: oauthMetadata,
                issuerMetadata: issuerMetadata,
                reissuingStoreEntryId: nil
            ),
            client: vci
        )
        return authorization.url
    }

    /// Requests the token with the authorization code in `callbackUrl`, then the credential, validates and stores
    /// it, and returns the number of stored credentials.
    func finishIssuance(callbackUrl: String) async throws -> Int {
        guard let pending else { throw DemoWalletError("No issuance is pending") }
        let context = pending.context
        let vci = pending.client
        let format = context.credential.supportedCredentialFormat
        let token = try await vci.oauth2Client.requestTokenWithAuthCode(
            oauthMetadata: context.oauthMetadata,
            url: callbackUrl,
            authorizationServer: context.oauthMetadata.issuer,
            state: context.state,
            scope: format.scope,
            authorizationDetails: authorizationDetails(context.credential),
            issuerMetadata: context.issuerMetadata
        ).run(as: TokenResponseWithDpopNonce.self, session: session).params
        guard let scheme = try await vci.resolveCredentialScheme(credentialFormat: format) else {
            throw DemoWalletError("Unknown credential scheme in \(format)")
        }
        let renewalInfo = CredentialRenewalInfo(
            refreshToken: token.refreshToken,
            issuerMetadata: context.issuerMetadata,
            oauthMetadata: context.oauthMetadata,
            credentialFormat: format,
            credentialIdentifier: context.credential.credentialIdentifier
        )
        let requests = try vci.prepareCredentialRequests(
            metadata: context.issuerMetadata,
            tokenResponse: token,
            // `NSSet<id<SupportedCredentialFormat>>` imports as `Set<AnyHashable>`; Kotlin objects are `NSObject`s
            credentialFormats: [format as! NSObject],
            previouslyRequestedScope: format.scope
        ).swiftResult(as: [OpenId4VciClient.PreparedCredentialRequest].self).get()
        for request in requests {
            let received = try await requestCredential(
                vci, request: request, issuerMetadata: context.issuerMetadata, token: token
            )
            for credential in received {
                let prepared = try await credential.prepareCredentialStorage(
                    holder: holder, scheme: scheme, policy: issuancePolicy, renewalInfo: renewalInfo
                ).swiftResult(as: PreparedCredentialStorage.self).get()
                let stored = try await holder.storeAccepted(prepared: prepared)
                    .swiftResult(as: CredentialStorageResult.self).get()
                guard stored.storedEntry != nil else {
                    throw DemoWalletError("Credential rejected: \(prepared.validation)")
                }
            }
        }
        self.pending = nil
        return try await credentialCount()
    }

    func credentialCount() async throws -> Int {
        try kotlinCollection(await holder.getCredentials())?.count ?? 0
    }

    /// Fetches a fresh `c_nonce` for the request, and retries once if the issuer rejects it.
    private func requestCredential(
        _ vci: OpenId4VciProtocolClient,
        request: OpenId4VciClient.PreparedCredentialRequest,
        issuerMetadata: IssuerMetadata,
        token: TokenResponseParameters,
        retryOnInvalidNonce: Bool = true
    ) async throws -> [ReceivedCredential] {
        let clientNonce = try await vci.nonceRequest(issuerMetadata: issuerMetadata)?
            .run(as: String.self, session: session)
        let credentialRequest = try await vci.createCredential(
            request: request, metadata: issuerMetadata, clientNonce: clientNonce
        ).swiftResult(as: OpenId4VciClientCredentialRequest.self).get()
        do {
            return try await vci.credentialRequest(
                request: credentialRequest, issuerMetadata: issuerMetadata, tokenResponse: token,
                credentialFormat: request.credentialFormat
            ).run(as: [ReceivedCredential].self, session: session)
        } catch let error where retryOnInvalidNonce
            && error.kotlinThrowable.map({ vci.isInvalidNonce(throwable: $0) }) == true {
            return try await requestCredential(
                vci, request: request, issuerMetadata: issuerMetadata, token: token, retryOnInvalidNonce: false
            )
        }
    }

    private func authorizationDetails(_ credential: CredentialIdentifierInfo) -> Set<OpenIdAuthorizationDetails> {
        OpenId4VciClientAdapter(clientId: clientId, proofCreators: []).buildAuthorizationDetails(
            credentialConfigurationId: credential.credentialIdentifier,
            authorizationServers: credential.issuerMetadata.authorizationServers
        )
    }
}

struct DemoWalletError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

/// Kotlin's `Collection` (unlike `List` and `Set`) reaches Swift untyped, as `Any`: an `NSArray` for lists, or an
/// `NSSet` for sets.
func kotlinCollection(_ value: Any?) throws -> [Any]? {
    switch value {
    case nil: return nil
    case let list as NSArray: return list as [AnyObject]
    case let set as NSSet: return set.allObjects
    case let other?: throw DemoWalletError("Expected a Kotlin collection, got \(type(of: other))")
    }
}
