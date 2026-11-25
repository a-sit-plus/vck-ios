import Foundation
import vck_ios

// Same client as Valera, which the A-SIT Plus demo issuer knows.
private let clientId = "https://wallet.a-sit.plus/app"
let issuanceCallback = "asitplus-wallet://wallet.a-sit.plus/app/callback/provisioning"

/// Minimal stateful wallet for a single issue-then-present demo run, written against VC-K's Swift package only.
///
/// Issuance proves possession of the holder key with a plain JWT proof. It sends no Wallet Instance Attestation and no
/// key attestations, so it only works with issuers that do not require them.
@MainActor
final class DemoWallet {
    let keyMaterial: KeyMaterial
    let holder: HolderAgent
    private let session: URLSession

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
        holder = HolderAgentBuilder(keyMaterial: keyMaterial, subjectCredentialStore: subjectCredentialStore).build()
        issuancePolicy = try ValidationPolicy.create(
            trust: TrustPolicyIntegrityOnly.shared, status: StatusPolicySkip.shared,
            timeLeeway: 5 * 60, requireTimeliness: true
        )
    }

    private func protocolClient() -> OpenId4VciProtocolClient {
        OpenId4VciClientAdapter(clientId: clientId, proofCreators: [JwtProofCreator(keyMaterial: keyMaterial)])
            .protocolClient(redirectUrl: issuanceCallback)
    }

    /// Starts the authorization for the issuer's first advertised credential, e.g. the PID SD-JWT on the A-SIT Plus
    /// demo issuer, and returns the URL to open in the browser.
    func startIssuance(issuer: String) async throws -> String {
        let normalized = issuer.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard normalized.hasPrefix("https://") else { throw DemoWalletError("Issuer must be an HTTPS URL") }
        let vci = protocolClient()
        let issuerMetadata = try await vci.loadIssuerMetadata(credentialIssuer: normalized)
            .run(as: IssuerMetadata.self, session: session)
        guard let credential = try vci.parseCredentialMetadata(issuerMetadata: issuerMetadata, issuer: nil)
            .swiftResult(as: [CredentialIdentifierInfo].self).get().first
        else { throw DemoWalletError("Issuer advertises no credentials") }
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
