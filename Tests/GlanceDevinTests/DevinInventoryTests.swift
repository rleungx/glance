import Foundation
import Testing
import GlanceCore
@testable import GlanceDevin

@Test
func devinPathsUseDocumentedStableGlobalRoots() {
    let home = URL(fileURLWithPath: "/example/home", isDirectory: true)
    let paths = DevinPaths(homeDirectory: home)
    #expect(paths.skillDirectories.map(\.path) == [
        "/example/home/.config/devin/skills",
        "/example/home/.agents/skills",
        "/example/home/.codeium/windsurf/skills",
    ])
    let override = DevinPaths(homeDirectory: home, environment: ["XDG_CONFIG_HOME": "/custom/config"])
    #expect(override.skillDirectories.first?.path == "/custom/config/devin/skills")
    #expect(DevinPaths(homeDirectory: home, environment: ["XDG_CONFIG_HOME": "relative"]).skillDirectories == paths.skillDirectories)
    #expect(DevinPaths(homeDirectory: home, environment: ["XDG_CONFIG_HOME": ""]).skillDirectories == paths.skillDirectories)
}

@Test
func devinMissingRootsAreAnEmptyInventoryNotAnError() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let inventory = DevinInventoryLoader(paths: DevinPaths(homeDirectory: root)).loadInventory()
    #expect(inventory.skills.isEmpty)
    #expect(inventory.unreadableLocations == 0)
    #expect(!FileManager.default.fileExists(atPath: root.path))
}

@Test
func devinDiscoversDefinitionsWithoutReadingOrExecutingTheirContent() throws {
    let fixture = try DevinFixture()
    defer { fixture.remove() }
    let file = try fixture.skill("review", in: 0)
    let body = "---\nname: Friendly display name\n---\n!`touch should-not-run`"
    try body.write(to: file, atomically: true, encoding: .utf8)
    _ = try fixture.skill("shared", in: 1)
    _ = try fixture.skill("legacy", in: 2)
    // Definitions are inventoried, not YAML-validated or decoded as prompts.
    let binary = try fixture.skill("binary-body", in: 0)
    try Data([0xff, 0xfe, 0x00]).write(to: binary)
    let loader = DevinInventoryLoader(paths: fixture.paths)
    let inventory = loader.loadInventory()
    #expect(inventory.skills.map(\.name) == ["binary-body", "legacy", "review", "shared"])
    #expect(inventory.skills.first { $0.name == "review" }?.file == file.resolvingSymlinksInPath())
    #expect(inventory.unreadableLocations == 0)
    #expect(try String(contentsOf: file, encoding: .utf8) == body)
}

@Test
func devinDoesNotInferProjectsPluginsOrNestedReferenceSkills() throws {
    let fixture = try DevinFixture()
    defer { fixture.remove() }
    _ = try fixture.skill("outer", in: 0)
    for directory in [
        fixture.paths.skillDirectories[0].appendingPathComponent("outer/references/example"),
        fixture.paths.skillDirectories[0].appendingPathComponent("group/nested"),
        fixture.root.appendingPathComponent("project/.devin/skills/project-only"),
        fixture.root.appendingPathComponent(".claude/plugins/example/skills/plugin-only"),
        fixture.root.appendingPathComponent(".codeium/windsurf-next/skills/other-channel"),
    ] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "# Example".write(to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }
    let inventory = DevinInventoryLoader(paths: fixture.paths).loadInventory()
    #expect(inventory.skills.map(\.name) == ["outer"])
    #expect(inventory.unreadableLocations == 0)
}

@Test
func devinSameNameDefinitionsRemainDistinctByLocation() throws {
    let fixture = try DevinFixture()
    defer { fixture.remove() }
    _ = try fixture.skill("review", in: 0)
    _ = try fixture.skill("review", in: 1)
    let skills = DevinInventoryLoader(paths: fixture.paths).loadInventory().skills
    #expect(skills.count == 2)
    #expect(Set(skills.map(\.id)).count == 2)
    #expect(skills.allSatisfy { $0.id.namespace == $0.file.path })
}

