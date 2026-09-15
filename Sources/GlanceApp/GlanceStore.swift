import Combine
import Foundation
import GlanceCore

@MainActor
final class GlanceStore: ObservableObject {
    @Published private(set) var snapshot: RankingSnapshot = .empty
    @Published private(set) var windowedSnapshots: [RollingWindow: RankingSnapshot] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshAt: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var noticeMessage: String?
    @Published private(set) var usageEvidence = UsageEvidence()
    @Published private(set) var currentSource: GlanceSource
    @Published private(set) var selectedWindow: RollingWindow
    @Published private(set) var policy: RankingPolicy

    private let sourceRegistry: any GlanceSourceResolving
    private let selectionStore: any SourceSelectionStoring
    private let policyStore: any RankingPolicyStoring
    private let windowSelectionStore: any WindowSelectionStoring
    private var repository: any CapabilityRepository
    private var refreshTask: Task<Void, Never>?
    private var refreshInFlightCount = 0
    private let shouldMaintainRefreshLoop: Bool
    private var inFlightRefresh: (key: RefreshKey, task: Task<Void, Never>)?
    private var pendingRefreshSources: Set<String> = []
    private var sourceGeneration = UUID()

    init(
        sourceRegistry: any GlanceSourceResolving = LiveGlanceSourceRegistry(),
        selectionStore: any SourceSelectionStoring = UserDefaultsSourceSelectionStore(),
        policyStore: any RankingPolicyStoring = UserDefaultsRankingPolicyStore(),
        windowSelectionStore: any WindowSelectionStoring = UserDefaultsWindowSelectionStore(),
        policy: RankingPolicy = .default,
        startRefreshLoop: Bool = true
    ) {
        self.sourceRegistry = sourceRegistry
        self.selectionStore = selectionStore
        self.policyStore = policyStore
        self.windowSelectionStore = windowSelectionStore
        self.shouldMaintainRefreshLoop = startRefreshLoop
        self.policy = GlanceStore.sanitizePolicy(policyStore.loadPolicy() ?? policy)
        self.selectedWindow = GlanceStore.resolveInitialWindow(
            availableWindows: RollingWindow.displayCases,
            selectedWindowRawValue: windowSelectionStore.loadSelectedWindowRawValue()
        )
        let savedSourceID = selectionStore.loadSelectedSourceID()
        let initialSource = GlanceStore.resolveInitialSource(
            availableSources: sourceRegistry.availableSources,
            selectedSourceID: savedSourceID
        )
        self.currentSource = initialSource
        self.repository = sourceRegistry.makeRepository(for: initialSource)

        // Migrate the retired source selection, never its usage history or skill data.
        if savedSourceID == "gemini-local", initialSource.id == GlanceSources.antigravityLocal.id {
            selectionStore.saveSelectedSourceID(initialSource.id)
        }

        if startRefreshLoop {
            refreshTask = Task { [weak self] in
                guard let self else { return }
                await self.refresh()
                await self.runRefreshLoop()
            }
        }
    }

    deinit {
        refreshTask?.cancel()
    }

    var statusIconName: String {
        if errorMessage != nil {
            return "exclamationmark.triangle"
        }
        if !visibleRemovalCandidates.isEmpty {
            return "eye.trianglebadge.exclamationmark"
        }
        return "eye"
    }

    var summaryLine: String {
        let snapshot = activeSnapshot
        if isInventoryOnly { return "\(snapshot.skills.count) skill definitions · usage unavailable" }
        let history = staleSnapshot
        let covered = history.evidence.covers(since: history.generatedAt.addingTimeInterval(-Double(max(policy.staleAfterDays, policy.removalAfterDays)) * 86_400), through: history.generatedAt)
        let cleanup = covered && errorMessage == nil ? "\(visibleStale.count) stale" : "cleanup paused"
        return "\(snapshot.skills.count) skills · \(cleanup)"
    }

    var availableSources: [GlanceSource] {
        sourceRegistry.availableSources
    }

    var currentDiagnostics: GlanceSourceDiagnostics {
        sourceRegistry.diagnostics(for: currentSource)
    }

    func diagnostics(for source: GlanceSource) -> GlanceSourceDiagnostics {
        sourceRegistry.diagnostics(for: source)
    }

    var currentSourcePaths: [String] {
        sourceRegistry.settingsPaths(for: currentSource)
    }

