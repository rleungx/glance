import Foundation
import Testing
import GlanceCore
@testable import GlanceOpenCode

@Test
func repositoryIncludesInstalledButUnusedSkillsFromSkillsDirectory() async throws {
    let fixture = try makeRepositoryFixture()
    defer { try? FileManager.default.removeItem(at: fixture.tempRoot) }

    try FileManager.default.createDirectory(at: fixture.skillsDirectory, withIntermediateDirectories: true)
    let skillDirectory = fixture.skillsDirectory.appending(path: "find-skills", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
    try "# Skill".write(to: skillDirectory.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)

    let repository = makeRepository(paths: fixture.paths, runtimeServers: ["mem0-mcp"])
    let capabilities = try await repository.loadCapabilities()
    let skill = capabilities.first { $0.id.kind == .skill && $0.id.name == "find-skills" }

    #expect(skill != nil)
    #expect(skill?.usageCount == 0)
    #expect(skill?.installedButUnused == false)
}

@Test
func repositoryBuildsTopSkillsFromInstalledSkillsPlusObservedUsage() async throws {
    let fixture = try makeRepositoryFixture()
    defer { try? FileManager.default.removeItem(at: fixture.tempRoot) }

    try FileManager.default.createDirectory(at: fixture.skillsDirectory, withIntermediateDirectories: true)
    let skillDirectory = fixture.skillsDirectory.appending(path: "find-skills", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
    try "# Skill".write(to: skillDirectory.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)

    let recentTimestamp = timestampMilliseconds(daysAgo: 2)
    let skillJSON = "{\"type\":\"tool\",\"tool\":\"skill\",\"state\":{\"status\":\"completed\",\"input\":{\"name\":\"find-skills\"},\"time\":{\"start\":1000,\"end\":1300}}}"
    try fixture.connection.execute("INSERT INTO part VALUES ('1', 'msg1', 'ses1', \(recentTimestamp), \(recentTimestamp), '\(skillJSON)');")

    let repository = makeRepository(paths: fixture.paths, runtimeServers: ["mem0-mcp"])
    let capabilities = try await repository.loadCapabilities()
    let snapshot = CapabilityRanker.buildSnapshot(from: capabilities)
    let skill = snapshot.skills.first { $0.id.name == "find-skills" }

    #expect(skill != nil)
    #expect(skill?.usageCount == 1)
    #expect(skill?.installedButUnused == false)
}

@Test
func repositoryIgnoresObservedSkillUsageWhenSkillIsNotInstalled() async throws {
    let fixture = try makeRepositoryFixture()
    defer { try? FileManager.default.removeItem(at: fixture.tempRoot) }

    try FileManager.default.createDirectory(at: fixture.skillsDirectory, withIntermediateDirectories: true)
    let skillDirectory = fixture.skillsDirectory.appending(path: "find-skills", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
    try "# Skill".write(to: skillDirectory.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)

    let ghostSkillJSON = "{\"type\":\"tool\",\"tool\":\"skill\",\"state\":{\"status\":\"completed\",\"input\":{\"name\":\"ghost-skill\"},\"time\":{\"start\":1000,\"end\":1300}}}"
    try fixture.connection.execute("INSERT INTO part VALUES ('1', 'msg1', 'ses1', 1700000000000, 1700000000000, '\(ghostSkillJSON)');")

    let repository = makeRepository(paths: fixture.paths, runtimeServers: ["mem0-mcp"])
    let capabilities = try await repository.loadCapabilities()

    #expect(capabilities.contains { $0.id.kind == .skill && $0.id.name == "find-skills" })
    #expect(!capabilities.contains { $0.id.kind == .skill && $0.id.name == "ghost-skill" })
}

@Test
func repositoryDoesNotSurfaceRuntimeOnlyMCPServersWhenConfigDefinesInstalledSet() async throws {
    let fixture = try makeRepositoryFixture()
    defer { try? FileManager.default.removeItem(at: fixture.tempRoot) }

    let mem0ToolJSON = "{\"type\":\"tool\",\"tool\":\"mem0-mcp_get_memories\",\"state\":{\"status\":\"completed\",\"time\":{\"start\":1000,\"end\":1300}}}"
    let oldMCPToolJSON = "{\"type\":\"tool\",\"tool\":\"old-mcp_search\",\"state\":{\"status\":\"completed\",\"time\":{\"start\":2000,\"end\":2600}}}"
    try fixture.connection.execute("INSERT INTO part VALUES ('1', 'msg1', 'ses1', 1700000000000, 1700000000000, '\(mem0ToolJSON)');")
    try fixture.connection.execute("INSERT INTO part VALUES ('2', 'msg2', 'ses1', 1700000100000, 1700000100000, '\(oldMCPToolJSON)');")

    let repository = makeRepository(paths: fixture.paths, runtimeServers: ["mem0-mcp", "old-mcp"])
    let capabilities = try await repository.loadCapabilities()

    #expect(capabilities.contains { $0.id.kind == .mcpServer && $0.id.namespace == "mem0-mcp" })
    #expect(!capabilities.contains { $0.id.kind == .mcpServer && $0.id.namespace == "old-mcp" })
    #expect(!capabilities.contains { $0.id.kind == .mcpTool && $0.id.namespace == "old-mcp" })
}

@Test
func repositoryDoesNotFallbackToRuntimeWhenMCPConfigExistsButAllServersAreDisabled() async throws {
    let fixture = try makeRepositoryFixture(mcpConfigJSON: """
    {
      "mcp": {
        "mem0-mcp": { "enabled": false }
      }
    }
    """)
    defer { try? FileManager.default.removeItem(at: fixture.tempRoot) }

    let runtimeOnlyToolJSON = "{\"type\":\"tool\",\"tool\":\"old-mcp_search\",\"state\":{\"status\":\"completed\",\"time\":{\"start\":1000,\"end\":1300}}}"
    try fixture.connection.execute("INSERT INTO part VALUES ('1', 'msg1', 'ses1', 1700000000000, 1700000000000, '\(runtimeOnlyToolJSON)');")

    let repository = makeRepository(paths: fixture.paths, runtimeServers: ["old-mcp"])
    let capabilities = try await repository.loadCapabilities()

    #expect(!capabilities.contains { $0.id.kind == .mcpServer })
    #expect(!capabilities.contains { $0.id.kind == .mcpTool })
}

@Test
func repositoryCanonicalizesObservedSkillNameToInstalledSkillCasing() async throws {
    let fixture = try makeRepositoryFixture()
    defer { try? FileManager.default.removeItem(at: fixture.tempRoot) }

    try FileManager.default.createDirectory(at: fixture.skillsDirectory, withIntermediateDirectories: true)
    let skillDirectory = fixture.skillsDirectory.appending(path: "Find-Skills", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
    try "# Skill".write(to: skillDirectory.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)

    let recentTimestamp = timestampMilliseconds(daysAgo: 2)
    let skillJSON = "{\"type\":\"tool\",\"tool\":\"skill\",\"state\":{\"status\":\"completed\",\"input\":{\"name\":\"find-skills\"},\"time\":{\"start\":1000,\"end\":1300}}}"
    try fixture.connection.execute("INSERT INTO part VALUES ('1', 'msg1', 'ses1', \(recentTimestamp), \(recentTimestamp), '\(skillJSON)');")

    let repository = makeRepository(paths: fixture.paths, runtimeServers: ["mem0-mcp"])
    let capabilities = try await repository.loadCapabilities()
    let skills = capabilities.filter { $0.id.kind == .skill }

    #expect(skills.count == 1)
    #expect(skills.first?.id.name == "Find-Skills")
    #expect(skills.first?.usageCount == 1)
}

@Test
func repositoryProducesDifferentSnapshotsForDay1AndDay7Windows() async throws {
    let fixture = try makeRepositoryFixture()
    defer { try? FileManager.default.removeItem(at: fixture.tempRoot) }

    try FileManager.default.createDirectory(at: fixture.skillsDirectory, withIntermediateDirectories: true)
    let skillDirectory = fixture.skillsDirectory.appending(path: "find-skills", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
    try "# Skill".write(to: skillDirectory.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)

    let recentSkillJSON = "{\"type\":\"tool\",\"tool\":\"skill\",\"state\":{\"status\":\"completed\",\"input\":{\"name\":\"find-skills\"},\"time\":{\"start\":1000,\"end\":1300}}}"
    let olderSkillJSON = "{\"type\":\"tool\",\"tool\":\"skill\",\"state\":{\"status\":\"completed\",\"input\":{\"name\":\"find-skills\"},\"time\":{\"start\":2000,\"end\":2300}}}"
    try fixture.connection.execute("INSERT INTO part VALUES ('1', 'msg1', 'ses1', 1700000000000, 1700000000000, '\(recentSkillJSON)');")
    try fixture.connection.execute("INSERT INTO part VALUES ('2', 'msg2', 'ses1', 1699568000000, 1699568000000, '\(olderSkillJSON)');")

    let repository = makeRepository(paths: fixture.paths, runtimeServers: ["mem0-mcp"])
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let capabilitiesByWindow = try await repository.loadCapabilities(windows: [.day1, .day7], now: now)

    let day1Skill = capabilitiesByWindow[.day1]?.first { $0.id.kind == .skill && $0.id.name == "find-skills" }
    let day7Skill = capabilitiesByWindow[.day7]?.first { $0.id.kind == .skill && $0.id.name == "find-skills" }

    #expect(day1Skill != nil)
    #expect(day7Skill != nil)
    #expect(day1Skill?.usageCount == 1)
    #expect(day7Skill?.usageCount == 2)
}

@Test
func repositoryLoadCapabilitiesUsesThirtyDayWindow() async throws {
    let fixture = try makeRepositoryFixture()
    defer { try? FileManager.default.removeItem(at: fixture.tempRoot) }

    try FileManager.default.createDirectory(at: fixture.skillsDirectory, withIntermediateDirectories: true)
    let skillDirectory = fixture.skillsDirectory.appending(path: "find-skills", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
    try "# Skill".write(to: skillDirectory.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)

    let now = Date()
    let withinThirtyDaysTimestamp = timestampMilliseconds(daysAgo: 10, now: now)
    let outsideThirtyDaysTimestamp = timestampMilliseconds(daysAgo: 40, now: now)
    let withinThirtyDaySkillJSON = "{\"type\":\"tool\",\"tool\":\"skill\",\"state\":{\"status\":\"completed\",\"input\":{\"name\":\"find-skills\"},\"time\":{\"start\":1000,\"end\":1300}}}"
    let outsideThirtyDaySkillJSON = "{\"type\":\"tool\",\"tool\":\"skill\",\"state\":{\"status\":\"completed\",\"input\":{\"name\":\"find-skills\"},\"time\":{\"start\":2000,\"end\":2300}}}"
    try fixture.connection.execute("INSERT INTO part VALUES ('1', 'msg1', 'ses1', \(withinThirtyDaysTimestamp), \(withinThirtyDaysTimestamp), '\(withinThirtyDaySkillJSON)');")
    try fixture.connection.execute("INSERT INTO part VALUES ('2', 'msg2', 'ses1', \(outsideThirtyDaysTimestamp), \(outsideThirtyDaysTimestamp), '\(outsideThirtyDaySkillJSON)');")

    let repository = makeRepository(paths: fixture.paths, runtimeServers: ["mem0-mcp"])
    let defaultCapabilities = try await repository.loadCapabilities()
    let windowedCapabilities = try await repository.loadCapabilities(windows: [.day30, .day45], now: now)

    let defaultSkill = defaultCapabilities.first { $0.id.kind == .skill && $0.id.name == "find-skills" }
    let day30Skill = windowedCapabilities[.day30]?.first { $0.id.kind == .skill && $0.id.name == "find-skills" }
    let day45Skill = windowedCapabilities[.day45]?.first { $0.id.kind == .skill && $0.id.name == "find-skills" }

    #expect(defaultSkill != nil)
    #expect(day30Skill != nil)
    #expect(day45Skill != nil)
    #expect(defaultSkill?.usageCount == day30Skill?.usageCount)
    #expect(day30Skill?.usageCount == 1)
    #expect(day45Skill?.usageCount == 2)
}

@Test
func repositoryUsesRuntimeMCPsWhenGlobalConfigOnlyContainsModel() async throws {
    let fixture = try makeRepositoryFixture(mcpConfigJSON: #"{"model":"provider/model"}"#)
    defer { try? FileManager.default.removeItem(at: fixture.tempRoot) }
    let timestamp = timestampMilliseconds(daysAgo: 1)
    let json = #"{"type":"tool","tool":"project-mcp_search","state":{"status":"completed","time":{"start":1000,"end":1300}}}"#
    try fixture.connection.execute("INSERT INTO part VALUES ('1', 'msg', 'session', \(timestamp), \(timestamp), '\(json)');")
    let capabilities = try await makeRepository(paths: fixture.paths, runtimeServers: ["project-mcp"]).loadCapabilities()
    #expect(capabilities.first { $0.id.kind == .mcpServer && $0.id.namespace == "project-mcp" }?.usageCount == 1)
    #expect(capabilities.first { $0.id.kind == .mcpTool && $0.id.name == "search" }?.usageCount == 1)
}

@Test
func repositoryCleanupPreservesHistoricalCountsAndFailureEvidence() async throws {
    let fixture = try makeRepositoryFixture()
    defer { try? FileManager.default.removeItem(at: fixture.tempRoot) }
    let now = Date()
    let timestamp = timestampMilliseconds(daysAgo: 200, now: now)
    for (name, count, status) in [("frequent", 100, "completed"), ("rare", 1, "completed"), ("failing", 100, "error")] {
        let directory = fixture.skillsDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "# Skill".write(to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        for index in 0..<count {
            let json = "{\"type\":\"tool\",\"tool\":\"skill\",\"state\":{\"status\":\"\(status)\",\"input\":{\"name\":\"\(name)\"},\"time\":{\"start\":1000,\"end\":1300}}}"
            try fixture.connection.execute("INSERT INTO part VALUES ('\(name)-\(index)', 'msg', 'session', \(timestamp), \(timestamp), '\(json)');")
        }
    }
    let windows = try await makeRepository(paths: fixture.paths, runtimeServers: []).loadCapabilities(windows: [.day7, .allTime], now: now)
    let history = try #require(windows[.allTime])
    let snapshot = CapabilityRanker.buildSnapshot(from: history, now: now)
    #expect(history.first { $0.id.name == "frequent" }?.usageCount == 100)
    #expect(history.first { $0.id.name == "failing" }?.failureCount == 100)
    #expect(!snapshot.removalCandidates.contains { $0.id.name == "frequent" })
    #expect(snapshot.removalCandidates.isEmpty)
    let verified = CapabilityRanker.buildSnapshot(from: history, now: now,
        evidence: UsageEvidence(completeness: .verified, verifiedFrom: .distantPast, verifiedThrough: now))
    #expect(verified.removalCandidates.contains { $0.id.name == "rare" })
    #expect(verified.removalCandidates.contains { $0.id.name == "failing" })
    #expect(!verified.removalCandidates.contains { $0.id.name == "frequent" })
    #expect(windows[.day7]?.allSatisfy { $0.usageCount == 0 } == true)
}

@Test
func repositoryMissingDatabaseReportsUnavailableAndPausesCleanup() async throws {
    let fixture = try makeRepositoryFixture()
    defer { try? FileManager.default.removeItem(at: fixture.tempRoot) }
    try FileManager.default.removeItem(at: fixture.paths.databaseURL)
    let result = try await makeRepository(paths: fixture.paths, runtimeServers: []).loadUsage(windows: [.allTime], now: .now)
    #expect(result.evidence.completeness == .unavailable)
    #expect(result.windows[.allTime]?.allSatisfy { !$0.installedButUnused } == true)
    #expect(CapabilityRanker.buildSnapshot(from: result.windows[.allTime] ?? [], evidence: result.evidence).removalCandidates.isEmpty)
}

@Test
func repositoryExcludesFutureRowsAndRetainsDatabaseEvidence() async throws {
    let fixture = try makeRepositoryFixture()
    defer { try? FileManager.default.removeItem(at: fixture.tempRoot) }
    let now = Date.now
    for (id, day) in [("past", 1), ("future", -1)] {
        let timestamp = timestampMilliseconds(daysAgo: day, now: now)
        let json = #"{"type":"tool","tool":"mem0-mcp_search","state":{"status":"completed"}}"#
        try fixture.connection.execute("INSERT INTO part VALUES ('\(id)', 'msg', 'session', \(timestamp), \(timestamp), '\(json)');")
    }
    let result = try await makeRepository(paths: fixture.paths, runtimeServers: []).loadUsage(windows: [.allTime, .day7], now: now)
    for usages in result.windows.values {
        let tool = try #require(usages.first { $0.id.kind == .mcpTool })
        #expect(tool.usageCount == 1)
        #expect(tool.evidenceSamples?.first?.record == "part.id=past")
    }
    #expect(result.evidence.completeness == .observed)
    #expect(result.evidence.observedThrough! < now)
}

private func makeRepositoryFixture(mcpConfigJSON: String = """
{
  "mcp": {
    "mem0-mcp": { "enabled": true }
  }
}
""") throws -> (tempRoot: URL, paths: OpenCodePaths, connection: SQLiteConnection, skillsDirectory: URL) {
    let tempRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

    let configDirectory = tempRoot.appending(path: ".config/opencode", directoryHint: .isDirectory)
    let dataDirectory = tempRoot.appending(path: ".local/share/opencode", directoryHint: .isDirectory)
    let skillsDirectory = tempRoot.appending(path: ".agents/skills", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: skillsDirectory, withIntermediateDirectories: true)

    try mcpConfigJSON.write(to: configDirectory.appending(path: "opencode.json"), atomically: true, encoding: .utf8)

    let databaseURL = dataDirectory.appending(path: "opencode.db")
    let connection = try SQLiteConnection(url: databaseURL, mode: .readWriteCreate)
    try connection.execute("CREATE TABLE part (id TEXT PRIMARY KEY, message_id TEXT, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT);")

    let paths = OpenCodePaths(
        homeDirectory: tempRoot,
        configDirectory: configDirectory,
        dataDirectory: dataDirectory,
        skillsDirectory: skillsDirectory
    )

    return (tempRoot, paths, connection, skillsDirectory)
}

private func makeRepository(paths: OpenCodePaths, runtimeServers: Set<String>) -> OpenCodeUsageRepository {
    OpenCodeUsageRepository(
        configLoader: OpenCodeConfigLoader(paths: paths),
        usageReader: OpenCodeUsageReader(paths: paths),
        mcpServerNameProvider: StubMCPServerNameProvider(serverNames: runtimeServers)
    )
}

private struct StubMCPServerNameProvider: OpenCodeMCPServerNameProviding {
    let serverNames: Set<String>

    func loadServerNames() async throws -> Set<String> {
        serverNames
    }
}

private func timestampMilliseconds(daysAgo: Int, now: Date = .now) -> Int64 {
    let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now) ?? now
    return Int64((date.timeIntervalSince1970 * 1_000).rounded(.down))
}
