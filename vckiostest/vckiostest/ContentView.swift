import AuthenticationServices
import Combine
import Security
import SwiftUI
import VckIos

private let secureEnclaveTag = Data("at.asitplus.wallet.vckiostest.holder".utf8)

private func loadOrCreateSecureEnclaveKey() throws -> SecKey {
    let query: [CFString: Any] = [
        kSecClass: kSecClassKey,
        kSecAttrApplicationTag: secureEnclaveTag,
        kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
        kSecReturnRef: true,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecSuccess, let key = item as! SecKey? { return key }
    guard status == errSecItemNotFound else {
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }

    var accessError: Unmanaged<CFError>?
    guard let access = SecAccessControlCreateWithFlags(
        kCFAllocatorDefault,
        kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        .privateKeyUsage,
        &accessError
    ) else { throw accessError!.takeRetainedValue() }

    let attributes: [CFString: Any] = [
        kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
        kSecAttrKeySizeInBits: 256,
        kSecAttrTokenID: kSecAttrTokenIDSecureEnclave,
        kSecPrivateKeyAttrs: [
            kSecAttrIsPermanent: true,
            kSecAttrApplicationTag: secureEnclaveTag,
            kSecAttrAccessControl: access,
        ],
    ]
    var keyError: Unmanaged<CFError>?
    guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &keyError) else {
        throw keyError!.takeRetainedValue()
    }
    return key
}

@MainActor
final class WalletModel: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published var issuer = "https://wallet-issuer.a-sit.plus"
    @Published var presentationRequest = ""
    @Published var log = "Ready. Run on a physical device (Secure Enclave is unavailable in Simulator)."
    @Published var busy = false
    @Published var hasPreparedPresentation = false

    private var wallet: DemoWallet?
    private var openId4VpHolder: OpenId4VpHolder?
    private var openId4VpClient: OpenId4VpProtocolClient?
    private var presentationState: AuthorizationResponsePreparationState?
    private var browserSession: ASWebAuthenticationSession?

    func issue() {
        Task { await run {
            let wallet = try self.walletInstance()
            let authUrl = try await wallet.startIssuance(issuer: self.issuer)
            self.append("Opening issuer login…")
            try await self.authenticate(at: authUrl)
        } }
    }

    func openRelyingParty() {
        // Remote presentation case 1: PID in SD-JWT format, with an OpenID4VP request opening `eu-eaap://`
        UIApplication.shared.open(URL(string: "https://wallet-rp.a-sit.plus/remote-case.html?id=1")!)
        append("In the RP, tap Start Request, then Open App Wallet.")
    }

    func handle(url: URL) {
        guard url.scheme != "asitplus-wallet" else { return }
        presentationState = nil
        hasPreparedPresentation = false
        presentationRequest = url.absoluteString
        append("OpenID4VP request received. Continue with step 3.")
    }

    func presentInput() {
        preparePresentation(presentationRequest)
    }

    private func preparePresentation(_ request: String) {
        Task { await run {
            self.presentationState = nil
            self.hasPreparedPresentation = false
            _ = try self.walletInstance()
            let state = try await self.openId4VpClient!.prepareAuthorizationResponse(input: request)
                .run(as: AuthorizationResponsePreparationState.self)
            let matches = try await kotlinValue(self.openId4VpHolder!
                .getMatchingCredentials(preparationState: state))!
            self.presentationState = state
            self.hasPreparedPresentation = true
            self.append("OpenID4VP request from \(state.audience) asks for:")
            for credential in state.request.parameters.dcqlQuery.map(requestedCredentials) ?? ["no DCQL query"] {
                self.append("- \(credential)")
            }
            self.append("Matching stored credentials: \(matchingCredentials(matches))")
        } }
    }

    func approvePresentation() {
        Task { await run {
            guard let state = self.presentationState else { return }
            let result = try await kotlinValue(self.openId4VpHolder!
                .finalizeAuthorizationResponse(
                    preparationState: state,
                    credentialPresentation: nil
                ))!
            let returnUrl = try await self.send(result)
            self.presentationState = nil
            self.hasPreparedPresentation = false
            self.append("User consented; presentation created and sent.")
            if let returnUrl, let url = URL(string: returnUrl) {
                await UIApplication.shared.open(url)
            }
        } }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)!.keyWindow!
    }

    private func walletInstance() throws -> DemoWallet {
        if let wallet { return wallet }
        // The Kotlin export takes the SecKey as an opaque pointer
        let key = try loadOrCreateSecureEnclaveKey()
        let pointer = Unmanaged.passUnretained(key).toOpaque()
        let keyMaterial = try kotlinValue(KeyMaterialAdapter.shared.fromSecKey(privateKey: pointer))!
        let store = SubjectCredentialStoreAdapter(SwiftSubjectCredentialStore())
        let created = try DemoWallet(keyMaterial: keyMaterial, subjectCredentialStore: store)
        let builder = OpenId4VpHolderBuilder(
            keyMaterial: keyMaterial,
            subjectCredentialStore: store
        )
        builder.holder = created.holder
        let holder = builder.build()
        openId4VpHolder = holder
        openId4VpClient = OpenId4VpProtocolClient(openId4VpHolder: holder)
        wallet = created
        append("Loaded Secure Enclave key and built OpenId4VpHolder from Swift.")
        return created
    }

    private func send(_ result: AuthenticationResponseResult) async throws -> String? {
        switch onEnum(of: result) {
        case .redirect(let response):
            return response.url
        case .post(let response):
            return try await openId4VpClient!.sendAuthorizationResponse(response: response).run(as: String?.self)
        case .dcApi:
            throw NSError(domain: "vckiostest", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "DC API requests are not supported by this demo"])
        }
    }

    private func authenticate(at urlString: String) async throws {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let callback = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "asitplus-wallet") {
                callback, error in
                if let callback { continuation.resume(returning: callback) }
                else { continuation.resume(throwing: error ?? URLError(.cancelled)) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            browserSession = session
            guard session.start() else {
                continuation.resume(throwing: URLError(.cannotLoadFromNetwork))
                return
            }
        }
        let count = try await walletInstance().finishIssuance(callbackUrl: callback.absoluteString)
        append("Credential issued and stored in memory (count: \(count)).")
    }

    private func run(_ operation: @escaping () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do { try await operation() }
        catch { append("ERROR: \(error.localizedDescription)") }
    }

    private func append(_ message: String) {
        log += "\n\(message)"
        print(message)
    }
}

