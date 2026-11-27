import Foundation
import Testing
import VckIos
@testable import vckiostest

struct RequestedCredentialsTests {

    /// As the demo RP's remote presentation case 1 requests it, plus a nested claim and an mdoc.
    @Test func summarizesDcqlQuery() throws {
        let query = try JoseCodec<DCQLQuery>(serializer: DCQLQuery.companion.serializer()).decode(data: Data(#"""
        {"credentials":[
          {"id":"pid","format":"dc+sd-jwt","meta":{"vct_values":["urn:eudi:pid:1"]},
           "claims":[{"path":["family_name"]},{"path":["given_name"]},{"path":["place_of_birth","country"]}]},
          {"id":"mdl","format":"mso_mdoc","meta":{"doctype_value":"org.iso.18013.5.1.mDL"},
           "claims":[{"path":["org.iso.18013.5.1","family_name"]}]}
        ]}
        """#.utf8))

        #expect(requestedCredentials(query) == [
            "dc+sd-jwt urn:eudi:pid:1: family_name, given_name, place_of_birth.country",
            "mso_mdoc org.iso.18013.5.1.mDL: org.iso.18013.5.1.family_name",
        ])
    }
}
