import Foundation
import Testing
import GlanceCore
@testable import GlanceOpenCode

@Test
func usageReaderAggregatesSkillAndMCPToolInvocations() throws {
    let fixture = try makeFixtureDatabase()
    defer { try? FileManager.default.removeItem(at: fixture.tempRoot) }

    let skillJSON = "{\"type\":\"tool\",\"tool\":\"skill\",\"state\":{\"status\":\"completed\",\"input\":{\"name\":\"find-skills\"},\"time\":{\"start\":1000,\"end\":1300}}}"
    let mcpJSON = "{\"type\":\"tool\",\"tool\":\"mem0-mcp_get_memories\",\"state\":{\"status\":\"completed\",\"time\":{\"start\":2000,\"end\":2900}}}"
    try fixture.connection.execute("INSERT INTO part VALUES ('1', 'msg1', 'ses1', 1700000000000, 1700000000000, '\(skillJSON)');")
    try fixture.connection.execute("INSERT INTO part VALUES ('2', 'msg2', 'ses1', 1700000100000, 1700000100000, '\(mcpJSON)');")

    let reader = OpenCodeUsageReader(paths: fixture.paths)
    let usages = try reader.loadObservedCapabilities(mcpServerNames: Set(["mem0-mcp"]))
    let identifiers = Set(usages.map(\.usage.id.rawValue))

    #expect(identifiers.contains(CapabilityID(kind: .skill, name: "find-skills").rawValue))
    #expect(identifiers.contains(CapabilityID(kind: .mcpTool, namespace: "mem0-mcp", name: "get_memories").rawValue))
}

@Test
func usageReaderRecognizesRuntimeMCPServersIncludingContext7WebsearchAndGrepApp() throws {
    let fixture = try makeFixtureDatabase()
    defer { try? FileManager.default.removeItem(at: fixture.tempRoot) }

    let context7JSON = "{\"type\":\"tool\",\"tool\":\"Context7_query-docs\",\"state\":{\"status\":\"completed\",\"time\":{\"start\":3000,\"end\":3900}}}"
    let websearchBuiltInJSON = "{\"type\":\"tool\",\"tool\":\"WebSearch\",\"state\":{\"status\":\"completed\",\"time\":{\"start\":4000,\"end\":4600}}}"
    let websearchExaJSON = "{\"type\":\"tool\",\"tool\":\"WebSearch_web_search_exa\",\"state\":{\"status\":\"completed\",\"time\":{\"start\":5000,\"end\":6200}}}"
    let grepAppJSON = "{\"type\":\"tool\",\"tool\":\"grep_app_searchGitHub\",\"state\":{\"status\":\"completed\",\"time\":{\"start\":7000,\"end\":7600}}}"

    try fixture.connection.execute("INSERT INTO part VALUES ('1', 'msg1', 'ses1', 1700000000000, 1700000000000, '\(context7JSON)');")
    try fixture.connection.execute("INSERT INTO part VALUES ('2', 'msg2', 'ses1', 1700000100000, 1700000100000, '\(websearchBuiltInJSON)');")
    try fixture.connection.execute("INSERT INTO part VALUES ('3', 'msg3', 'ses1', 1700000200000, 1700000200000, '\(websearchExaJSON)');")
    try fixture.connection.execute("INSERT INTO part VALUES ('4', 'msg4', 'ses1', 1700000300000, 1700000300000, '\(grepAppJSON)');")

    let reader = OpenCodeUsageReader(paths: fixture.paths)
    let usages = try reader.loadObservedCapabilities(mcpServerNames: Set(["context7", "websearch", "grep_app"]))
    let identifiers = Set(usages.map(\.usage.id.rawValue))

    #expect(identifiers.contains(CapabilityID(kind: .mcpTool, namespace: "context7", name: "query-docs").rawValue))
    #expect(identifiers.contains(CapabilityID(kind: .mcpTool, namespace: "websearch", name: "web_search_exa").rawValue))
    #expect(identifiers.contains(CapabilityID(kind: .mcpTool, namespace: "grep_app", name: "searchgithub").rawValue))
    #expect(!identifiers.contains(CapabilityID(kind: .mcpTool, namespace: "websearch", name: "websearch").rawValue))
}