struct ContentView: View {
    @ObservedObject var model: WalletModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("VC-K iOS end-to-end").font(.title2)
            TextField("Issuer URL", text: $model.issuer)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            Button("1. Issue PID (SD-JWT)") { model.issue() }
                .buttonStyle(.borderedProminent)
                .disabled(model.busy)
            Button("2. Open demo RP (PID SD-JWT)") { model.openRelyingParty() }
                .buttonStyle(.bordered)
                .disabled(model.busy)
            TextField("Scanned OpenID4VP request URL", text: $model.presentationRequest)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            Button("3. Parse request and inspect consent data") { model.presentInput() }
                .buttonStyle(.bordered)
                .disabled(model.busy || model.presentationRequest.isEmpty)
            Button("4. Consent and present") { model.approvePresentation() }
                .buttonStyle(.borderedProminent)
                .disabled(model.busy || !model.hasPreparedPresentation)
            ScrollView { Text(model.log).font(.caption.monospaced()).textSelection(.enabled) }
            Spacer()
        }
        .padding()
    }
}

/// One line per credential the DCQL query asks for, e.g. `dc+sd-jwt urn:eudi:pid:1: family_name, given_name`.
func requestedCredentials(_ query: DCQLQuery) -> [String] {
    let claims = (try? claimsPaths(query)) ?? []
    return query.credentials.enumerated().map { index, credential in
        let type = switch credential.meta {
        case let sdJwt as DCQLSdJwtCredentialMetadataAndValidityConstraints: sdJwt.vctValues.joined(separator: " or ")
        case let mdoc as DCQLIsoMdocCredentialMetadataAndValidityConstraints: mdoc.doctypeValue
        default: "of any type"
        }
        let paths = index < claims.count ? claims[index]?.joined(separator: ", ") : nil
        return "\(credential.format.text) \(type): \(paths ?? "all claims")"
    }
}

/// The claims paths of each credential query, e.g. `place_of_birth.country`, read from the query's JSON, as their
/// segments are Kotlin value classes, opaque in Swift.
private func claimsPaths(_ query: DCQLQuery) throws -> [[String]?] {
    let json = try JSONSerialization.jsonObject(with: try dcqlQueryCodec.encode(value: query)) as? [String: Any]
    return (json?["credentials"] as? [[String: Any]] ?? []).map { credential in
        (credential["claims"] as? [[String: Any]])?.map { claim in
            (claim["path"] as? [Any] ?? []).map { $0 is NSNull ? "*" : "\($0)" }.joined(separator: ".")
        }
    }
}

private let dcqlQueryCodec = JoseCodec<DCQLQuery>(serializer: DCQLQuery.companion.serializer())

/// The stored credentials that match the DCQL query; with none, consenting answers the request with `access_denied`.
private func matchingCredentials(_ matches: any CredentialMatchingResult) -> String {
    guard let dcql = matches as? DCQLMatchingResult<AnyObject> else { return "\(type(of: matches))" }
    let entries = dcql.matchingResult.credentialQueryMatches.values.joined()
        .compactMap { $0.credential as? any SubjectCredentialStoreStoreEntry }
        .map { "\($0.credentialFormat.text) \($0.schemeIdentifier)" }
    return entries.isEmpty ? "none, consenting will answer access_denied" : entries.joined(separator: ", ")
}
