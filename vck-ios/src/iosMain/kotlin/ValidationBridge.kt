import at.asitplus.wallet.lib.validation.CredentialTrustAnchors
import at.asitplus.wallet.lib.validation.CredentialValidator
import at.asitplus.wallet.lib.validation.HolderBindingPolicy
import at.asitplus.wallet.lib.validation.RegistrationPolicy
import at.asitplus.wallet.lib.validation.RelyingPartyTrustAnchors
import at.asitplus.wallet.lib.validation.RelyingPartyValidator
import at.asitplus.wallet.lib.validation.RequiredClaimsPolicy
import at.asitplus.wallet.lib.agent.validation.StatusListTokenResolver
import at.asitplus.wallet.lib.validation.StatusPolicy
import at.asitplus.wallet.lib.validation.StatusValidator
import at.asitplus.wallet.lib.validation.TrustPolicy
import at.asitplus.wallet.lib.validation.ValidationPolicy
import kotlin.time.Duration.Companion.seconds

/**
 * Kotlin defaults and [kotlin.time.Duration] conversions that Swift cannot express directly:
 * a `Duration` reaches Swift as its raw `Int64` encoding, not as a number of seconds.
 */
object ValidationBridge {
    @Throws(IllegalArgumentException::class)
    fun policy(
        trust: TrustPolicy,
        status: StatusPolicy,
        timeLeewaySeconds: Double,
        requireTimeliness: Boolean,
        holderBinding: HolderBindingPolicy,
        requiredClaims: RequiredClaimsPolicy,
        registration: RegistrationPolicy,
    ): ValidationPolicy = ValidationPolicy(
        trust = trust,
        status = status,
        timeLeeway = timeLeewaySeconds.seconds,
        requireTimeliness = requireTimeliness,
        holderBinding = holderBinding,
        requiredClaims = requiredClaims,
        registration = registration,
    )

    fun statusValidator(statusListTokenResolver: StatusListTokenResolver?): StatusValidator =
        StatusValidator(statusListTokenResolver)

    fun credentialValidator(
        trustAnchors: CredentialTrustAnchors?,
        statusValidator: StatusValidator,
    ): CredentialValidator = CredentialValidator(trustAnchors, statusValidator)

    @Throws(IllegalArgumentException::class)
    fun relyingPartyValidator(
        trust: RelyingPartyTrustAnchors,
        statusValidator: StatusValidator,
        maxRegistrationValiditySeconds: Double,
    ): RelyingPartyValidator = RelyingPartyValidator(
        trust = trust,
        statusValidator = statusValidator,
        maxRegistrationValidity = maxRegistrationValiditySeconds.seconds,
    )
}
