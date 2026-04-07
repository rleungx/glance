import Foundation
import Testing
@testable import GlanceClaude

@Test
func claudeConfigLoaderReadsMCPServersFromGlobalConfig() throws {
    let tempRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let configPath = tempRoot.appending(path: ".claude.json")
    try "{\"mcpServers\":{\"mem0-mcp\":{\"enabled\":true},\"websearch\":{\"enabled\":false}}}".write(to: configPath, atomically: true, encoding: .utf8)

    let loader = ClaudeConfigLoader(paths: ClaudePaths(homeDirectory: tempRoot))
    let servers = try loader.loadConfiguredMCPServers()

    #expect(servers.count == 2)
    #expect(servers.first?.name == "mem0-mcp")
    #expect(servers.first?.enabled == true)
}
