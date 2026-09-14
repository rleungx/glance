import Foundation
import Testing
import GlanceCore
@testable import GlanceCodex

@Test
func codexDeduplicatesArchivedCallsButPreservesDistinctInvocations() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = CodexPaths(homeDirectory: root)
    let first = #"{"type":"response_item","timestamp":"2026-04-01T12:00:00Z","payload":{"type":"function_call","call_id":"a","name":"mcp__docs__search","arguments":"{}"}}"#
    for directory in paths.sessionDirectories {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try first.write(to: directory.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)
    }
    try first.replacingOccurrences(of: #""a""#, with: #""b""#).write(to: paths.sessionsDirectory.appendingPathComponent("other.jsonl"), atomically: true, encoding: .utf8)
    let result = try CodexTranscriptUsageReader(paths: paths).loadObservedEvents(since: .distantPast)
    #expect(result.events.count == 2)
    #expect(result.evidence.duplicates == 1)
    #expect(result.evidence.inferredIdentities == 0)
    #expect(result.events.allSatisfy { $0.reference != nil })
    try first.replacingOccurrences(of: "search", with: "different").write(to: paths.sessionsDirectory.appendingPathComponent("conflicting.jsonl"), atomically: true, encoding: .utf8)
    let conflicting = try CodexTranscriptUsageReader(paths: paths).loadObservedEvents(since: .distantPast)
    #expect(conflicting.evidence.completeness == .partial)
    #expect(conflicting.evidence.skippedRecords > 0)
}

@Test
func codexDiscoversSharedAndSymlinkedSkillsAndCustomHome() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = CodexPaths(homeDirectory: root, codexDirectory: root.appendingPathComponent("custom-codex"))
    let target = root.appendingPathComponent("outside/folder-name")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    try "---\nname: actual-name\n---\n# Skill".write(to: target.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    let shared = root.appendingPathComponent(".agents/skills")
    try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: shared.appendingPathComponent("linked"), withDestinationURL: target)
    let builtin = paths.skillsDirectory.appendingPathComponent(".system/builtin")
    try FileManager.default.createDirectory(at: builtin, withIntermediateDirectories: true)
    try "# Built-in".write(to: builtin.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    let inventory = CodexConfigLoader(paths: paths).loadInventory()
    #expect(Set(inventory.skills.map(\.name)) == ["actual-name", "builtin"])
    #expect(inventory.skills.first { $0.name == "builtin" }?.builtIn == true)
    #expect(inventory.errors == 0)
    #expect(paths.sessionsDirectory.path.contains("custom-codex/sessions"))
}

@Test
func codexMissingSessionsAndMalformedRecordsHaveDifferentQuality() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = CodexPaths(homeDirectory: root)
    let reader = CodexTranscriptUsageReader(paths: paths)
    #expect(try reader.loadObservedEvents(since: .distantPast).evidence.completeness == .unavailable)
    try FileManager.default.createDirectory(at: paths.sessionsDirectory, withIntermediateDirectories: true)
    try "{truncated".write(to: paths.sessionsDirectory.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)
    let result = try reader.loadObservedEvents(since: .distantPast)
    #expect(result.evidence.completeness == .partial)
    #expect(result.evidence.skippedRecords == 1)
}

@Test
func codexMalformedMessageBlocksPreserveSelectedSkillsAndDeduplicateCopies() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = CodexPaths(homeDirectory: root)
    try FileManager.default.createDirectory(at: paths.sessionsDirectory, withIntermediateDirectories: true)
    let content: [Any] = [42, ["type": "input_text", "text": "<skill>\n<name>demo</name>\n<path>/skills/demo/SKILL.md</path>\nInstructions\n</skill>"]]
    let data = try JSONSerialization.data(withJSONObject: ["type": "response_item", "timestamp": "2026-04-01T12:00:00Z", "payload": ["type": "message", "role": "user", "content": content]])
    for name in ["original.jsonl", "copy.jsonl"] { try data.write(to: paths.sessionsDirectory.appendingPathComponent(name)) }
    let result = try CodexTranscriptUsageReader(paths: paths).loadObservedEvents(since: .distantPast)
    #expect(result.events.count == 1)
    #expect(result.events.first?.skillName == "demo")
    #expect(result.evidence.duplicates == 1)
    #expect(result.evidence.inferredIdentities == 1)
    #expect(result.evidence.completeness == .partial)
    #expect(result.evidence.skippedRecords == 2)
}
