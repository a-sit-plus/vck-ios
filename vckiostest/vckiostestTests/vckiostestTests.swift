//
//  vckiostestTests.swift
//  vckiostestTests
//
//  Created by Bernd Prünster on 22.07.26.
//

import Testing
import Foundation
import vck_ios

struct vckiostestTests {

    @Test func byteArrayConversions() throws {
        let bytes = Array(UInt8.min...UInt8.max)
        let kotlin = try bytes.kotlinByteArray
        #expect(kotlin.bytes == bytes)
        #expect(kotlin.data == Data(bytes))
        #expect(try Data().kotlinByteArray.bytes.isEmpty)
        kotlin.set(index: 0, value: -1)
        #expect(bytes[0] == 0)
        #expect(kotlin.bytes[0] == 255)
    }

    @Test func swiftSuspendClosures() async throws {
        let zero = SwiftSuspendFunction0 { "zero" }
        #expect(try await zero() as? String == "zero")
        let one = SwiftSuspendFunction1 { (value: String) in value.uppercased() }
        #expect(try await one("one") as? String == "ONE")
        let two = SwiftSuspendFunction2 { (a: String, b: String) in a + b }
        #expect(try await two("a", "b") as? String == "ab")
        let optional = SwiftSuspendFunction1 { (value: String?) -> String? in value }
        #expect(try await optional(nil) == nil)
        await #expect(throws: (any Error).self) { try await one(KotlinInt(int: 42)) }
        let failing = SwiftSuspendFunction0<String> {
            throw NSError(domain: "test", code: 7)
        }
        await #expect(throws: (any Error).self) { try await failing() }
        let cancelled = SwiftSuspendFunction0<String> { throw CancellationError() }
        await #expect(throws: CancellationError.self) { try await cancelled() }
        let unit = SwiftSuspendFunction0 { () }
        #expect(try await unit() is KotlinUnit)
    }

    @Test func kotlinResultErrors() throws {
        let success = KmmResult<NSString>(value: "ok")
        #expect(try kotlinValue(success) == "ok")
        let failure = KmmResult<NSString>(failure: KotlinIllegalArgumentException(message: "failed"))
        #expect(throws: (any Error).self) { try kotlinValue(failure) }
    }

    @Test func walletServiceDefaults() throws {
        let firstKey = WalletServiceDefaults.keyMaterial
        let secondKey = WalletServiceDefaults.keyMaterial
        #expect(firstKey !== secondKey)
        #expect(WalletServiceDefaults.encryptionService !== WalletServiceDefaults.encryptionService)
        let wallet = WalletServiceAdapter()
        #expect(wallet.service.clientId == "https://wallet.a-sit.at/app")
        let details = try #require(wallet.buildAuthorizationDetails(credentialConfigurationId: "pid").first)
        #expect(details.credentialConfigurationId == "pid")
        #expect(details.locations == nil)

        let custom = WalletServiceAdapter(clientId: "https://custom.example/wallet")
        #expect(custom.service.clientId == "https://custom.example/wallet")
        let servers: Set<String> = ["https://auth.example"]
        let multiple = custom.buildAuthorizationDetails(
            credentialConfigurationIds: ["pid", "mdl"], authorizationServers: servers
        )
        #expect(multiple.count == 2)
        #expect(multiple.allSatisfy { $0.locations == servers })

        let before = ClockAdapter.system.now()
        #expect(ClockAdapter.system.now().compareTo(other: before) >= 0)
    }

}
