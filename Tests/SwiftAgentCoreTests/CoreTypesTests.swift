import Testing
@testable import SwiftAgentCore

struct CoreTypesTests {
    @Test
    func versionIsSet() {
        #expect(CoreTypes.version == "0.1.0")
    }

    @Test
    func versionIsNotEmpty() {
        #expect(!CoreTypes.version.isEmpty)
    }
}
