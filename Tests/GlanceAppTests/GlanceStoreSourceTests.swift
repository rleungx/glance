import Foundation
import Testing
import GlanceCore
import GlanceOpenCode
@testable import GlanceApp

@Test
@MainActor
func glanceStoreFallsBackToDefaultSourceWhenSelectionIsUnknown() {
    let selectionStore = InMemorySelectionStore(selectedSourceID: "missing")
    let store = GlanceStore(
        sourceRegistry: TestSourceRegistry(),
        selectionStore: selectionStore,
        startRefreshLoop: false
    )

    #expect(store.currentSource == GlanceSources.default)
    #expect(store.currentSourcePaths == ["~/OpenCode/db.sqlite"])
}

@Test
@MainActor
func glanceStoreSwitchesSourceAndPersistsSelection() async {
    let sourceA = GlanceSource(id: "opencode-local", displayName: "OpenCode", detail: "Current local source")
    let sourceB = GlanceSource(id: "future-source", displayName: "Future", detail: "Preview source")
    let selectionStore = InMemorySelectionStore(selectedSourceID: sourceA.id)
    let registry = TestSourceRegistry(sources: [sourceA, sourceB])
    let store = GlanceStore(
        sourceRegistry: registry,
        selectionStore: selectionStore,
        startRefreshLoop: false
    )

    store.selectSource(sourceB)
    await store.refresh()

    #expect(store.currentSource == sourceB)
    #expect(selectionStore.savedSelectedSourceID == sourceB.id)
    #expect(store.currentSourcePaths == ["~/Future/source.json"])
    #expect(store.snapshot.skills.count == 1)
}

@Test
@MainActor
func glanceStoreDropsStaleRefreshResultsAfterSourceSwitch() async {
    let sourceA = GlanceSource(id: "opencode-local", displayName: "OpenCode", detail: "Current source")
    let sourceB = GlanceSource(id: "future-source", displayName: "Future", detail: "Preview source")
    let selectionStore = InMemorySelectionStore(selectedSourceID: sourceA.id)
    let registry = BlockingTestSourceRegistry(sourceA: sourceA, sourceB: sourceB)
    let store = GlanceStore(
        sourceRegistry: registry,
        selectionStore: selectionStore,
        startRefreshLoop: false
    )

    let oldRefreshTask = Task {
        await store.refresh()
    }

    await registry.blockingRepository.waitUntilStarted()

    store.selectSource(sourceB)
    await store.refresh()
    await registry.blockingRepository.release()
    await oldRefreshTask.value

    #expect(store.currentSource == sourceB)
    #expect(store.snapshot.skills.map(\.id.name) == ["future-skill"])
}

@Test
@MainActor
func glanceStoreClearsRenderedStateWhileSwitchingBetweenReadySources() async throws {
    let sourceA = GlanceSource(id: "opencode-local", displayName: "OpenCode", detail: "Current source")
    let sourceB = GlanceSource(id: "claude-source", displayName: "Claude", detail: "Claude source")
    let selectionStore = InMemorySelectionStore(selectedSourceID: sourceA.id)
    let registry = ReadySourceSwitchingRegistry(sourceA: sourceA, sourceB: sourceB)
    let store = GlanceStore(
        sourceRegistry: registry,
        selectionStore: selectionStore,
        startRefreshLoop: false
    )

    await store.refresh()

    #expect(store.lastRefreshAt != nil)
    #expect(store.snapshot.skills.map(\.id.name) == ["old-source-skill"])
    #expect(store.noticeMessage == "Old warning")

    store.selectSource(sourceB)
    let completionTask = Task {
        await store.refresh()
    }

    await registry.claudeRepository.waitUntilStarted()

    #expect(store.currentSource == sourceB)
    #expect(store.snapshot.allCapabilities.isEmpty)
    #expect(store.noticeMessage == nil)
    #expect(store.lastRefreshAt == nil)

    await registry.claudeRepository.release()
    await completionTask.value

    #expect(store.snapshot.skills.map(\.id.name) == ["claude-skill"])
    #expect(store.noticeMessage == "Claude warning")
    #expect(store.lastRefreshAt != nil)
}

