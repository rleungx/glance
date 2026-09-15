import Foundation
import Testing
import GlanceCore
@testable import GlanceOpenCode

@Test
func usageReaderCountsOnlySkillsInMixedToolHistory() throws {
    let fixture = try makeFixtureDatabase()
    defer { try? FileManager.default.removeItem(at: fixture.tempRoot) }

    let skillJSON = "{\"type\":\"tool\",\"tool\":\"skill\",\"state\":{\"status\":\"completed\",\"input\":{\"name\":\"find-skills\"},\"time\":{\"start\":1000,\"end\":1300}}}"
    let mcpJSON = "{\"type\":\"tool\",\"tool\":\"mem0-mcp_get_memories\",\"state\":{\"status\":\"completed\",\"time\":{\"start\":2000,\"end\":2900}}}"
    try fixture.connection.execute("INSERT INTO part VALUES ('1', 'msg1', 'ses1', 1700000000000, 1700000000000, '\(skillJSON)');")
    try fixture.connection.execute("INSERT INTO part VALUES ('2', 'msg2', 'ses1', 1700000100000, 1700000100000, '\(mcpJSON)');")

    let bridgeJSON = #"{"type":"tool","tool":"skill_mcp","state":{"status":"completed","input":{"name":"find-skills","mcp_name":"docs","tool_name":"search"}}}"#
    try fixture.connection.execute("INSERT INTO part VALUES ('3', 'msg3', 'ses1', 1700000200000, 1700000200000, '\(bridgeJSON)');")

    let reader = OpenCodeUsageReader(paths: fixture.paths)
    let usages = try reader.loadObservedCapabilities()
    let identifiers = Set(usages.map(\.usage.id.rawValue))

    #expect(identifiers.contains(CapabilityID(kind: .skill, name: "find-skills").rawValue))
    #expect(usages.count == 1)
    #expect(usages.first?.usage.usageCount == 1)
    #expect(usages.first?.usage.successCount == 1)
    #expect(usages.first?.usage.avgLatencyMs == 300)
}

@Test
func usageReaderFiltersObservedCapabilitiesByCutoffDate() throws {
    let fixture = try makeFixtureDatabase()
    defer { try? FileManager.default.removeItem(at: fixture.tempRoot) }

    let oldSkillJSON = "{\"type\":\"tool\",\"tool\":\"skill\",\"state\":{\"status\":\"completed\",\"input\":{\"name\":\"find-skills\"},\"time\":{\"start\":1000,\"end\":1300}}}"
    let newSkillJSON = "{\"type\":\"tool\",\"tool\":\"skill\",\"state\":{\"status\":\"completed\",\"input\":{\"name\":\"find-skills\"},\"time\":{\"start\":2000,\"end\":2300}}}"
    try fixture.connection.execute("INSERT INTO part VALUES ('1', 'msg1', 'ses1', 1700000000000, 1700000000000, '\(oldSkillJSON)');")
    try fixture.connection.execute("INSERT INTO part VALUES ('2', 'msg2', 'ses1', 1703000000000, 1703000000000, '\(newSkillJSON)');")

    let reader = OpenCodeUsageReader(paths: fixture.paths)
    let cutoffDate = Date(timeIntervalSince1970: 1_702_000_000)

    let allTimeUsages = try reader.loadObservedCapabilities()
    let cutoffUsages = try reader.loadObservedCapabilities(since: cutoffDate)

    #expect(allTimeUsages.count == 1)
    #expect(allTimeUsages.first?.usage.usageCount == 2)
    #expect(cutoffUsages.count == 1)
    #expect(cutoffUsages.first?.usage.usageCount == 1)
    #expect(cutoffUsages.first?.usage.firstUsedAt == Date(timeIntervalSince1970: 1_703_000_000))
}

@Test
func usageReaderFailsClearlyWhenPartTableIsMissing() throws {
    let tempRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let dataDirectory = tempRoot.appending(path: ".local/share/opencode", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
    let databaseURL = dataDirectory.appending(path: "opencode.db")

    _ = try SQLiteConnection(url: databaseURL, mode: .readWriteCreate)

    let paths = OpenCodePaths(
        homeDirectory: tempRoot,
        configDirectory: tempRoot.appending(path: ".config/opencode", directoryHint: .isDirectory),
        dataDirectory: dataDirectory,
        skillsDirectory: tempRoot.appending(path: ".agents/skills", directoryHint: .isDirectory)
    )

    let reader = OpenCodeUsageReader(paths: paths)

    #expect(throws: OpenCodeDataError.self) {
        try reader.loadObservedCapabilities()
    }
}

private func makeFixtureDatabase() throws -> (tempRoot: URL, paths: OpenCodePaths, connection: SQLiteConnection) {
    let tempRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

    let dataDirectory = tempRoot.appending(path: ".local/share/opencode", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
    let databaseURL = dataDirectory.appending(path: "opencode.db")

    let connection = try SQLiteConnection(url: databaseURL, mode: .readWriteCreate)
    try connection.execute("CREATE TABLE part (id TEXT PRIMARY KEY, message_id TEXT, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT);")

    let paths = OpenCodePaths(
        homeDirectory: tempRoot,
        configDirectory: tempRoot.appending(path: ".config/opencode", directoryHint: .isDirectory),
        dataDirectory: dataDirectory,
        skillsDirectory: tempRoot.appending(path: ".agents/skills", directoryHint: .isDirectory)
    )

    return (tempRoot, paths, connection)
}
