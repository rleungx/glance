import Foundation
import Testing
import GlanceCore
import GlanceAntigravity
import GlanceDevin
@testable import GlanceApp

@Test
func antigravityReplacesGeminiWhileDevinRemainsAvailable() {
    let paths = AntigravityPaths(homeDirectory: URL(fileURLWithPath: "/nonexistent-glance-antigravity-test"))
    let registry = LiveGlanceSourceRegistry(antigravityPaths: paths)
    #expect(registry.availableSources.contains(GlanceSources.antigravityLocal))
    #expect(registry.availableSources.contains(GlanceSources.devinCLILocal))
    #expect(!registry.availableSources.contains { $0.id == "gemini-local" })
    #expect(Set(registry.availableSources.map(\.id)).count == registry.availableSources.count)
    #expect(registry.makeRepository(for: GlanceSources.antigravityLocal) is AntigravityInventoryRepository)
    #expect(registry.makeRepository(for: GlanceSources.devinCLILocal) is DevinInventoryRepository)
    let diagnostics = registry.diagnostics(for: GlanceSources.antigravityLocal)
    #expect(diagnostics.usageSupport == .inventoryOnly)
    #expect(!diagnostics.supportsRollingWindows)
    #expect(diagnostics.readiness == .needsSetup)
    #expect(diagnostics.artifacts.map(\.label) == ["Application skills", "IDE skills"])
    #expect(registry.settingsPaths(for: GlanceSources.antigravityLocal).count == 2)
    #expect(GlanceSources.antigravityLocal.logoAssetName == nil)
}

@Test
@MainActor
func antigravityInventoryLoadsWithoutUsageWindowsOrCleanupRecommendations() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("glance-antigravity-store-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = AntigravityPaths(homeDirectory: root)
    let definition = paths.ideSkillsDirectory.appendingPathComponent("review")
    try FileManager.default.createDirectory(at: definition, withIntermediateDirectories: true)
    try "# Synthetic skill".write(to: definition.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    let preferences = AntigravityTestPreferences()
    let store = GlanceStore(sourceRegistry: LiveGlanceSourceRegistry(antigravityPaths: paths), selectionStore: preferences,
        policyStore: preferences, windowSelectionStore: preferences, startRefreshLoop: false)
    await store.refresh()
    #expect(store.isInventoryOnly)
    #expect(store.currentDiagnostics.statusLabel == "Inventory only")
    #expect(store.activeSnapshot.sourceID == GlanceSources.antigravityLocal.id)
    #expect(store.activeSnapshot.skills.map(\.id.name) == ["review"])
    #expect(Set(store.windowedSnapshots.keys) == [.allTime])
    #expect(store.effectiveWindowLabel == "Inventory")
    #expect(store.errorMessage == nil)
    #expect(store.noticeMessage?.contains(AntigravityInventoryRepository.scopeNotice) == true)
    #expect(store.usageEvidence.completeness == .unavailable)
    #expect(store.visibleStale.isEmpty)
    #expect(store.visibleRemovalCandidates.isEmpty)
    store.setSelectedWindow(.day1)
    #expect(store.activeSnapshot.skills.map(\.id.name) == ["review"])
    #expect(store.effectiveWindowLabel == "Inventory")
}

@Test
@MainActor
func antigravityMigratesOnlyTheRetiredGeminiSelection() {
    for id in ["gemini-local", GlanceSources.antigravityLocal.id, GlanceSources.devinCLILocal.id, GlanceSources.claudeCodeLocal.id] {
        let preferences = AntigravityTestPreferences(id: id)
        let store = GlanceStore(selectionStore: preferences, policyStore: preferences,
                                windowSelectionStore: preferences, startRefreshLoop: false)
        let expected = id == "gemini-local" ? GlanceSources.antigravityLocal.id : id
        #expect(store.currentSource.id == expected)
        #expect(preferences.id == expected)
        #expect(preferences.saveCount == (id == "gemini-local" ? 1 : 0))
        #expect(store.snapshot.skills.isEmpty)
        #expect(store.usageEvidence.completeness == .unavailable)
    }
}

@Test
@MainActor
func antigravityBrokenRootSurfacesIncompleteInventory() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("glance-antigravity-broken-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = AntigravityPaths(homeDirectory: root)
    try FileManager.default.createDirectory(at: paths.applicationSkillsDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: paths.applicationSkillsDirectory,
                                               withDestinationURL: root.appendingPathComponent("missing"))
    let preferences = AntigravityTestPreferences()
    let registry = LiveGlanceSourceRegistry(antigravityPaths: paths)
    #expect(registry.diagnostics(for: GlanceSources.antigravityLocal).readiness == .ready)
    let store = GlanceStore(sourceRegistry: registry, selectionStore: preferences, policyStore: preferences,
                            windowSelectionStore: preferences, startRefreshLoop: false)
    await store.refresh()
    #expect(store.errorMessage == nil)
    #expect(store.usageEvidence.skippedFiles == 1)
    #expect(store.usageEvidence.completeness == .unavailable)
    #expect(store.noticeMessage?.contains("inventory may be incomplete") == true)
    #expect(store.activeSnapshot.skills.isEmpty)
    #expect(store.visibleRemovalCandidates.isEmpty)
}

private final class AntigravityTestPreferences: SourceSelectionStoring, RankingPolicyStoring, WindowSelectionStoring {
    var id: String?
    var saveCount = 0
    init(id: String = GlanceSources.antigravityLocal.id) { self.id = id }
    func loadSelectedSourceID() -> String? { id }
    func saveSelectedSourceID(_ id: String?) { self.id = id; saveCount += 1 }
    func loadPolicy() -> RankingPolicy? { .default }
    func savePolicy(_ policy: RankingPolicy) {}
    func loadSelectedWindowRawValue() -> Int? { 7 }
    func saveSelectedWindowRawValue(_ rawValue: Int) {}
}