@Test
@MainActor
func glanceStoreCoalescesConcurrentRefreshRequests() async {
    let selectionStore = InMemorySelectionStore(selectedSourceID: GlanceSources.default.id)
    let repository = CountingBlockingCapabilityRepository(capabilities: [CapabilityUsage(id: CapabilityID(kind: .skill, name: "demo"), usageCount: 1)])
    let registry = SingleRepositorySourceRegistry(repository: repository)
    let store = GlanceStore(
        sourceRegistry: registry,
        selectionStore: selectionStore,
        startRefreshLoop: false
    )

    let firstTask = Task { await store.refresh() }
    await repository.waitUntilStarted()
    let secondTask = Task { await store.refresh() }
    await repository.release()
    await firstTask.value
    await secondTask.value

    let loadCount = await repository.loadCount
    #expect(loadCount == 1)
}

@Test
@MainActor
func glanceStoreRunsFollowUpRefreshWhenPolicyChangesDuringInFlightWindowedRefresh() async {
    let selectionStore = InMemorySelectionStore(selectedSourceID: GlanceSources.default.id)
    let windowStore = InMemoryWindowSelectionStore(rawValue: RollingWindow.day7.rawValue)
    let policyStore = InMemoryPolicyStore(policy: RankingPolicy.default)
    let repository = CountingBlockingWindowedCapabilityRepository(capabilities: [CapabilityUsage(id: CapabilityID(kind: .skill, name: "demo"), usageCount: 1)])
    let registry = SingleWindowedRepositorySourceRegistry(repository: repository)
    let store = GlanceStore(
        sourceRegistry: registry,
        selectionStore: selectionStore,
        policyStore: policyStore,
        windowSelectionStore: windowStore,
        startRefreshLoop: false
    )

    let firstRefreshTask = Task {
        await store.refresh()
    }
    await repository.waitUntilStarted(count: 1)

    store.updatePolicy { policy in
        var updated = policy
        updated.removalAfterDays = 90
        return updated
    }

    await repository.releaseNext()
    await repository.waitUntilStarted(count: 2)
    await repository.releaseNext()
    await firstRefreshTask.value

    let requestedWindows = await repository.requestedWindowsByLoad
    #expect(requestedWindows.count == 2)
    #expect(requestedWindows[0].contains(.day7))
    #expect(requestedWindows[0].contains(.allTime))
    #expect(requestedWindows[0].count == 2)
    #expect(requestedWindows[0].contains(.day90) == false)
    #expect(requestedWindows[1].contains(.day7))
    #expect(requestedWindows[1].contains(.allTime))
    #expect(requestedWindows[1].count == 2)
}

@Test
@MainActor
func glanceStoreRunsFollowUpRefreshWhenPolicyChangesWithoutCleanupWindowChange() async {
    let selectionStore = InMemorySelectionStore(selectedSourceID: GlanceSources.default.id)
    let windowStore = InMemoryWindowSelectionStore(rawValue: RollingWindow.day7.rawValue)
    let policyStore = InMemoryPolicyStore(policy: RankingPolicy.default)
    let repository = CountingBlockingWindowedCapabilityRepository(capabilities: [CapabilityUsage(id: CapabilityID(kind: .skill, name: "demo"), usageCount: 1)])
    let registry = SingleWindowedRepositorySourceRegistry(repository: repository)
    let store = GlanceStore(
        sourceRegistry: registry,
        selectionStore: selectionStore,
        policyStore: policyStore,
        windowSelectionStore: windowStore,
        startRefreshLoop: false
    )

    let firstRefreshTask = Task {
        await store.refresh()
    }
    await repository.waitUntilStarted(count: 1)

    store.updatePolicy { policy in
        var updated = policy
        updated.minimumUsageToKeep = 8
        return updated
    }

    await repository.releaseNext()
    await repository.waitUntilStarted(count: 2)
    await repository.releaseNext()
    await firstRefreshTask.value

    let requestedWindows = await repository.requestedWindowsByLoad
    #expect(requestedWindows.count == 2)
    #expect(requestedWindows[0] == requestedWindows[1])
    #expect(requestedWindows[0].contains(.day7))
    #expect(requestedWindows[0].contains(.allTime))
    #expect(requestedWindows[0].count == 2)
}

