import Foundation

/// Implement this protocol in Swift; the adapter supplies Kotlin's ObjC requirements.
@available(iOS 13, macOS 10.15, watchOS 6, tvOS 13, *)
public protocol SwiftCredentialStore: AnyObject {
    func getCredentials(credentialSchemes: [CredentialScheme]?) async throws -> [SubjectCredentialStoreStoreEntry]
    func storeCredential(issuerSigned: IssuerSigned, scheme: IsoMdocCredentialScheme,
                         renewalInfo: CredentialRenewalInfo?, issuer: X509Certificate?) async throws
        -> SubjectCredentialStoreStoreEntry
    func storeCredential(vc: VerifiableCredentialJws, vcSerialized: String, scheme: VcJwtCredentialScheme,
                         renewalInfo: CredentialRenewalInfo?, issuer: X509Certificate?) async throws
        -> SubjectCredentialStoreStoreEntry
    func storeCredential(vc: VerifiableCredentialSdJwt, vcSerialized: String, disclosures: [String: Any],
                         scheme: SdJwtCredentialScheme, renewalInfo: CredentialRenewalInfo?,
                         issuer: X509Certificate?) async throws -> SubjectCredentialStoreStoreEntry
}

/// Pass this adapter to Kotlin APIs expecting SubjectCredentialStore.
/// Kotlin cancellation cannot cancel an already-running Swift implementation.
@available(iOS 13, macOS 10.15, watchOS 6, tvOS 13, *)
public final class SubjectCredentialStoreAdapter: NSObject, SubjectCredentialStore {
    private let store: SwiftCredentialStore

    public init(_ store: SwiftCredentialStore) { self.store = store }

    public func __getCredentials(credentialSchemes: Any?) async throws -> KmmResult<NSArray> {
        do {
            let schemes = try callbackArgument(credentialSchemes, as: [CredentialScheme]?.self)
            let entries = try await store.getCredentials(credentialSchemes: schemes)
            return KmmResult(value: entries as NSArray)
        } catch is CancellationError {
            try SwiftErrorBridge.shared.cancellation()
            throw CancellationError() // The Kotlin helper always throws.
        } catch {
            return KmmResult(failure: SwiftErrorBridge.shared.fromError(error: error as NSError))
        }
    }

    public func __storeCredential(issuerSigned: IssuerSigned, scheme: IsoMdocCredentialScheme,
                                  renewalInfo: CredentialRenewalInfo?, issuer: X509Certificate?) async throws
        -> SubjectCredentialStoreStoreEntry {
        try await call {
            try await self.store.storeCredential(issuerSigned: issuerSigned, scheme: scheme,
                                                 renewalInfo: renewalInfo, issuer: issuer)
        }
    }

    public func __storeCredential(vc: VerifiableCredentialJws, vcSerialized: String, scheme: VcJwtCredentialScheme,
                                  renewalInfo: CredentialRenewalInfo?, issuer: X509Certificate?) async throws
        -> SubjectCredentialStoreStoreEntry {
        try await call {
            try await self.store.storeCredential(vc: vc, vcSerialized: vcSerialized, scheme: scheme,
                                                 renewalInfo: renewalInfo, issuer: issuer)
        }
    }

    public func __storeCredential(vc: VerifiableCredentialSdJwt, vcSerialized: String, disclosures: [String: Any],
                                  scheme: SdJwtCredentialScheme, renewalInfo: CredentialRenewalInfo?,
                                  issuer: X509Certificate?) async throws -> SubjectCredentialStoreStoreEntry {
        try await call {
            try await self.store.storeCredential(vc: vc, vcSerialized: vcSerialized, disclosures: disclosures,
                                                 scheme: scheme, renewalInfo: renewalInfo, issuer: issuer)
        }
    }

    private func call<T>(_ operation: () async throws -> T) async throws -> T {
        do { return try await operation() }
        catch is CancellationError {
            try SwiftErrorBridge.shared.cancellation()
            throw CancellationError() // The Kotlin helper always throws.
        }
    }
}
