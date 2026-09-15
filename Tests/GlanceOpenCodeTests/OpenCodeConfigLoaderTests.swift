import Foundation
import Testing
@testable import GlanceOpenCode

@Test
func configLoaderFindsInstalledSkillsWithoutReadingGlobalConfig() throws {
    let tempRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let configDirectory = tempRoot.appending(path: ".config/opencode", directoryHint: .isDirectory)
    let skillsDirectory = tempRoot.appending(path: ".agents/skills", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: skillsDirectory, withIntermediateDirectories: true)

    let skillDirectory = skillsDirectory.appending(path: "find-skills", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
    try "# Skill".write(to: skillDirectory.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)

    try "{invalid config".write(to: configDirectory.appending(path: "opencode.json"), atomically: true, encoding: .utf8)

    let paths = OpenCodePaths(
        homeDirectory: tempRoot,
        configDirectory: configDirectory,
        dataDirectory: tempRoot.appending(path: ".local/share/opencode", directoryHint: .isDirectory),
        skillsDirectory: skillsDirectory
    )
    let loader = OpenCodeConfigLoader(paths: paths)

    let skills = try loader.loadInstalledSkills()

    #expect(skills.map(\.name) == ["find-skills"])
}
