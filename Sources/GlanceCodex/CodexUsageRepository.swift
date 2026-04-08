import Foundation
import GlanceCore

public actor CodexUsageRepository: WindowedCapabilityRepository, WarningReportingRepository {
    private let configLoader: CodexConfigLoader
    private let transcriptReader: CodexTranscriptUsageReader
    private var warnings: [String] = []

    public init(
        configLoader: CodexConfigLoader = CodexConfigLoader(),
        transcriptReader: CodexTranscriptUsageReader = CodexTranscriptUsageReader()
    ) {
        self.configLoader = configLoader
        self.transcriptReader = transcriptReader
    }

    public func loadCapabilities() async throws -> [CapabilityUsage] {
        try await loadCapabilities(windows: [.day30], now: .now)[.day30] ?? []
    }

    public func loadCapabilities(windows: [RollingWindow], now: Date) async throws -> [RollingWindow: [CapabilityUsage]] {
        let installedSkills = configLoader.loadInstalledSkills()
        let maxWindow = windows.map(\.rawValue).max() ?? 30
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -maxWindow, to: now) ?? now
        let loadResult = try transcriptReader.loadObservedEvents(since: cutoffDate)
        warnings = makeWarnings(from: loadResult)
        let eventsByWindow = bucket(events: loadResult.events, windows: windows, now: now)

        var output: [RollingWindow: [CapabilityUsage]] = [:]
        for window in windows {
            output[window] = buildCapabilities(installedSkills: installedSkills, events: eventsByWindow[window] ?? [])
        }
        return output
    }

    public func currentWarnings() async -> [String] {
        warnings
    }

    private func makeWarnings(from loadResult: CodexTranscriptLoadResult) -> [String] {
        var warnings: [String] = []
        if loadResult.skippedFilesCount > 0 {
            warnings.append("Some Codex sessions could not be read, so these results may be incomplete.")
        }
        if loadResult.skippedEntriesCount > 0 {
            warnings.append("Some Codex session entries could not be parsed, so these results may be incomplete.")
        }
        return warnings
    }

    private func buildCapabilities(installedSkills: [CodexInstalledSkill], events: [CodexObservedToolEvent]) -> [CapabilityUsage] {
        var capabilities: [CapabilityID: CapabilityUsage] = [:]
        for skill in installedSkills {
            let id = CapabilityID(kind: .skill, name: skill.name)
            capabilities[id] = CapabilityUsage(id: id, usageCount: 0, installedButUnused: true)
        }

        var serverAccumulators: [CapabilityID: CapabilityUsage] = [:]
        for event in events {
            let toolID = CapabilityID(kind: .mcpTool, namespace: event.serverName, name: event.toolName)
            let serverID = CapabilityID(kind: .mcpServer, namespace: event.serverName, name: event.serverName)
            let usage = CapabilityUsage(id: toolID, usageCount: 1, firstUsedAt: event.timestamp, lastUsedAt: event.timestamp)
            let serverUsage = CapabilityUsage(id: serverID, usageCount: 1, firstUsedAt: event.timestamp, lastUsedAt: event.timestamp)
            capabilities[toolID] = merge(capabilities[toolID] ?? CapabilityUsage(id: toolID, usageCount: 0, installedButUnused: true), with: usage)
            serverAccumulators[serverID] = merge(serverAccumulators[serverID] ?? CapabilityUsage(id: serverID, usageCount: 0, installedButUnused: true), with: serverUsage)
        }

        for (serverID, usage) in serverAccumulators {
            capabilities[serverID] = merge(capabilities[serverID] ?? CapabilityUsage(id: serverID, usageCount: 0, installedButUnused: true), with: usage)
        }

        return Array(capabilities.values)
    }

    private func bucket(events: [CodexObservedToolEvent], windows: [RollingWindow], now: Date) -> [RollingWindow: [CodexObservedToolEvent]] {
        let sortedWindows = windows.sorted { $0.rawValue < $1.rawValue }
        let cutoffs = Dictionary(uniqueKeysWithValues: sortedWindows.map { ($0, Calendar.current.date(byAdding: .day, value: -$0.rawValue, to: now) ?? now) })
        var buckets: [RollingWindow: [CodexObservedToolEvent]] = Dictionary(uniqueKeysWithValues: windows.map { ($0, []) })

        for event in events {
            for window in sortedWindows {
                guard let cutoff = cutoffs[window], event.timestamp >= cutoff else { continue }
                if let startIndex = sortedWindows.firstIndex(of: window) {
                    for qualifyingWindow in sortedWindows[startIndex...] {
                        buckets[qualifyingWindow, default: []].append(event)
                    }
                }
                break
            }
        }

        return buckets
    }

    private func merge(_ lhs: CapabilityUsage, with rhs: CapabilityUsage) -> CapabilityUsage {
        precondition(lhs.id == rhs.id)
        return CapabilityUsage(
            id: lhs.id,
            usageCount: lhs.usageCount + rhs.usageCount,
            firstUsedAt: minDate(lhs.firstUsedAt, rhs.firstUsedAt),
            lastUsedAt: maxDate(lhs.lastUsedAt, rhs.lastUsedAt),
            successCount: lhs.successCount + rhs.successCount,
            failureCount: lhs.failureCount + rhs.failureCount,
            avgLatencyMs: nil,
            installedButUnused: (lhs.usageCount + rhs.usageCount) == 0 && (lhs.installedButUnused || rhs.installedButUnused)
        )
    }

    private func minDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (.some(left), .some(right)): return min(left, right)
        case let (.some(left), nil): return left
        case let (nil, .some(right)): return right
        case (nil, nil): return nil
        }
    }

    private func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (.some(left), .some(right)): return max(left, right)
        case let (.some(left), nil): return left
        case let (nil, .some(right)): return right
        case (nil, nil): return nil
        }
    }
}
