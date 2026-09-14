import Foundation
import Testing
import GlanceCore
@testable import GlanceGemini

@Test
func geminiMissingHistoryIsUnavailableAndMalformedToolsDoNotEraseSiblings() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = GeminiPaths(homeDirectory: root)
    let reader = GeminiTranscriptUsageReader(paths: paths)
    #expect(try reader.loadObservedEvents(since: .distantPast).evidence.completeness == .unavailable)
    let chats = paths.tmpDirectory.appendingPathComponent("project/chats")
    try FileManager.default.createDirectory(at: chats, withIntermediateDirectories: true)
    let content = #"{"sessionId":"session","messages":[{"timestamp":"2026-04-01T12:00:00Z","toolCalls":[{"id":"a","name":"activate_skill","args":{"name":"demo"},"status":"success"},{"name":42,"args":{}},{"id":"b","name":"mcp_docs_search","args":{},"timestamp":"invalid"}]}]}"#
    try content.write(to: chats.appendingPathComponent("session-original.json"), atomically: true, encoding: .utf8)
    for _ in 0..<2 {
        let result = try reader.loadObservedEvents(since: .distantPast)
        #expect(result.events.count == 1)
        #expect(result.evidence.skippedRecords == 2)
        #expect(result.evidence.completeness == .partial)
        #expect(result.events.first?.reference?.record == "message 1, tool 1")
    }
}

@Test
func geminiCopiedSessionsCountOnceAndNativeIDsPreserveDistinctCalls() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = GeminiPaths(homeDirectory: root)
    let chats = paths.tmpDirectory.appendingPathComponent("project/chats")
    try FileManager.default.createDirectory(at: chats, withIntermediateDirectories: true)
    let content = #"{"sessionId":"session","messages":[{"timestamp":"2026-04-01T12:00:00Z","toolCalls":[{"id":"a","name":"activate_skill","args":{"name":"demo"}},{"id":"b","name":"activate_skill","args":{"name":"demo"}}]}]}"#
    for name in ["session-original.json", "session-copy.json"] {
        try content.write(to: chats.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
    let result = try GeminiTranscriptUsageReader(paths: paths).loadObservedEvents(since: .distantPast)
    #expect(result.events.count == 2)
    #expect(result.evidence.duplicates == 2)
    #expect(result.evidence.inferredIdentities == 0)
    try content.replacingOccurrences(of: "demo", with: "other").write(to: chats.appendingPathComponent("session-conflicting.json"), atomically: true, encoding: .utf8)
    let conflict = try GeminiTranscriptUsageReader(paths: paths).loadObservedEvents(since: .distantPast)
    #expect(conflict.evidence.completeness == .partial)
    #expect(conflict.evidence.skippedRecords > 0)
}

@Test
func geminiFallbackIdentityIsExplicitAndInventoryFormatLossIsReported() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = GeminiPaths(homeDirectory: root)
    let chats = paths.tmpDirectory.appendingPathComponent("project/chats")
    try FileManager.default.createDirectory(at: chats, withIntermediateDirectories: true)
    let content = #"{"messages":[{"timestamp":"2026-04-01T12:00:00Z","toolCalls":[{"name":"activate_skill","args":{"name":"demo"}}]}]}"#
    for name in ["session-original.json", "session-copy.json"] {
        try content.write(to: chats.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
    let reader = GeminiTranscriptUsageReader(paths: paths)
    let parsed = try reader.loadObservedEvents(since: .distantPast)
    #expect(parsed.events.count == 1)
    #expect(parsed.evidence.inferredIdentities == 1)
    let repository = GeminiUsageRepository(configLoader: GeminiConfigLoader(paths: paths, commandRunner: ChangedFormatRunner()), transcriptReader: reader)
    let result = try await repository.loadUsage(windows: [.allTime], now: ISO8601DateFormatter().date(from: "2026-04-02T00:00:00Z")!)
    #expect(result.evidence.completeness == .partial)
    #expect(result.evidence.unmatchedRecords == 1)
    #expect(result.warnings.contains { $0.contains("inventory output") })
    #expect(CapabilityRanker.buildSnapshot(from: result.windows[.allTime] ?? [], evidence: result.evidence).removalCandidates.isEmpty)
}

private struct ChangedFormatRunner: GeminiCommandRunning {
    func run(arguments: [String]) throws -> String { "New format: {capabilities: [demo]}" }
}
