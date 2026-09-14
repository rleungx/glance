import Foundation
import Testing
import GlanceCore
@testable import GlanceClaude

@Test
func claudeRepositoryReadsRealNestedAssistantToolsAndAllHistory() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = ClaudePaths(homeDirectory: root)
    let project = paths.transcriptsDirectory.appendingPathComponent("project/session/subagents")
    let skill = root.appendingPathComponent(".claude/skills/My-Skill")
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
    try "# Skill".write(to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    try #"{"mcpServers":{"docs":{}}}"#.write(to: root.appendingPathComponent(".claude.json"), atomically: true, encoding: .utf8)
    let line = #"{"type":"assistant","timestamp":"2025-01-01T12:00:00Z","message":{"content":[{"type":"text","text":"Using tools"},{"type":"tool_use","id":"mcp-1","name":"mcp__docs__search","input":{"query":"demo"}},{"type":"tool_use","id":"skill-1","name":"Skill","input":{"skill":"my-skill"}}]}}"#
    try (line + "\n{bad json\n").write(to: project.appendingPathComponent("agent.jsonl"), atomically: true, encoding: .utf8)
    try line.write(to: paths.transcriptsDirectory.appendingPathComponent("resumed.jsonl"), atomically: true, encoding: .utf8)
    let repository = ClaudeUsageRepository(configLoader: ClaudeConfigLoader(paths: paths), transcriptReader: ClaudeTranscriptUsageReader(paths: paths))
    let now = ISO8601DateFormatter().date(from: "2026-04-01T12:00:00Z")!
    for _ in 0..<2 {
        let windows = try await repository.loadCapabilities(windows: [.day7, .allTime], now: now)
        #expect(windows[.allTime]?.first { $0.id.kind == .skill }?.usageCount == 1)
        #expect(windows[.allTime]?.first { $0.id.kind == .mcpServer }?.usageCount == 1)
        #expect(windows[.allTime]?.first { $0.id.kind == .mcpTool }?.id.name == "search")
        #expect(windows[.day7]?.allSatisfy { $0.usageCount == 0 } == true)
        #expect(await repository.currentWarnings().isEmpty == false)
    }
}

@Test
func claudeUsageRepositoryBuildsWindowedSnapshotsForConfiguredMCPs() async throws {
    let tempRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let claudeDir = tempRoot.appending(path: ".claude", directoryHint: .isDirectory)
    let transcriptsDir = claudeDir.appending(path: "projects/demo", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: transcriptsDir, withIntermediateDirectories: true)
    try ("{\"mcpServers\":{\"mem0-mcp\":{\"enabled\":true}}}").write(to: tempRoot.appending(path: ".claude.json"), atomically: true, encoding: .utf8)
    try """
    {"type":"tool_use","timestamp":"2026-04-01T12:00:00.000Z","tool_name":"mem0-mcp_get_memories"}
    """.write(to: transcriptsDir.appending(path: "session.jsonl"), atomically: true, encoding: .utf8)

    let paths = ClaudePaths(homeDirectory: tempRoot)
    let repository = ClaudeUsageRepository(configLoader: ClaudeConfigLoader(paths: paths), transcriptReader: ClaudeTranscriptUsageReader(paths: paths))
    let formatter = ISO8601DateFormatter()
    let now = formatter.date(from: "2026-04-01T13:00:00Z")!
    let windows = try await repository.loadCapabilities(windows: [.day1, .day30], now: now)

    #expect(windows[.day1]?.contains(where: { $0.id.kind == .mcpServer && $0.id.namespace == "mem0-mcp" && $0.usageCount == 1 }) == true)
    #expect(windows[.day30]?.contains(where: { $0.id.kind == .mcpTool && $0.id.namespace == "mem0-mcp" }) == true)
}

