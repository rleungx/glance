import Foundation
import Testing
@testable import GlanceGemini

@Test
func geminiConfigLoaderParsesSkillsListOutput() throws {
    let runner = StubGeminiCommandRunner(outputs: [
        ["skills", "list", "--all"]: """
        Loaded cached credentials.
        Discovered Agent Skills:

        find-skills [Enabled]
          Description: Helps users discover skills.
          Location:    /tmp/glance-test/skills/find-skills/SKILL.md

        skill-creator [Enabled] [Built-in]
          Description: Guide for creating skills.
          Location:    /opt/homebrew/builtin/skill-creator/SKILL.md
        """,
        ["mcp", "list"]: "No MCP servers configured.",
    ])

    let loader = GeminiConfigLoader(paths: GeminiPaths(homeDirectory: FileManager.default.homeDirectoryForCurrentUser), commandRunner: runner)
    let skills = try loader.loadInstalledSkills()

    #expect(skills.map(\.name) == ["find-skills", "skill-creator"])
    #expect(skills.first?.enabled == true)
    #expect(skills.last?.builtIn == true)
}

@Test
func geminiConfigLoaderParsesMcpListOutput() throws {
    let runner = StubGeminiCommandRunner(outputs: [
        ["skills", "list", "--all"]: "",
        ["mcp", "list"]: """
        Configured MCP servers:

        ✓ mem0-mcp: npx mem0 (stdio) - Connected
        ○ old-server: http://localhost:3000 (http) - Disabled
        ✗ websearch (from demo-ext): https://example.com (http) - Disconnected
        """,
    ])

    let loader = GeminiConfigLoader(paths: GeminiPaths(homeDirectory: FileManager.default.homeDirectoryForCurrentUser), commandRunner: runner)
    let servers = try loader.loadConfiguredMCPServers()

    #expect(servers.map(\.name) == ["mem0-mcp", "old-server", "websearch"])
    #expect(servers.map(\.enabled) == [true, false, true])
}

@Test
func geminiConfigLoaderCachesSkillAndMcpCommandsWithinTTL() throws {
    let runner = CountingGeminiCommandRunner(outputs: [
        ["skills", "list", "--all"]: "find-skills [Enabled]\n  Location: /tmp/find-skills/SKILL.md",
        ["mcp", "list"]: "No MCP servers configured.",
    ])

    var now = Date(timeIntervalSince1970: 1_000)
    let loader = GeminiConfigLoader(
        paths: GeminiPaths(homeDirectory: FileManager.default.homeDirectoryForCurrentUser),
        commandRunner: runner,
        cacheTTL: 60,
        nowProvider: { now }
    )

    _ = try loader.loadInstalledSkills()
    _ = try loader.loadInstalledSkills()
    _ = try loader.loadConfiguredMCPServers()
    _ = try loader.loadConfiguredMCPServers()
    #expect(runner.callCount(for: ["skills", "list", "--all"]) == 1)
    #expect(runner.callCount(for: ["mcp", "list"]) == 1)

    now = Date(timeIntervalSince1970: 1_100)
    _ = try loader.loadInstalledSkills()
    _ = try loader.loadConfiguredMCPServers()
    #expect(runner.callCount(for: ["skills", "list", "--all"]) == 2)
    #expect(runner.callCount(for: ["mcp", "list"]) == 2)
}

@Test
func geminiConfigLoaderUsesLongerDefaultTTL() throws {
    let runner = CountingGeminiCommandRunner(outputs: [
        ["skills", "list", "--all"]: "find-skills [Enabled]\n  Location: /tmp/find-skills/SKILL.md",
        ["mcp", "list"]: "No MCP servers configured.",
    ])

    var now = Date(timeIntervalSince1970: 1_000)
    let loader = GeminiConfigLoader(
        paths: GeminiPaths(homeDirectory: FileManager.default.homeDirectoryForCurrentUser),
        commandRunner: runner,
        nowProvider: { now }
    )

    _ = try loader.loadInstalledSkills()
    _ = try loader.loadConfiguredMCPServers()

    now = Date(timeIntervalSince1970: 1_120)
    _ = try loader.loadInstalledSkills()
    _ = try loader.loadConfiguredMCPServers()

    #expect(runner.callCount(for: ["skills", "list", "--all"]) == 1)
    #expect(runner.callCount(for: ["mcp", "list"]) == 1)
}

@Test
func geminiExecutableLocatorFindsBinaryFromExplicitOverride() throws {
    let tempRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let executableURL = tempRoot.appending(path: "gemini", directoryHint: .notDirectory)
    try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

    let locator = GeminiExecutableLocator(
        homeDirectory: tempRoot,
        environment: ["GLANCE_GEMINI_EXECUTABLE": executableURL.path]
    )

    #expect(locator.executableURL() == executableURL)
    #expect(locator.isInstalled())
}

@Test
func geminiExecutableLocatorFallsBackToKnownHomeBinPath() throws {
    let tempRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let binDirectory = tempRoot.appending(path: "bin", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
    let executableURL = binDirectory.appending(path: "gemini", directoryHint: .notDirectory)
    try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

    let locator = GeminiExecutableLocator(homeDirectory: tempRoot, environment: [:])

    #expect(locator.executableURL() == executableURL)
    #expect(locator.isInstalled())
}

@Test
func geminiExecutableLocatorExpandsTildeInOverridePath() throws {
    let tempRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let binDirectory = tempRoot.appending(path: "bin", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
    let executableURL = binDirectory.appending(path: "gemini", directoryHint: .notDirectory)
    try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

    let locator = GeminiExecutableLocator(
        homeDirectory: tempRoot,
        environment: ["GLANCE_GEMINI_EXECUTABLE": "~/bin/gemini"]
    )

    #expect(locator.executableURL() == executableURL)
}

@Test
func geminiExecutableLocatorIgnoresRelativePathEntries() throws {
    let tempRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let relativeDirectory = tempRoot.appending(path: "relative-bin", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: relativeDirectory, withIntermediateDirectories: true)
    let executableURL = relativeDirectory.appending(path: "gemini", directoryHint: .notDirectory)
    try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

    let locator = GeminiExecutableLocator(
        homeDirectory: tempRoot,
        environment: ["PATH": "relative-bin:/usr/bin"]
    )

    #expect(locator.executableURL() != executableURL)
}

@Test
func geminiProcessRunnerIgnoresStderrWhenCommandSucceeds() throws {
    let result = try GeminiProcessRunner.result(
        output: "find-skills [Enabled]\n",
        errorOutput: "warning: cached credentials expired soon\n",
        terminationStatus: 0
    )

    #expect(result == "find-skills [Enabled]\n")
}

@Test
func geminiProcessRunnerUsesStderrForFailuresWhenAvailable() {
    #expect(throws: (any Error).self) {
        _ = try GeminiProcessRunner.result(
            output: "",
            errorOutput: "fatal: command failed\n",
            terminationStatus: 1
        )
    }
}

@Test
func geminiProcessRunnerFallsBackToStdoutForFailureWhenStderrIsEmpty() {
    #expect(throws: (any Error).self) {
        _ = try GeminiProcessRunner.result(
            output: "fatal: command failed\n",
            errorOutput: "",
            terminationStatus: 1
        )
    }
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
