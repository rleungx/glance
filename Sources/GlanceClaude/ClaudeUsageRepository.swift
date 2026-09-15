import Foundation
import GlanceCore

public actor ClaudeUsageRepository: EvidenceReportingRepository, WarningReportingRepository {
    private let configLoader: ClaudeConfigLoader
    private let transcriptReader: ClaudeTranscriptUsageReader
    private var warnings: [String] = []

    public init(
        configLoader: ClaudeConfigLoader = ClaudeConfigLoader(),
        transcriptReader: ClaudeTranscriptUsageReader = ClaudeTranscriptUsageReader()
    ) {
        self.configLoader = configLoader
        self.transcriptReader = transcriptReader
    }

    public func loadCapabilities() async throws -> [CapabilityUsage] {
        try await loadCapabilities(windows: [.day30], now: .now)[.day30] ?? []
    }

    public func loadUsage(windows: [RollingWindow], now: Date) async throws -> UsageLoadResult {
        let installedSkills = try configLoader.loadInstalledSkills()
        let installedSkillMap = Dictionary(installedSkills.map { ($0.name.lowercased(), $0.name) }, uniquingKeysWith: { first, _ in first })
        let cutoffDate = windows.map { $0.cutoffDate(relativeTo: now) }.min() ?? .distantPast
        let loadResult = try transcriptReader.loadObservedEvents(since: cutoffDate)
        warnings = loadResult.skippedFilesCount > 0 ? ["Some Claude transcripts were skipped, so these results may be incomplete."] : []
        var evidence = loadResult.evidence
        evidence.sources = Array(Set(evidence.sources + configLoader.evidenceSources)).sorted()
        let events = loadResult.events.filter { $0.timestamp <= now }
        evidence.unmatchedRecords = events.filter { event in
            return event.skillName.map { installedSkillMap[$0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] == nil } ?? false
        }.count
        if evidence.unmatchedRecords > 0 { evidence.completeness = .partial }
        evidence.skippedRecords += loadResult.events.count - events.count
        if evidence.skippedRecords > 0 { evidence.completeness = .partial }
        evidence.observedThrough = events.map(\.timestamp).max()
        let eventsByWindow = bucket(events: events, windows: windows, now: now)

        var output: [RollingWindow: [CapabilityUsage]] = [:]
        for window in windows {
            output[window] = buildCapabilities(
                installedSkills: installedSkills,
                installedSkillMap: installedSkillMap,
                events: eventsByWindow[window] ?? []
            )
        }
        if evidence.completeness == .partial || evidence.completeness == .unavailable {
            warnings.append(evidence.summary)
        }
        return UsageLoadResult(windows: output, evidence: evidence, warnings: warnings)
    }

    public func currentWarnings() async -> [String] {
        warnings
    }

    private func buildCapabilities(
        installedSkills: [ClaudeInstalledSkill],
        installedSkillMap: [String: String],
        events: [ClaudeObservedToolEvent]
    ) -> [CapabilityUsage] {
        var capabilities: [CapabilityID: CapabilityUsage] = [:]

        for skill in installedSkills {
            let id = CapabilityID(kind: .skill, name: skill.name)
            capabilities[id] = CapabilityUsage(id: id, usageCount: 0, installedButUnused: false)
        }

        for event in events {
            guard let skillName = event.skillName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { continue }
            if let canonicalSkill = installedSkillMap[skillName] {
                let id = CapabilityID(kind: .skill, name: canonicalSkill)
                capabilities[id] = merge(capabilities[id] ?? CapabilityUsage(id: id, usageCount: 0, installedButUnused: false), with: singleEventUsage(id: id, timestamp: event.timestamp, reference: event.reference))
            }
        }

        return Array(capabilities.values)
    }

    private func bucket(
        events: [ClaudeObservedToolEvent],
        windows: [RollingWindow],
        now: Date
    ) -> [RollingWindow: [ClaudeObservedToolEvent]] {
        let sortedWindows = windows.sorted { $0.lookbackDays < $1.lookbackDays }
        let cutoffs = Dictionary(uniqueKeysWithValues: sortedWindows.map { window in
            (window, window.cutoffDate(relativeTo: now))
        })

        var buckets: [RollingWindow: [ClaudeObservedToolEvent]] = Dictionary(uniqueKeysWithValues: windows.map { ($0, []) })

        for event in events {
            for window in sortedWindows {
                guard let cutoff = cutoffs[window] else { continue }
                if event.timestamp >= cutoff {
                    if let startIndex = sortedWindows.firstIndex(of: window) {
                        for qualifyingWindow in sortedWindows[startIndex...] {
                            buckets[qualifyingWindow, default: []].append(event)
                        }
                    }
                    break
                }
            }
        }

        return buckets
    }

    private func singleEventUsage(id: CapabilityID, timestamp: Date, reference: UsageRecordReference?) -> CapabilityUsage {
        CapabilityUsage(id: id, usageCount: 1, firstUsedAt: timestamp, lastUsedAt: timestamp, installedButUnused: false, evidenceSamples: reference.map { [$0] })
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