@Test
func claudeUsageRepositoryKeepsThirtyOneDayOldUsageOutOfTopWindowButInsideCleanupWindow() async throws {
    let tempRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let claudeDir = tempRoot.appending(path: ".claude", directoryHint: .isDirectory)
    let transcriptsDir = claudeDir.appending(path: "projects/demo", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: transcriptsDir, withIntermediateDirectories: true)
    try "{\"mcpServers\":{\"mem0-mcp\":{\"enabled\":true}}}".write(to: tempRoot.appending(path: ".claude.json"), atomically: true, encoding: .utf8)
    try """
    {"type":"tool_use","timestamp":"2026-03-01T12:00:00.000Z","tool_name":"mem0-mcp_get_memories"}
    """.write(to: transcriptsDir.appending(path: "session.jsonl"), atomically: true, encoding: .utf8)

    let paths = ClaudePaths(homeDirectory: tempRoot)
    let repository = ClaudeUsageRepository(configLoader: ClaudeConfigLoader(paths: paths), transcriptReader: ClaudeTranscriptUsageReader(paths: paths))
    let formatter = ISO8601DateFormatter()
    let now = formatter.date(from: "2026-04-01T13:00:00Z")!
    let windows = try await repository.loadCapabilities(windows: [.day30, .day45], now: now)

    #expect(windows[.day30]?.contains(where: { $0.id.kind == .mcpServer && $0.id.namespace == "mem0-mcp" && $0.usageCount > 0 }) == false)
    #expect(windows[.day45]?.contains(where: { $0.id.kind == .mcpServer && $0.id.namespace == "mem0-mcp" && $0.usageCount == 1 }) == true)
}

@Test
func claudeUsageRepositoryAppliesWindowBoundariesIndependently() async throws {
    let tempRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let claudeDir = tempRoot.appending(path: ".claude", directoryHint: .isDirectory)
    let transcriptsDir = claudeDir.appending(path: "projects/demo", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: transcriptsDir, withIntermediateDirectories: true)
    try "{\"mcpServers\":{\"mem0-mcp\":{\"enabled\":true}}}".write(to: tempRoot.appending(path: ".claude.json"), atomically: true, encoding: .utf8)
    try """
    {"type":"tool_use","timestamp":"2026-04-01T12:00:00.000Z","tool_name":"mem0-mcp_get_memories"}
    {"type":"tool_use","timestamp":"2026-03-27T12:00:00.000Z","tool_name":"mem0-mcp_search"}
    {"type":"tool_use","timestamp":"2026-03-03T12:00:00.000Z","tool_name":"mem0-mcp_query"}
    """.write(to: transcriptsDir.appending(path: "session.jsonl"), atomically: true, encoding: .utf8)

    let paths = ClaudePaths(homeDirectory: tempRoot)
    let repository = ClaudeUsageRepository(configLoader: ClaudeConfigLoader(paths: paths), transcriptReader: ClaudeTranscriptUsageReader(paths: paths))
    let formatter = ISO8601DateFormatter()
    let now = formatter.date(from: "2026-04-02T12:00:00Z")!
    let windows = try await repository.loadCapabilities(windows: [.day1, .day7, .day45], now: now)

    #expect(windows[.day1]?.contains(where: { $0.id.kind == .mcpTool && $0.id.name == "get_memories" }) == true)
    #expect(windows[.day1]?.contains(where: { $0.id.kind == .mcpTool && $0.id.name == "search" }) == false)
    #expect(windows[.day7]?.contains(where: { $0.id.kind == .mcpTool && $0.id.name == "search" }) == true)
    #expect(windows[.day45]?.contains(where: { $0.id.kind == .mcpTool && $0.id.name == "query" }) == true)
}

@Test
func claudeUsageRepositorySupportsNinetyAndOneHundredTwentyDayLookback() async throws {
    let tempRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let claudeDir = tempRoot.appending(path: ".claude", directoryHint: .isDirectory)
    let transcriptsDir = claudeDir.appending(path: "projects/demo", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: transcriptsDir, withIntermediateDirectories: true)
    try ("{\"mcpServers\":{\"mem0-mcp\":{\"enabled\":true}}}").write(to: tempRoot.appending(path: ".claude.json"), atomically: true, encoding: .utf8)
    try """
    {"type":"tool_use","timestamp":"2026-02-20T12:00:00.000Z","tool_name":"mem0-mcp_get_memories"}
    {"type":"tool_use","timestamp":"2025-12-15T12:00:00.000Z","tool_name":"mem0-mcp_search"}
    """.write(to: transcriptsDir.appending(path: "session.jsonl"), atomically: true, encoding: .utf8)

    let paths = ClaudePaths(homeDirectory: tempRoot)
    let repository = ClaudeUsageRepository(configLoader: ClaudeConfigLoader(paths: paths), transcriptReader: ClaudeTranscriptUsageReader(paths: paths))
    let formatter = ISO8601DateFormatter()
    let now = formatter.date(from: "2026-04-01T12:00:00Z")!
    let windows = try await repository.loadCapabilities(windows: [.day90, .day120], now: now)

    #expect(windows[.day90]?.contains(where: { $0.id.kind == .mcpTool && $0.id.name == "get_memories" }) == true)
    #expect(windows[.day90]?.contains(where: { $0.id.kind == .mcpTool && $0.id.name == "search" }) == false)
    #expect(windows[.day120]?.contains(where: { $0.id.kind == .mcpTool && $0.id.name == "search" }) == true)
}