    var effectiveWindowLabel: String {
        if isInventoryOnly { return "Inventory" }
        return currentDiagnostics.supportsRollingWindows ? selectedWindow.title : "All time"
    }

    var isInventoryOnly: Bool {
        currentDiagnostics.usageSupport == .inventoryOnly
    }

    var visibleStale: [CapabilityUsage] {
        errorMessage == nil && !isInventoryOnly ? staleSnapshot.stale : []
    }

    var visibleRemovalCandidates: [CapabilityUsage] {
        errorMessage == nil && !isInventoryOnly ? staleSnapshot.removalCandidates : []
    }

    var activeSnapshot: RankingSnapshot {
        let result = currentDiagnostics.supportsRollingWindows ? windowedSnapshots[selectedWindow] : snapshot
        guard let result, result.sourceID == currentSource.id else { return .empty }
        return result
    }

    var staleSnapshot: RankingSnapshot {
        windowedSnapshots[cleanupWindow] ?? .empty
    }

    var availableWindows: [RollingWindow] {
        RollingWindow.displayCases
    }

    private var cleanupWindow: RollingWindow {
        .allTime
    }

    func selectSource(id: String) {
        guard let source = availableSources.first(where: { $0.id == id }) else {
            return
        }
        selectSource(source)
    }

    func selectSource(_ source: GlanceSource) {
        guard source != currentSource else { return }

        pendingRefreshSources.removeAll()
        sourceGeneration = UUID()
        inFlightRefresh?.task.cancel()
        inFlightRefresh = nil
        refreshInFlightCount = 0
        isRefreshing = false
        let diagnostics = sourceRegistry.diagnostics(for: source)
        currentSource = source
        repository = sourceRegistry.makeRepository(for: source)
        selectionStore.saveSelectedSourceID(source.id)
        snapshot = .empty
        windowedSnapshots = [:]
        lastRefreshAt = nil
        noticeMessage = nil
        usageEvidence = UsageEvidence()
        errorMessage = diagnostics.readiness == .ready ? nil : diagnostics.summary

        Task {
            await refresh()
        }
    }

    func setSelectedWindow(_ window: RollingWindow) {
        guard selectedWindow != window else { return }
        selectedWindow = window
        windowSelectionStore.saveSelectedWindowRawValue(window.rawValue)
        if let refreshedSnapshot = windowedSnapshots[window] {
            snapshot = refreshedSnapshot
        } else if currentDiagnostics.supportsRollingWindows {
            snapshot = .empty
            lastRefreshAt = nil
            pendingRefreshSources.insert(currentSource.id)
            Task {
                await refresh()
            }
        }
    }

    func updatePolicy(_ update: (RankingPolicy) -> RankingPolicy) {
        let newPolicy = GlanceStore.sanitizePolicy(update(policy))
        guard newPolicy != policy else { return }
        policy = newPolicy
        pendingRefreshSources.insert(currentSource.id)
        policyStore.savePolicy(newPolicy)
        restartRefreshLoop()
        Task {
            await refresh()
        }
    }

