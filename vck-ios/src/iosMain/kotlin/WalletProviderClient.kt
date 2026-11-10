import at.asitplus.attestation.supreme.AttestationChallenge
import at.asitplus.attestation.supreme.createAttestationProof
import at.asitplus.openid.ClientNonceResponse
import at.asitplus.openid.DurationSecondsIntSerializer
import at.asitplus.signum.indispensable.asn1.ObjectIdentifier
import at.asitplus.signum.indispensable.asn1.encoding.encodeToAsn1Primitive
import at.asitplus.signum.indispensable.josef.JsonWebKey
import at.asitplus.signum.indispensable.josef.JsonWebToken
import at.asitplus.signum.indispensable.josef.JwsCompactTyped
import at.asitplus.signum.indispensable.josef.KeyAttestationJwt
import at.asitplus.signum.indispensable.josef.io.joseCompliantSerializer
import at.asitplus.signum.indispensable.josef.toJsonWebKey
import at.asitplus.signum.indispensable.pki.Pkcs10CertificationRequestAttribute
import at.asitplus.signum.indispensable.pki.X509Certificate
import at.asitplus.signum.internals.toNSData
import at.asitplus.signum.supreme.os.PlatformSigningProvider
import at.asitplus.wallet.lib.agent.KeyMaterial
import at.asitplus.wallet.lib.agent.SignerBasedKeyMaterial
import at.asitplus.wallet.lib.jws.JwsHeaderNone
import at.asitplus.wallet.lib.jws.SignJwt
import at.asitplus.wallet.lib.oidvci.BuildClientAttestationPoPJwt
import at.asitplus.wallet.lib.oidvci.OpenId4VciClient
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import platform.Foundation.NSBundle
import kotlin.time.Clock
import kotlin.time.Duration

// Same wallet provider and wallet solution as Valera, see its attestation/Constants.kt.
const val WALLET_PROVIDER_HOST = "https://wallet-provider.a-sit.plus"
private const val WALLET_SOLUTION_OID = "2.25.210184084534939142470042512176304499012"
private const val PATH_CHALLENGE = "api/v1/challenge"
private const val PATH_INSTANCE = "api/v1/instanceAttestation"
private const val PATH_KEY_ATTESTATION = "api/v1/keyAttestation"
private const val PATH_NONCE = "api/v1/nonce"
private const val KS_ALIAS_WIA = "at.asitplus.wallet.vckios.wia"
private const val ISO_18045_MODERATE = "iso_18045_moderate"

/**
 * Loads a Wallet Instance Attestation (WIA) and key attestations (WUA) from the wallet provider, as Valera does.
 * The WIA binds a fresh Secure Enclave key attested with App Attest, so this needs a physical device, and the
 * wallet provider has to accept this app's App ID.
 */
