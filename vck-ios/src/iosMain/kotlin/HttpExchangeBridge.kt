import at.asitplus.signum.internals.toNSData
import at.asitplus.wallet.lib.ProtocolRequest
import at.asitplus.wallet.lib.ReceivedHttpResponse
import io.ktor.http.Headers
import io.ktor.http.HttpStatusCode
import platform.Foundation.NSData

/** A [ProtocolRequest] flattened to Foundation types, to be sent with `URLSession`. */
class SwiftHttpRequest internal constructor(
    val url: String,
    val method: String,
    /** Values of repeated headers are joined with `, ` (RFC 9110, 5.3). */
    val headers: Map<String, String>,
    val contentType: String?,
    val body: NSData?,
)

/** Converts VC-K's transport-agnostic HTTP types, whose ktor types Swift cannot easily build or read. */
object HttpExchangeBridge {
    fun request(request: ProtocolRequest): SwiftHttpRequest = with(request.http) {
        SwiftHttpRequest(
            url = url,
            method = method.value,
            headers = headers.entries().associate { (name, values) -> name to values.joinToString(", ") },
            contentType = body?.contentType?.toString(),
            body = body?.text?.encodeToByteArray()?.toNSData(),
        )
    }

    fun response(status: Int, headers: Map<String, String>, body: String): ReceivedHttpResponse =
        ReceivedHttpResponse(
            status = HttpStatusCode.fromValue(status),
            headers = Headers.build { headers.forEach { (name, value) -> append(name, value) } },
            body = body,
        )
}
