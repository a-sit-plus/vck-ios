@file:OptIn(ExperimentalObjCName::class, ExperimentalSerializationApi::class)

import at.asitplus.KmmResult
import at.asitplus.catching
import at.asitplus.dcapi.ios.IosDcApiMdocPreRequestSummary
import at.asitplus.dcapi.request.IsoMdocRequest
import at.asitplus.iso.IssuerSigned
import at.asitplus.signum.indispensable.cosef.CoseHeader
import at.asitplus.signum.indispensable.cosef.io.coseCompliantSerializer
import at.asitplus.signum.indispensable.josef.JsonWebKey
import at.asitplus.signum.indispensable.josef.JwsHeader
import at.asitplus.signum.indispensable.josef.JwsCompactTyped
import at.asitplus.signum.indispensable.josef.KeyAttestationJwt
import at.asitplus.signum.indispensable.josef.io.joseCompliantSerializer
import at.asitplus.signum.internals.toByteArray
import at.asitplus.signum.internals.toNSData
import at.asitplus.openid.ClientNonceResponse
import at.asitplus.openid.OAuth2AuthorizationServerMetadata
import at.asitplus.openid.TokenResponseParameters
import at.asitplus.openid.IssuerMetadata
import at.asitplus.openid.CredentialResponseParameters
import at.asitplus.openid.CredentialRequestParameters
import at.asitplus.wallet.lib.agent.SubjectCredentialStore
import at.asitplus.wallet.lib.data.KeyBindingJws
import at.asitplus.wallet.lib.ktor.openid.ProvisioningContext
import at.asitplus.wallet.lib.openid.AuthorizationResponsePreparationState
import at.asitplus.wallet.lib.data.SelectiveDisclosureItem
import at.asitplus.wallet.lib.data.VerifiableCredentialJws
import at.asitplus.wallet.lib.data.VerifiableCredentialSdJwt
import kotlinx.serialization.decodeFromByteArray
import kotlinx.serialization.encodeToByteArray
import kotlinx.serialization.SerializationException
import kotlinx.serialization.ExperimentalSerializationApi
import platform.Foundation.NSData
import kotlin.experimental.ExperimentalObjCName

object VckSerializer {

    // JOSE / JSON

    /** Parses compact JWS and its payload; does not verify the attestation signature. */
    @Throws(SerializationException::class)
    fun joseDeserializeKeyAttestationJwt(@ObjCName("_") string: String): JwsCompactTyped<KeyAttestationJwt> =
        JwsCompactTyped<KeyAttestationJwt>(string)

    // JwsHeader

    @Throws(SerializationException::class)
    fun joseDeserializeJwsHeader(@ObjCName("_") string: String): JwsHeader =
        joseCompliantSerializer.decodeFromString<JwsHeader>(string)

    @Throws(SerializationException::class)
    fun joseSerializeJwsHeader(@ObjCName("_") header: JwsHeader): NSData =
        joseCompliantSerializer.encodeToString(header).encodeToByteArray().toNSData()

    // JsonWebKey, replacing the deprecated JsonWebKey.serialize()

    @Throws(SerializationException::class)
    fun joseDeserializeJsonWebKey(@ObjCName("_") data: NSData): JsonWebKey =
        joseCompliantSerializer.decodeFromString<JsonWebKey>(data.toByteArray().decodeToString())

    @Throws(SerializationException::class)
    fun joseSerializeJsonWebKey(@ObjCName("_") key: JsonWebKey): NSData =
        joseCompliantSerializer.encodeToString(key).encodeToByteArray().toNSData()

    // KeyBindingJws

    @Throws(SerializationException::class)
    fun joseSerializeKeyBindingJws(@ObjCName("_") binding: KeyBindingJws): NSData =
        joseCompliantSerializer.encodeToString(binding).encodeToByteArray().toNSData()

    @Throws(SerializationException::class)
    fun joseDeserializeVerifiableCredentialJws(@ObjCName("_") string: String): VerifiableCredentialJws =
        joseCompliantSerializer.decodeFromString<VerifiableCredentialJws>(string)

    @Throws(SerializationException::class)
    fun joseDeserializeVerifiableCredentialSdJwt(@ObjCName("_") string: String): VerifiableCredentialSdJwt =
        joseCompliantSerializer.decodeFromString<VerifiableCredentialSdJwt>(string)

    @Throws(SerializationException::class)
    fun joseDeserializeSelectiveDisclosureItem(@ObjCName("_") string: String): SelectiveDisclosureItem =
        joseCompliantSerializer.decodeFromString<SelectiveDisclosureItem>(string)


    // OAuth 2.0: authorization server metadata and token response, e.g. for OpenId4VciClientAdapter.createCredential

    @Throws(SerializationException::class)
    fun joseDeserializeOAuth2AuthorizationServerMetadata(@ObjCName("_") data: NSData): OAuth2AuthorizationServerMetadata =
        joseCompliantSerializer.decodeFromString<OAuth2AuthorizationServerMetadata>(data.toByteArray().decodeToString())

