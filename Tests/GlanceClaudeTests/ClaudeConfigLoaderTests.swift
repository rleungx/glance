import Foundation
import Testing
@testable import GlanceClaude

@Test
func claudeConfigLoaderFindsSkillsWithoutReadingGlobalConfig() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = ClaudePaths(homeDirectory: root)
    let skill = paths.globalSkillsDirectory.appendingPathComponent("demo")
    try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
    try "# Demo".write(to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    try "{invalid config".write(to: root.appendingPathComponent(".claude.json"), atomically: true, encoding: .utf8)

    let loader = ClaudeConfigLoader(paths: paths)
    #expect(try loader.loadInstalledSkills().map(\.name) == ["demo"])
    #expect(!loader.evidenceSources.contains { $0.hasSuffix(".claude.json") })
}
