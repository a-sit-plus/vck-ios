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
import at.asitplus.wallet.lib.ktor.openid.OpenId4VciKtorClient
import at.asitplus.wallet.lib.ktor.openid.ProvisioningContext
import at.asitplus.wallet.lib.oauth2.OAuth2Client
import at.asitplus.wallet.lib.oidvci.JwtProofCreator
import at.asitplus.wallet.lib.oidvci.OpenId4VciClient
import at.asitplus.wallet.lib.validation.StatusPolicy
import at.asitplus.wallet.lib.validation.TrustPolicy
import at.asitplus.wallet.lib.validation.ValidationPolicy
import at.asitplus.wallet.lib.validation.firstRejection
import io.ktor.client.HttpClient
import io.ktor.client.engine.darwin.Darwin
import platform.Security.SecKeyRef
import kotlin.time.Duration.Companion.minutes

//IGNOERE ME, JUST HERE TO STREAMLINE END-TO-END Flow!!!

private const val CLIENT_ID = "https://wallet.a-sit.at/app"
const val ISSUANCE_CALLBACK = "asitplus-wallet://wallet.a-sit.plus/app/callback/provisioning"

// The demo configures no trust anchors and no status list resolver.
private val ISSUANCE_POLICY = ValidationPolicy(
    trust = TrustPolicy.IntegrityOnly,
    status = StatusPolicy.Skip,
    timeLeeway = 5.minutes,
    requireTimeliness = true,
)

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
    private val issuance = OpenId4VciKtorClient(
        httpClient = http,
        oauth2Client = OAuth2Client(
            clientId = CLIENT_ID,
            redirectUrl = ISSUANCE_CALLBACK,
        ),
        vciClient = OpenId4VciClient(proofCreators = listOf(JwtProofCreator(keyMaterial))),
    )
    private var pendingIssuance: ProvisioningContext? = null

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
        result.prepareCredentialStorage(holder, ISSUANCE_POLICY).getOrThrow().forEach { prepared ->
            holder.storeAccepted(prepared).getOrThrow().storedEntry
                ?: throw prepared.validation.report.firstRejection() ?: IllegalStateException("Credential rejected")
        }
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