    @Throws(SerializationException::class)
    fun joseDeserializeTokenResponseParameters(@ObjCName("_") data: NSData): TokenResponseParameters =
        joseCompliantSerializer.decodeFromString<TokenResponseParameters>(data.toByteArray().decodeToString())

    @Throws(SerializationException::class)
    fun joseSerializeTokenResponseParameters(@ObjCName("_") response: TokenResponseParameters): NSData =
        joseCompliantSerializer.encodeToString(response).encodeToByteArray().toNSData()

    // Persistence: a Swift SubjectCredentialStore, and flows interrupted by the browser or the app being killed

    @Throws(SerializationException::class)
    fun joseDeserializeStoreEntry(@ObjCName("_") data: NSData): SubjectCredentialStore.StoreEntry =
        joseCompliantSerializer.decodeFromString<SubjectCredentialStore.StoreEntry>(data.toByteArray().decodeToString())

    @Throws(SerializationException::class)
    fun joseSerializeStoreEntry(@ObjCName("_") entry: SubjectCredentialStore.StoreEntry): NSData =
        joseCompliantSerializer.encodeToString(entry).encodeToByteArray().toNSData()

    @Throws(SerializationException::class)
    fun joseDeserializeProvisioningContext(@ObjCName("_") data: NSData): ProvisioningContext =
        joseCompliantSerializer.decodeFromString<ProvisioningContext>(data.toByteArray().decodeToString())

    @Throws(SerializationException::class)
    fun joseSerializeProvisioningContext(@ObjCName("_") context: ProvisioningContext): NSData =
        joseCompliantSerializer.encodeToString(context).encodeToByteArray().toNSData()

    @Throws(SerializationException::class)
    fun joseDeserializeAuthorizationResponsePreparationState(
        @ObjCName("_") data: NSData,
    ): AuthorizationResponsePreparationState = joseCompliantSerializer
        .decodeFromString<AuthorizationResponsePreparationState>(data.toByteArray().decodeToString())

    @Throws(SerializationException::class)
    fun joseSerializeAuthorizationResponsePreparationState(
        @ObjCName("_") state: AuthorizationResponsePreparationState,
    ): NSData = joseCompliantSerializer.encodeToString(state).encodeToByteArray().toNSData()

    // NonceResponse

    @Throws(SerializationException::class)
    fun joseDeserializeClientNonceResponse(@ObjCName("_") data: NSData): ClientNonceResponse =
        joseCompliantSerializer.decodeFromString<ClientNonceResponse>(data.toByteArray().decodeToString())

    // IssuerMetadata

    @Throws(SerializationException::class)
    fun joseDeserializeIssuerMetadata(@ObjCName("_") data: NSData): IssuerMetadata =
        joseCompliantSerializer.decodeFromString<IssuerMetadata>(data.toByteArray().decodeToString())

    @Throws(SerializationException::class)
    fun joseSerializeIssuerMetadata(@ObjCName("_") metadata: IssuerMetadata): NSData =
        joseCompliantSerializer.encodeToString(metadata).encodeToByteArray().toNSData()

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

    // Digital Credentials API

    @Throws(SerializationException::class)
    fun joseDeserializeIsoMdocRequest(@ObjCName("_") data: NSData): IsoMdocRequest =
        joseCompliantSerializer.decodeFromString<IsoMdocRequest>(data.toByteArray().decodeToString())

    @Throws(SerializationException::class)
    fun joseSerializeIsoMdocRequest(@ObjCName("_") request: IsoMdocRequest): NSData =
        joseCompliantSerializer.encodeToString(request).encodeToByteArray().toNSData()

    @Throws(SerializationException::class)
    fun joseDeserializeIosDcApiMdocPreRequestSummary(@ObjCName("_") data: NSData): IosDcApiMdocPreRequestSummary =
        joseCompliantSerializer.decodeFromString<IosDcApiMdocPreRequestSummary>(data.toByteArray().decodeToString())

    @Throws(SerializationException::class)
    fun joseSerializeIosDcApiMdocPreRequestSummary(@ObjCName("_") summary: IosDcApiMdocPreRequestSummary): NSData =
        joseCompliantSerializer.encodeToString(summary).encodeToByteArray().toNSData()

    // COSE / binary

    // CoseHeader

    @OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)
    @Throws(SerializationException::class)
    fun coseDeserializeCoseHeader(@ObjCName("_") data: NSData): CoseHeader =
        coseCompliantSerializer.decodeFromByteArray<CoseHeader>(data.toByteArray())

    @Throws(SerializationException::class)
    fun coseDeserializeIssuerSigned(@ObjCName("_") data: NSData): IssuerSigned =
        coseCompliantSerializer.decodeFromByteArray<IssuerSigned>(data.toByteArray())

    @OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)
    @Throws(SerializationException::class)
    fun coseSerializeCoseHeader(@ObjCName("_") header: CoseHeader): NSData =
        coseCompliantSerializer.encodeToByteArray(header).toNSData()
}
