@file:OptIn(kotlin.experimental.ExperimentalObjCName::class)

import at.asitplus.signum.indispensable.josef.JsonWebKey
import at.asitplus.wallet.lib.RemoteResourceRetrieverFunction
import at.asitplus.wallet.lib.agent.EphemeralKeyWithoutCert
import at.asitplus.wallet.lib.agent.KeyMaterial
import at.asitplus.wallet.lib.oidvci.WalletEncryptionService
import kotlin.time.Clock

/** Kotlin defaults that Swift cannot construct directly. */
@ObjCName(swiftName = "WalletServiceDefaultsBridge")
object WalletServiceDefaults {
    // Fresh keys and encryption state for each service, as in WalletService's constructor.
    val keyMaterial: KeyMaterial get() = EphemeralKeyWithoutCert()
    val encryptionService: WalletEncryptionService get() = WalletEncryptionService()
    val remoteResourceRetriever: RemoteResourceRetrieverFunction = { null }
    val selectProofJwtKeyBinding: suspend (KeyMaterial) -> Pair<JsonWebKey?, String?> = {
        Pair(it.jsonWebKey, null)
    }
}

/** Exposes the standard system clock through its exported interface. */
@ObjCName(swiftName = "ClockAdapterBridge")
object ClockAdapter {
    val system: Clock get() = Clock.System
}
