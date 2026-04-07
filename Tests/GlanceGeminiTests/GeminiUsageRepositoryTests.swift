import Foundation
import Testing
import GlanceCore
@testable import GlanceGemini

@Test
func geminiUsageRepositoryBuildsInstalledFirstWindowedUsage() async throws {
    let tempRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let chatsDir = tempRoot.appending(path: ".gemini/tmp/demo/chats", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: chatsDir, withIntermediateDirectories: true)
    let sessionFile = chatsDir.appending(path: "session-2026-04-02T10-00-demo.json", directoryHint: .notDirectory)
    try """
    {
      "messages": [
        {
          "timestamp": "2026-04-02T10:00:00.000Z",
          "toolCalls": [
            {"name": "activate_skill", "args": {"name": "find-skills"}, "status": "success", "timestamp": "2026-04-02T10:00:05.000Z"},
            {"name": "mcp_mem0-mcp_get_memories", "args": {}, "status": "success", "timestamp": "2026-04-02T10:00:06.000Z"},
            {"name": "activate_skill", "args": {"name": "ghost-skill"}, "status": "success", "timestamp": "2026-04-02T10:00:07.000Z"}
          ]
        }
      ]
    }
    """.write(to: sessionFile, atomically: true, encoding: .utf8)

    let runner = StubGeminiCommandRunner(outputs: [
        ["skills", "list", "--all"]: """
        find-skills [Enabled]
          Location: /tmp/glance-test/skills/find-skills/SKILL.md
        skill-creator [Enabled] [Built-in]
          Location: /opt/homebrew/builtin/skill-creator/SKILL.md
        """,
        ["mcp", "list"]: """
        Configured MCP servers:
        ✓ mem0-mcp: npx mem0 (stdio) - Connected
        """,
    ])

    let paths = GeminiPaths(homeDirectory: tempRoot)
    let repo = GeminiUsageRepository(
        configLoader: GeminiConfigLoader(paths: paths, commandRunner: runner),
        transcriptReader: GeminiTranscriptUsageReader(paths: paths)
    )
    let formatter = ISO8601DateFormatter()
    let now = formatter.date(from: "2026-04-02T12:00:00Z")!
    let windows = try await repo.loadCapabilities(windows: [.day1, .day30], now: now)

    #expect(windows[.day1]?.contains(where: { $0.id.kind == .skill && $0.id.name == "find-skills" && $0.usageCount == 1 }) == true)
    #expect(windows[.day1]?.contains(where: { $0.id.kind == .skill && $0.id.name == "skill-creator" && $0.usageCount == 0 }) == true)
    #expect(windows[.day1]?.contains(where: { $0.id.kind == .skill && $0.id.name == "ghost-skill" }) == false)
    #expect(windows[.day30]?.contains(where: { $0.id.kind == .mcpServer && $0.id.namespace == "mem0-mcp" && $0.usageCount == 1 }) == true)
}

@Test
func geminiUsageRepositoryAppliesWindowBoundariesIndependently() async throws {
    let tempRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let chatsDir = tempRoot.appending(path: ".gemini/tmp/demo/chats", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: chatsDir, withIntermediateDirectories: true)
    let sessionFile = chatsDir.appending(path: "session-2026-04-02T10-00-demo.json", directoryHint: .notDirectory)
    try """
    {
      "messages": [
        {
          "timestamp": "2026-04-01T10:00:00.000Z",
          "toolCalls": [
            {"name": "mcp_mem0-mcp_get_memories", "args": {}, "status": "success", "timestamp": "2026-04-02T10:00:00.000Z"},
            {"name": "mcp_mem0-mcp_search", "args": {}, "status": "success", "timestamp": "2026-03-28T10:00:00.000Z"},
            {"name": "mcp_mem0-mcp_query", "args": {}, "status": "success", "timestamp": "2026-03-04T10:00:00.000Z"}
          ]
        }
      ]
    }
    """.write(to: sessionFile, atomically: true, encoding: .utf8)

    let runner = StubGeminiCommandRunner(outputs: [
        ["skills", "list", "--all"]: "",
        ["mcp", "list"]: """
        Configured MCP servers:
        ✓ mem0-mcp: npx mem0 (stdio) - Connected
        """,
    ])

    let paths = GeminiPaths(homeDirectory: tempRoot)
    let repo = GeminiUsageRepository(
        configLoader: GeminiConfigLoader(paths: paths, commandRunner: runner),
        transcriptReader: GeminiTranscriptUsageReader(paths: paths)
    )
    let formatter = ISO8601DateFormatter()
    let now = formatter.date(from: "2026-04-02T12:00:00Z")!
    let windows = try await repo.loadCapabilities(windows: [.day1, .day7, .day45], now: now)

    #expect(windows[.day1]?.contains(where: { $0.id.kind == .mcpTool && $0.id.name == "get_memories" }) == true)
    #expect(windows[.day1]?.contains(where: { $0.id.kind == .mcpTool && $0.id.name == "search" }) == false)
    #expect(windows[.day7]?.contains(where: { $0.id.kind == .mcpTool && $0.id.name == "search" }) == true)
    #expect(windows[.day45]?.contains(where: { $0.id.kind == .mcpTool && $0.id.name == "query" }) == true)
}

