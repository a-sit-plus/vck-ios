import Foundation

public enum WalletServiceDefaults {
    private static var shared: WalletServiceDefaultsBridge { WalletServiceDefaultsBridge.shared }
    public static var keyMaterial: KeyMaterial { shared.keyMaterial }
    public static var encryptionService: WalletEncryptionService { shared.encryptionService }
    public static var remoteResourceRetriever: KotlinSuspendFunction1 { shared.remoteResourceRetriever }
    public static var selectProofJwtKeyBinding: KotlinSuspendFunction1 { shared.selectProofJwtKeyBinding }
}

public enum ClockAdapter {
    private static var shared: ClockAdapterBridge { ClockAdapterBridge.shared }
    public static var system: KotlinClock { shared.system }
}

/// Native Swift defaults, bundled into the framework by SKIE.
public struct WalletServiceAdapter {
    public let service: OpenId4VciClient
    /// Default `client_id` (issuer of proof JWTs) for `createCredential`.
    public let clientId: String

    /// Builds the proof creators as VC-K's deprecated key-material constructor did:
    /// a JWT proof, plus an attestation proof when `loadKeyAttestation` is set.
    public init(
        clientId: String = "https://wallet.a-sit.at/app",
        keyMaterial: KeyMaterial = WalletServiceDefaults.keyMaterial,
        remoteResourceRetriever: KotlinSuspendFunction1 = WalletServiceDefaults.remoteResourceRetriever,
        encryptionService: WalletEncryptionService = WalletServiceDefaults.encryptionService,
        loadKeyAttestation: KotlinSuspendFunction1? = nil,
        selectProofJwtKeyBinding: KotlinSuspendFunction1 = WalletServiceDefaults.selectProofJwtKeyBinding,
        clock: KotlinClock = ClockAdapter.system
    ) {
        var proofCreators: [ProofCreator] = [JwtProofCreator(
            keyMaterial: keyMaterial,
            loadKeyAttestation: loadKeyAttestation,
            selectProofJwtKeyBinding: selectProofJwtKeyBinding,
            clock: clock
        )]
        if let loadKeyAttestation {
            proofCreators.append(AttestationProofCreator(loadKeyAttestation: loadKeyAttestation))
        }
        self.init(
            clientId: clientId,
            remoteResourceRetriever: remoteResourceRetriever,
            encryptionService: encryptionService,
            proofCreators: proofCreators
        )
    }

    /// The first proof creator accepted by the issuer for a credential is used.
    public init(
        clientId: String = "https://wallet.a-sit.at/app",
        remoteResourceRetriever: KotlinSuspendFunction1 = WalletServiceDefaults.remoteResourceRetriever,
        encryptionService: WalletEncryptionService = WalletServiceDefaults.encryptionService,
        proofCreators: [ProofCreator]
    ) {
        self.clientId = clientId
        service = OpenId4VciClient(
            clientId: clientId,
            remoteResourceRetriever: remoteResourceRetriever,
            encryptionService: encryptionService,
            proofCreators: proofCreators
        )
    }

    public func buildAuthorizationDetails(
        credentialConfigurationId: String,
        authorizationServers: Set<String>? = nil
    ) -> Set<OpenIdAuthorizationDetails> {
        service.buildAuthorizationDetails(
            credentialConfigurationId: credentialConfigurationId,
            authorizationServers: authorizationServers
        )
    }

    public func buildAuthorizationDetails(
        credentialConfigurationIds: Set<String>,
        authorizationServers: Set<String>? = nil
    ) -> Set<OpenIdAuthorizationDetails> {
        service.buildAuthorizationDetails(
            credentialConfigurationIds: credentialConfigurationIds,
            authorizationServers: authorizationServers
        )
    }

    /// `clientId` defaults to the adapter's; the proof clock is set in `init`.
    @available(iOS 13, macOS 10.15, watchOS 6, tvOS 13, *)
    public func createCredential(
        tokenResponse: TokenResponseParameters,
        metadata: IssuerMetadata,
        credentialFormat: SupportedCredentialFormat,
        clientNonce: String? = nil,
        previouslyRequestedScope: String? = nil,
        clientId: String? = nil
    ) async throws -> [OpenId4VciClientCredentialRequest] {
        let result = try await service.createCredential(
            tokenResponse: tokenResponse,
            metadata: metadata,
            credentialFormat: credentialFormat,
            clientNonce: clientNonce,
            previouslyRequestedScope: previouslyRequestedScope,
            clientId: clientId ?? self.clientId
        )
        return try callbackArgument(kotlinValue(result), as: [OpenId4VciClientCredentialRequest].self)
    }
}

public extension OpenId4VciClient.RequestOptions {
    static func create(
        credentialScheme: CredentialScheme,
        representation: ConstantIndex.CredentialRepresentation = .plainJwt,
        state: String = UUID().uuidString.lowercased()
    ) -> OpenId4VciClient.RequestOptions {
        OpenId4VciClient.RequestOptions(
            credentialScheme: credentialScheme,
            representation: representation,
            state: state
        )
    }
}
