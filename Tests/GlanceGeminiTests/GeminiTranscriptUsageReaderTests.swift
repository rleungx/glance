import Foundation
import Testing
@testable import GlanceGemini

@Test
func geminiTranscriptReaderLoadsToolCallEvents() throws {
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
            {"name": "mcp_mem0-mcp_get_memories", "args": {}, "status": "success"}
          ]
        }
      ]
    }
    """.write(to: sessionFile, atomically: true, encoding: .utf8)

    let reader = GeminiTranscriptUsageReader(paths: GeminiPaths(homeDirectory: tempRoot))
    let result = try reader.loadObservedEvents(since: Date(timeIntervalSince1970: 0))

    #expect(result.events.count == 2)
    #expect(result.events.first?.toolName == "activate_skill")
    #expect(result.events.last?.toolName == "mcp_mem0-mcp_get_memories")
}

@Test
func geminiTranscriptReaderSkipsInvalidSessionFiles() throws {
    let tempRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let chatsDir = tempRoot.appending(path: ".gemini/tmp/demo/chats", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: chatsDir, withIntermediateDirectories: true)
    try "{".write(to: chatsDir.appending(path: "session-bad.json"), atomically: true, encoding: .utf8)
    try """
    {
      "messages": [
        {
          "timestamp": "2026-04-02T10:00:00.000Z",
          "toolCalls": [
            {"name": "activate_skill", "args": {"name": "find-skills"}, "status": "mystery", "timestamp": "2026-04-02T10:00:05.000Z"}
          ]
        }
      ]
    }
    """.write(to: chatsDir.appending(path: "session-good.json"), atomically: true, encoding: .utf8)

    let reader = GeminiTranscriptUsageReader(paths: GeminiPaths(homeDirectory: tempRoot))
    let result = try reader.loadObservedEvents(since: Date(timeIntervalSince1970: 0))

    #expect(result.events.count == 1)
    #expect(result.events.first?.status == .unknown)
    #expect(result.skippedFilesCount == 1)
}

@Test
func geminiTranscriptReaderReloadsWhenSessionChanges() throws {
    let tempRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let chatsDir = tempRoot.appending(path: ".gemini/tmp/demo/chats", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: chatsDir, withIntermediateDirectories: true)
    let sessionFile = chatsDir.appending(path: "session-2026-04-02T10-00-demo.json", directoryHint: .notDirectory)
    try """
    {"messages":[{"timestamp":"2026-04-02T10:00:00.000Z","toolCalls":[{"name":"activate_skill","args":{"name":"find-skills"},"status":"success","timestamp":"2026-04-02T10:00:05.000Z"}]}]}
    """.write(to: sessionFile, atomically: true, encoding: .utf8)

    let reader = GeminiTranscriptUsageReader(paths: GeminiPaths(homeDirectory: tempRoot))
    let firstEvents = try reader.loadObservedEvents(since: Date(timeIntervalSince1970: 0))
    try """
    {"messages":[{"timestamp":"2026-04-02T10:00:00.000Z","toolCalls":[{"name":"activate_skill","args":{"name":"find-skills"},"status":"success","timestamp":"2026-04-02T10:00:05.000Z"},{"name":"mcp_mem0-mcp_get_memories","args":{},"status":"success","timestamp":"2026-04-02T10:00:06.000Z"}]}]}
    """.write(to: sessionFile, atomically: true, encoding: .utf8)
    let secondEvents = try reader.loadObservedEvents(since: Date(timeIntervalSince1970: 0))

    #expect(firstEvents.events.count == 1)
    #expect(secondEvents.events.count == 2)
}
