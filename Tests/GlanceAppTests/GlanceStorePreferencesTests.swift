import Foundation
import Testing
import GlanceCore
@testable import GlanceApp

@Test
@MainActor
func glanceStoreLoadsPersistedPolicyAndWindow() {
    let policy = RankingPolicy(halfLifeDays: 14, staleAfterDays: 10, removalAfterDays: 20, minimumUsageToKeep: 2, neverUsedCountsAsStale: false, refreshIntervalSeconds: 120)
    let store = GlanceStore(
        sourceRegistry: TestSourceRegistry(),
        selectionStore: InMemorySelectionStore(selectedSourceID: GlanceSources.default.id),
        policyStore: InMemoryPolicyStore(policy: policy),
        windowSelectionStore: InMemoryWindowSelectionStore(rawValue: RollingWindow.day14.rawValue),
        startRefreshLoop: false
    )

    #expect(store.policy == policy)
    #expect(store.selectedWindow == RollingWindow.day14)
}

@Test
@MainActor
func glanceStorePersistsPolicyAndWindowChanges() {
    let selectionStore = InMemorySelectionStore(selectedSourceID: GlanceSources.default.id)
    let policyStore = InMemoryPolicyStore(policy: nil)
    let windowStore = InMemoryWindowSelectionStore(rawValue: nil)
    let store = GlanceStore(
        sourceRegistry: TestSourceRegistry(),
        selectionStore: selectionStore,
        policyStore: policyStore,
        windowSelectionStore: windowStore,
        startRefreshLoop: false
    )

    store.setSelectedWindow(RollingWindow.day14)
    store.updatePolicy { policy in
        var updated = policy
        updated.refreshIntervalSeconds = 90
        updated.staleAfterDays = 9
        updated.removalAfterDays = 18
        return updated
    }

    #expect(windowStore.savedRawValue == RollingWindow.day14.rawValue)
    #expect(policyStore.savedPolicy?.refreshIntervalSeconds == 90)
    #expect(policyStore.savedPolicy?.staleAfterDays == 9)
    #expect(policyStore.savedPolicy?.removalAfterDays == 18)
}

@Test
@MainActor
func glanceStoreSanitizesPersistedRefreshIntervalToOneMinuteMinimum() {
    let policy = RankingPolicy(refreshIntervalSeconds: 5)
    let store = GlanceStore(
        sourceRegistry: TestSourceRegistry(),
        selectionStore: InMemorySelectionStore(selectedSourceID: GlanceSources.default.id),
        policyStore: InMemoryPolicyStore(policy: policy),
        startRefreshLoop: false
    )

    #expect(store.policy.refreshIntervalSeconds == 60)
}

@Test
func glanceAppMetadataPrefersShortVersionForDisplay() {
    let metadata = GlanceAppMetadata(infoDictionary: [
        "CFBundleShortVersionString": "1.2.3",
        "CFBundleVersion": "45",
    ])

    #expect(metadata.versionDescription == "1.2.3")
    #expect(metadata.versionLine == "Version 1.2.3")
}

@Test
func glanceAppMetadataFallsBackToSingleVersionValueWhenShortVersionIsMissing() {
    let metadata = GlanceAppMetadata(infoDictionary: [
        "CFBundleVersion": "45",
    ])

    #expect(metadata.versionDescription == "45")
}

@Test
func glanceAppMetadataFallsBackToDebugWhenVersionInfoIsUnavailable() {
    let metadata = GlanceAppMetadata(infoDictionary: [:])

    #expect(metadata.versionDescription == "debug")
    #expect(metadata.versionLine == "Version debug")
}

private final class InMemoryPolicyStore: RankingPolicyStoring {
    private(set) var savedPolicy: RankingPolicy?

    init(policy: RankingPolicy?) {
        self.savedPolicy = policy
    }

    func loadPolicy() -> RankingPolicy? {
        savedPolicy
    }

    func savePolicy(_ policy: RankingPolicy) {
        savedPolicy = policy
    }
}

private final class InMemorySelectionStore: SourceSelectionStoring {
    private(set) var savedSelectedSourceID: String?

    init(selectedSourceID: String?) {
        self.savedSelectedSourceID = selectedSourceID
    }

    func loadSelectedSourceID() -> String? {
        savedSelectedSourceID
    }

    func saveSelectedSourceID(_ id: String?) {
        savedSelectedSourceID = id
    }
}

private final class InMemoryWindowSelectionStore: WindowSelectionStoring {
    private(set) var savedRawValue: Int?

    init(rawValue: Int?) {
        self.savedRawValue = rawValue
    }

    func loadSelectedWindowRawValue() -> Int? {
        savedRawValue
    }

    func saveSelectedWindowRawValue(_ rawValue: Int) {
        savedRawValue = rawValue
    }
}

private struct TestSourceRegistry: GlanceSourceResolving {
    var availableSources: [GlanceSource] {
        [GlanceSources.default]
    }

    func makeRepository(for source: GlanceSource) -> any CapabilityRepository {
        StubCapabilityRepository(capabilities: [])
    }

    func settingsPaths(for source: GlanceSource) -> [String] {
        []
    }

    func diagnostics(for source: GlanceSource) -> GlanceSourceDiagnostics {
        GlanceSourceDiagnostics(readiness: .ready, supportsRollingWindows: false, artifacts: [], summary: "Ready")
    }

    func userFacingErrorMessage(for source: GlanceSource, error: Error) -> String {
        error.localizedDescription
    }
}

private struct StubCapabilityRepository: CapabilityRepository {
    let capabilities: [CapabilityUsage]

    func loadCapabilities() async throws -> [CapabilityUsage] {
        capabilities
    }
}
