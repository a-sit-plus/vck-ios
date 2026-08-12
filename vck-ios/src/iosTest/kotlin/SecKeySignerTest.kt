@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)

import at.asitplus.signum.indispensable.SignatureAlgorithm
import at.asitplus.signum.internals.createCFDictionary
import at.asitplus.signum.internals.corecall
import at.asitplus.signum.internals.manage
import at.asitplus.signum.supreme.signature
import at.asitplus.signum.supreme.sign.makeVerifier
import at.asitplus.signum.supreme.sign.verify
import kotlinx.cinterop.memScoped
import kotlinx.coroutines.runBlocking
import platform.Security.SecKeyCreateRandomKey
import platform.Security.kSecAttrKeySizeInBits
import platform.Security.kSecAttrKeyType
import platform.Security.kSecAttrKeyTypeEC
import kotlin.test.Test

class SecKeySignerTest {
    @Test
    fun signsWithSecKey() {
        runBlocking {
            val privateKey = memScoped {
                corecall {
                    SecKeyCreateRandomKey(createCFDictionary {
                        kSecAttrKeyType mapsTo kSecAttrKeyTypeEC
                        kSecAttrKeySizeInBits mapsTo 256
                    }, error)
                }.manage()
            }
            val signer = SignerAdapter.fromSecKey(privateKey.value, SignatureAlgorithm.ECDSAwithSHA256).getOrThrow()
            val message = "SecKey-backed Signum signer".encodeToByteArray()

            signer.makeVerifier().getOrThrow().verify(message, signer.sign(message).signature).getOrThrow()
        }
    }
}