internal class WalletProviderClient(
    private val transport: HttpTransport,
    host: String = WALLET_PROVIDER_HOST,
) {
    private val host = host.trimEnd('/')

    /** Creates a new attested key and returns it with the WIA binding it in `cnf.jwk`. */
    suspend fun loadInstanceAttestation(
        preferredClientStatusPeriod: Duration?,
    ): Pair<KeyMaterial, JwsCompactTyped<JsonWebToken>> {
        val challenge = Json.decodeFromString<AttestationChallenge>(get("$host/$PATH_CHALLENGE")).also {
            val now = Clock.System.now()
            check(it.issuedAt <= now && now <= it.validUntil) {
                "System time off: challenge valid ${it.issuedAt}..${it.validUntil}, local time $now"
            }
        }
        // Best effort, there may be no key to delete yet
        PlatformSigningProvider.deleteSigningKey(KS_ALIAS_WIA)
        val request = InstanceAttestationRequest(appVersion(), preferredClientStatusPeriod)
        val proof = challenge.createAttestationProof(
            alias = KS_ALIAS_WIA,
            additionalCsrAttributes = listOf(
                Pkcs10CertificationRequestAttribute(
                    ObjectIdentifier(WALLET_SOLUTION_OID),
                    listOf(joseCompliantSerializer.encodeToString(request).encodeToAsn1Primitive()),
                )
            ),
        ) { emptyList() }.getOrThrow()
        val wia = JwsCompactTyped<JsonWebToken>(
            post("$host/$PATH_INSTANCE", "application/octet-stream", proof.data.encodeToDer())
        )
        val signer = PlatformSigningProvider.getSignerForKey(KS_ALIAS_WIA).getOrThrow()
        val keyMaterial = object : SignerBasedKeyMaterial(signer) {
            override suspend fun getCertificate(): X509Certificate? = null
        }
        require(wia.payload.confirmationClaim?.jsonWebKey?.jwkThumbprint == keyMaterial.jsonWebKey.jwkThumbprint) {
            "Instance attestation does not bind the attested key"
        }
        return keyMaterial to wia
    }

    /** Loads a key attestation for [holderKey], authenticated with [wia] and a proof of possession of [wiaKey]. */
    suspend fun loadKeyAttestation(
        wia: JwsCompactTyped<JsonWebToken>,
        wiaKey: KeyMaterial,
        holderKey: KeyMaterial,
        input: OpenId4VciClient.KeyAttestationInput,
    ): JwsCompactTyped<KeyAttestationJwt> {
        val providerNonce = joseCompliantSerializer.decodeFromString<ClientNonceResponse>(get("$host/$PATH_NONCE"))
        val pop = BuildClientAttestationPoPJwt(
            signJwt = SignJwt(wiaKey, JwsHeaderNone()),
            audience = host,
            nonce = providerNonce.clientNonce,
        )
        val holderJwk = holderKey.publicKey.toJsonWebKey()
        val request = KeyAttestationRequest(
            token = wia.jws.toString(),
            proof = pop.jws.toString(),
            keys = listOf(holderJwk),
            nonce = input.clientNonce,
            keyStorage = setOf(ISO_18045_MODERATE),
            userAuthentication = setOf(ISO_18045_MODERATE),
            preferredKeyStorageStatusPeriod = input.requirements?.preferredTtl,
            supportedAlgorithms = input.supportedAlgorithms,
        )
        val body = post(
            "$host/$PATH_KEY_ATTESTATION", "application/json",
            joseCompliantSerializer.encodeToString(request).encodeToByteArray(),
        )
        return JwsCompactTyped<KeyAttestationJwt>(body).also {
            require(it.payload.attestedKeys.firstOrNull()?.jwkThumbprint == holderJwk.jwkThumbprint) {
                "Key attestation does not attest the holder key"
            }
        }
    }

    private suspend fun get(url: String): String =
        send(SwiftHttpRequest(url, "GET", emptyMap(), contentType = null, body = null))

    private suspend fun post(url: String, contentType: String, body: ByteArray): String =
        send(SwiftHttpRequest(url, "POST", emptyMap(), contentType, body.toNSData()))

    private suspend fun send(request: SwiftHttpRequest): String = transport.send(request).let {
        check(it.status.value == 200) { "Wallet provider answered ${it.status.value} for ${request.url}: ${it.body}" }
        it.body
    }

    private fun appVersion(): String =
        NSBundle.mainBundle.objectForInfoDictionaryKey("CFBundleShortVersionString") as? String ?: "0"
}

@Serializable
private data class InstanceAttestationRequest(
    val versionName: String,
    val preferredClientStatusPeriod: Duration? = null,
)

@Serializable
private data class KeyAttestationRequest(
    @SerialName("token") val token: String,
    @SerialName("proof") val proof: String,
    @SerialName("keys") val keys: List<JsonWebKey>,
    @SerialName("nonce") val nonce: String?,
    @SerialName("key_storage") val keyStorage: Set<String>,
    @SerialName("user_authentication") val userAuthentication: Set<String>,
    @SerialName("preferred_key_storage_status_period")
    @Serializable(with = DurationSecondsIntSerializer::class)
    val preferredKeyStorageStatusPeriod: Duration?,
    @SerialName("supported_algorithms") val supportedAlgorithms: Collection<String>?,
)
