import AuthenticationServices
import Combine
import Security
import SwiftUI
import vck_ios

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

    private var wallet: BasicWallet?
    private var openId4VpHolder: OpenId4VpHolder?
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
        UIApplication.shared.open(URL(string: "https://wallet-rp.a-sit.plus/pidsdjwt.html")!)
        append("In the RP, create the request and tap Open App Wallet.")
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
            let state = try await self.openId4VpHolder!
                .startAuthorizationResponsePreparation(input: request).getOrThrow()!
            let matches = try await self.openId4VpHolder!
                .getMatchingCredentials(preparationState: state).getOrThrow()!
            self.presentationState = state
            self.hasPreparedPresentation = true
            self.append("OpenID4VP request prepared. Audience: \(state.audience)")
            self.append("Request object verified: \(String(describing: state.requestObjectVerified))")
            self.append("Credentials/claims proposed for consent: \(String(describing: matches))")
        } }
    }

    func approvePresentation() {
        Task { await run {
            guard let state = self.presentationState else { return }
            let result = try await self.openId4VpHolder!
                .finalizeAuthorizationResponse(
                    preparationState: state,
                    credentialPresentation: nil
                ).getOrThrow()!
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

    private func walletInstance() throws -> BasicWallet {
        if let wallet { return wallet }
        //cheap trick
        let key = try loadOrCreateSecureEnclaveKey()
        let pointer = Unmanaged.passUnretained(key).toOpaque()
        let keyMaterial = KeyMaterialAdapter.shared.fromSecKey(privateKey: pointer).getOrThrow()!
        let store = SwiftSubjectCredentialStore()
        let created = BasicWallet(keyMaterial: keyMaterial, subjectCredentialStore: store)
        //use a builder wrapper
        let builder = OpenId4VpHolderBuilder(
            keyMaterial: keyMaterial,
            subjectCredentialStore: store
        )
        builder.holder = created.holder
        builder.remoteResourceRetriever = created.remoteResourceRetriever
        openId4VpHolder = builder.build()
        wallet = created
        append("Loaded Secure Enclave key and built OpenId4VpHolder from Swift.")
        return created
    }

    private func send(_ result: AuthenticationResponseResult) async throws -> String? {
        switch onEnum(of: result) {
        case .redirect(let response):
            return response.url
        case .post(let response):
            guard let url = URL(string: response.url) else { throw URLError(.badURL) }
            var components = URLComponents()
            components.queryItems = response.params.map { URLQueryItem(name: $0.key, value: $0.value) }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
            let (data, urlResponse) = try await URLSession.shared.data(for: request)
            guard let http = urlResponse as? HTTPURLResponse, (200...399).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            if let location = http.value(forHTTPHeaderField: "Location") { return location }
            return try? JSONDecoder().decode(PresentationSuccess.self, from: data).redirectUri
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
        append("Credential issued and stored in memory (count: \(count.intValue)).")
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

private struct PresentationSuccess: Decodable {
    let redirectUri: String

    enum CodingKeys: String, CodingKey {
        case redirectUri = "redirect_uri"
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
            Button("1. Issue first credential") { model.issue() }
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