@Test
@MainActor
func glanceStoreRefreshesWhenSelectingMissingWindowedSnapshot() async {
    let selectionStore = InMemorySelectionStore(selectedSourceID: GlanceSources.default.id)
    let windowStore = InMemoryWindowSelectionStore(rawValue: RollingWindow.day7.rawValue)
    let repository = CountingBlockingWindowedCapabilityRepository(capabilities: [CapabilityUsage(id: CapabilityID(kind: .skill, name: "demo"), usageCount: 1)])
    let registry = SingleWindowedRepositorySourceRegistry(repository: repository)
    let store = GlanceStore(
        sourceRegistry: registry,
        selectionStore: selectionStore,
        windowSelectionStore: windowStore,
        startRefreshLoop: false
    )

    let firstRefreshTask = Task {
        await store.refresh()
    }
    await repository.waitUntilStarted(count: 1)
    await repository.releaseNext()
    await firstRefreshTask.value

    store.setSelectedWindow(.day14)
    await repository.waitUntilStarted(count: 2)
    await repository.releaseNext()

    let requestedWindows = await repository.requestedWindowsByLoad
    #expect(requestedWindows.count == 2)
    #expect(requestedWindows[0].contains(.day7))
    #expect(requestedWindows[1].contains(.day14))
    #expect(requestedWindows[1].contains(.allTime))
    #expect(requestedWindows[1].count == 2)
}

@Test
@MainActor
func glanceStoreRunsFollowUpRefreshWhenSelectingMissingWindowDuringInFlightRefresh() async {
    let selectionStore = InMemorySelectionStore(selectedSourceID: GlanceSources.default.id)
    let windowStore = InMemoryWindowSelectionStore(rawValue: RollingWindow.day7.rawValue)
    let repository = CountingBlockingWindowedCapabilityRepository(capabilities: [CapabilityUsage(id: CapabilityID(kind: .skill, name: "demo"), usageCount: 1)])
    let registry = SingleWindowedRepositorySourceRegistry(repository: repository)
    let store = GlanceStore(
        sourceRegistry: registry,
        selectionStore: selectionStore,
        windowSelectionStore: windowStore,
        startRefreshLoop: false
    )

    let firstRefreshTask = Task {
        await store.refresh()
    }
    await repository.waitUntilStarted(count: 1)

    store.setSelectedWindow(.day14)

    await repository.releaseNext()
    await repository.waitUntilStarted(count: 2)
    await repository.releaseNext()
    await firstRefreshTask.value

    let requestedWindows = await repository.requestedWindowsByLoad
    #expect(requestedWindows.count == 2)
    #expect(requestedWindows[0].contains(.day7))
    #expect(requestedWindows[0].contains(.allTime))
    #expect(requestedWindows[1].contains(.day14))
    #expect(requestedWindows[1].contains(.allTime))
}

@Test
@MainActor
func glanceStoreSkipsRefreshWhenSourceNeedsSetup() async {
    let selectionStore = InMemorySelectionStore(selectedSourceID: GlanceSources.default.id)
    let repository = CountingBlockingCapabilityRepository(capabilities: [CapabilityUsage(id: CapabilityID(kind: .skill, name: "demo"), usageCount: 1)])
    let diagnostics = GlanceSourceDiagnostics(readiness: .needsSetup, supportsRollingWindows: false, artifacts: [], summary: "Source needs setup")
    let registry = DiagnosticsSourceRegistry(repository: repository, diagnostics: diagnostics)
    let store = GlanceStore(
        sourceRegistry: registry,
        selectionStore: selectionStore,
        startRefreshLoop: false
    )

    await store.refresh()

    let loadCount = await repository.loadCount
    #expect(loadCount == 0)
    #expect(store.activeSnapshot.allCapabilities.isEmpty)
    #expect(store.errorMessage == "Source needs setup")
    #expect(store.effectiveWindowLabel == "All time")
}

