import Foundation
import vck_ios

class SwiftSubjectCredentialStore: SubjectCredentialStore {
    private var credentials: [UUID: any SubjectCredentialStoreStoreEntry] = [:]

    func __getCredentials(credentialSchemes: Any?) async throws -> KmmResult<NSArray> {
        let entries = Array(credentials.values)
        guard let credentialSchemes else { return KmmResult(value: entries as NSArray) }

        let schemes = (credentialSchemes as? [Any])?.compactMap { $0 as? any CredentialScheme } ?? []
        let filtered = entries.filter { entry in
            guard let identifier = entry.schemeIdentifier else { return false }
            return schemes.contains { scheme in
                switch entry {
                case is SubjectCredentialStoreStoreEntryIso:
                    return identifier == (scheme as? any IsoMdocCredentialScheme)?.isoDocType
                case is SubjectCredentialStoreStoreEntrySdJwt:
                    return identifier == (scheme as? any SdJwtCredentialScheme)?.sdJwtType
                case is SubjectCredentialStoreStoreEntryVc:
                    return identifier == (scheme as? any VcJwtCredentialScheme)?.vcType
                default:
                    return false
                }
            }
        }
        return KmmResult(value: filtered as NSArray)
    }

    func __storeCredential(issuerSigned: IssuerSigned, scheme: any IsoMdocCredentialScheme, renewalInfo: CredentialRenewalInfo?) async throws
        -> any SubjectCredentialStoreStoreEntry {
        try await __storeCredential(
            issuerSigned: issuerSigned,
            scheme: scheme,
            renewalInfo: renewalInfo,
            issuer: nil
        )
    }

    func __storeCredential(issuerSigned: IssuerSigned, scheme: any IsoMdocCredentialScheme, renewalInfo: CredentialRenewalInfo?, issuer: X509Certificate?) async throws
        -> any SubjectCredentialStoreStoreEntry {
        store(SubjectCredentialStoreStoreEntryIso(
            issuerSigned: issuerSigned,
            schemaUri: nil,
            renewalInfo: renewalInfo,
            issuer: issuer,
            schemeIdentifier: scheme.isoDocType
        ))
    }

    func __storeCredential(vc: VerifiableCredentialJws, vcSerialized: String, scheme: any VcJwtCredentialScheme, renewalInfo: CredentialRenewalInfo?) async throws
        -> any SubjectCredentialStoreStoreEntry {
        try await __storeCredential(
            vc: vc,
            vcSerialized: vcSerialized,
            scheme: scheme,
            renewalInfo: renewalInfo,
            issuer: nil
        )
    }

    func __storeCredential(vc: VerifiableCredentialJws, vcSerialized: String, scheme: any VcJwtCredentialScheme, renewalInfo: CredentialRenewalInfo?, issuer: X509Certificate?) async throws
        -> any SubjectCredentialStoreStoreEntry {
        store(SubjectCredentialStoreStoreEntryVc(
            vcSerialized: vcSerialized,
            vc: vc,
            schemaUri: nil,
            renewalInfo: renewalInfo,
            issuer: issuer,
            schemeIdentifier: scheme.vcType
        ))
    }

    func __storeCredential(vc: VerifiableCredentialSdJwt, vcSerialized: String, disclosures: [String: Any], scheme: any SdJwtCredentialScheme, renewalInfo: CredentialRenewalInfo?) async throws
        -> any SubjectCredentialStoreStoreEntry {
        try await __storeCredential(
            vc: vc,
            vcSerialized: vcSerialized,
            disclosures: disclosures,
            scheme: scheme,
            renewalInfo: renewalInfo,
            issuer: nil
        )
    }

    func __storeCredential(vc: VerifiableCredentialSdJwt, vcSerialized: String, disclosures: [String: Any], scheme: any SdJwtCredentialScheme, renewalInfo: CredentialRenewalInfo?, issuer: X509Certificate?) async throws
        -> any SubjectCredentialStoreStoreEntry {
        store(SubjectCredentialStoreStoreEntrySdJwt(
            vcSerialized: vcSerialized,
            sdJwt: vc,
            disclosures: disclosures,
            schemaUri: nil,
            renewalInfo: renewalInfo,
            issuer: issuer,
            schemeIdentifier: scheme.sdJwtType
        ))
    }

    private func store(_ entry: any SubjectCredentialStoreStoreEntry) -> any SubjectCredentialStoreStoreEntry {
        credentials[UUID()] = entry
        return entry
    }
}