@Test
func usageReaderDoesNotTreatBuiltInCodeSearchAndWebSearchAsMCPWithoutPrefix() throws {
    let fixture = try makeFixtureDatabase()
    defer { try? FileManager.default.removeItem(at: fixture.tempRoot) }

    let codeSearchBuiltInJSON = "{\"type\":\"tool\",\"tool\":\"CodeSearch\",\"state\":{\"status\":\"completed\",\"time\":{\"start\":3000,\"end\":3900}}}"
    let codeSearchPrefixedJSON = "{\"type\":\"tool\",\"tool\":\"codesearch_searchGitHub\",\"state\":{\"status\":\"completed\",\"time\":{\"start\":4000,\"end\":4600}}}"
    let websearchBuiltInJSON = "{\"type\":\"tool\",\"tool\":\"WebSearch\",\"state\":{\"status\":\"completed\",\"time\":{\"start\":5000,\"end\":5600}}}"
    let websearchPrefixedJSON = "{\"type\":\"tool\",\"tool\":\"websearch_web_search_exa\",\"state\":{\"status\":\"completed\",\"time\":{\"start\":6000,\"end\":6900}}}"

    try fixture.connection.execute("INSERT INTO part VALUES ('1', 'msg1', 'ses1', 1700000000000, 1700000000000, '\(codeSearchBuiltInJSON)');")
    try fixture.connection.execute("INSERT INTO part VALUES ('2', 'msg2', 'ses1', 1700000100000, 1700000100000, '\(codeSearchPrefixedJSON)');")
    try fixture.connection.execute("INSERT INTO part VALUES ('3', 'msg3', 'ses1', 1700000200000, 1700000200000, '\(websearchBuiltInJSON)');")
    try fixture.connection.execute("INSERT INTO part VALUES ('4', 'msg4', 'ses1', 1700000300000, 1700000300000, '\(websearchPrefixedJSON)');")

    let reader = OpenCodeUsageReader(paths: fixture.paths)
    let usages = try reader.loadObservedCapabilities(mcpServerNames: Set(["codesearch", "websearch"]))
    let identifiers = Set(usages.map(\.usage.id.rawValue))

    #expect(identifiers.contains(CapabilityID(kind: .mcpTool, namespace: "codesearch", name: "searchgithub").rawValue))
    #expect(identifiers.contains(CapabilityID(kind: .mcpTool, namespace: "websearch", name: "web_search_exa").rawValue))
    #expect(!identifiers.contains(CapabilityID(kind: .mcpTool, namespace: "codesearch", name: "codesearch").rawValue))
    #expect(!identifiers.contains(CapabilityID(kind: .mcpTool, namespace: "websearch", name: "websearch").rawValue))
}

@Test
func usageReaderNormalizesSkillMCPInvocations() throws {
    let fixture = try makeFixtureDatabase()
    defer { try? FileManager.default.removeItem(at: fixture.tempRoot) }

    let skillMCPJSON = "{\"type\":\"tool\",\"tool\":\"skill_mcp\",\"state\":{\"status\":\"completed\",\"input\":{\"mcp_name\":\"mem0-mcp\",\"tool_name\":\"search_memories\"},\"time\":{\"start\":2000,\"end\":2900}}}"
    try fixture.connection.execute("INSERT INTO part VALUES ('1', 'msg1', 'ses1', 1700000000000, 1700000000000, '\(skillMCPJSON)');")

    let reader = OpenCodeUsageReader(paths: fixture.paths)
    let usages = try reader.loadObservedCapabilities(mcpServerNames: Set(["mem0-mcp"]))

    #expect(usages.count == 1)
    #expect(usages.first?.usage.id == CapabilityID(kind: .mcpTool, namespace: "mem0-mcp", name: "search_memories"))
    #expect(usages.first?.serverName == "mem0-mcp")
}

@Test
func usageReaderIgnoresSkillMCPInvocationsForUnavailableServer() throws {
    let fixture = try makeFixtureDatabase()
    defer { try? FileManager.default.removeItem(at: fixture.tempRoot) }

    let skillMCPJSON = "{\"type\":\"tool\",\"tool\":\"skill_mcp\",\"state\":{\"status\":\"completed\",\"input\":{\"mcp_name\":\"old-mcp\",\"tool_name\":\"search_memories\"},\"time\":{\"start\":2000,\"end\":2900}}}"
    try fixture.connection.execute("INSERT INTO part VALUES ('1', 'msg1', 'ses1', 1700000000000, 1700000000000, '\(skillMCPJSON)');")

    let reader = OpenCodeUsageReader(paths: fixture.paths)
    let usages = try reader.loadObservedCapabilities(mcpServerNames: Set(["mem0-mcp"]))

    #expect(usages.isEmpty)
}

@Test
func usageReaderIgnoresUnconfiguredMcpLookingTools() throws {
    let fixture = try makeFixtureDatabase()
    defer { try? FileManager.default.removeItem(at: fixture.tempRoot) }

    let unknownMCPJSON = "{\"type\":\"tool\",\"tool\":\"unknown-mcp_doThing\",\"state\":{\"status\":\"completed\",\"time\":{\"start\":2000,\"end\":2900}}}"
    try fixture.connection.execute("INSERT INTO part VALUES ('1', 'msg1', 'ses1', 1700000000000, 1700000000000, '\(unknownMCPJSON)');")

    let reader = OpenCodeUsageReader(paths: fixture.paths)
    let usages = try reader.loadObservedCapabilities(mcpServerNames: Set(["mem0-mcp"]))

    #expect(usages.isEmpty)
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

    let allTimeUsages = try reader.loadObservedCapabilities(mcpServerNames: Set<String>())
    let cutoffUsages = try reader.loadObservedCapabilities(mcpServerNames: Set<String>(), since: cutoffDate)

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
        try reader.loadObservedCapabilities(mcpServerNames: Set<String>())
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