@Test
@MainActor
func glanceStorePreservesRenderedStateWhenRefreshFindsSourceNeedsSetup() async throws {
    let selectionStore = InMemorySelectionStore(selectedSourceID: GlanceSources.default.id)
    let repository = StubCapabilityRepository(capabilities: [CapabilityUsage(id: CapabilityID(kind: .skill, name: "demo"), usageCount: 1)])
    let diagnostics = MutableDiagnosticsSourceRegistry(
        repository: repository,
        diagnostics: GlanceSourceDiagnostics(readiness: .ready, supportsRollingWindows: false, artifacts: [], summary: "Ready")
    )
    let store = GlanceStore(
        sourceRegistry: diagnostics,
        selectionStore: selectionStore,
        startRefreshLoop: false
    )

    await store.refresh()
    let previousRefreshAt = try #require(store.lastRefreshAt)
    #expect(store.snapshot.skills.map(\.id.name) == ["demo"])

    diagnostics.diagnostics = GlanceSourceDiagnostics(readiness: .needsSetup, supportsRollingWindows: false, artifacts: [], summary: "Source needs setup")
    await store.refresh()

    #expect(store.snapshot.skills.map(\.id.name) == ["demo"])
    #expect(store.lastRefreshAt == previousRefreshAt)
    #expect(store.errorMessage == "Source needs setup")
}

@Test
@MainActor
func glanceStoreRecoversAfterSourceBecomesReady() async {
    let selectionStore = InMemorySelectionStore(selectedSourceID: GlanceSources.default.id)
    let repository = StubCapabilityRepository(capabilities: [CapabilityUsage(id: CapabilityID(kind: .skill, name: "demo"), usageCount: 1)])
    let diagnostics = MutableDiagnosticsSourceRegistry(
        repository: repository,
        diagnostics: GlanceSourceDiagnostics(readiness: .needsSetup, supportsRollingWindows: false, artifacts: [], summary: "Source needs setup")
    )
    let store = GlanceStore(
        sourceRegistry: diagnostics,
        selectionStore: selectionStore,
        startRefreshLoop: false
    )

    await store.refresh()
    #expect(store.snapshot.allCapabilities.isEmpty)
    #expect(store.errorMessage == "Source needs setup")

    diagnostics.diagnostics = GlanceSourceDiagnostics(readiness: .ready, supportsRollingWindows: false, artifacts: [], summary: "Ready")
    await store.refresh()

    #expect(store.snapshot.skills.map(\.id.name) == ["demo"])
    #expect(store.errorMessage == nil)
}

@Test
@MainActor
func glanceStoreUsesSourceSpecificUserFacingErrorMessage() async {
    let selectionStore = InMemorySelectionStore(selectedSourceID: GlanceSources.default.id)
    let registry = ErroringSourceRegistry(
        source: GlanceSources.openCodeLocal,
        error: OpenCodeDataError.sqlite("locked")
    )
    let store = GlanceStore(
        sourceRegistry: registry,
        selectionStore: selectionStore,
        startRefreshLoop: false
    )

    await store.refresh()

    #expect(store.errorMessage == "Glance could not read the OpenCode database. Make sure OpenCode data is available and try again.")
}

@Test
@MainActor
func glanceStoreRejectsOldGenerationAfterSwitchingBackToSameSource() async {
    let oldRepository = BlockingCapabilityRepository(capabilities: [CapabilityUsage(id: CapabilityID(kind: .skill, name: "old"), usageCount: 1)])
    let newRepository = BlockingCapabilityRepository(capabilities: [CapabilityUsage(id: CapabilityID(kind: .skill, name: "new"), usageCount: 2)])
    let registry = GenerationSourceRegistry(first: oldRepository, second: newRepository)
    let store = GlanceStore(sourceRegistry: registry, selectionStore: InMemorySelectionStore(selectedSourceID: registry.sourceA.id), startRefreshLoop: false)
    let oldTask = Task { await store.refresh() }
    await oldRepository.waitUntilStarted()
    store.selectSource(registry.sourceB)
    store.selectSource(registry.sourceA)
    let newTask = Task { await store.refresh() }
    await newRepository.waitUntilStarted()
    await oldRepository.release()
    await oldTask.value

    #expect(store.isRefreshing)
    #expect(store.snapshot.allCapabilities.isEmpty)
    #expect(store.lastRefreshAt == nil)

    await newRepository.release()
    await newTask.value
    #expect(store.snapshot.skills.map(\.id.name) == ["new"])
    #expect(!store.isRefreshing)
}