@Test
func geminiUsageRepositorySupportsUnderscoreMcpServerNames() async throws {
    let tempRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let chatsDir = tempRoot.appending(path: ".gemini/tmp/demo/chats", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: chatsDir, withIntermediateDirectories: true)
    let sessionFile = chatsDir.appending(path: "session-2026-04-02T10-00-demo.json", directoryHint: .notDirectory)
    try """
    {
      "messages": [
        {
          "timestamp": "2026-04-02T10:00:00.000Z",
          "toolCalls": [
            {"name": "mcp_my_server_get_memories", "args": {}, "status": "success", "timestamp": "2026-04-02T10:00:05.000Z"}
          ]
        }
      ]
    }
    """.write(to: sessionFile, atomically: true, encoding: .utf8)

    let runner = StubGeminiCommandRunner(outputs: [
        ["skills", "list", "--all"]: "",
        ["mcp", "list"]: """
        Configured MCP servers:
        ✓ my_server: http://localhost:3000 (http) - Connected
        """,
    ])

    let paths = GeminiPaths(homeDirectory: tempRoot)
    let repo = GeminiUsageRepository(
        configLoader: GeminiConfigLoader(paths: paths, commandRunner: runner),
        transcriptReader: GeminiTranscriptUsageReader(paths: paths)
    )
    let formatter = ISO8601DateFormatter()
    let now = formatter.date(from: "2026-04-02T12:00:00Z")!
    let windows = try await repo.loadCapabilities(windows: [.day1], now: now)

    #expect(windows[.day1]?.contains(where: { $0.id.kind == .mcpTool && $0.id.namespace == "my_server" && $0.id.name == "get_memories" }) == true)
}

@Test
func geminiUsageRepositorySupportsNinetyAndOneHundredTwentyDayLookback() async throws {
    let tempRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let chatsDir = tempRoot.appending(path: ".gemini/tmp/demo/chats", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: chatsDir, withIntermediateDirectories: true)
    let sessionFile = chatsDir.appending(path: "session-2026-04-02T10-00-demo.json", directoryHint: .notDirectory)
    try """
    {
      "messages": [
        {
          "timestamp": "2026-04-01T10:00:00.000Z",
          "toolCalls": [
            {"name": "mcp_mem0-mcp_get_memories", "args": {}, "status": "success", "timestamp": "2026-02-20T10:00:00.000Z"},
            {"name": "mcp_mem0-mcp_search", "args": {}, "status": "success", "timestamp": "2025-12-15T10:00:00.000Z"}
          ]
        }
      ]
    }
    """.write(to: sessionFile, atomically: true, encoding: .utf8)

    let runner = StubGeminiCommandRunner(outputs: [
        ["skills", "list", "--all"]: "",
        ["mcp", "list"]: """
        Configured MCP servers:
        ✓ mem0-mcp: npx mem0 (stdio) - Connected
        """,
    ])

    let paths = GeminiPaths(homeDirectory: tempRoot)
    let repo = GeminiUsageRepository(
        configLoader: GeminiConfigLoader(paths: paths, commandRunner: runner),
        transcriptReader: GeminiTranscriptUsageReader(paths: paths)
    )
    let formatter = ISO8601DateFormatter()
    let now = formatter.date(from: "2026-04-01T12:00:00Z")!
    let windows = try await repo.loadCapabilities(windows: [.day90, .day120], now: now)

    #expect(windows[.day90]?.contains(where: { $0.id.kind == .mcpTool && $0.id.name == "get_memories" }) == true)
    #expect(windows[.day90]?.contains(where: { $0.id.kind == .mcpTool && $0.id.name == "search" }) == false)
    #expect(windows[.day120]?.contains(where: { $0.id.kind == .mcpTool && $0.id.name == "search" }) == true)
}

