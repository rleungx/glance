import Foundation
import Testing
import GlanceCore
@testable import GlanceCodex

@Test
func codexRepositoryLeavesUnobservedSkillUsageUnknown() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.tempRoot) }

    let skillDirectory = fixture.paths.skillsDirectory.appending(path: "my-skill", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
    try "# Skill".write(to: skillDirectory.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)

    let repository = CodexUsageRepository(
        configLoader: CodexConfigLoader(paths: fixture.paths),
        transcriptReader: CodexTranscriptUsageReader(paths: fixture.paths)
    )
    let capabilities = try await repository.loadCapabilities()

    let skill = capabilities.first { $0.id.kind == .skill && $0.id.name == "my-skill" }
    #expect(skill != nil)
    #expect(skill?.usageCount == 0)
    #expect(skill?.installedButUnused == false)
    #expect(CapabilityRanker.buildSnapshot(from: capabilities).removalCandidates.isEmpty)
}

@Test
func codexRepositoryAggregatesMcpUsageAcrossWindows() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.tempRoot) }

    try writeSession(
        to: fixture.paths.sessionsDirectory.appending(path: "2026/04/04/session.jsonl"),
        lines: [
            sessionLine(daysAgo: 1, name: "mcp__chat__send_message"),
            sessionLine(daysAgo: 10, name: "mcp__chat__read_history"),
        ]
    )

    let repository = CodexUsageRepository(
        configLoader: CodexConfigLoader(paths: fixture.paths),
        transcriptReader: CodexTranscriptUsageReader(paths: fixture.paths)
    )
    let now = Date(timeIntervalSince1970: 1_744_000_000)
    let output = try await repository.loadCapabilities(windows: [.day7, .day30], now: now)

    let day7Server = output[.day7]?.first { $0.id.kind == .mcpServer && $0.id.namespace == "chat" }
    let day30Server = output[.day30]?.first { $0.id.kind == .mcpServer && $0.id.namespace == "chat" }
    let day7Tool = output[.day7]?.first { $0.id.kind == .mcpTool && $0.id.namespace == "chat" && $0.id.name == "send_message" }
    let day30Tool = output[.day30]?.first { $0.id.kind == .mcpTool && $0.id.namespace == "chat" && $0.id.name == "read_history" }

    #expect(day7Server?.usageCount == 1)
    #expect(day30Server?.usageCount == 2)
    #expect(day7Tool?.usageCount == 1)
    #expect(day30Tool?.usageCount == 1)
}

@Test
func codexRepositoryLoadCapabilitiesUsesThirtyDayWindow() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.tempRoot) }
    let now = Date()

    try writeSession(
        to: fixture.paths.sessionsDirectory.appending(path: "2026/04/04/session.jsonl"),
        lines: [
            sessionLine(daysAgo: 10, name: "mcp__chat__send_message", now: now),
            sessionLine(daysAgo: 40, name: "mcp__chat__read_history", now: now),
        ]
    )

    let repository = CodexUsageRepository(
        configLoader: CodexConfigLoader(paths: fixture.paths),
        transcriptReader: CodexTranscriptUsageReader(paths: fixture.paths)
    )
    let capabilities = try await repository.loadCapabilities()

    #expect(capabilities.contains { $0.id.kind == .mcpTool && $0.id.namespace == "chat" && $0.id.name == "send_message" })
    #expect(!capabilities.contains { $0.id.kind == .mcpTool && $0.id.namespace == "chat" && $0.id.name == "read_history" })
}

@Test
func codexRepositoryWarnsWhenSessionContainsMalformedMcpEntries() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.tempRoot) }

    try writeSession(
        to: fixture.paths.sessionsDirectory.appending(path: "2026/04/04/session.jsonl"),
        lines: [
            sessionLine(daysAgo: 1, name: "mcp__chat__send_message"),
            "{\"timestamp\":\"2026-04-04T00:00:00.000Z\",\"type\":\"response_item\",\"payload\":{\"type\":\"function_call\",\"name\":\"mcp__broken\"}}",
            "not json at all",
        ]
    )

    let repository = CodexUsageRepository(
        configLoader: CodexConfigLoader(paths: fixture.paths),
        transcriptReader: CodexTranscriptUsageReader(paths: fixture.paths)
    )
    _ = try await repository.loadCapabilities(windows: [.day7], now: Date(timeIntervalSince1970: 1_744_000_000))
    let warnings = await repository.currentWarnings()

    #expect(warnings.contains("Some Codex session entries could not be parsed, so these results may be incomplete."))
}

