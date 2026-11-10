import at.asitplus.dcapi.request.IsoMdocRequest
import at.asitplus.iso.EncryptionInfo
import at.asitplus.iso.EncryptionParameters
import at.asitplus.signum.indispensable.cosef.CoseEllipticCurve
import at.asitplus.signum.indispensable.cosef.CoseKey
import at.asitplus.signum.indispensable.cosef.CoseKeyParams
import at.asitplus.signum.indispensable.cosef.CoseKeyType
import at.asitplus.signum.internals.toByteArray
import at.asitplus.signum.internals.toNSData
import at.asitplus.openid.TokenResponseParameters
import at.asitplus.wallet.lib.HttpBody
import at.asitplus.wallet.lib.ReceivedHttpResponse
import at.asitplus.wallet.lib.openid.AuthenticationResponseResult
import at.asitplus.wallet.lib.openid.OpenId4VpProtocolClient
import kotlinx.coroutines.runBlocking
import at.asitplus.wallet.lib.agent.EphemeralKeyWithoutCert
import at.asitplus.wallet.lib.agent.SubjectCredentialStore
import at.asitplus.wallet.lib.data.VerifiableCredentialSdJwt
import at.asitplus.wallet.lib.ktor.openid.ProvisioningContext
import at.asitplus.wallet.lib.oidvci.CredentialIdentifierInfo
import at.asitplus.wallet.lib.PreparedHttpRequest
import at.asitplus.wallet.lib.ProtocolRequest
import io.ktor.http.ContentType
import io.ktor.http.HttpMethod
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import at.asitplus.wallet.lib.validation.HolderBindingPolicy
import at.asitplus.wallet.lib.validation.RegistrationPolicy
import at.asitplus.wallet.lib.validation.RequiredClaimsPolicy
import at.asitplus.wallet.lib.validation.StatusPolicy
import at.asitplus.wallet.lib.validation.TrustPolicy
import kotlinx.serialization.SerializationException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertSame
import kotlin.time.Clock
import kotlin.time.Duration.Companion.days
import kotlin.time.Duration.Companion.minutes

class SwiftBridgeTest {
    @Test
    fun dcApiSerializationRoundTrips() {
        val summary = VckSerializer.joseDeserializeIosDcApiMdocPreRequestSummary(
            """{"documentRequests":[{"docType":"org.iso.18013.5.1.mDL","namespaces":{"org.iso.18013.5.1":{"family_name":false}}}]}"""
                .encodeToByteArray().toNSData()
        )
        assertEquals(summary, VckSerializer.joseDeserializeIosDcApiMdocPreRequestSummary(
            VckSerializer.joseSerializeIosDcApiMdocPreRequestSummary(summary)
        ))
        val request = IsoMdocRequest(
            deviceRequest = summary.toDeviceRequest(),
            encryptionInfo = EncryptionInfo(
                type = "dcapi",
                encryptionParameters = EncryptionParameters(
                    recipientPublicKey = CoseKey(
                        type = CoseKeyType.EC2,
                        keyParams = CoseKeyParams.EcYBoolParams(curve = CoseEllipticCurve.P256)
                    )
                )
            )
        )
        assertEquals(request, VckSerializer.joseDeserializeIsoMdocRequest(
            VckSerializer.joseSerializeIsoMdocRequest(request)
        ))
        assertFailsWith<SerializationException> {
            VckSerializer.joseDeserializeIsoMdocRequest("{}".encodeToByteArray().toNSData())
        }
        assertFailsWith<SerializationException> {
            VckSerializer.joseDeserializeIosDcApiMdocPreRequestSummary("{}".encodeToByteArray().toNSData())
        }
    }

    @Test
    fun issuerMetadataRoundTripAndSystemClock() {
        val json = """{
            "credential_issuer": "https://issuer.example",
            "credential_endpoint": "https://issuer.example/credential",
            "authorization_servers": ["https://auth.example"],
            "nonce_endpoint": "https://issuer.example/nonce",
            "credential_configurations_supported": {
                "pid": {"format": "dc+sd-jwt", "vct": "urn:example:pid"}
            }
        }"""
        val metadata = VckSerializer.joseDeserializeIssuerMetadata(json.encodeToByteArray().toNSData())
        assertEquals("https://issuer.example", metadata.credentialIssuer)
        assertEquals(setOf("pid"), metadata.supportedCredentialConfigurations.keys)
        assertEquals(metadata, VckSerializer.joseDeserializeIssuerMetadata(
            VckSerializer.joseSerializeIssuerMetadata(metadata)
        ))
        assertFailsWith<SerializationException> {
            VckSerializer.joseDeserializeIssuerMetadata("{}".encodeToByteArray().toNSData())
        }
        assertSame(Clock.System, ClockAdapter.system)
    }

