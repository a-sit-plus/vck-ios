# VC-K iOS Demo

`vckiostest` is an iOS app showing how to integrate [VC-K](https://github.com/a-sit-plus/vck) through its Swift
package: issue a credential with OpenID4VCI, and present it with OpenID4VP, holding the key in the Secure Enclave.

The Swift package, i.e. `VckIos.xcframework` with its Kotlin and Swift adapters, lives in VC-K (module `vck-ios`,
`Package.swift` in its root). This repository contains no Kotlin.

## Run

The Xcode project references a checkout of VC-K next to this repository (`../vck`) as a local package:

```sh
git clone https://github.com/a-sit-plus/vck ../vck
(cd ../vck && ./gradlew :vck-ios:assembleVckIosDebugXCFramework)
open vckiostest/vckiostest.xcodeproj
```

VC-K's `Package.swift` uses this debug build while it exists; see VC-K's `DEVELOPMENT.md`. After rebuilding it, use
*File* → *Packages* → *Reset Package Caches* in Xcode.

Run the app on a physical device, as the Secure Enclave is not available in the Simulator:

1. Issue: gets a Wallet Instance Attestation (WIA) from `wallet-provider.a-sit.plus`, loads the issuer's metadata and
   starts the authorization for the PID in SD-JWT format (`urn:eudi:pid:1#dc+sd-jwt`), e.g. of
   `https://wallet-issuer.a-sit.plus`, then requests the credential with the authorization code, with a key attestation
   for the holder key. The WIA binds a Secure Enclave key attested with App Attest, as in Valera, so the wallet provider
   has to accept the app's App ID.
2. Open the demo relying party's remote presentation case 1 (PID in SD-JWT format), start the request, and open it
   with the app, which handles its `eu-eaap://` link.
3. Parse the request and inspect the matching credentials.
4. Consent and present.

Run the unit tests on a simulator with:

```sh
cd vckiostest
xcodebuild test -project vckiostest.xcodeproj -scheme vckiostest -only-testing:vckiostestTests \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Use the released package

To depend on a released VC-K instead of the local checkout, replace the local package in Xcode with
`https://github.com/a-sit-plus/vck` and its product `VckIos`, or in a `Package.swift`:

```swift
.package(url: "https://github.com/a-sit-plus/vck", from: "10.0.0")
```

## Where to look

- [`DemoWallet.swift`](vckiostest/vckiostest/DemoWallet.swift): OpenID4VCI with `OpenId4VciProtocolClient`, sending
  its requests with `HttpExchange.run(as:)`, and validating and storing credentials with `HolderAgent`.
- [`WalletProviderClient.swift`](vckiostest/vckiostest/WalletProviderClient.swift): the WIA and key attestations from
  the wallet provider, attesting a Secure Enclave key with App Attest as Warden Supreme's client does, with the CSR
  built in [`CertificationRequest.swift`](vckiostest/vckiostest/CertificationRequest.swift). Only signature data
  authentication is implemented.
- [`ContentView.swift`](vckiostest/vckiostest/ContentView.swift): the Secure Enclave key as `KeyMaterial`, and
  OpenID4VP with `OpenId4VpHolderBuilder` and `OpenId4VpProtocolClient`.
- [`SwiftSubjectCredentialStore.swift`](vckiostest/vckiostest/SwiftSubjectCredentialStore.swift): a credential store
  in Swift, passed to VC-K with `SubjectCredentialStoreAdapter`.
- [`vckiostestTests.swift`](vckiostest/vckiostestTests/vckiostestTests.swift): the Swift adapters, e.g.
  `SwiftSuspendFunction1` for Kotlin suspend callbacks, `kotlinValue` to unwrap `KmmResult`s, `JoseCodec`, `JwsCompactCodec`, and
  `ValidationPolicy.create`.

## Swift interop notes

- Kotlin's default arguments are not exported. Use the builders (`HolderAgentBuilder`, `OpenId4VpHolderBuilder`) and
  factories with Swift defaults (`ValidationPolicy.create`, `OAuth2Client.create`, `OpenId4VciClientAdapter`, ...).
- `Duration` reaches Swift as raw `Int64` bits; the factories take seconds instead.
- Encode and decode any serializable type with `JoseCodec` or `CoseCodec`, e.g.
  `JoseCodec<ProvisioningContext>(serializer: ProvisioningContext.companion.serializer())`, and parse a compact JWS
  with `JwsCompactCodec`, e.g. `JwsCompactCodec<KeyAttestationJwt>(serializer: KeyAttestationJwt.companion.serializer())`.
- Call Kotlin callbacks with callable syntax (`try await callback(argument)`), and unwrap results with
  `try kotlinValue(result)` rather than `getOrThrow()`: the raw exports only allow `CancellationException`, so other
  errors would abort the process.
- Kotlin cancelling a coroutine does not cancel a Swift closure that is already running
  ([SKIE limitation](https://skie.touchlab.co/features/suspend#overriding-suspend-functions)).
- Read `error.oauth2Exception` for errors of the issuer or authorization server, and its `error` and
  `errorDescription`, as SKIE renames each subclass's `description` to `description_`.
