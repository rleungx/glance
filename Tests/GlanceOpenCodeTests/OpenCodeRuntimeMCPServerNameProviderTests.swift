import Foundation
import Testing
@testable import GlanceOpenCode

@Test
func runtimeMCPProviderLoadsServerNamesFromHTTPStatus() async throws {
    let tempRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let paths = OpenCodePaths(
        homeDirectory: tempRoot,
        configDirectory: tempRoot.appending(path: ".config/opencode", directoryHint: .isDirectory),
        dataDirectory: tempRoot.appending(path: ".local/share/opencode", directoryHint: .isDirectory),
        skillsDirectory: tempRoot.appending(path: ".agents/skills", directoryHint: .isDirectory)
    )

    let provider = OpenCodeRuntimeMCPServerNameProvider(
        paths: paths,
        fetchMCPStatusData: { _ in
            Data("{\"websearch\":{\"status\":\"connected\"},\"grep_app\":{\"status\":\"connected\"},\"mem0-mcp\":{\"status\":\"connected\"}}".utf8)
        }
    )

    let names = try await provider.loadServerNames()

    #expect(names == Set(["websearch", "grep_app", "mem0-mcp"]))
}

@Test
func runtimeMCPProviderFallsBackToLogsWhenHTTPUnavailable() async throws {
    let tempRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let dataDirectory = tempRoot.appending(path: ".local/share/opencode", directoryHint: .isDirectory)
    let logDirectory = dataDirectory.appending(path: "log", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    try """
    INFO service=mcp key=websearch type=remote found
    INFO service=mcp key=context7 type=remote found
    INFO service=mcp key=grep_app type=remote found
    """.write(to: logDirectory.appending(path: "2026-04-01T000000.log"), atomically: true, encoding: .utf8)

    let paths = OpenCodePaths(
        homeDirectory: tempRoot,
        configDirectory: tempRoot.appending(path: ".config/opencode", directoryHint: .isDirectory),
        dataDirectory: dataDirectory,
        skillsDirectory: tempRoot.appending(path: ".agents/skills", directoryHint: .isDirectory)
    )

    let provider = OpenCodeRuntimeMCPServerNameProvider(
        paths: paths,
        fetchMCPStatusData: { _ in throw OpenCodeDataError.unexpectedData("offline") }
    )

    let names = try await provider.loadServerNames()

    #expect(names == Set(["websearch", "context7", "grep_app"]))
}

@Test
func runtimeMCPProviderNormalizesQuotedAndPunctuatedLogKeys() async throws {
    let tempRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let dataDirectory = tempRoot.appending(path: ".local/share/opencode", directoryHint: .isDirectory)
    let logDirectory = dataDirectory.appending(path: "log", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    try """
    INFO service=mcp key="websearch". type=remote found
    INFO service=mcp key='context7', type=remote found
    INFO service=mcp key=grep_app; type=remote found
    INFO service=mcp key=`mem0-mcp`) type=remote found
    """.write(to: logDirectory.appending(path: "2026-04-02T000000.log"), atomically: true, encoding: .utf8)

    let paths = OpenCodePaths(
        homeDirectory: tempRoot,
        configDirectory: tempRoot.appending(path: ".config/opencode", directoryHint: .isDirectory),
        dataDirectory: dataDirectory,
        skillsDirectory: tempRoot.appending(path: ".agents/skills", directoryHint: .isDirectory)
    )

    let provider = OpenCodeRuntimeMCPServerNameProvider(
        paths: paths,
        fetchMCPStatusData: { _ in throw OpenCodeDataError.unexpectedData("offline") }
    )

    let names = try await provider.loadServerNames()

    #expect(names == Set(["websearch", "context7", "grep_app", "mem0-mcp"]))
}