@Test
func codexReaderDoesNotTreatNonMcpFunctionCallsAsParseLoss() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.tempRoot) }

    try writeSession(
        to: fixture.paths.sessionsDirectory.appending(path: "2026/04/04/session.jsonl"),
        lines: [
            sessionLine(daysAgo: 1, name: "apply_patch"),
        ]
    )

    let result = try CodexTranscriptUsageReader(paths: fixture.paths).loadObservedEvents(since: .distantPast)
    #expect(result.events.isEmpty)
    #expect(result.skippedEntriesCount == 0)
    #expect(result.skippedFilesCount == 0)
}

@Test
func codexRepositoryCountsSelectedSkillsWithoutCountingCatalogMentions() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.tempRoot) }
    let skillDirectory = fixture.paths.skillsDirectory.appendingPathComponent("My-Skill")
    try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
    try "# Skill".write(to: skillDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    func message(role: String, text: String, timestamp: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: ["type": "response_item", "timestamp": timestamp, "payload": ["type": "message", "role": role, "content": [["type": "input_text", "text": text]]]])
        return String(decoding: data, as: UTF8.self)
    }
    let skillText = "<skill>\n<name>my-skill</name>\n<path>/skills/My-Skill/SKILL.md</path>\n# Instructions\n</skill>"
    try writeSession(to: fixture.paths.sessionsDirectory.appendingPathComponent("2026/session.jsonl"), lines: [
        try message(role: "user", text: skillText, timestamp: "2025-01-01T12:00:00Z"),
        try message(role: "user", text: skillText, timestamp: "2026-04-01T12:00:00.000Z"),
        try message(role: "assistant", text: skillText, timestamp: "2026-04-01T12:00:00Z"),
        try message(role: "user", text: "Available skills: my-skill (/skills/My-Skill/SKILL.md)", timestamp: "2026-04-01T12:00:00Z"),
    ])
    let repository = CodexUsageRepository(configLoader: CodexConfigLoader(paths: fixture.paths), transcriptReader: CodexTranscriptUsageReader(paths: fixture.paths))
    let now = ISO8601DateFormatter().date(from: "2026-04-02T12:00:00Z")!
    let windows = try await repository.loadCapabilities(windows: [.allTime, .day7], now: now)
    let allTime = try #require(windows[.allTime]?.first { $0.id.kind == .skill })
    #expect(allTime.id.name == "My-Skill")
    #expect(allTime.usageCount == 2)
    #expect(!allTime.installedButUnused)
    #expect(windows[.day7]?.first { $0.id.kind == .skill }?.usageCount == 1)
}

private func makeFixture() throws -> (tempRoot: URL, paths: CodexPaths) {
    let tempRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    let codexDirectory = tempRoot.appending(path: ".codex", directoryHint: .isDirectory)
    let sessionsDirectory = codexDirectory.appending(path: "sessions", directoryHint: .isDirectory)
    let skillsDirectory = codexDirectory.appending(path: "skills", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: skillsDirectory, withIntermediateDirectories: true)
    try "model = \"gpt-5.4\"\n".write(to: codexDirectory.appending(path: "config.toml"), atomically: true, encoding: .utf8)
    return (tempRoot, CodexPaths(homeDirectory: tempRoot))
}

private func writeSession(to url: URL, lines: [String]) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
}

private func sessionLine(daysAgo: Int, name: String, now: Date = Date(timeIntervalSince1970: 1_744_000_000)) -> String {
    let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now) ?? now
    let timestamp = makeDateFormatter().string(from: date)
    return "{\"timestamp\":\"\(timestamp)\",\"type\":\"response_item\",\"payload\":{\"type\":\"function_call\",\"name\":\"\(name)\"}}"
}

private func makeDateFormatter() -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}
