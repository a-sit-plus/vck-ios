@file:OptIn(ExperimentalObjCName::class, ExperimentalSerializationApi::class)

import at.asitplus.dif.PresentationSubmission
import at.asitplus.signum.indispensable.cosef.CoseHeader
import at.asitplus.signum.indispensable.cosef.io.coseCompliantSerializer
import at.asitplus.signum.indispensable.josef.JwsHeader
import at.asitplus.signum.indispensable.josef.io.joseCompliantSerializer
import at.asitplus.signum.internals.toByteArray
import at.asitplus.signum.internals.toNSData
import at.asitplus.openid.ClientNonceResponse
import at.asitplus.openid.CredentialResponseParameters
import at.asitplus.openid.CredentialRequestParameters
import at.asitplus.wallet.lib.data.KeyBindingJws
import kotlinx.serialization.decodeFromByteArray
import kotlinx.serialization.encodeToByteArray
import kotlinx.serialization.SerializationException
import kotlinx.serialization.ExperimentalSerializationApi
import platform.Foundation.NSData
import kotlin.experimental.ExperimentalObjCName

object VckSerializer {

    // JOSE / JSON

    // JwsHeader

    @Throws(SerializationException::class)
    fun joseDeserializeJwsHeader(@ObjCName("_") string: String): JwsHeader =
        joseCompliantSerializer.decodeFromString<JwsHeader>(string)

    @Throws(SerializationException::class)
    fun joseSerializeJwsHeader(@ObjCName("_") header: JwsHeader): NSData =
        joseCompliantSerializer.encodeToString(header).encodeToByteArray().toNSData()

    // KeyBindingJws

    @Throws(SerializationException::class)
    fun joseSerializeKeyBindingJws(@ObjCName("_") binding: KeyBindingJws): NSData =
        joseCompliantSerializer.encodeToString(binding).encodeToByteArray().toNSData()


    // NonceResponse

    @Throws(SerializationException::class)
    fun joseDeserializeClientNonceResponse(@ObjCName("_") data: NSData): ClientNonceResponse =
        joseCompliantSerializer.decodeFromString<ClientNonceResponse>(data.toByteArray().decodeToString())

    // CredentialResponseParameters

    @Throws(SerializationException::class)
    fun joseDeserializeCredentialResponseParameters(@ObjCName("_") data: NSData): CredentialResponseParameters =
        joseCompliantSerializer.decodeFromString<CredentialResponseParameters>(data.toByteArray().decodeToString())

    // CredentialRequestParameters

    @Throws(SerializationException::class)
    fun joseDeserializeCredentialRequestParameters(@ObjCName("_") data: NSData): CredentialRequestParameters =
        joseCompliantSerializer.decodeFromString<CredentialRequestParameters>(data.toByteArray().decodeToString())

    @Throws(SerializationException::class)
    fun joseSerializeCredentialRequestParameters(@ObjCName("_") response: CredentialRequestParameters): NSData =
        joseCompliantSerializer.encodeToString(response).encodeToByteArray().toNSData()

    // PresentationSubmission

    @Throws(SerializationException::class)
    fun joseSerializePresentationSubmission(@ObjCName("_") submission: PresentationSubmission): String =
        joseCompliantSerializer.encodeToString(submission)

    // COSE / binary

    // CoseHeader

    @OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)
    @Throws(SerializationException::class)
    fun coseDeserializeCoseHeader(@ObjCName("_") data: NSData): CoseHeader =
        coseCompliantSerializer.decodeFromByteArray<CoseHeader>(data.toByteArray())

    @OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)
    @Throws(SerializationException::class)
    fun coseSerializeCoseHeader(@ObjCName("_") header: CoseHeader): NSData =
        coseCompliantSerializer.encodeToByteArray(header).toNSData()
}