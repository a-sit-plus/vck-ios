import at.asitplus.openid.IdToken
import at.asitplus.signum.indispensable.SignatureAlgorithm
import at.asitplus.signum.indispensable.josef.JsonWebKeySet
import at.asitplus.wallet.lib.RemoteResourceRetrieverFunction
import at.asitplus.wallet.lib.agent.EphemeralKeyWithoutCert
import at.asitplus.wallet.lib.agent.Holder
import at.asitplus.wallet.lib.agent.HolderAgent
import at.asitplus.wallet.lib.agent.InMemorySubjectCredentialStore
import at.asitplus.wallet.lib.agent.KeyMaterial
import at.asitplus.wallet.lib.agent.RandomSource
import at.asitplus.wallet.lib.agent.SubjectCredentialStore
import at.asitplus.wallet.lib.cbor.CoseHeaderNone
import at.asitplus.wallet.lib.cbor.SignCoseDetached
import at.asitplus.wallet.lib.cbor.SignCoseDetachedFun
import at.asitplus.wallet.lib.jws.EncryptJwe
import at.asitplus.wallet.lib.jws.EncryptJweFun
import at.asitplus.wallet.lib.jws.JwsHeaderCertOrJwk
import at.asitplus.wallet.lib.jws.SignJwt
import at.asitplus.wallet.lib.jws.SignJwtFun
import at.asitplus.wallet.lib.oidc.RequestObjectJwsVerifier
import at.asitplus.wallet.lib.openid.OpenId4VpHolder
import at.asitplus.wallet.lib.utils.DefaultMapStore
import at.asitplus.wallet.lib.utils.MapStore
import kotlin.time.Clock

/** Swift-friendly configuration for [OpenId4VpHolder].  in the cheapest way possible*/
class OpenId4VpHolderBuilder(
    val keyMaterial: KeyMaterial,
    val subjectCredentialStore: SubjectCredentialStore,
) {
    constructor() : this(EphemeralKeyWithoutCert(), InMemorySubjectCredentialStore())

    // Null means: derive the value from the current keyMaterial in build().
    /** Holds the credentials and creates the verifiable presentation. */
    var holder: Holder? = null
    /** Signs the ID token for SIOPv2 responses. */
    var signIdToken: SignJwtFun<IdToken>? = null
    /** Encrypts the authn response to the holder using [keyMaterial], if requested. */
    var encryptJarm: EncryptJweFun? = null
    /** Advertised in [OpenId4VpHolder.metadata] and compared against holder's requirements. */
    var supportedAlgorithms: Set<SignatureAlgorithm> = setOf(SignatureAlgorithm.ECDSAwithSHA256)
    /** Signs the session transcript for mDoc responses. */
    var signDeviceAuthDetached: SignCoseDetachedFun<ByteArray>? = null
    /** Clock used for the signed ID token. */
    var clock: Clock = Clock.System
    /** Advertised as `issuer` in [OpenId4VpHolder.metadata]. */
    var clientId: String = "https://wallet.a-sit.at/"
    /** Advertised as `authorization_endpoint` in [OpenId4VpHolder.metadata]. */
    var authorizationEndpoint: String = "openid4vp:"
    /**
     * Need to implement if resources are defined by reference, i.e. the URL for a [JsonWebKeySet],
     * or the authentication request itself as `request_uri`, or `presentation_definition_uri`.
     * Implementations need to fetch the url passed in, and return either the body, if there is one,
     * or the HTTP header `Location`, i.e. if the server sends the request object as a redirect.
     */
    var remoteResourceRetriever: RemoteResourceRetrieverFunction = { null }
    /**
     * Need to verify the request object serialized as a JWS,
     * which may be signed with a pre-registered key (see [at.asitplus.wallet.lib.openid.ClientIdScheme.PreRegistered]).
     */
    var requestObjectJwsVerifier: RequestObjectJwsVerifier = RequestObjectJwsVerifier { true }
    /** Stores our nonce used when fetching authn requests using POST. */
    var walletNonceMapStore: MapStore<String, String> = DefaultMapStore()
    /** Source for random bytes, i.e., nonces for encrypted responses. */
    var randomSource: RandomSource = RandomSource.Secure
    /** Callback to load encryption keys for pre-registered clients. */
    var lookupJsonWebKeysForClient: (OpenId4VpHolder.JsonWebKeyLookupInput) -> JsonWebKeySet? = { null }

    fun build(): OpenId4VpHolder = OpenId4VpHolder(
        keyMaterial = keyMaterial,
        holder = holder ?: HolderAgent(keyMaterial, subjectCredentialStore),
        signIdToken = signIdToken ?: SignJwt(keyMaterial, JwsHeaderCertOrJwk()),
        encryptJarm = encryptJarm ?: EncryptJwe(keyMaterial),
        supportedAlgorithms = supportedAlgorithms,
        signDeviceAuthDetached = signDeviceAuthDetached
            ?: SignCoseDetached(keyMaterial, CoseHeaderNone(), CoseHeaderNone()),
        clock = clock,
        clientId = clientId,
        authorizationEndpoint = authorizationEndpoint,
        remoteResourceRetriever = remoteResourceRetriever,
        requestObjectJwsVerifier = requestObjectJwsVerifier,
        walletNonceMapStore = walletNonceMapStore,
        randomSource = randomSource,
        lookupJsonWebKeysForClient = lookupJsonWebKeysForClient,
    )
}