    func refresh() async {
        let key = RefreshKey(sourceID: currentSource.id, generation: sourceGeneration)
        if let inFlightRefresh, inFlightRefresh.key == key {
            await inFlightRefresh.task.value
            if key.generation == sourceGeneration, pendingRefreshSources.remove(key.sourceID) != nil {
                await refresh()
            }
            return
        }

        pendingRefreshSources.remove(key.sourceID)
        let requestedRepository = repository
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.performRefresh(for: key, repository: requestedRepository)
        }
        inFlightRefresh = (key, task)
        await task.value
    }

    private func runRefreshLoop() async {
        while !Task.isCancelled {
            let sleepNanoseconds = sanitizedRefreshIntervalNanoseconds
            try? await Task.sleep(nanoseconds: sleepNanoseconds)
            if Task.isCancelled { break }
            await refresh()
        }
    }

    private var sanitizedRefreshIntervalNanoseconds: UInt64 {
        let seconds = min(max(policy.refreshIntervalSeconds, 60), 3_600)
        return UInt64(seconds * 1_000_000_000)
    }

    private func beginRefresh() {
        refreshInFlightCount += 1
        isRefreshing = refreshInFlightCount > 0
    }

    private func endRefresh() {
        refreshInFlightCount = max(0, refreshInFlightCount - 1)
        isRefreshing = refreshInFlightCount > 0
    }

    private func restartRefreshLoop() {
        guard shouldMaintainRefreshLoop else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.runRefreshLoop()
        }
    }

    private func performRefresh(for key: RefreshKey, repository requestedRepository: any CapabilityRepository) async {
        guard key.generation == sourceGeneration, !Task.isCancelled else { return }
        beginRefresh()
        defer {
            if key.generation == sourceGeneration {
                endRefresh()
                if inFlightRefresh?.key == key {
                    inFlightRefresh = nil
                }
            }
        }

        let diagnostics = currentDiagnostics
        if diagnostics.readiness != .ready {
            errorMessage = diagnostics.summary
            noticeMessage = nil
            return
        }

        do {
            let now = Date.now
            let capabilitiesByWindow: [RollingWindow: [CapabilityUsage]]
            var evidence = UsageEvidence()
            var warning: String?
            if let evidenceRepository = requestedRepository as? any EvidenceReportingRepository {
                let windows = diagnostics.supportsRollingWindows ? Array(Set([selectedWindow, cleanupWindow])) : [.allTime]
                let result = try await evidenceRepository.loadUsage(windows: windows, now: now)
                capabilitiesByWindow = result.windows
                evidence = result.evidence
                warning = ([evidence.summary] + result.warnings.filter { $0 != evidence.summary }).joined(separator: "\n")
            } else if let windowedRepository = requestedRepository as? any WindowedCapabilityRepository {
                let requestedWindows = Array(Set([selectedWindow, cleanupWindow])).sorted { $0.rawValue < $1.rawValue }
                capabilitiesByWindow = try await windowedRepository.loadCapabilities(windows: requestedWindows, now: now)
            } else {
                let capabilities = try await requestedRepository.loadCapabilities()
                capabilitiesByWindow = [.allTime: capabilities]
            }
            if !(requestedRepository is any EvidenceReportingRepository), let warningRepository = requestedRepository as? any WarningReportingRepository {
                warning = await warningRepository.currentWarnings().first
            }
            // Publish one generation atomically, after the last suspension point.
            guard key.generation == sourceGeneration, !Task.isCancelled else { return }
            windowedSnapshots = [:]
            for (window, capabilities) in capabilitiesByWindow {
                windowedSnapshots[window] = CapabilityRanker.buildSnapshot(from: capabilities, policy: policy, now: now, evidence: evidence, sourceID: key.sourceID, window: window)
            }
            snapshot = currentDiagnostics.supportsRollingWindows ? (windowedSnapshots[selectedWindow] ?? .empty) : (windowedSnapshots[.allTime] ?? .empty)
            usageEvidence = evidence
            lastRefreshAt = now
            errorMessage = nil
            noticeMessage = warning
        } catch {
            guard key.generation == sourceGeneration, !Task.isCancelled else {
                return
            }
            noticeMessage = nil
            errorMessage = sourceRegistry.userFacingErrorMessage(for: currentSource, error: error)
        }
    }

    private static func resolveInitialSource(
        availableSources: [GlanceSource],
        selectedSourceID: String?
    ) -> GlanceSource {
        if selectedSourceID == "gemini-local",
           let replacement = availableSources.first(where: { $0.id == GlanceSources.antigravityLocal.id }) {
            return replacement
        }
        if let selectedSourceID,
           let source = availableSources.first(where: { $0.id == selectedSourceID }) {
            return source
        }

        return availableSources.first ?? GlanceSources.default
    }

    private static func resolveInitialWindow(
        availableWindows: [RollingWindow],
        selectedWindowRawValue: Int?
    ) -> RollingWindow {
        if let selectedWindowRawValue,
           let window = availableWindows.first(where: { $0.rawValue == selectedWindowRawValue }) {
            return window
        }

        return .day7
    }

    private static func sanitizePolicy(_ policy: RankingPolicy) -> RankingPolicy {
        var sanitized = policy
        sanitized.halfLifeDays = max(1, sanitized.halfLifeDays)
        sanitized.refreshIntervalSeconds = min(max(sanitized.refreshIntervalSeconds, 60), 3_600)
        sanitized.staleAfterDays = max(1, sanitized.staleAfterDays)
        sanitized.removalAfterDays = max(sanitized.staleAfterDays, sanitized.removalAfterDays)
        sanitized.minimumUsageToKeep = max(1, sanitized.minimumUsageToKeep)
        return sanitized
    }
}

private struct RefreshKey: Equatable {
    let sourceID: String
    let generation: UUID
}
