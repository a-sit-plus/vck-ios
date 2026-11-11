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

    func storeCredential(entry: any SubjectCredentialStoreStoreEntry) async throws -> any SubjectCredentialStoreStoreEntry {
        credentials[UUID()] = entry
        return entry
    }
}
