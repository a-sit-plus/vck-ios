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
    public let service: WalletService

    public init(
        clientId: String = "https://wallet.a-sit.at/app",
        keyMaterial: KeyMaterial = WalletServiceDefaults.keyMaterial,
        remoteResourceRetriever: KotlinSuspendFunction1 = WalletServiceDefaults.remoteResourceRetriever,
        encryptionService: WalletEncryptionService = WalletServiceDefaults.encryptionService,
        loadKeyAttestation: KotlinSuspendFunction1? = nil,
        selectProofJwtKeyBinding: KotlinSuspendFunction1 = WalletServiceDefaults.selectProofJwtKeyBinding
    ) {
        service = WalletService(
            clientId: clientId,
            keyMaterial: keyMaterial,
            remoteResourceRetriever: remoteResourceRetriever,
            encryptionService: encryptionService,
            loadKeyAttestation: loadKeyAttestation,
            selectProofJwtKeyBinding: selectProofJwtKeyBinding
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

    @available(iOS 13, macOS 10.15, watchOS 6, tvOS 13, *)
    public func createCredential(
        tokenResponse: TokenResponseParameters,
        metadata: IssuerMetadata,
        credentialFormat: SupportedCredentialFormat,
        clientNonce: String? = nil,
        previouslyRequestedScope: String? = nil,
        clock: KotlinClock = ClockAdapter.system
    ) async throws -> [WalletServiceCredentialRequest] {
        let result = try await service.createCredential(
            tokenResponse: tokenResponse,
            metadata: metadata,
            credentialFormat: credentialFormat,
            clientNonce: clientNonce,
            previouslyRequestedScope: previouslyRequestedScope,
            clock: clock
        )
        return try callbackArgument(kotlinValue(result), as: [WalletServiceCredentialRequest].self)
    }
}

public extension WalletService.RequestOptions {
    static func create(
        credentialScheme: CredentialScheme,
        representation: ConstantIndex.CredentialRepresentation = .plainJwt,
        state: String = UUID().uuidString.lowercased()
    ) -> WalletService.RequestOptions {
        WalletService.RequestOptions(
            credentialScheme: credentialScheme,
            representation: representation,
            state: state
        )
    }
}
