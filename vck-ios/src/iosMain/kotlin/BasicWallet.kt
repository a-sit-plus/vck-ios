@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)

import at.asitplus.KmmResult
import at.asitplus.catching
import at.asitplus.catchingUnwrapped
import at.asitplus.openid.IssuerMetadata
import at.asitplus.openid.TokenResponseParameters
import at.asitplus.signum.indispensable.SignatureAlgorithm
import at.asitplus.signum.indispensable.pki.X509Certificate
import at.asitplus.signum.supreme.sign.Signer
import at.asitplus.wallet.lib.agent.CredentialRenewalInfo
import at.asitplus.wallet.lib.agent.HolderAgent
import at.asitplus.wallet.lib.agent.InMemorySubjectCredentialStore
import at.asitplus.wallet.lib.agent.KeyMaterial
import at.asitplus.wallet.lib.agent.SignerBasedKeyMaterial
import at.asitplus.wallet.lib.agent.SubjectCredentialStore
import at.asitplus.wallet.lib.ktor.openid.ProvisioningContext
import at.asitplus.wallet.lib.oauth2.OAuth2Client
import at.asitplus.wallet.lib.oauth2.OAuth2ProtocolClient
import at.asitplus.wallet.lib.oidvci.CredentialIdentifierInfo
import at.asitplus.wallet.lib.oidvci.JwtProofCreator
import at.asitplus.wallet.lib.oidvci.OpenId4VciClient
import at.asitplus.wallet.lib.oidvci.OpenId4VciProtocolClient
import at.asitplus.wallet.lib.oidvci.ReceivedCredential
import at.asitplus.wallet.lib.validation.StatusPolicy
import at.asitplus.wallet.lib.validation.TrustPolicy
import at.asitplus.wallet.lib.validation.ValidationPolicy
import at.asitplus.wallet.lib.validation.firstRejection
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

/**
 * Minimal stateful bridge for a single issue-then-present demo run.
 * Sends all HTTP requests with [transport], e.g. `URLSessionTransport` in Swift.
 */
class BasicWallet(
    val keyMaterial: KeyMaterial,
    subjectCredentialStore: SubjectCredentialStore,
    private val transport: HttpTransport,
) {
    constructor(keyMaterial: KeyMaterial, transport: HttpTransport) :
            this(keyMaterial, InMemorySubjectCredentialStore(), transport)

    val holder = HolderAgent(keyMaterial, subjectCredentialStore)
    private val vci = OpenId4VciProtocolClient(
        vciClient = OpenId4VciClient(proofCreators = listOf(JwtProofCreator(keyMaterial))),
        oauth2Client = OAuth2ProtocolClient(OAuth2Client(clientId = CLIENT_ID, redirectUrl = ISSUANCE_CALLBACK)),
    )
    /** Serializable with [VckSerializer.joseSerializeProvisioningContext], to resume after the app was killed. */
    var pendingIssuance: ProvisioningContext? = null

    /** Uses the issuer's first advertised credential: PID SD-JWT on the A-SIT Plus demo issuer. */
    @Throws(Throwable::class)
    suspend fun startIssuance(issuer: String): String {
        val normalized = issuer.trim().trimEnd('/')
        require(normalized.startsWith("https://")) { "Issuer must be an HTTPS URL" }
        val issuerMetadata = vci.loadIssuerMetadata(normalized).execute(transport)
        val credential = vci.parseCredentialMetadata(issuerMetadata).getOrThrow().firstOrNull()
            ?: error("Issuer advertises no credentials")
        val authorizationServer = vci.selectAuthorizationServer(issuerMetadata, normalized)
        val oauthMetadata = vci.oauth2Client.loadAuthorizationServerMetadata(authorizationServer).execute(transport)
        val authorization = vci.oauth2Client.startAuthorization(
            oauthMetadata = oauthMetadata,
            authorizationServer = authorizationServer,
            authorizationDetails = credential.authorizationDetails(),
            scope = credential.supportedCredentialFormat.scope,
            issuerMetadata = issuerMetadata,
        ).execute(transport)
        pendingIssuance = ProvisioningContext(
            state = authorization.state,
            credential = credential,
            oauthMetadata = oauthMetadata,
            issuerMetadata = issuerMetadata,
        )
        return authorization.url
    }

    @Throws(Throwable::class)
    suspend fun finishIssuance(callbackUrl: String): Int {
        val context = pendingIssuance ?: error("No issuance is pending")
        val format = context.credential.supportedCredentialFormat
        val token = vci.oauth2Client.requestTokenWithAuthCode(
            oauthMetadata = context.oauthMetadata,
            url = callbackUrl,
            authorizationServer = context.oauthMetadata.issuer,
            state = context.state,
            scope = format.scope,
            authorizationDetails = context.credential.authorizationDetails(),
            issuerMetadata = context.issuerMetadata,
        ).execute(transport).params
        val scheme = vci.resolveCredentialScheme(format) ?: error("Unknown credential scheme in $format")
        val renewalInfo = CredentialRenewalInfo(
            refreshToken = token.refreshToken,
            issuerMetadata = context.issuerMetadata,
            oauthMetadata = context.oauthMetadata,
            credentialFormat = format,
            credentialIdentifier = context.credential.credentialIdentifier,
        )
        vci.prepareCredentialRequests(
            metadata = context.issuerMetadata,
            tokenResponse = token,
            credentialFormats = setOf(format),
            previouslyRequestedScope = format.scope,
        ).getOrThrow().flatMap { requestCredential(it, context.issuerMetadata, token) }.forEach { received ->
            val prepared = received.prepareCredentialStorage(holder, scheme, ISSUANCE_POLICY, renewalInfo).getOrThrow()
            holder.storeAccepted(prepared).getOrThrow().storedEntry
                ?: throw prepared.validation.report.firstRejection() ?: IllegalStateException("Credential rejected")
        }
        pendingIssuance = null
        return holder.getCredentials()?.size ?: 0
    }

    @Throws(Throwable::class)
    suspend fun credentialCount(): Int = holder.getCredentials()?.size ?: 0

    /** Fetches a fresh `c_nonce` for each request, and retries once if the issuer rejects it. */
    private suspend fun requestCredential(
        request: OpenId4VciClient.PreparedCredentialRequest,
        issuerMetadata: IssuerMetadata,
        token: TokenResponseParameters,
        retryOnInvalidNonce: Boolean = true,
    ): List<ReceivedCredential> {
        val clientNonce = vci.nonceRequest(issuerMetadata)?.execute(transport)
        val credentialRequest = vci.createCredential(request, issuerMetadata, clientNonce).getOrThrow()
        return catchingUnwrapped {
            vci.credentialRequest(credentialRequest, issuerMetadata, token, request.credentialFormat).execute(transport)
        }.getOrElse {
            if (retryOnInvalidNonce && vci.isInvalidNonce(it))
                requestCredential(request, issuerMetadata, token, retryOnInvalidNonce = false)
            else throw it
        }
    }

    private fun CredentialIdentifierInfo.authorizationDetails() =
        vci.vciClient.buildAuthorizationDetails(setOf(credentialIdentifier), issuerMetadata.authorizationServers)
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
    fun fromSecKey(privateKey: SecKeyRef?, transport: HttpTransport): KmmResult<BasicWallet> = catching {
        BasicWallet(KeyMaterialAdapter.fromSecKey(privateKey).getOrThrow(), transport)
    }
}
