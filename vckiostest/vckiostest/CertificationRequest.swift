import Foundation
import Security

/// A PKCS#10 CSR attribute: `SEQUENCE { type OBJECT IDENTIFIER, values SET OF ANY }` with one value.
struct CsrAttribute {
    let oid: String
    /// The DER encoding of the single value.
    let value: Data

    func encoded() throws -> Data { Der.sequence([try Der.oid(oid), Der.set([value])]) }
}

/// Builds the P-256 CSR that Warden Supreme verifies, as its client does: the subject only contains a `serialNumber`
/// with the challenge nonce, and the attributes are in DER order.
enum CertificationRequest {
    static func signed(
        serialNumber: String,
        publicKey: Data,
        attributes: [CsrAttribute],
        privateKey: SecKey
    ) throws -> Data {
        let subject = Der.sequence([
            Der.set([Der.sequence([try Der.oid("2.5.4.5"), Der.printableString(serialNumber)])])
        ])
        let subjectPublicKeyInfo = Der.sequence([
            Der.sequence([try Der.oid("1.2.840.10045.2.1"), try Der.oid("1.2.840.10045.3.1.7")]),
            Der.bitString(publicKey),
        ])
        let tbs = Der.sequence([
            Der.integer(0),
            subject,
            subjectPublicKeyInfo,
            Der.implicitSet(tag: 0, try attributes.map { try $0.encoded() }),
        ])
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey, .ecdsaSignatureMessageX962SHA256, tbs as CFData, &error
        ) as Data? else { throw error!.takeRetainedValue() }
        return Der.sequence([tbs, Der.sequence([try Der.oid("1.2.840.10045.4.3.2")]), Der.bitString(signature)])
    }
}

/// The few DER encodings a CSR needs.
enum Der {
    static func sequence(_ items: [Data]) -> Data { tlv(0x30, items.reduce(Data(), +)) }

    /// `SET OF`, whose elements DER orders by their encodings.
    static func set(_ items: [Data]) -> Data { tlv(0x31, sorted(items)) }

    /// `[tag] IMPLICIT SET OF`, e.g. the attributes of a CSR.
    static func implicitSet(tag: UInt8, _ items: [Data]) -> Data { tlv(0xA0 | tag, sorted(items)) }

    /// A non-negative integer below 128.
    static func integer(_ value: UInt8) -> Data {
        precondition(value < 0x80)
        return tlv(0x02, Data([value]))
    }

    static func utf8String(_ value: String) -> Data { tlv(0x0C, Data(value.utf8)) }

    static func printableString(_ value: String) -> Data { tlv(0x13, Data(value.utf8)) }

    static func bitString(_ bytes: Data) -> Data { tlv(0x03, Data([0]) + bytes) }

    /// Arcs may exceed 64 bits, e.g. the UUID arcs below `2.25`.
    static func oid(_ dotted: String) throws -> Data {
        let arcs = try dotted.split(separator: ".").map { arc -> [UInt8] in
            guard !arc.isEmpty, arc.allSatisfy({ $0.isASCII && $0.isWholeNumber }) else { throw DerError("Invalid OID \(dotted)") }
            return arc.map { $0.asciiValue! - 0x30 }
        }
        guard arcs.count >= 2, arcs[0].count == 1, arcs[0][0] <= 2 else { throw DerError("Invalid OID \(dotted)") }
        var content = base128(add(arcs[1], UInt64(arcs[0][0]) * 40))
        for arc in arcs.dropFirst(2) { content.append(base128(arc)) }
        return tlv(0x06, content)
    }

    private static func tlv(_ tag: UInt8, _ content: Data) -> Data {
        var encoded = Data([tag])
        if content.count < 0x80 {
            encoded.append(UInt8(content.count))
        } else {
            var length = content.count
            var bytes: [UInt8] = []
            while length > 0 {
                bytes.insert(UInt8(length & 0xFF), at: 0)
                length >>= 8
            }
            encoded.append(0x80 | UInt8(bytes.count))
            encoded.append(contentsOf: bytes)
        }
        encoded.append(content)
        return encoded
    }

    private static func sorted(_ items: [Data]) -> Data {
        items.sorted { $0.lexicographicallyPrecedes($1) }.reduce(Data(), +)
    }

    /// Adds `value` to the decimal number `digits`, most significant digit first.
    private static func add(_ digits: [UInt8], _ value: UInt64) -> [UInt8] {
        var result = digits
        var carry = value
        var index = result.count - 1
        while carry > 0 {
            if index < 0 {
                result.insert(0, at: 0)
                index = 0
            }
            let sum = UInt64(result[index]) + carry % 10
            result[index] = UInt8(sum % 10)
            carry = carry / 10 + sum / 10
            index -= 1
        }
        return result
    }

    /// Base-128 digits of the decimal number `digits`, with the continuation bit set on all but the last.
    private static func base128(_ digits: [UInt8]) -> Data {
        var remaining = digits
        var groups: [UInt8] = []
        repeat {
            var remainder = 0
            var quotient: [UInt8] = []
            for digit in remaining {
                let current = remainder * 10 + Int(digit)
                if !quotient.isEmpty || current >= 128 { quotient.append(UInt8(current / 128)) }
                remainder = current % 128
            }
            groups.insert(UInt8(remainder), at: 0)
            remaining = quotient
        } while !remaining.isEmpty
        return Data(groups.enumerated().map { $0.offset < groups.count - 1 ? $0.element | 0x80 : $0.element })
    }
}

struct DerError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
