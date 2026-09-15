import Foundation
import Testing
import GlanceCore
import GlanceDevin
@testable import GlanceApp

@Test
func devinSourceIsSeparateFromOtherAgentsAndAdvertisesInventoryOnly() {
    let paths = DevinPaths(homeDirectory: URL(fileURLWithPath: "/nonexistent-glance-devin-test"))
    let registry = LiveGlanceSourceRegistry(devinPaths: paths)
    #expect(registry.availableSources.contains(GlanceSources.devinCLILocal))
    #expect(Set(registry.availableSources.map(\.id)).count == registry.availableSources.count)
    #expect(registry.makeRepository(for: GlanceSources.devinCLILocal) is DevinInventoryRepository)
    let diagnostics = registry.diagnostics(for: GlanceSources.devinCLILocal)
    #expect(diagnostics.usageSupport == .inventoryOnly)
    #expect(!diagnostics.supportsRollingWindows)
    #expect(diagnostics.readiness == .needsSetup)
    #expect(registry.settingsPaths(for: GlanceSources.devinCLILocal).count == 3)
}

@Test
func inventorySupportRoundTripsAndOlderDiagnosticsStillDecode() throws {
    let old = Data(#"{"readiness":"ready","supportsRollingWindows":true,"artifacts":[],"summary":"Ready"}"#.utf8)
    let decoded = try JSONDecoder().decode(GlanceSourceDiagnostics.self, from: old)
    #expect(decoded.usageSupport == .observations)
    #expect(decoded.statusLabel == "Ready")
    let inventory = GlanceSourceDiagnostics(readiness: .ready, supportsRollingWindows: false,
        artifacts: [], summary: "Definitions only", usageSupport: .inventoryOnly)
    #expect(inventory.statusLabel == "Inventory only")
    #expect(try JSONDecoder().decode(GlanceSourceDiagnostics.self, from: JSONEncoder().encode(inventory)) == inventory)
}

@Test
@MainActor
func devinInventoryLoadsWithoutUsageWindowsOrCleanupRecommendations() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("glance-devin-store-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = DevinPaths(homeDirectory: root)
    let definition = paths.skillDirectories[0].appendingPathComponent("review")
    try FileManager.default.createDirectory(at: definition, withIntermediateDirectories: true)
    try "# Synthetic skill".write(to: definition.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    let preferences = DevinTestPreferences()
    let store = GlanceStore(sourceRegistry: LiveGlanceSourceRegistry(devinPaths: paths), selectionStore: preferences,
        policyStore: preferences, windowSelectionStore: preferences, startRefreshLoop: false)
    await store.refresh()
    #expect(store.isInventoryOnly)
    #expect(store.currentDiagnostics.statusLabel == "Inventory only")
    #expect(store.activeSnapshot.skills.map(\.id.name) == ["review"])
    #expect(Set(store.windowedSnapshots.keys) == [.allTime])
    #expect(store.effectiveWindowLabel == "Inventory")
    #expect(store.errorMessage == nil)
    #expect(store.noticeMessage?.contains("usage statistics are not available") == true)
    #expect(store.usageEvidence.completeness == .unavailable)
    #expect(store.visibleStale.isEmpty)
    #expect(store.visibleRemovalCandidates.isEmpty)
    store.setSelectedWindow(.day1)
    #expect(store.activeSnapshot.skills.map(\.id.name) == ["review"])
    #expect(store.effectiveWindowLabel == "Inventory")
}

private final class DevinTestPreferences: SourceSelectionStoring, RankingPolicyStoring, WindowSelectionStoring {
    func loadSelectedSourceID() -> String? { GlanceSources.devinCLILocal.id }
    func saveSelectedSourceID(_ id: String?) {}
    func loadPolicy() -> RankingPolicy? { .default }
    func savePolicy(_ policy: RankingPolicy) {}
    func loadSelectedWindowRawValue() -> Int? { 7 }
    func saveSelectedWindowRawValue(_ rawValue: Int) {}
}
