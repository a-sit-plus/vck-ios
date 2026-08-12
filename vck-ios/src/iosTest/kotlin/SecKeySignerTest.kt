@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)

import at.asitplus.signum.indispensable.SignatureAlgorithm
import at.asitplus.signum.internals.cfDictionaryOf
import at.asitplus.signum.internals.createCFDictionary
import at.asitplus.signum.internals.corecall
import at.asitplus.signum.internals.manage
import at.asitplus.signum.internals.toNSData
import at.asitplus.signum.supreme.signature
import at.asitplus.signum.supreme.sign.makeVerifier
import at.asitplus.signum.supreme.sign.verify
import kotlinx.cinterop.memScoped
import kotlinx.coroutines.runBlocking
import platform.Security.SecKeyCreateRandomKey
import platform.Security.SecItemDelete
import platform.Security.kSecAttrApplicationTag
import platform.Security.kSecAttrIsPermanent
import platform.Security.kSecAttrKeySizeInBits
import platform.Security.kSecAttrKeyType
import platform.Security.kSecAttrKeyTypeEC
import platform.Security.kSecClass
import platform.Security.kSecClassKey
import platform.Security.kSecPrivateKeyAttrs
import kotlin.test.Test

class SecKeySignerTest {
    @Test
    fun signsWithSecKey() {
        runBlocking {
            val tag = "SecKeySignerTest".encodeToByteArray().toNSData()
            val deleteKey = {
                memScoped {
                    SecItemDelete(createCFDictionary {
                        kSecClass mapsTo kSecClassKey
                        kSecAttrKeyType mapsTo kSecAttrKeyTypeEC
                        kSecAttrApplicationTag mapsTo tag
                    })
                }
            }
            deleteKey()
            val privateKey = memScoped {
                corecall {
                    SecKeyCreateRandomKey(createCFDictionary {
                        kSecAttrKeyType mapsTo kSecAttrKeyTypeEC
                        kSecAttrKeySizeInBits mapsTo 256
                        kSecPrivateKeyAttrs mapsTo cfDictionaryOf(
                            kSecAttrIsPermanent to true,
                            kSecAttrApplicationTag to tag,
                        )
                    }, error)
                }.manage()
            }
            try {
                val signer = SignerAdapter.fromSecKey(privateKey.value, SignatureAlgorithm.ECDSAwithSHA256).getOrThrow()
                val message = "SecKey-backed Signum signer".encodeToByteArray()

                signer.makeVerifier().getOrThrow().verify(message, signer.sign(message).signature).getOrThrow()
            } finally {
                deleteKey()
            }
        }
    }
}