@Test
@MainActor
func glanceStoreDoesNotShowPreviousSourceWhenNewSourceFails() async {
    let registry = GenerationSourceRegistry(
        first: WarningCapabilityRepository(capabilities: [CapabilityUsage(id: CapabilityID(kind: .skill, name: "old"), usageCount: 1)], warnings: ["old warning"]),
        second: StubCapabilityRepository(capabilities: [])
    )
    let store = GlanceStore(sourceRegistry: registry, selectionStore: InMemorySelectionStore(selectedSourceID: registry.sourceA.id), startRefreshLoop: false)
    await store.refresh()
    #expect(!store.snapshot.allCapabilities.isEmpty)
    store.selectSource(registry.sourceB)
    await store.refresh()
    #expect(store.errorMessage != nil)
    #expect(store.snapshot.allCapabilities.isEmpty)
    #expect(store.windowedSnapshots.isEmpty)
    #expect(store.lastRefreshAt == nil)
    #expect(store.noticeMessage == nil)
}

@Test
@MainActor
func glanceStoreRejectsWarningsThatCompleteAfterSourceSwitch() async {
    let warningGate = BlockingCapabilityRepository(capabilities: [])
    let registry = GenerationSourceRegistry(
        first: DelayedWarningsRepository(gate: warningGate),
        second: StubCapabilityRepository(capabilities: [CapabilityUsage(id: CapabilityID(kind: .skill, name: "new"), usageCount: 1)])
    )
    let store = GlanceStore(sourceRegistry: registry, selectionStore: InMemorySelectionStore(selectedSourceID: registry.sourceA.id), startRefreshLoop: false)
    let oldTask = Task { await store.refresh() }
    await warningGate.waitUntilStarted()
    store.selectSource(registry.sourceB)
    store.selectSource(registry.sourceA)
    await store.refresh()
    await warningGate.release()
    await oldTask.value
    #expect(store.snapshot.skills.map(\.id.name) == ["new"])
    #expect(store.noticeMessage == nil)
    #expect(!store.isRefreshing)
}

private struct DelayedWarningsRepository: WarningReportingRepository {
    let gate: BlockingCapabilityRepository
    func loadCapabilities() async throws -> [CapabilityUsage] {
        [CapabilityUsage(id: CapabilityID(kind: .skill, name: "old"), usageCount: 1)]
    }
    func currentWarnings() async -> [String] {
        _ = try? await gate.loadCapabilities()
        return ["old warning"]
    }
}

private final class GenerationSourceRegistry: GlanceSourceResolving {
    let sourceA = GlanceSource(id: "a", displayName: "A", detail: "Test A")
    let sourceB = GlanceSource(id: "b", displayName: "B", detail: "Test B")
    let first: any CapabilityRepository
    let second: any CapabilityRepository
    private var aRequests = 0

    init(first: any CapabilityRepository, second: any CapabilityRepository) {
        self.first = first
        self.second = second
    }

    var availableSources: [GlanceSource] { [sourceA, sourceB] }
    func makeRepository(for source: GlanceSource) -> any CapabilityRepository {
        guard source == sourceA else { return ErroringCapabilityRepository(error: OpenCodeDataError.sqlite("test failure")) }
        aRequests += 1
        return aRequests == 1 ? first : second
    }
    func settingsPaths(for source: GlanceSource) -> [String] { [] }
    func diagnostics(for source: GlanceSource) -> GlanceSourceDiagnostics {
        GlanceSourceDiagnostics(readiness: .ready, supportsRollingWindows: false, artifacts: [], summary: "Ready")
    }
    func userFacingErrorMessage(for source: GlanceSource, error: Error) -> String { error.localizedDescription }
}

@Test
@MainActor
func glanceStoreDoesNotRelabelOldWindowAfterLoadFailure() async {
    let repository = FailingWindowRepository()
    let registry = SingleWindowedRepositorySourceRegistry(repository: repository)
    let store = GlanceStore(sourceRegistry: registry,
        selectionStore: InMemorySelectionStore(selectedSourceID: GlanceSources.default.id),
        windowSelectionStore: InMemoryWindowSelectionStore(rawValue: 7), startRefreshLoop: false)
    await store.refresh()
    #expect(store.activeSnapshot.skills.first?.usageCount == 7)
    #expect(store.activeSnapshot.window == .day7)
    #expect(store.activeSnapshot.sourceID == store.currentSource.id)
    store.setSelectedWindow(.day14)
    #expect(store.activeSnapshot.allCapabilities.isEmpty)
    await store.refresh()
    #expect(store.errorMessage != nil)
    #expect(store.effectiveWindowLabel == "14d")
    #expect(store.activeSnapshot.allCapabilities.isEmpty)
    #expect(store.visibleRemovalCandidates.isEmpty)
}

