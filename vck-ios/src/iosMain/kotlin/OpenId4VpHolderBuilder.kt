import at.asitplus.openid.IdToken
import at.asitplus.signum.indispensable.SignatureAlgorithm
import at.asitplus.signum.indispensable.josef.JsonWebKeySet
import at.asitplus.wallet.lib.RemoteResourceRetrieverFunction
import at.asitplus.wallet.lib.agent.EphemeralKeyWithoutCert
import at.asitplus.wallet.lib.agent.Holder
import at.asitplus.wallet.lib.agent.HolderAgent
import at.asitplus.wallet.lib.agent.KeyMaterial
import at.asitplus.wallet.lib.agent.RandomSource
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

/** Swift-friendly configuration for [OpenId4VpHolder]. */
class OpenId4VpHolderBuilder(
    val keyMaterial: KeyMaterial,
) {
    constructor() : this(EphemeralKeyWithoutCert())

    // Null means: derive the value from the current keyMaterial in build().
    var holder: Holder? = null
    var signIdToken: SignJwtFun<IdToken>? = null
    var encryptJarm: EncryptJweFun? = null
    var supportedAlgorithms: Set<SignatureAlgorithm> = setOf(SignatureAlgorithm.ECDSAwithSHA256)
    var signDeviceAuthDetached: SignCoseDetachedFun<ByteArray>? = null
    var clock: Clock = Clock.System
    var clientId: String = "https://wallet.a-sit.at/"
    var authorizationEndpoint: String = "openid4vp:"
    var remoteResourceRetriever: RemoteResourceRetrieverFunction = { null }
    var requestObjectJwsVerifier: RequestObjectJwsVerifier = RequestObjectJwsVerifier { true }
    var walletNonceMapStore: MapStore<String, String> = DefaultMapStore()
    var randomSource: RandomSource = RandomSource.Secure
    var lookupJsonWebKeysForClient: (OpenId4VpHolder.JsonWebKeyLookupInput) -> JsonWebKeySet? = { null }

    fun build(): OpenId4VpHolder {
        val keyMaterial = keyMaterial
        return OpenId4VpHolder(
            keyMaterial = keyMaterial,
            holder = holder ?: HolderAgent(keyMaterial),
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
}