@Test
func devinDeduplicatesSymlinkedRootsAndHandlesBrokenLinks() throws {
    let fixture = try DevinFixture()
    defer { fixture.remove() }
    _ = try fixture.skill("review", in: 0)
    let shared = fixture.paths.skillDirectories[1]
    try FileManager.default.createDirectory(at: shared.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: shared, withDestinationURL: fixture.paths.skillDirectories[0])
    let broken = fixture.paths.skillDirectories[0].appendingPathComponent("broken")
    try FileManager.default.createSymbolicLink(at: broken, withDestinationURL: fixture.root.appendingPathComponent("absent"))
    let definition = fixture.paths.skillDirectories[0].appendingPathComponent("broken-definition")
    try FileManager.default.createDirectory(at: definition, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: definition.appendingPathComponent("SKILL.md"),
                                              withDestinationURL: fixture.root.appendingPathComponent("absent-file"))
    let inventory = DevinInventoryLoader(paths: fixture.paths).loadInventory()
    #expect(inventory.skills.map(\.name) == ["review"])
    #expect(inventory.unreadableLocations == 2)
}

@Test
func devinInvalidRootsAndNonFileDefinitionsProduceWarnings() async throws {
    let fixture = try DevinFixture()
    defer { fixture.remove() }
    let root = fixture.paths.skillDirectories[0]
    try FileManager.default.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "not a directory".write(to: root, atomically: true, encoding: .utf8)
    try FileManager.default.createDirectory(at: fixture.paths.skillDirectories[1].appendingPathComponent("invalid/SKILL.md"),
                                            withIntermediateDirectories: true)
    _ = try fixture.skill("readable", in: 2)
    let inventory = DevinInventoryLoader(paths: fixture.paths).loadInventory()
    #expect(inventory.skills.map(\.name) == ["readable"])
    #expect(inventory.unreadableLocations == 2)
    let result = try await DevinInventoryRepository(paths: fixture.paths).loadUsage(windows: [.day7], now: .now)
    #expect(result.warnings.contains { $0.contains("2 skill locations") })
    #expect(result.evidence.skippedFiles == 2)
    #expect(result.evidence.completeness == .unavailable)
}

@Test
func devinInventoryNeverClaimsUsageOrCleanupEligibility() async throws {
    let fixture = try DevinFixture()
    defer { fixture.remove() }
    _ = try fixture.skill("review", in: 0)
    let repository = DevinInventoryRepository(paths: fixture.paths)
    let result = try await repository.loadUsage(windows: [.day1, .day7, .allTime], now: .now)
    #expect(Set(result.windows.keys) == [.allTime])
    #expect(result.evidence.completeness == .unavailable)
    #expect(result.evidence.filesRead == 0)
    #expect(result.evidence.observedFrom == nil)
    #expect(result.evidence.observedThrough == nil)
    #expect(result.warnings == [DevinInventoryRepository.scopeNotice])
    let capabilities = try #require(result.windows[.allTime])
    #expect(capabilities.count == 1)
    #expect(capabilities.allSatisfy { !$0.installedButUnused && !$0.hasOutcomeData && $0.lastUsedAt == nil })
    let snapshot = CapabilityRanker.buildSnapshot(from: capabilities, evidence: result.evidence)
    #expect(snapshot.stale.isEmpty)
    #expect(snapshot.removalCandidates.isEmpty)
    #expect(try await repository.loadCapabilities() == capabilities)
}

private struct DevinFixture {
    let root: URL
    var paths: DevinPaths { DevinPaths(homeDirectory: root) }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("glance-devin-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func skill(_ name: String, in index: Int) throws -> URL {
        let directory = paths.skillDirectories[index].appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("SKILL.md")
        try "# Synthetic skill".write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}
