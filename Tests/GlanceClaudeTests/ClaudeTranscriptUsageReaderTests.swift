import Foundation
import Testing
@testable import GlanceClaude

@Test
func claudeTranscriptReaderLoadsRecentToolUseEvents() throws {
    let tempRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let transcriptsDir = tempRoot.appending(path: ".claude/projects/demo", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: transcriptsDir, withIntermediateDirectories: true)
    let transcript = transcriptsDir.appending(path: "session.jsonl")
    try """
    {"type":"tool_use","timestamp":"2026-04-01T12:00:00.000Z","tool_name":"mem0-mcp_get_memories"}
    {"type":"tool_result","timestamp":"2026-04-01T12:00:01.000Z","tool_name":"mem0-mcp_get_memories"}
    """.write(to: transcript, atomically: true, encoding: .utf8)

    let reader = ClaudeTranscriptUsageReader(paths: ClaudePaths(homeDirectory: tempRoot))
    let result = try reader.loadObservedEvents(since: Date(timeIntervalSince1970: 0))

    #expect(result.events.count == 1)
    #expect(result.events.first?.toolName == "mem0-mcp_get_memories")
    #expect(result.skippedFilesCount == 0)
}

@Test
func claudeTranscriptReaderParsesTimestampsWithoutFractionalSeconds() throws {
    let tempRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let transcriptsDir = tempRoot.appending(path: ".claude/projects/demo", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: transcriptsDir, withIntermediateDirectories: true)
    let transcript = transcriptsDir.appending(path: "session.jsonl")
    try """
    {"type":"tool_use","timestamp":"2026-04-01T12:00:00Z","tool_name":"mem0-mcp_get_memories"}
    """.write(to: transcript, atomically: true, encoding: .utf8)

    let reader = ClaudeTranscriptUsageReader(paths: ClaudePaths(homeDirectory: tempRoot))
    let result = try reader.loadObservedEvents(since: Date(timeIntervalSince1970: 0))

    #expect(result.events.count == 1)
}

@Test
func claudeTranscriptReaderReloadsWhenTranscriptChanges() throws {
    let tempRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let transcriptsDir = tempRoot.appending(path: ".claude/projects/demo", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: transcriptsDir, withIntermediateDirectories: true)
    let transcript = transcriptsDir.appending(path: "session.jsonl")
    try "{\"type\":\"tool_use\",\"timestamp\":\"2026-04-01T12:00:00.000Z\",\"tool_name\":\"mem0-mcp_get_memories\"}\n".write(to: transcript, atomically: true, encoding: .utf8)

    let reader = ClaudeTranscriptUsageReader(paths: ClaudePaths(homeDirectory: tempRoot))
    let firstEvents = try reader.loadObservedEvents(since: Date(timeIntervalSince1970: 0))
    try """
    {"type":"tool_use","timestamp":"2026-04-01T12:00:00.000Z","tool_name":"mem0-mcp_get_memories"}
    {"type":"tool_use","timestamp":"2026-04-01T12:10:00.000Z","tool_name":"mem0-mcp_search"}
    """.write(to: transcript, atomically: true, encoding: .utf8)
    let secondEvents = try reader.loadObservedEvents(since: Date(timeIntervalSince1970: 0))

    #expect(firstEvents.events.count == 1)
    #expect(secondEvents.events.count == 2)
}

@Test
func claudeTranscriptReaderReportsSkippedMalformedFiles() throws {
    let tempRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let transcriptsDir = tempRoot.appending(path: ".claude/projects/demo", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: transcriptsDir, withIntermediateDirectories: true)
    try "{bad json".write(to: transcriptsDir.appending(path: "bad.jsonl"), atomically: true, encoding: .utf8)
    try "{\"type\":\"tool_use\",\"timestamp\":\"2026-04-01T12:00:00.000Z\",\"tool_name\":\"mem0-mcp_get_memories\"}\n".write(to: transcriptsDir.appending(path: "good.jsonl"), atomically: true, encoding: .utf8)

    let reader = ClaudeTranscriptUsageReader(paths: ClaudePaths(homeDirectory: tempRoot))
    let result = try reader.loadObservedEvents(since: Date(timeIntervalSince1970: 0))

    #expect(result.events.count == 1)
    #expect(result.skippedFilesCount == 1)
}

@Test
func claudeTranscriptReaderCountsMixedValidAndMalformedLinesAsSkipped() throws {
    let tempRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let transcriptsDir = tempRoot.appending(path: ".claude/projects/demo", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: transcriptsDir, withIntermediateDirectories: true)
    try """
    {"type":"tool_use","timestamp":"2026-04-01T12:00:00.000Z","tool_name":"mem0-mcp_get_memories"}
    {"type":"tool_result","timestamp":"2026-04-01T12:00:01.000Z","tool_name":"mem0-mcp_get_memories"}
    {bad json
    """.write(to: transcriptsDir.appending(path: "mixed.jsonl"), atomically: true, encoding: .utf8)

    let reader = ClaudeTranscriptUsageReader(paths: ClaudePaths(homeDirectory: tempRoot))
    let result = try reader.loadObservedEvents(since: Date(timeIntervalSince1970: 0))

    #expect(result.events.count == 1)
    #expect(result.skippedFilesCount == 1)
}
