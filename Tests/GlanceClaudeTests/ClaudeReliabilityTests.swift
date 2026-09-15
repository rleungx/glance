import Foundation
import Testing
import GlanceCore
@testable import GlanceClaude

@Test
func claudeMissingTranscriptsAreUnavailableNotUnused() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = ClaudePaths(homeDirectory: root)
    let skill = paths.globalSkillsDirectory.appendingPathComponent("demo")
    try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
    try "# Demo".write(to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    let repository = ClaudeUsageRepository(configLoader: ClaudeConfigLoader(paths: paths), transcriptReader: ClaudeTranscriptUsageReader(paths: paths))
    let result = try await repository.loadUsage(windows: [.allTime], now: .now)
    #expect(result.evidence.completeness == .unavailable)
    #expect(result.windows[.allTime]?.first?.installedButUnused == false)
    #expect(CapabilityRanker.buildSnapshot(from: result.windows[.allTime] ?? [], evidence: result.evidence).removalCandidates.isEmpty)
}

@Test
func claudeMalformedBlockPreservesSiblingCallsAndCachedWarning() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = ClaudePaths(homeDirectory: root)
    try FileManager.default.createDirectory(at: paths.transcriptsDirectory, withIntermediateDirectories: true)
    let line = #"{"type":"assistant","timestamp":"2026-04-01T12:00:00Z","message":{"content":[{"type":"tool_use","id":"a","name":"mcp__docs__search","input":{"skill":42}},{"type":"tool_use","id":"b","name":"Skill","input":{"skill":42}},{"type":"tool_use","id":"c","name":"Skill","input":{"skill":"demo"}}]}}"#
    try line.write(to: paths.transcriptsDirectory.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)
    let reader = ClaudeTranscriptUsageReader(paths: paths)
    for _ in 0..<2 {
        let result = try reader.loadObservedEvents(since: .distantPast)
        #expect(result.events.count == 1)
        #expect(result.evidence.skippedRecords == 1)
        #expect(result.evidence.completeness == .partial)
        #expect(result.events.first?.reference?.record == "line 1, block 3")
    }
}

@Test
func claudeDetectsRewritesWithUnchangedMetadataAndDeduplicatesCopies() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = ClaudePaths(homeDirectory: root)
    try FileManager.default.createDirectory(at: paths.transcriptsDirectory, withIntermediateDirectories: true)
    let file = paths.transcriptsDirectory.appendingPathComponent("session.jsonl")
    let original = #"{"type":"assistant","timestamp":"2026-04-01T12:00:00Z","message":{"content":[{"type":"tool_use","id":"a","name":"Skill","input":{"skill":"first"}}]}}"#
    try original.write(to: file, atomically: true, encoding: .utf8)
    let mtime = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as! Date
    let reader = ClaudeTranscriptUsageReader(paths: paths)
    #expect(try reader.loadObservedEvents(since: .distantPast).events.first?.skillName == "first")
    let updated = original.replacingOccurrences(of: "first", with: "other")
    try updated.write(to: file, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: file.path)
    try updated.write(to: paths.transcriptsDirectory.appendingPathComponent("copy.jsonl"), atomically: true, encoding: .utf8)
    let result = try reader.loadObservedEvents(since: .distantPast)
    #expect(result.events.count == 1)
    #expect(result.events.first?.skillName == "other")
    #expect(result.evidence.duplicates == 1)
    try original.write(to: paths.transcriptsDirectory.appendingPathComponent("conflicting.jsonl"), atomically: true, encoding: .utf8)
    let conflict = try reader.loadObservedEvents(since: .distantPast)
    #expect(conflict.evidence.completeness == .partial)
    #expect(conflict.evidence.skippedRecords > 0)
}