@Test
func geminiUsageRepositoryUsesConfigCacheWithinTTLOnRefresh() async throws {
    let tempRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let chatsDir = tempRoot.appending(path: ".gemini/tmp/demo/chats", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: chatsDir, withIntermediateDirectories: true)
    let sessionFile = chatsDir.appending(path: "session-2026-04-02T10-00-demo.json", directoryHint: .notDirectory)
    try "{\n  \"messages\": []\n}\n".write(to: sessionFile, atomically: true, encoding: .utf8)

    let runner = CountingGeminiCommandRunner(outputs: [
        ["skills", "list", "--all"]: "find-skills [Enabled]\n  Location: /tmp/find-skills/SKILL.md",
        ["mcp", "list"]: "No MCP servers configured.",
    ])

    var now = Date(timeIntervalSince1970: 1_000)
    let paths = GeminiPaths(homeDirectory: tempRoot)
    let repo = GeminiUsageRepository(
        configLoader: GeminiConfigLoader(paths: paths, commandRunner: runner, cacheTTL: 60, nowProvider: { now }),
        transcriptReader: GeminiTranscriptUsageReader(paths: paths)
    )

    _ = try await repo.loadCapabilities(windows: [.day30], now: now)
    now = Date(timeIntervalSince1970: 1_005)
    _ = try await repo.loadCapabilities(windows: [.day30], now: now)

    #expect(runner.callCount(for: ["skills", "list", "--all"]) == 1)
    #expect(runner.callCount(for: ["mcp", "list"]) == 1)
}

@Test
func geminiUsageRepositoryReadsSessionFilesFromProjectChatsDirectories() async throws {
    let tempRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let scopedChatsDir = tempRoot.appending(path: ".gemini/tmp/demo/chats", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: scopedChatsDir, withIntermediateDirectories: true)
    let scopedSession = scopedChatsDir.appending(path: "session-scoped.json", directoryHint: .notDirectory)
    try """
    {
      "messages": [
        {
          "timestamp": "2026-04-02T10:00:00.000Z",
          "toolCalls": [
            {"name": "activate_skill", "args": {"name": "find-skills"}, "status": "success", "timestamp": "2026-04-02T10:00:05.000Z"}
          ]
        }
      ]
    }
    """.write(to: scopedSession, atomically: true, encoding: .utf8)

    let rootChatsDir = tempRoot.appending(path: ".gemini/tmp/chats", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: rootChatsDir, withIntermediateDirectories: true)
    let rootSession = rootChatsDir.appending(path: "session-root.json", directoryHint: .notDirectory)
    try """
    {
      "messages": [
        {
          "timestamp": "2026-04-02T10:00:00.000Z",
          "toolCalls": [
            {"name": "activate_skill", "args": {"name": "skill-creator"}, "status": "success", "timestamp": "2026-04-02T10:00:05.000Z"}
          ]
        }
      ]
    }
    """.write(to: rootSession, atomically: true, encoding: .utf8)

    let runner = StubGeminiCommandRunner(outputs: [
        ["skills", "list", "--all"]: """
        find-skills [Enabled]
          Location: /tmp/glance-test/skills/find-skills/SKILL.md
        skill-creator [Enabled] [Built-in]
          Location: /opt/homebrew/builtin/skill-creator/SKILL.md
        """,
        ["mcp", "list"]: "No MCP servers configured.",
    ])

    let paths = GeminiPaths(homeDirectory: tempRoot)
    let repo = GeminiUsageRepository(
        configLoader: GeminiConfigLoader(paths: paths, commandRunner: runner),
        transcriptReader: GeminiTranscriptUsageReader(paths: paths)
    )
    let formatter = ISO8601DateFormatter()
    let now = formatter.date(from: "2026-04-02T12:00:00Z")!
    let windows = try await repo.loadCapabilities(windows: [.day30], now: now)

    #expect(windows[.day30]?.contains(where: { $0.id.kind == .skill && $0.id.name == "find-skills" && $0.usageCount == 1 }) == true)
    #expect(windows[.day30]?.contains(where: { $0.id.kind == .skill && $0.id.name == "skill-creator" && $0.usageCount == 0 }) == true)
}

private struct StubGeminiCommandRunner: GeminiCommandRunning {
    let outputs: [[String]: String]

    func run(arguments: [String]) throws -> String {
        guard let output = outputs[arguments] else {
            throw GeminiDataError.commandFailed("Missing stub output for: \(arguments.joined(separator: " "))")
        }
        return output
    }
}

private final class CountingGeminiCommandRunner: GeminiCommandRunning, @unchecked Sendable {
    let outputs: [[String]: String]
    private var counts: [[String]: Int] = [:]

    init(outputs: [[String]: String]) {
        self.outputs = outputs
    }

    func run(arguments: [String]) throws -> String {
        counts[arguments, default: 0] += 1
        guard let output = outputs[arguments] else {
            throw GeminiDataError.commandFailed("Missing stub output for: \(arguments.joined(separator: " "))")
        }
        return output
    }

    func callCount(for arguments: [String]) -> Int {
        counts[arguments, default: 0]
    }
}
