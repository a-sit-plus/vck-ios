import Foundation
import vck_ios

class SwiftSubjectCredentialStore: SwiftCredentialStore {
    private var credentials: [UUID: any SubjectCredentialStoreStoreEntry] = [:]

    func getCredentials(credentialSchemes: [any CredentialScheme]? = nil) async throws -> [any SubjectCredentialStoreStoreEntry] {
        let entries = Array(credentials.values)
        guard let schemes = credentialSchemes else { return entries }

        let filtered = entries.filter { entry in
            let identifier = entry.schemeIdentifier
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
        return filtered
    }

    func storeCredential(issuerSigned: IssuerSigned, scheme: any IsoMdocCredentialScheme, renewalInfo: CredentialRenewalInfo? = nil, issuer: X509Certificate? = nil) async throws
        -> any SubjectCredentialStoreStoreEntry {
        store(SubjectCredentialStoreStoreEntryIso(
            issuerSigned: issuerSigned,
            renewalInfo: renewalInfo,
            issuer: issuer,
            schemeIdentifier: try requiredIdentifier(scheme.isoDocType)
        ))
    }

    func storeCredential(vc: VerifiableCredentialJws, vcSerialized: String, scheme: any VcJwtCredentialScheme, renewalInfo: CredentialRenewalInfo? = nil, issuer: X509Certificate? = nil) async throws
        -> any SubjectCredentialStoreStoreEntry {
        store(SubjectCredentialStoreStoreEntryVc(
            vcSerialized: vcSerialized,
            vc: vc,
            renewalInfo: renewalInfo,
            issuer: issuer,
            schemeIdentifier: try requiredIdentifier(scheme.vcType)
        ))
    }

    func storeCredential(vc: VerifiableCredentialSdJwt, vcSerialized: String, disclosures: [String: Any], scheme: any SdJwtCredentialScheme, renewalInfo: CredentialRenewalInfo? = nil, issuer: X509Certificate? = nil) async throws
        -> any SubjectCredentialStoreStoreEntry {
        store(SubjectCredentialStoreStoreEntrySdJwt(
            vcSerialized: vcSerialized,
            sdJwt: vc,
            disclosures: disclosures,
            renewalInfo: renewalInfo,
            issuer: issuer,
            schemeIdentifier: try requiredIdentifier(scheme.sdJwtType)
        ))
    }

    private func requiredIdentifier(_ identifier: String?) throws -> String {
        guard let identifier else {
            throw NSError(domain: "SwiftSubjectCredentialStore", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Credential scheme is missing its format identifier"])
        }
        return identifier
    }

    private func store(_ entry: any SubjectCredentialStoreStoreEntry) -> any SubjectCredentialStoreStoreEntry {
        credentials[UUID()] = entry
        return entry
    }
}
