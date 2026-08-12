@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)

import at.asitplus.KmmResult
import at.asitplus.catching
import at.asitplus.signum.indispensable.CryptoPrivateKey
import at.asitplus.signum.indispensable.CryptoPublicKey
import at.asitplus.signum.indispensable.CryptoSignature
import at.asitplus.signum.indispensable.KeyAgreementPublicValue
import at.asitplus.signum.indispensable.SecretExposure
import at.asitplus.signum.indispensable.SignatureAlgorithm
import at.asitplus.signum.indispensable.secKeyAlgorithmPreHashed
import at.asitplus.signum.internals.OwnedCFValue
import at.asitplus.signum.internals.corecall
import at.asitplus.signum.internals.giveToCF
import at.asitplus.signum.internals.manage
import at.asitplus.signum.internals.takeFromCF
import at.asitplus.signum.internals.toByteArray
import at.asitplus.signum.internals.toNSData
import at.asitplus.signum.supreme.SignatureResult
import at.asitplus.signum.supreme.os.PlatformSigningProvider
import at.asitplus.signum.supreme.sign.SignatureInput
import at.asitplus.signum.supreme.sign.Signer
import at.asitplus.signum.supreme.sign.preHashedSignatureFormat
import platform.CoreFoundation.CFRetain
import platform.Foundation.NSData
import platform.Security.SecKeyCopyExternalRepresentation
import platform.Security.SecKeyCopyPublicKey
import platform.Security.SecKeyCreateSignature
import platform.Security.SecKeyIsAlgorithmSupported
import platform.Security.SecKeyRef
import platform.Security.kSecKeyOperationTypeSign

object SignerAdapter {

    @Suppress("UNCHECKED_CAST")
    fun fromSecKey(privateKey: SecKeyRef?, algorithm: SignatureAlgorithm): KmmResult<Signer> = catching {
        val key = requireNotNull(privateKey) { "privateKey must not be null" }
        require(SecKeyIsAlgorithmSupported(key, kSecKeyOperationTypeSign, algorithm.secKeyAlgorithmPreHashed)) {
            "SecKey does not support $algorithm"
        }
        val retainedKey = (CFRetain(key) as SecKeyRef).manage()
        val publicKey = corecall { SecKeyCopyPublicKey(retainedKey.value) }.manage()
        val publicKeyBytes = corecall { SecKeyCopyExternalRepresentation(publicKey.value, error) }
            .takeFromCF<NSData>().toByteArray()

        when (val parsedPublicKey = CryptoPublicKey.fromIosEncoded(publicKeyBytes)) {
            is CryptoPublicKey.EC -> {
                val ecAlgorithm = algorithm as? SignatureAlgorithm.ECDSA
                    ?: throw IllegalArgumentException("EC SecKey requires an ECDSA algorithm")
                require(ecAlgorithm.requiredCurve == null || ecAlgorithm.requiredCurve == parsedPublicKey.curve) {
                    "ECDSA curve does not match SecKey"
                }
                SecKeySigner.EC(retainedKey, parsedPublicKey, ecAlgorithm)
            }
            is CryptoPublicKey.RSA -> SecKeySigner.RSA(retainedKey, parsedPublicKey, algorithm as? SignatureAlgorithm.RSA
                ?: throw IllegalArgumentException("RSA SecKey requires an RSA algorithm"))
        }
    }
}

private sealed class SecKeySigner(protected val privateKey: OwnedCFValue<SecKeyRef>) : Signer {
    final override val mayRequireUserUnlock = true

    final override suspend fun sign(data: SignatureInput): SignatureResult<*> = try {
        val digest = data.convertTo(signatureAlgorithm.preHashedSignatureFormat).getOrThrow().data.single().toNSData()
        val signature = corecall {
            SecKeyCreateSignature(privateKey.value, signatureAlgorithm.secKeyAlgorithmPreHashed, digest.let(::giveToCF), error)
        }.takeFromCF<NSData>().toByteArray()

        SignatureResult.Success(when (val key = publicKey) {
            is CryptoPublicKey.EC -> CryptoSignature.EC.decodeFromDer(signature).withCurve(key.curve)
            is CryptoPublicKey.RSA -> CryptoSignature.RSA(signature)
        })
    } catch (exception: Throwable) {
        SignatureResult.FromException(exception)
    }

    class EC(
        privateKey: OwnedCFValue<SecKeyRef>,
        override val publicKey: CryptoPublicKey.EC,
        override val signatureAlgorithm: SignatureAlgorithm.ECDSA,
    ) : SecKeySigner(privateKey), Signer.ECDSA {
        @SecretExposure
        override fun exportPrivateKey(): KmmResult<CryptoPrivateKey.EC.WithPublicKey> =
            KmmResult.failure(UnsupportedOperationException("SecKey-backed private keys cannot be exported"))

        override suspend fun keyAgreement(publicValue: KeyAgreementPublicValue.ECDH): KmmResult<ByteArray> =
            KmmResult.failure(UnsupportedOperationException("SecKeySigner only supports signing"))
    }

    class RSA(
        privateKey: OwnedCFValue<SecKeyRef>,
        override val publicKey: CryptoPublicKey.RSA,
        override val signatureAlgorithm: SignatureAlgorithm.RSA,
    ) : SecKeySigner(privateKey), Signer.RSA {
        @SecretExposure
        override fun exportPrivateKey(): KmmResult<CryptoPrivateKey.RSA> =
            KmmResult.failure(UnsupportedOperationException("SecKey-backed private keys cannot be exported"))
    }
}
