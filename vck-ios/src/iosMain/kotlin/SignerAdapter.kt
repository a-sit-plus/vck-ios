import at.asitplus.KmmResult
import at.asitplus.signum.supreme.os.PlatformSigningProvider
import at.asitplus.signum.supreme.sign.Signer

object SignerAdapter {
    suspend fun load(alias: String, unlockMessage: String, cancelMessage: String): KmmResult<Signer> =
        PlatformSigningProvider.getSignerForKey(alias) {
            unlockPrompt {
                message = unlockMessage
                cancelText = cancelMessage
            }
        }
}