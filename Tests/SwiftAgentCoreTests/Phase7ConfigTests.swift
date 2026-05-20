import Testing
import Foundation
@testable import SwiftAgentCore

struct ConfigLoaderTests {
    @Test
    func mergeConcatenatesArrays() {
        let loader = ConfigLoader()
        let base = Settings(mcpServers: [MCPServerConfig(name: "a", transport: .stdio)])
        let overlay = Settings(mcpServers: [MCPServerConfig(name: "b", transport: .sse)])
        let merged = loader.merge(base, overlay)
        #expect(merged.mcpServers.count == 2)
    }

    @Test
    func loadReturnsNilForMissingFile() throws {
        let loader = ConfigLoader()
        let url = URL(fileURLWithPath: "/tmp/nonexistent_config_\(UUID()).json")
        let result = try loader.loadFile(url: url)
        #expect(result == nil)
    }

    @Test
    func mergeOverridesScalars() {
        let loader = ConfigLoader()
        let base = Settings(maxTokens: 100_000)
        let overlay = Settings(maxTokens: 300_000)
        let merged = loader.merge(base, overlay)
        #expect(merged.maxTokens == 300_000)
    }
}

struct ConfigSchemaTests {
    @Test
    func validatesValidSettings() {
        let schema = ConfigSchema()
        let issues = schema.validate(Settings())
        #expect(issues.isEmpty)
    }

    @Test
    func warnsOnUnknownModel() {
        let schema = ConfigSchema()
        let settings = Settings(model: ModelConfig(provider: .firstParty, modelID: "unknown-model-99"))
        let issues = schema.validate(settings)
        #expect(issues.contains { $0.path.contains("modelID") })
    }
}
