package at.asitplus.wallet

import OpenId4VpHolderBuilder
import kotlin.test.Test
import kotlin.test.assertEquals

class Test {

    @Test
    fun buildsOpenId4VpHolderWithConfiguration() {
        val builder = OpenId4VpHolderBuilder().apply {
            clientId = "https://example.test/wallet"
            authorizationEndpoint = "openid4vp-test:"
        }
        val metadata = builder.build().metadata

        assertEquals(builder.clientId, metadata.issuer)
        assertEquals(builder.authorizationEndpoint, metadata.authorizationEndpoint)
    }
}
