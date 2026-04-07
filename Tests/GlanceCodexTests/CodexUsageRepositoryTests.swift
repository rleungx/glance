import Foundation
import Testing
import GlanceCore
@testable import GlanceCodex

@Test
func codexRepositoryIncludesInstalledSkillsAsUnused() async throws {
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
    #expect(skill?.installedButUnused == true)
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
