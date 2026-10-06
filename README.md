# VC-K iOS Framework

./vckiostest is a test app. to run:
* Build an xcframework from this root: `./gradlew assembleVck-iosDebugXCFramework`
* The debug framework is _LINKED_ from the vckiostest XCode app, no no copying
* Build and run iOS app on simulator or physical device
* Enjoy

The Swift adapter is bundled into the framework by SKIE; external default-argument
overload generation stays disabled.

```swift
import vck_ios

let keyMaterial = WalletServiceDefaults.keyMaterial
let wallet = WalletServiceAdapter(clientId: "https://wallet.example", keyMaterial: keyMaterial)
let details = wallet.buildAuthorizationDetails(credentialConfigurationId: "pid")
let clock = ClockAdapter.system // Kotlin Clock.System
let metadata = try VckSerializer.shared.joseDeserializeIssuerMetadata(jsonData)
let json = try VckSerializer.shared.joseSerializeIssuerMetadata(metadata)
let requests = try await wallet.createCredential(
    tokenResponse: tokenResponse, metadata: metadata, credentialFormat: credentialFormat
)
```

Use `wallet.service` for the remaining WalletService API. Optional constructor
arguments and `createCredential`'s nonce, scope, and clock can all be overridden.
`WalletServiceDefaults` and `ClockAdapter` expose Swift static accessors.
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
let wallet = WalletServiceAdapter(remoteResourceRetriever: retriever)
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
