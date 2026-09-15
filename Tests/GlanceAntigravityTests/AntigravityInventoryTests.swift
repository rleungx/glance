import Foundation
import Testing
import GlanceCore
@testable import GlanceAntigravity

@Test
func antigravityPathsUseDocumentedApplicationAndIDERoots() {
    let paths = AntigravityPaths(homeDirectory: URL(fileURLWithPath: "/example/home", isDirectory: true))
    #expect(paths.skillDirectories.map(\.path) == [
        "/example/home/.gemini/config/skills",
        "/example/home/.gemini/antigravity/skills",
    ])
}

@Test
func antigravityMissingRootsAreAnEmptyInventoryNotAnError() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let inventory = AntigravityInventoryLoader(paths: AntigravityPaths(homeDirectory: root)).loadInventory()
    #expect(inventory.skills.isEmpty)
    #expect(inventory.unreadableLocations == 0)
    #expect(!FileManager.default.fileExists(atPath: root.path))
}

@Test
func antigravityDiscoversDefinitionsWithoutReadingOrExecutingTheirContent() throws {
    let fixture = try AntigravityFixture()
    defer { fixture.remove() }
    let file = try fixture.skill("review", in: 0)
    let body = "---\nname: Friendly display name\n---\n!`touch should-not-run`"
    try body.write(to: file, atomically: true, encoding: .utf8)
    _ = try fixture.skill("ide", in: 1)
    // Definitions are inventoried, not YAML-validated or decoded as prompts.
    let binary = try fixture.skill("binary-body", in: 0)
    try Data([0xff, 0xfe, 0x00]).write(to: binary)
    let loader = AntigravityInventoryLoader(paths: fixture.paths)
    let inventory = loader.loadInventory()
    #expect(inventory.skills.map(\.name) == ["binary-body", "ide", "review"])
    #expect(inventory.skills.first { $0.name == "review" }?.file == file.resolvingSymlinksInPath())
    #expect(inventory.unreadableLocations == 0)
    #expect(try String(contentsOf: file, encoding: .utf8) == body)
}

@Test
func antigravityDoesNotInferProjectsPluginsOrNestedReferenceSkills() throws {
    let fixture = try AntigravityFixture()
    defer { fixture.remove() }
    _ = try fixture.skill("outer", in: 0)
    for directory in [
        fixture.paths.skillDirectories[0].appendingPathComponent("outer/references/example"),
        fixture.paths.skillDirectories[0].appendingPathComponent("group/nested"),
        fixture.root.appendingPathComponent("project/.agents/skills/project-only"),
        fixture.root.appendingPathComponent("project/.agent/skills/legacy-project"),
        fixture.root.appendingPathComponent(".gemini/skills/gemini-only"),
        fixture.root.appendingPathComponent(".agents/skills/shared-only"),
        fixture.root.appendingPathComponent(".gemini/config/plugins/example/skills/plugin-only"),
        fixture.root.appendingPathComponent(".gemini/antigravity-cli/skills/cli-only"),
    ] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "# Example".write(to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }
    let inventory = AntigravityInventoryLoader(paths: fixture.paths).loadInventory()
    #expect(inventory.skills.map(\.name) == ["outer"])
    #expect(inventory.unreadableLocations == 0)
}

@Test
func antigravitySameNameDefinitionsRemainDistinctByLocation() throws {
    let fixture = try AntigravityFixture()
    defer { fixture.remove() }
    _ = try fixture.skill("review", in: 0)
    _ = try fixture.skill("review", in: 1)
    let skills = AntigravityInventoryLoader(paths: fixture.paths).loadInventory().skills
    #expect(skills.count == 2)
    #expect(Set(skills.map(\.id)).count == 2)
    #expect(skills.allSatisfy { $0.id.namespace == $0.file.path })
}

@Test
func antigravityDeduplicatesSymlinkedRootsAndHandlesBrokenLinks() throws {
    let fixture = try AntigravityFixture()
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
    let inventory = AntigravityInventoryLoader(paths: fixture.paths).loadInventory()
    #expect(inventory.skills.map(\.name) == ["review"])
    #expect(inventory.unreadableLocations == 2)
}