@Test
func claudeUsageRepositoryLeavesOutcomeCountsAtZeroWhenOutcomeIsUnknown() async throws {
    let tempRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let claudeDir = tempRoot.appending(path: ".claude", directoryHint: .isDirectory)
    let transcriptsDir = claudeDir.appending(path: "projects/demo", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: transcriptsDir, withIntermediateDirectories: true)
    try ("{\"mcpServers\":{\"mem0-mcp\":{\"enabled\":true}}}").write(to: tempRoot.appending(path: ".claude.json"), atomically: true, encoding: .utf8)
    try """
    {"type":"tool_use","timestamp":"2026-04-01T12:00:00.000Z","tool_name":"mem0-mcp_get_memories"}
    """.write(to: transcriptsDir.appending(path: "session.jsonl"), atomically: true, encoding: .utf8)

    let paths = ClaudePaths(homeDirectory: tempRoot)
    let repository = ClaudeUsageRepository(configLoader: ClaudeConfigLoader(paths: paths), transcriptReader: ClaudeTranscriptUsageReader(paths: paths))
    let formatter = ISO8601DateFormatter()
    let now = formatter.date(from: "2026-04-01T13:00:00Z")!
    let windows = try await repository.loadCapabilities(windows: [.day30], now: now)

    let toolUsage = try #require(windows[.day30]?.first(where: { $0.id.kind == .mcpTool && $0.id.namespace == "mem0-mcp" && $0.id.name == "get_memories" }))
    #expect(toolUsage.usageCount == 1)
    #expect(toolUsage.successCount == 0)
    #expect(toolUsage.failureCount == 0)
}

@Test
func claudeUsageRepositoryWarnsWhenTranscriptHasPartialParseLoss() async throws {
    let tempRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let claudeDir = tempRoot.appending(path: ".claude", directoryHint: .isDirectory)
    let transcriptsDir = claudeDir.appending(path: "projects/demo", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: transcriptsDir, withIntermediateDirectories: true)
    try ("{\"mcpServers\":{\"mem0-mcp\":{\"enabled\":true}}}").write(to: tempRoot.appending(path: ".claude.json"), atomically: true, encoding: .utf8)
    try """
    {"type":"tool_use","timestamp":"2026-04-01T12:00:00.000Z","tool_name":"mem0-mcp_get_memories"}
    {"type":"tool_result","timestamp":"2026-04-01T12:00:01.000Z","tool_name":"mem0-mcp_get_memories"}
    {bad json
    """.write(to: transcriptsDir.appending(path: "session.jsonl"), atomically: true, encoding: .utf8)

    let paths = ClaudePaths(homeDirectory: tempRoot)
    let repository = ClaudeUsageRepository(configLoader: ClaudeConfigLoader(paths: paths), transcriptReader: ClaudeTranscriptUsageReader(paths: paths))
    let formatter = ISO8601DateFormatter()
    let now = formatter.date(from: "2026-04-01T13:00:00Z")!
    let windows = try await repository.loadCapabilities(windows: [.day30], now: now)

    #expect(windows[.day30]?.contains(where: { $0.id.kind == .mcpTool && $0.id.namespace == "mem0-mcp" && $0.id.name == "get_memories" && $0.usageCount == 1 }) == true)
    let warnings = await repository.currentWarnings()
    #expect(warnings.contains("Some Claude transcripts were skipped, so these results may be incomplete."))
    #expect(warnings.contains { $0.contains("Cleanup suggestions are paused") })
}
