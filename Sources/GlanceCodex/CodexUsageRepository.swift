import Foundation
import GlanceCore

public actor CodexUsageRepository: EvidenceReportingRepository, WarningReportingRepository {
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

    public func loadUsage(windows: [RollingWindow], now: Date) async throws -> UsageLoadResult {
        let inventory = configLoader.loadInventory()
        let installedSkills = inventory.skills
        let cutoffDate = windows.map { $0.cutoffDate(relativeTo: now) }.min() ?? .distantPast
        let loadResult = try transcriptReader.loadObservedEvents(since: cutoffDate)
        warnings = makeWarnings(from: loadResult)
        var evidence = loadResult.evidence
        evidence.sources += inventory.sources
        evidence.skippedFiles += inventory.errors
        if inventory.errors > 0 { evidence.completeness = .partial }
        let events = loadResult.events.filter { $0.timestamp <= now }
        let installedNames = Set(installedSkills.map { $0.name.lowercased() })
        evidence.unmatchedRecords = events.filter { event in event.skillName.map { !installedNames.contains($0.lowercased()) } ?? false }.count
        if evidence.unmatchedRecords > 0 { evidence.completeness = .partial }
        evidence.skippedRecords += loadResult.events.count - events.count
        if evidence.skippedRecords > 0 { evidence.completeness = .partial }
        evidence.observedThrough = events.map(\.timestamp).max()
        let eventsByWindow = bucket(events: events, windows: windows, now: now)

        var output: [RollingWindow: [CapabilityUsage]] = [:]
        for window in windows {
            output[window] = buildCapabilities(installedSkills: installedSkills, events: eventsByWindow[window] ?? [])
        }
        if evidence.completeness == .partial || evidence.completeness == .unavailable {
            warnings.append(evidence.summary)
        }
        return UsageLoadResult(windows: output, evidence: evidence, warnings: warnings)
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
        let skillNames = Dictionary(installedSkills.map { ($0.name.lowercased(), $0.name) }, uniquingKeysWith: { first, _ in first })
        for skill in installedSkills {
            let id = CapabilityID(kind: .skill, name: skill.name)
            // Implicit skill reads are not reliably represented by a dedicated
            // event in every Codex version. Lack of evidence is not non-use.
            capabilities[id] = CapabilityUsage(id: id, usageCount: 0)
        }

        var serverAccumulators: [CapabilityID: CapabilityUsage] = [:]
        for event in events {
            if let name = event.skillName, let canonical = skillNames[name.lowercased()] {
                let id = CapabilityID(kind: .skill, name: canonical)
                let usage = CapabilityUsage(id: id, usageCount: 1, firstUsedAt: event.timestamp, lastUsedAt: event.timestamp, evidenceSamples: event.reference.map { [$0] })
                capabilities[id] = merge(capabilities[id] ?? CapabilityUsage(id: id, usageCount: 0), with: usage)
                continue
            }
            guard event.skillName == nil else { continue }
            let toolID = CapabilityID(kind: .mcpTool, namespace: event.serverName, name: event.toolName)
            let serverID = CapabilityID(kind: .mcpServer, namespace: event.serverName, name: event.serverName)
            let usage = CapabilityUsage(id: toolID, usageCount: 1, firstUsedAt: event.timestamp, lastUsedAt: event.timestamp, evidenceSamples: event.reference.map { [$0] })
            let serverUsage = CapabilityUsage(id: serverID, usageCount: 1, firstUsedAt: event.timestamp, lastUsedAt: event.timestamp, evidenceSamples: event.reference.map { [$0] })
            capabilities[toolID] = merge(capabilities[toolID] ?? CapabilityUsage(id: toolID, usageCount: 0, installedButUnused: false), with: usage)
            serverAccumulators[serverID] = merge(serverAccumulators[serverID] ?? CapabilityUsage(id: serverID, usageCount: 0, installedButUnused: false), with: serverUsage)
        }

        for (serverID, usage) in serverAccumulators {
            capabilities[serverID] = merge(capabilities[serverID] ?? CapabilityUsage(id: serverID, usageCount: 0, installedButUnused: false), with: usage)
        }

        return Array(capabilities.values)
    }

    private func bucket(events: [CodexObservedToolEvent], windows: [RollingWindow], now: Date) -> [RollingWindow: [CodexObservedToolEvent]] {
        let sortedWindows = windows.sorted { $0.lookbackDays < $1.lookbackDays }
        let cutoffs = Dictionary(uniqueKeysWithValues: sortedWindows.map { ($0, $0.cutoffDate(relativeTo: now)) })
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
            installedButUnused: false,
            evidenceSamples: Array(((lhs.evidenceSamples ?? []) + (rhs.evidenceSamples ?? [])).prefix(5))
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