@Test
func antigravityInvalidRootsAndNonFileDefinitionsProduceWarnings() async throws {
    let fixture = try AntigravityFixture()
    defer { fixture.remove() }
    let root = fixture.paths.skillDirectories[0]
    try FileManager.default.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "not a directory".write(to: root, atomically: true, encoding: .utf8)
    try FileManager.default.createDirectory(at: fixture.paths.skillDirectories[1].appendingPathComponent("invalid/SKILL.md"),
                                            withIntermediateDirectories: true)
    _ = try fixture.skill("readable", in: 1)
    let inventory = AntigravityInventoryLoader(paths: fixture.paths).loadInventory()
    #expect(inventory.skills.map(\.name) == ["readable"])
    #expect(inventory.unreadableLocations == 2)
    let result = try await AntigravityInventoryRepository(paths: fixture.paths).loadUsage(windows: [.day7], now: .now)
    #expect(result.warnings.contains { $0.contains("2 skill locations") })
    #expect(result.evidence.skippedFiles == 2)
    #expect(result.evidence.completeness == .unavailable)
}

@Test
func antigravityInventoryNeverClaimsUsageOrCleanupEligibility() async throws {
    let fixture = try AntigravityFixture()
    defer { fixture.remove() }
    _ = try fixture.skill("review", in: 0)
    let repository = AntigravityInventoryRepository(paths: fixture.paths)
    let result = try await repository.loadUsage(windows: [.day1, .day7, .allTime], now: .now)
    #expect(Set(result.windows.keys) == [.allTime])
    #expect(result.evidence.completeness == .unavailable)
    #expect(result.evidence.filesRead == 0)
    #expect(result.evidence.observedFrom == nil)
    #expect(result.evidence.observedThrough == nil)
    #expect(result.warnings == [AntigravityInventoryRepository.scopeNotice])
    let capabilities = try #require(result.windows[.allTime])
    #expect(capabilities.count == 1)
    #expect(capabilities.allSatisfy { !$0.installedButUnused && !$0.hasOutcomeData && $0.lastUsedAt == nil })
    let snapshot = CapabilityRanker.buildSnapshot(from: capabilities, evidence: result.evidence)
    #expect(snapshot.stale.isEmpty)
    #expect(snapshot.removalCandidates.isEmpty)
    #expect(try await repository.loadCapabilities() == capabilities)
}

@Test
func antigravityRefreshReflectsDefinitionChangesWithoutReadingGeminiHistory() async throws {
    let fixture = try AntigravityFixture()
    defer { fixture.remove() }
    let file = try fixture.skill("review", in: 0)
    let repository = AntigravityInventoryRepository(paths: fixture.paths)
    #expect(try await repository.loadCapabilities().map(\.id.name) == ["review"])
    try FileManager.default.removeItem(at: file)
    _ = try fixture.skill("deploy", in: 1)
    let history = fixture.root.appendingPathComponent(".gemini/tmp/project/chats")
    try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
    try #"{"messages":[{"toolCalls":[{"name":"activate_skill","args":{"name":"gemini-only"}}]}]}"#
        .write(to: history.appendingPathComponent("session-example.json"), atomically: true, encoding: .utf8)
    let result = try await repository.loadUsage(windows: [.day7], now: .now)
    #expect(result.windows[.allTime]?.map(\.id.name) == ["deploy"])
    #expect(result.evidence.filesRead == 0)
    #expect(result.evidence.sources == fixture.paths.skillDirectories.map(\.path))
}

@Test
func antigravityBrokenRootAndDirectorySymlinkAreNotMistakenForEmptyInventory() throws {
    let fixture = try AntigravityFixture()
    defer { fixture.remove() }
    let appRoot = fixture.paths.skillDirectories[0]
    try FileManager.default.createDirectory(at: appRoot.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: appRoot, withDestinationURL: fixture.root.appendingPathComponent("absent-root"))
    let file = try fixture.skill("review", in: 1)
    let alias = fixture.paths.skillDirectories[1].appendingPathComponent("alias")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: file.deletingLastPathComponent())
    let inventory = AntigravityInventoryLoader(paths: fixture.paths).loadInventory()
    #expect(inventory.unreadableLocations == 1)
    #expect(inventory.skills.map(\.name) == ["alias", "review"])
    #expect(Set(inventory.skills.map(\.file)).count == 1)
    #expect(Set(inventory.skills.map(\.id)).count == 2)
}

private struct AntigravityFixture {
    let root: URL
    var paths: AntigravityPaths { AntigravityPaths(homeDirectory: root) }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("glance-antigravity-test-" + UUID().uuidString)
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
