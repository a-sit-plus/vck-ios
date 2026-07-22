@file:OptIn(ExperimentalObjCName::class)

import at.asitplus.signum.indispensable.cosef.CoseHeader
import at.asitplus.signum.indispensable.cosef.io.coseCompliantSerializer
import at.asitplus.signum.indispensable.josef.JwsHeader
import at.asitplus.signum.indispensable.josef.io.joseCompliantSerializer
import at.asitplus.signum.internals.toByteArray
import at.asitplus.signum.internals.toNSData
import kotlinx.serialization.decodeFromByteArray
import kotlinx.serialization.encodeToByteArray
import platform.Foundation.NSData
import kotlin.experimental.ExperimentalObjCName

object VckSerializer {

    fun <T> joseDeserializeJwsHeader(@ObjCName("_") string: String): JwsHeader =
        joseCompliantSerializer.decodeFromString<JwsHeader>(string)

    fun <T> joseSerializeJwsHeader(@ObjCName("_") header: JwsHeader): String =
        joseCompliantSerializer.encodeToString(header)


    fun <T> coseDeserializeCoseHeader(@ObjCName("_") bytes: NSData): CoseHeader =
        coseCompliantSerializer.decodeFromByteArray<CoseHeader>(bytes.toByteArray())

    fun <T> coseSerializeCoseHeader(@ObjCName("_") header: CoseHeader): NSData =
        coseCompliantSerializer.encodeToByteArray(header).toNSData()

}