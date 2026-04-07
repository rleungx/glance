import Foundation
import Testing
import GlanceCore
@testable import GlanceClaude

@Test
func claudeUsageRepositoryBuildsWindowedSnapshotsForConfiguredMCPs() async throws {
    let tempRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let claudeDir = tempRoot.appending(path: ".claude", directoryHint: .isDirectory)
    let transcriptsDir = claudeDir.appending(path: "transcripts", directoryHint: .isDirectory)
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
    let transcriptsDir = claudeDir.appending(path: "transcripts", directoryHint: .isDirectory)
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
    let transcriptsDir = claudeDir.appending(path: "transcripts", directoryHint: .isDirectory)
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
    let transcriptsDir = claudeDir.appending(path: "transcripts", directoryHint: .isDirectory)
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
    let transcriptsDir = claudeDir.appending(path: "transcripts", directoryHint: .isDirectory)
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
    let transcriptsDir = claudeDir.appending(path: "transcripts", directoryHint: .isDirectory)
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
    #expect(warnings == ["Some Claude transcripts were skipped, so these results may be incomplete."])
}
