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
        let initialSource = GlanceStore.resolveInitialSource(
            availableSources: sourceRegistry.availableSources,
            selectedSourceID: selectionStore.loadSelectedSourceID()
        )
        self.currentSource = initialSource
        self.repository = sourceRegistry.makeRepository(for: initialSource)

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
        return "\(snapshot.skills.count) skills · \(snapshot.mcpServers.count) MCPs · \(visibleStale.count) stale"
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
        currentDiagnostics.supportsRollingWindows ? selectedWindow.title : "All time"
    }

    var topMCPs: [CapabilityUsage] {
        activeSnapshot.mcpServers
    }

    var visibleStale: [CapabilityUsage] {
        staleSnapshot.stale.filter { $0.id.kind != .mcpTool }
    }

    var visibleRemovalCandidates: [CapabilityUsage] {
        staleSnapshot.removalCandidates.filter { $0.id.kind != .mcpTool }
    }

    var activeSnapshot: RankingSnapshot {
        windowedSnapshots[selectedWindow] ?? snapshot
    }

    var staleSnapshot: RankingSnapshot {
        windowedSnapshots[cleanupWindow] ?? windowedSnapshots[.day30] ?? activeSnapshot
    }

    var availableWindows: [RollingWindow] {
        RollingWindow.displayCases
    }

    private var cleanupWindow: RollingWindow {
        let maxDays = max(policy.staleAfterDays, policy.removalAfterDays)
        if maxDays <= 30 { return .day30 }
        if maxDays <= 45 { return .day45 }
        if maxDays <= 60 { return .day60 }
        if maxDays <= 90 { return .day90 }
        return .day120
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
        let diagnostics = sourceRegistry.diagnostics(for: source)
        currentSource = source
        repository = sourceRegistry.makeRepository(for: source)
        selectionStore.saveSelectedSourceID(source.id)
        if diagnostics.readiness == .ready {
            errorMessage = nil
        } else {
            snapshot = .empty
            windowedSnapshots = [:]
            lastRefreshAt = nil
            errorMessage = diagnostics.summary
            noticeMessage = nil
        }

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
        let key = RefreshKey(sourceID: currentSource.id, cleanupWindow: cleanupWindow)
        if let inFlightRefresh, inFlightRefresh.key.sourceID == key.sourceID {
            await inFlightRefresh.task.value
            if pendingRefreshSources.remove(key.sourceID) != nil, currentSource.id == key.sourceID {
                await refresh()
            }
            return
        }

        pendingRefreshSources.remove(key.sourceID)
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.performRefresh(for: key)
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

    private func performRefresh(for key: RefreshKey) async {
        let requestedSourceID = currentSource.id
        let requestedRepository = repository
        beginRefresh()
        defer {
            endRefresh()
            if inFlightRefresh?.key == key {
                inFlightRefresh = nil
            }
        }

        let diagnostics = currentDiagnostics
        if diagnostics.readiness != .ready {
            errorMessage = diagnostics.summary
            noticeMessage = nil
            return
        }

        do {
            if let windowedRepository = requestedRepository as? any WindowedCapabilityRepository {
                let requestedWindows = Array(Set([selectedWindow, cleanupWindow])).sorted { $0.rawValue < $1.rawValue }
                let capabilitiesByWindow = try await windowedRepository.loadCapabilities(windows: requestedWindows, now: .now)
                guard requestedSourceID == currentSource.id else {
                    return
                }
                windowedSnapshots = capabilitiesByWindow.mapValues { capabilities in
                    CapabilityRanker.buildSnapshot(from: capabilities, policy: policy, now: .now)
                }
                snapshot = windowedSnapshots[selectedWindow] ?? windowedSnapshots[.day30] ?? .empty
            } else {
                let capabilities = try await requestedRepository.loadCapabilities()
                guard requestedSourceID == currentSource.id else {
                    return
                }
                snapshot = CapabilityRanker.buildSnapshot(from: capabilities, policy: policy, now: .now)
                windowedSnapshots = [:]
            }
            lastRefreshAt = .now
            errorMessage = nil
            if let warningRepository = requestedRepository as? any WarningReportingRepository {
                noticeMessage = await warningRepository.currentWarnings().first
            } else {
                noticeMessage = nil
            }
        } catch {
            guard requestedSourceID == currentSource.id else {
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
    let cleanupWindow: RollingWindow
}