@Test
@MainActor
func glanceStorePublishesEvidenceAtomicallyAndBlocksPartialCleanup() async {
    let registry = SingleWindowedRepositorySourceRegistry(repository: PartialEvidenceRepository())
    let store = GlanceStore(sourceRegistry: registry,
        selectionStore: InMemorySelectionStore(selectedSourceID: GlanceSources.default.id), startRefreshLoop: false)
    await store.refresh()
    #expect(store.activeSnapshot.allCapabilities.count == 1)
    #expect(store.usageEvidence.skippedRecords == 3)
    #expect(store.activeSnapshot.evidence == store.usageEvidence)
    #expect(store.visibleRemovalCandidates.isEmpty)
    #expect(store.visibleStale.isEmpty)
    #expect(store.noticeMessage?.contains("3 unparsed records") == true)
}

private struct PartialEvidenceRepository: EvidenceReportingRepository {
    func loadCapabilities() async throws -> [CapabilityUsage] { [] }
    func loadUsage(windows: [RollingWindow], now: Date) async throws -> UsageLoadResult {
        let usage = CapabilityUsage(id: CapabilityID(kind: .skill, name: "demo"), usageCount: 0, installedButUnused: true)
        return UsageLoadResult(windows: Dictionary(uniqueKeysWithValues: windows.map { ($0, [usage]) }),
            evidence: UsageEvidence(completeness: .partial, skippedRecords: 3))
    }
}

