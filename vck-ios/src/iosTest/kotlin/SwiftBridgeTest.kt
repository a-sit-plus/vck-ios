import at.asitplus.signum.internals.toNSData
import kotlinx.serialization.SerializationException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertSame
import kotlin.time.Clock

class SwiftBridgeTest {
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