    @Test
    fun validationBridgeTakesSeconds() {
        fun policy(seconds: Double) = ValidationBridge.policy(
            TrustPolicy.IntegrityOnly, StatusPolicy.Skip, seconds, true,
            HolderBindingPolicy.None, RequiredClaimsPolicy.Skip, RegistrationPolicy.Require,
        )
        assertEquals(5.minutes, policy(300.0).timeLeeway)
        assertFailsWith<IllegalArgumentException> { policy(-1.0) }
        assertFailsWith<IllegalArgumentException> { policy(Double.NaN) }
        ValidationBridge.relyingPartyValidator(
            at.asitplus.wallet.lib.validation.RelyingPartyTrustAnchors(),
            ValidationBridge.statusValidator(null),
            365.days.inWholeSeconds.toDouble(),
        )
    }

    @Test
    fun httpExchangeBridgeFlattensRequests() {
        val flat = HttpExchangeBridge.request(
            ProtocolRequest.RequestObject(
                PreparedHttpRequest(
                    url = "https://rp.example/request",
                    method = HttpMethod.Post,
                    headers = headersOf("Accept" to listOf("a", "b")),
                    body = HttpBody(ContentType.Application.FormUrlEncoded, "x=1"),
                )
            )
        )
        assertEquals("https://rp.example/request", flat.url)
        assertEquals("POST", flat.method)
        assertEquals(mapOf("Accept" to "a, b"), flat.headers)
        assertEquals("application/x-www-form-urlencoded", flat.contentType)
        assertEquals("x=1", flat.body?.toByteArray()?.decodeToString())

        val response = HttpExchangeBridge.response(201, mapOf("Location" to "https://rp.example/next"), "body")
        assertEquals(HttpStatusCode.Created, response.status)
        assertEquals("https://rp.example/next", response.headers["Location"])
        assertEquals("body", response.body)
    }

    @Test
    fun persistenceAndOAuthSerializationRoundTrips() {
        val key = EphemeralKeyWithoutCert().jsonWebKey
        assertEquals(key, VckSerializer.joseDeserializeJsonWebKey(VckSerializer.joseSerializeJsonWebKey(key)))

        val token = VckSerializer.joseDeserializeTokenResponseParameters(
            """{"access_token":"token","token_type":"DPoP","scope":"pid"}""".encodeToByteArray().toNSData()
        )
        assertEquals(TokenResponseParameters(accessToken = "token", tokenType = "DPoP", scope = "pid"), token)
        assertEquals(token, VckSerializer.joseDeserializeTokenResponseParameters(
            VckSerializer.joseSerializeTokenResponseParameters(token)
        ))

        val entry = SubjectCredentialStore.StoreEntry.SdJwt(
            vcSerialized = "eyJ~",
            sdJwt = VerifiableCredentialSdJwt(verifiableCredentialType = "urn:example:pid"),
            disclosures = mapOf("digest" to VckSerializer.joseDeserializeSelectiveDisclosureItem(
                "[\"salt\",\"given_name\",\"Erika\"]"
            )),
            schemeIdentifier = "urn:example:pid",
        )
        assertEquals(entry, VckSerializer.joseDeserializeStoreEntry(VckSerializer.joseSerializeStoreEntry(entry)))

        val issuerMetadata = VckSerializer.joseDeserializeIssuerMetadata("""{
            "credential_issuer": "https://issuer.example",
            "credential_endpoint": "https://issuer.example/credential",
            "credential_configurations_supported": {"pid": {"format": "dc+sd-jwt", "vct": "urn:example:pid"}}
        }""".encodeToByteArray().toNSData())
        val context = ProvisioningContext(
            state = "state",
            credential = CredentialIdentifierInfo(
                issuerMetadata, "pid", issuerMetadata.supportedCredentialConfigurations.getValue("pid")
            ),
            oauthMetadata = VckSerializer.joseDeserializeOAuth2AuthorizationServerMetadata(
                """{"issuer":"https://auth.example","token_endpoint":"https://auth.example/token"}"""
                    .encodeToByteArray().toNSData()
            ),
            issuerMetadata = issuerMetadata,
        )
        assertEquals(context, VckSerializer.joseDeserializeProvisioningContext(
            VckSerializer.joseSerializeProvisioningContext(context)
        ))
    }

    @Test
    fun exchangesRunOverTransport() = runBlocking {
        val sent = mutableListOf<SwiftHttpRequest>()
        val transport = object : HttpTransport {
            override suspend fun send(request: SwiftHttpRequest): ReceivedHttpResponse {
                sent += request
                return HttpExchangeBridge.response(200, emptyMap(), """{"redirect_uri":"https://verifier.example/done"}""")
            }
        }
        val client = OpenId4VpProtocolClient(OpenId4VpHolderBuilder().build())
        val redirect = client.sendAuthorizationResponse(
            AuthenticationResponseResult.Post("https://verifier.example/response", mapOf("vp_token" to "token"))
        ).execute(transport)
        assertEquals("https://verifier.example/done", redirect)
        assertEquals(listOf("https://verifier.example/response"), sent.map { it.url })
        assertEquals("POST", sent.single().method)
    }
}
