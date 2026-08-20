@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)

import at.asitplus.KmmResult
import at.asitplus.catching
import at.asitplus.signum.indispensable.SignatureAlgorithm
import at.asitplus.signum.indispensable.pki.X509Certificate
import at.asitplus.signum.supreme.sign.Signer
import at.asitplus.wallet.lib.agent.HolderAgent
import at.asitplus.wallet.lib.agent.InMemorySubjectCredentialStore
import at.asitplus.wallet.lib.agent.KeyMaterial
import at.asitplus.wallet.lib.agent.SignerBasedKeyMaterial
import at.asitplus.wallet.lib.agent.SubjectCredentialStore
import at.asitplus.wallet.lib.ktor.openid.OpenId4VciClient
import at.asitplus.wallet.lib.oauth2.OAuth2Client
import at.asitplus.wallet.lib.oidvci.encodeToParameters
import at.asitplus.wallet.lib.oidvci.WalletService
import at.asitplus.wallet.lib.RemoteResourceRetrieverInput
import io.ktor.client.HttpClient
import io.ktor.client.engine.darwin.Darwin
import io.ktor.client.request.forms.submitForm
import io.ktor.client.request.get
import io.ktor.client.request.headers
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpMethod
import io.ktor.http.URLBuilder
import io.ktor.http.parameters
import platform.Security.SecKeyRef

//IGNOERE ME, JUST HERE TO STREAMLINE END-TO-END Flow!!!

private const val CLIENT_ID = "https://wallet.a-sit.at/app"
const val ISSUANCE_CALLBACK = "asitplus-wallet://wallet.a-sit.plus/app/callback/provisioning"

private class SecKeyMaterial(signer: Signer) : SignerBasedKeyMaterial(signer) {
    override suspend fun getCertificate(): X509Certificate? = null
}

/** Minimal stateful bridge for a single issue-then-present demo run. */
class BasicWallet(
    val keyMaterial: KeyMaterial,
    subjectCredentialStore: SubjectCredentialStore,
) {
    constructor(keyMaterial: KeyMaterial) : this(keyMaterial, InMemorySubjectCredentialStore())

    val holder = HolderAgent(keyMaterial, subjectCredentialStore)
    private val http = HttpClient(Darwin)
    val remoteResourceRetriever: suspend (RemoteResourceRetrieverInput) -> String? = { input ->
        val response = if (input.method == HttpMethod.Post) {
            http.submitForm(input.url, parameters {
                input.requestObjectParameters?.encodeToParameters()?.forEach { append(it.key, it.value) }
            }) { headers { input.headers.forEach { append(it.key, it.value) } } }
        } else {
            http.get(URLBuilder(input.url).apply {
                input.requestObjectParameters?.encodeToParameters()?.forEach { parameters.append(it.key, it.value) }
            }.build()) { headers { input.headers.forEach { append(it.key, it.value) } } }
        }
        response.bodyAsText()
    }
    private val issuance = OpenId4VciClient(
        engine = Darwin.create(),
        oid4vciService = WalletService(clientId = CLIENT_ID, keyMaterial = keyMaterial),
        oauth2InternalClient = OAuth2Client(
            clientId = CLIENT_ID,
            redirectUrl = ISSUANCE_CALLBACK,
        ),
    )
    private var pendingIssuance: at.asitplus.wallet.lib.ktor.openid.ProvisioningContext? = null

    /** Uses the issuer's first advertised credential: PID SD-JWT on the A-SIT Plus demo issuer. */
    @Throws(Throwable::class)
    suspend fun startIssuance(issuer: String): String {
        val normalized = issuer.trim().trimEnd('/')
        require(normalized.startsWith("https://")) { "Issuer must be an HTTPS URL" }
        val credential = issuance.loadCredentialMetadata(normalized).getOrThrow().firstOrNull()
            ?: error("Issuer advertises no credentials")
        return issuance.startProvisioningWithAuthRequestReturningResult(normalized, credential)
            .getOrThrow()
            .also { pendingIssuance = it.context }
            .url
    }

    @Throws(Throwable::class)
    suspend fun finishIssuance(callbackUrl: String): Int {
        val context = pendingIssuance ?: error("No issuance is pending")
        val result = issuance.resumeWithAuthCode(callbackUrl, context).getOrThrow()
        result.credentials.forEach { holder.storeCredential(it, result.refreshToken).getOrThrow() }
        pendingIssuance = null
        return holder.getCredentials()?.size ?: 0
    }

    @Throws(Throwable::class)
    suspend fun credentialCount(): Int = holder.getCredentials()?.size ?: 0
}

//SUPER-cheap wrapper
object KeyMaterialAdapter {
    fun fromSecKey(privateKey: SecKeyRef?): KmmResult<KeyMaterial> = catching {
        SecKeyMaterial(
            SignerAdapter.fromSecKey(privateKey, SignatureAlgorithm.ECDSAwithSHA256).getOrThrow()
        )
    }
}

object BasicWalletFactory {
    fun fromSecKey(privateKey: SecKeyRef?): KmmResult<BasicWallet> = catching {
        BasicWallet(KeyMaterialAdapter.fromSecKey(privateKey).getOrThrow())
    }
}
