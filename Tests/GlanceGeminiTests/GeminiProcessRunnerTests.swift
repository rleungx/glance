import Foundation
import Testing
@testable import GlanceGemini

@Test
func geminiRunnerFindsNodeBesideExecutableWithFinderPath() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let bin = root.appendingPathComponent("bin")
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    let executable = bin.appendingPathComponent("gemini")
    let node = bin.appendingPathComponent("node")
    try "#!/usr/bin/env node\n".write(to: executable, atomically: true, encoding: .utf8)
    // Stand-in interpreter: env must locate this via the child's augmented PATH.
    try "#!/bin/sh\nprintf '%s:%s:%s' \"$GLANCE_TEST_MARKER\" \"$2\" \"$3\"\n".write(to: node, atomically: true, encoding: .utf8)
    for file in [executable, node] {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
    }
    let locator = GeminiExecutableLocator(homeDirectory: root, environment: ["PATH": "/usr/bin:/bin", "GLANCE_TEST_MARKER": "retained"])
    #expect(locator.executableURL() == executable)
    let output = try GeminiProcessRunner(executableLocator: locator).run(arguments: ["skills", "list"])
    #expect(output == "retained:skills:list")
}
