import at.asitplus.dcapi.request.IsoMdocRequest
import at.asitplus.iso.EncryptionInfo
import at.asitplus.iso.EncryptionParameters
import at.asitplus.signum.indispensable.cosef.CoseEllipticCurve
import at.asitplus.signum.indispensable.cosef.CoseKey
import at.asitplus.signum.indispensable.cosef.CoseKeyParams
import at.asitplus.signum.indispensable.cosef.CoseKeyType
import at.asitplus.signum.internals.toNSData
import kotlinx.serialization.SerializationException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertSame
import kotlin.time.Clock

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
        assertEquals(setOf("pid"), metadata.supportedCredentialConfigurations?.keys)
        assertEquals(metadata, VckSerializer.joseDeserializeIssuerMetadata(
            VckSerializer.joseSerializeIssuerMetadata(metadata)
        ))
        assertFailsWith<SerializationException> {
            VckSerializer.joseDeserializeIssuerMetadata("{}".encodeToByteArray().toNSData())
        }
        assertSame(Clock.System, ClockAdapter.system)
    }
}
