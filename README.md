# VC-K iOS Framework

./vckiostest is a test app. to run:
* Build an xcframework from this root: `./gradlew assembleVck-iosDebugXCFramework`
* The debug framework is _LINKED_ from the vckiostest XCode app, no no copying
* Build and run iOS app on simulator or physical device (issuance needs a physical device: `BasicWallet` gets a
  Wallet Instance Attestation and key attestations from `wallet-provider.a-sit.plus` via App Attest, as Valera
  does, so the wallet provider must accept the app's App ID)
* Enjoy

The Swift adapter is bundled into the framework by SKIE; external default-argument
overload generation stays disabled.

```swift
import vck_ios

let keyMaterial = OpenId4VciClientDefaults.keyMaterial
let wallet = OpenId4VciClientAdapter(clientId: "https://wallet.example", keyMaterial: keyMaterial)
let details = wallet.buildAuthorizationDetails(credentialConfigurationId: "pid")
let clock = ClockAdapter.system // Kotlin Clock.System
let metadata = try VckSerializer.shared.joseDeserializeIssuerMetadata(jsonData)
let json = try VckSerializer.shared.joseSerializeIssuerMetadata(metadata)
let tokenResponse = TokenResponseParameters(accessToken: "token", tokenType: "Bearer")
let requests = try await wallet.createCredential(
    tokenResponse: tokenResponse, metadata: metadata, credentialFormat: credentialFormat
)
```

Use `wallet.client` for the remaining `OpenId4VciClient` API (VC-K 9 renamed
`WalletService`; the old adapter names remain as deprecated aliases). Optional constructor arguments (including the proof `clock`) and
`createCredential`'s nonce, scope, and client ID can all be overridden; pass
`proofCreators:` to choose the proofs yourself. Since VC-K 9, `createCredential` only
requests the given `credentialFormat`, even if the token's scope grants more.
`OpenId4VciClientDefaults` and `ClockAdapter` expose Swift static accessors.
Default key material and encryption services are fresh
instances on each access.

Swift closures can implement Kotlin suspend callbacks without handwritten protocol
conformance:

```swift
let retriever = SwiftSuspendFunction1 { (input: RemoteResourceRetrieverInput) -> String? in
    guard let url = URL(string: input.url) else { throw URLError(.badURL) }
    let (data, _) = try await URLSession.shared.data(from: url)
    return String(data: data, encoding: .utf8)
}
let wallet = OpenId4VciClientAdapter(remoteResourceRetriever: retriever)
let response = try await retriever(input) // safe callable syntax, not the raw invoke export
let kotlinBytes = try Data([0, 128, 255]).kotlinByteArray
let swiftBytes = kotlinBytes.bytes // or kotlinBytes.data
let value = try kotlinValue(result) // safe, typed KmmResult unwrapping
```

`SwiftSuspendFunction0`, `SwiftSuspendFunction1`, and `SwiftSuspendFunction2` accept
`async throws` closures. Specify the actual Kotlin parameter and return types;
primitive nullable parameters may arrive as Kotlin number wrappers. Ordinary
non-suspending Kotlin lambdas already export as Swift closures and need no shim.
Conversions copy byte buffers, preserving unsigned Swift byte values.
The retrieval example handles GET responses; implement POST and header handling
when required by the issuer's flow.

`loadKeyAttestation` must return a `KmmResult` containing a typed compact JWS, not
a `String` or `KmmResult<NSString>`. Parse the compact `attestationProof` string in Kotlin:

```swift
let loadAttestation = SwiftSuspendFunction1 { (input: OpenId4VciClient.KeyAttestationInput) in
    let attestationProof: String = try await fetchAttestationProof(input)
    return KmmResult(value: try VckSerializer.shared.joseDeserializeKeyAttestationJwt(attestationProof))
}
let wallet = OpenId4VciClientAdapter(loadKeyAttestation: loadAttestation)
```

The throwing helper returns `JwsTyped<JwsCompact, KeyAttestationJwt>`; Kotlin's
`JwsCompactTyped` typealias is exported as `JwsTyped`. Invalid compact JWS or payload
data throws a Swift error. Wrap the parsed value in `KmmResult` for the callback.
Parsing does not verify the attestation's signature.

Use callable syntax (`try await callback(argument)`) when invoking callbacks from
Swift. It routes through a Kotlin export annotated with `@Throws(Throwable::class)`.
The raw `invoke` export only allows Kotlin `CancellationException`; other Swift
errors become `ObjCErrorException` and can abort the process. Similarly, use
`try kotlinValue(result)` rather than an unannotated `getOrThrow()` across the Swift boundary.

The adapters preserve thrown Swift `CancellationError` as Kotlin cancellation, but
Kotlin cancelling a coroutine does not cancel an already-running Swift closure.
[SKIE documents this limitation](https://skie.touchlab.co/features/suspend#overriding-suspend-functions)
for Swift implementations of suspend interfaces.
Keep side effects in callbacks aware of the lifetime of the operation.

Run the saved simulator checks with a booted ARM64 iOS simulator:

```sh
zsh checks/interop.sh
# These modes intentionally reproduce process-aborting error exports:
zsh checks/interop.sh booted --raw-error
zsh checks/interop.sh booted --raw-store-error
zsh checks/interop.sh booted --raw-store-cancellation
zsh checks/interop.sh booted --raw-result-error
```

The store reproducer uses a minimal Swift `SubjectCredentialStore` implementation;
it does not reproduce any historical app crash without its stack trace.

Swift stores can implement `SwiftCredentialStore` with ordinary `getCredentials`
and `storeCredential` method names and Swift arrays. Pass the thin adapter to Kotlin:

```swift
let store = SubjectCredentialStoreAdapter(SwiftSubjectCredentialStore())
let wallet = BasicWallet(keyMaterial: keyMaterial, subjectCredentialStore: store)
```

The adapter contains the `__` protocol requirements, reports read failures as
`KmmResult` failures, and converts thrown Swift cancellation to Kotlin cancellation.
Write failures still require a Kotlin caller that catches them or exports them
with `@Throws`; the raw upstream `storeCredential` export allows only cancellation.

## VC-K 9 interop

OpenID4VP protocol clients return HTTP exchanges for any HTTP stack. Run them with
`URLSession` (redirects are not followed, as in VC-K's ktor clients):

```swift
let client = OpenId4VpProtocolClient(openId4VpHolder: builder.build())
let state = try await client.prepareAuthorizationResponse(input: requestUrl)
    .run(as: AuthorizationResponsePreparationState.self)
// ... finalizeAuthorizationResponse on the holder, then for direct_post:
let redirectUri = try await client.sendAuthorizationResponse(response: post).run(as: String?.self)
```

Validation takes a `ValidationPolicy`, which has no default in VC-K 9. Kotlin's
`Duration` reaches Swift as raw `Int64` bits, so build policies and validators with
the factories, which take seconds and supply Kotlin's defaults:

```swift
let policy = try ValidationPolicy.create(
    trust: TrustPolicyIntegrityOnly.shared, status: StatusPolicySkip.shared,
    timeLeeway: 300, requireTimeliness: true
)
builder.relyingPartyValidator = try RelyingPartyValidator.create(trust: .create(accessCertificates: anchors))
holderBuilder.credentialValidator = CredentialValidator.create(trustAnchors: issuerAnchors)
```

A Swift `SwiftCredentialStore` implements `getCredentials` and `storeCredential(entry:)`;
persist entries with `VckSerializer.shared.joseSerializeStoreEntry(_:)`. `VckSerializer`
also (de)serializes `ProvisioningContext` and `AuthorizationResponsePreparationState`
(to resume flows after the app was killed), `TokenResponseParameters`,
`OAuth2AuthorizationServerMetadata`, and `JsonWebKey` (instead of the deprecated
`serialize()`).
