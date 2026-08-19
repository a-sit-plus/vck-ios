import at.asitplus.wallet.lib.agent.EphemeralKeyWithoutCert
import at.asitplus.wallet.lib.agent.HolderAgent
import at.asitplus.wallet.lib.agent.InMemorySubjectCredentialStore
import at.asitplus.wallet.lib.agent.KeyMaterial
import at.asitplus.wallet.lib.agent.SubjectCredentialStore
import at.asitplus.wallet.lib.agent.Validator
import at.asitplus.wallet.lib.agent.ValidatorMdoc
import at.asitplus.wallet.lib.agent.ValidatorSdJwt
import at.asitplus.wallet.lib.agent.ValidatorVcJws
import at.asitplus.wallet.lib.agent.VerifiablePresentationFactory
import at.asitplus.wallet.lib.data.KeyBindingJws
import at.asitplus.wallet.lib.data.VerifiablePresentationJws
import at.asitplus.wallet.lib.data.dif.PresentationExchangeInputEvaluator
import at.asitplus.wallet.lib.jws.JwsHeaderCertOrJwk
import at.asitplus.wallet.lib.jws.JwsHeaderNone
import at.asitplus.wallet.lib.jws.SignJwt
import at.asitplus.wallet.lib.jws.SignJwtFun

/** Swift-friendly configuration for [HolderAgent].  in the cheapest way possible*/
class HolderAgentBuilder(
    val keyMaterial: KeyMaterial,
    val subjectCredentialStore: SubjectCredentialStore,
) {
    constructor() : this(EphemeralKeyWithoutCert(), InMemorySubjectCredentialStore())

    var validator: Validator = Validator()
    var validatorVcJws: ValidatorVcJws = ValidatorVcJws(validator = validator)
    var validatorSdJwt: ValidatorSdJwt = ValidatorSdJwt(validator = validator)
    var validatorMdoc: ValidatorMdoc = ValidatorMdoc(validator = validator)
    var signVerifiablePresentation: SignJwtFun<VerifiablePresentationJws> =
        SignJwt(keyMaterial, JwsHeaderCertOrJwk())
    var signKeyBinding: SignJwtFun<KeyBindingJws> = SignJwt(keyMaterial, JwsHeaderNone())
    var verifiablePresentationFactory: VerifiablePresentationFactory =
        VerifiablePresentationFactory(keyMaterial, signVerifiablePresentation, signKeyBinding)
    var difInputEvaluator: PresentationExchangeInputEvaluator = PresentationExchangeInputEvaluator

    fun build(): HolderAgent = HolderAgent(
        keyMaterial = keyMaterial,
        subjectCredentialStore = subjectCredentialStore,
        validator = validator,
        validatorVcJws = validatorVcJws,
        validatorSdJwt = validatorSdJwt,
        validatorMdoc = validatorMdoc,
        signVerifiablePresentation = signVerifiablePresentation,
        signKeyBinding = signKeyBinding,
        verifiablePresentationFactory = verifiablePresentationFactory,
        difInputEvaluator = difInputEvaluator,
    )
}