private struct FailingWindowRepository: WindowedCapabilityRepository {
    func loadCapabilities() async throws -> [CapabilityUsage] { [] }
    func loadCapabilities(windows: [RollingWindow], now: Date) async throws -> [RollingWindow: [CapabilityUsage]] {
        if windows.contains(.day14) { throw OpenCodeDataError.sqlite("test failure") }
        return Dictionary(uniqueKeysWithValues: windows.map { ($0, [CapabilityUsage(id: CapabilityID(kind: .skill, name: "demo"), usageCount: 7)]) })
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
    let sources: [GlanceSource]

    init(sources: [GlanceSource] = [GlanceSources.default]) {
        self.sources = sources
    }

    var availableSources: [GlanceSource] {
        sources
    }

    func makeRepository(for source: GlanceSource) -> any CapabilityRepository {
        switch source.id {
        case "future-source":
            return StubCapabilityRepository(capabilities: [
                CapabilityUsage(id: CapabilityID(kind: .skill, name: "future-skill"), usageCount: 1)
            ])
        default:
            return StubCapabilityRepository(capabilities: [])
        }
    }

    func settingsPaths(for source: GlanceSource) -> [String] {
        switch source.id {
        case "future-source":
            return ["~/Future/source.json"]
        default:
            return ["~/OpenCode/db.sqlite"]
        }
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

private final class BlockingTestSourceRegistry: GlanceSourceResolving {
    let sourceA: GlanceSource
    let sourceB: GlanceSource
    let blockingRepository: BlockingCapabilityRepository
    private let futureRepository: StubCapabilityRepository

    init(sourceA: GlanceSource, sourceB: GlanceSource) {
        self.sourceA = sourceA
        self.sourceB = sourceB
        self.blockingRepository = BlockingCapabilityRepository(capabilities: [
            CapabilityUsage(id: CapabilityID(kind: .skill, name: "old-source-skill"), usageCount: 1)
        ])
        self.futureRepository = StubCapabilityRepository(capabilities: [
            CapabilityUsage(id: CapabilityID(kind: .skill, name: "future-skill"), usageCount: 1)
        ])
    }

    var availableSources: [GlanceSource] {
        [sourceA, sourceB]
    }

    func makeRepository(for source: GlanceSource) -> any CapabilityRepository {
        switch source.id {
        case sourceB.id:
            return futureRepository
        default:
            return blockingRepository
        }
    }

    func settingsPaths(for source: GlanceSource) -> [String] {
        [source.id]
    }

    func diagnostics(for source: GlanceSource) -> GlanceSourceDiagnostics {
        GlanceSourceDiagnostics(readiness: .ready, supportsRollingWindows: false, artifacts: [], summary: "Ready")
    }

    func userFacingErrorMessage(for source: GlanceSource, error: Error) -> String {
        error.localizedDescription
    }
}

private final class ReadySourceSwitchingRegistry: GlanceSourceResolving {
    let sourceA: GlanceSource
    let sourceB: GlanceSource
    let claudeRepository: BlockingWarningCapabilityRepository
    private let openCodeRepository: WarningCapabilityRepository

    init(sourceA: GlanceSource, sourceB: GlanceSource) {
        self.sourceA = sourceA
        self.sourceB = sourceB
        self.openCodeRepository = WarningCapabilityRepository(
            capabilities: [
                CapabilityUsage(id: CapabilityID(kind: .skill, name: "old-source-skill"), usageCount: 1)
            ],
            warnings: ["Old warning"]
        )
        self.claudeRepository = BlockingWarningCapabilityRepository(
            capabilities: [
                CapabilityUsage(id: CapabilityID(kind: .skill, name: "claude-skill"), usageCount: 1)
            ],
            warnings: ["Claude warning"]
        )
    }

    var availableSources: [GlanceSource] {
        [sourceA, sourceB]
    }

    func makeRepository(for source: GlanceSource) -> any CapabilityRepository {
        switch source.id {
        case sourceB.id:
            claudeRepository
        default:
            openCodeRepository
        }
    }

    func settingsPaths(for source: GlanceSource) -> [String] {
        [source.id]
    }

    func diagnostics(for source: GlanceSource) -> GlanceSourceDiagnostics {
        GlanceSourceDiagnostics(readiness: .ready, supportsRollingWindows: false, artifacts: [], summary: "Ready")
    }

    func userFacingErrorMessage(for source: GlanceSource, error: Error) -> String {
        error.localizedDescription
    }
}

private actor BlockingCapabilityRepository: CapabilityRepository {
    private let capabilities: [CapabilityUsage]
    private var didStart = false
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(capabilities: [CapabilityUsage]) {
        self.capabilities = capabilities
    }

    func loadCapabilities() async throws -> [CapabilityUsage] {
        didStart = true
        startedContinuation?.resume()
        startedContinuation = nil

        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }

        return capabilities
    }

    func waitUntilStarted() async {
        if didStart {
            return
        }

        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private struct WarningCapabilityRepository: WarningReportingRepository {
    let capabilities: [CapabilityUsage]
    let warnings: [String]

    func loadCapabilities() async throws -> [CapabilityUsage] {
        capabilities
    }

    func currentWarnings() async -> [String] {
        warnings
    }
}

private struct SingleRepositorySourceRegistry: GlanceSourceResolving {
    let repository: any CapabilityRepository

    var availableSources: [GlanceSource] {
        [GlanceSources.default]
    }

    func makeRepository(for source: GlanceSource) -> any CapabilityRepository {
        repository
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

private struct DiagnosticsSourceRegistry: GlanceSourceResolving {
    let repository: any CapabilityRepository
    let diagnostics: GlanceSourceDiagnostics

    var availableSources: [GlanceSource] {
        [GlanceSources.default]
    }

    func makeRepository(for source: GlanceSource) -> any CapabilityRepository {
        repository
    }

    func settingsPaths(for source: GlanceSource) -> [String] {
        []
    }

    func diagnostics(for source: GlanceSource) -> GlanceSourceDiagnostics {
        diagnostics
    }

    func userFacingErrorMessage(for source: GlanceSource, error: Error) -> String {
        error.localizedDescription
    }
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

private struct SingleWindowedRepositorySourceRegistry: GlanceSourceResolving {
    let repository: any WindowedCapabilityRepository

    var availableSources: [GlanceSource] {
        [GlanceSources.default]
    }

    func makeRepository(for source: GlanceSource) -> any CapabilityRepository {
        repository
    }

    func settingsPaths(for source: GlanceSource) -> [String] {
        []
    }

    func diagnostics(for source: GlanceSource) -> GlanceSourceDiagnostics {
        GlanceSourceDiagnostics(readiness: .ready, supportsRollingWindows: true, artifacts: [], summary: "Ready")
    }

    func userFacingErrorMessage(for source: GlanceSource, error: Error) -> String {
        error.localizedDescription
    }
}

private actor CountingBlockingWindowedCapabilityRepository: WindowedCapabilityRepository {
    private let capabilities: [CapabilityUsage]
    private(set) var requestedWindowsByLoad: [[RollingWindow]] = []
    private var startedContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var releaseContinuations: [CheckedContinuation<Void, Never>] = []

    init(capabilities: [CapabilityUsage]) {
        self.capabilities = capabilities
    }

    func loadCapabilities() async throws -> [CapabilityUsage] {
        []
    }

    func loadCapabilities(windows: [RollingWindow], now: Date) async throws -> [RollingWindow: [CapabilityUsage]] {
        requestedWindowsByLoad.append(windows)
        let count = requestedWindowsByLoad.count
        startedContinuations[count]?.resume()
        startedContinuations[count] = nil

        await withCheckedContinuation { continuation in
            releaseContinuations.append(continuation)
        }

        return Dictionary(uniqueKeysWithValues: windows.map { ($0, capabilities) })
    }

    func waitUntilStarted(count targetCount: Int) async {
        if requestedWindowsByLoad.count >= targetCount {
            return
        }

        await withCheckedContinuation { continuation in
            startedContinuations[targetCount] = continuation
        }
    }

    func releaseNext() {
        guard !releaseContinuations.isEmpty else {
            return
        }
        let continuation = releaseContinuations.removeFirst()
        continuation.resume()
    }
}

private struct ErroringSourceRegistry: GlanceSourceResolving {
    let source: GlanceSource
    let error: Error

    var availableSources: [GlanceSource] {
        [source]
    }

    func makeRepository(for source: GlanceSource) -> any CapabilityRepository {
        ErroringCapabilityRepository(error: error)
    }

    func settingsPaths(for source: GlanceSource) -> [String] {
        []
    }

    func diagnostics(for source: GlanceSource) -> GlanceSourceDiagnostics {
        GlanceSourceDiagnostics(readiness: .ready, supportsRollingWindows: false, artifacts: [], summary: "Ready")
    }

    func userFacingErrorMessage(for source: GlanceSource, error: Error) -> String {
        LiveGlanceSourceRegistry().userFacingErrorMessage(for: source, error: error)
    }
}

private struct ErroringCapabilityRepository: CapabilityRepository {
    let error: Error

    func loadCapabilities() async throws -> [CapabilityUsage] {
        throw error
    }
}

private final class MutableDiagnosticsSourceRegistry: GlanceSourceResolving {
    let repository: any CapabilityRepository
    var diagnostics: GlanceSourceDiagnostics

    init(repository: any CapabilityRepository, diagnostics: GlanceSourceDiagnostics) {
        self.repository = repository
        self.diagnostics = diagnostics
    }

    var availableSources: [GlanceSource] {
        [GlanceSources.default]
    }

    func makeRepository(for source: GlanceSource) -> any CapabilityRepository {
        repository
    }

    func settingsPaths(for source: GlanceSource) -> [String] {
        []
    }

    func diagnostics(for source: GlanceSource) -> GlanceSourceDiagnostics {
        diagnostics
    }

    func userFacingErrorMessage(for source: GlanceSource, error: Error) -> String {
        error.localizedDescription
    }
}

private actor CountingBlockingCapabilityRepository: CapabilityRepository {
    private let capabilities: [CapabilityUsage]
    private(set) var loadCount = 0
    private var didStart = false
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(capabilities: [CapabilityUsage]) {
        self.capabilities = capabilities
    }

    func loadCapabilities() async throws -> [CapabilityUsage] {
        loadCount += 1
        didStart = true
        startedContinuation?.resume()
        startedContinuation = nil
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
        return capabilities
    }

    func waitUntilStarted() async {
        if didStart { return }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor BlockingWarningCapabilityRepository: WarningReportingRepository {
    private let capabilities: [CapabilityUsage]
    private let warnings: [String]
    private var didStart = false
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(capabilities: [CapabilityUsage], warnings: [String]) {
        self.capabilities = capabilities
        self.warnings = warnings
    }

    func loadCapabilities() async throws -> [CapabilityUsage] {
        didStart = true
        startedContinuation?.resume()
        startedContinuation = nil

        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }

        return capabilities
    }

    func currentWarnings() async -> [String] {
        warnings
    }

    func waitUntilStarted() async {
        if didStart {
            return
        }

        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
