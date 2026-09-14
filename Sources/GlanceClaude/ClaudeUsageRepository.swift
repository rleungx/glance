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
        let configuredServers = try configLoader.loadConfiguredMCPServers().filter(\.enabled)
        let installedSkillMap = Dictionary(installedSkills.map { ($0.name.lowercased(), $0.name) }, uniquingKeysWith: { first, _ in first })
        let serverNames = Set(configuredServers.map { $0.name.lowercased() })
        let serverNameCandidates = serverNames.sorted { $0.count > $1.count }
        let cutoffDate = windows.map { $0.cutoffDate(relativeTo: now) }.min() ?? .distantPast
        let loadResult = try transcriptReader.loadObservedEvents(since: cutoffDate)
        warnings = loadResult.skippedFilesCount > 0 ? ["Some Claude transcripts were skipped, so these results may be incomplete."] : []
        var evidence = loadResult.evidence
        evidence.sources = Array(Set(evidence.sources + configLoader.evidenceSources)).sorted()
        let events = loadResult.events.filter { $0.timestamp <= now }
        evidence.unmatchedRecords = events.filter { event in
            if let skill = event.skillName { return installedSkillMap[skill.lowercased()] == nil }
            let name = event.toolName.lowercased()
            return name.hasPrefix("mcp__") && !serverNameCandidates.contains { name.hasPrefix("mcp__" + $0 + "__") }
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
                configuredServers: configuredServers,
                serverNameCandidates: serverNameCandidates,
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
        configuredServers: [ClaudeConfiguredMCPServer],
        serverNameCandidates: [String],
        events: [ClaudeObservedToolEvent]
    ) -> [CapabilityUsage] {
        var capabilities: [CapabilityID: CapabilityUsage] = [:]

        for skill in installedSkills {
            let id = CapabilityID(kind: .skill, name: skill.name)
            capabilities[id] = CapabilityUsage(id: id, usageCount: 0, installedButUnused: false)
        }

        for server in configuredServers {
            let normalized = server.name.lowercased()
            let id = CapabilityID(kind: .mcpServer, namespace: normalized, name: normalized)
            capabilities[id] = CapabilityUsage(id: id, usageCount: 0, installedButUnused: false)
        }

        var aggregatedServerUsage: [CapabilityID: CapabilityUsage] = [:]

        for event in events {
            let normalizedToolName = event.toolName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            let skillName = event.skillName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                ?? normalizedToolName
            if let canonicalSkill = installedSkillMap[skillName] {
                let id = CapabilityID(kind: .skill, name: canonicalSkill)
                capabilities[id] = merge(capabilities[id] ?? CapabilityUsage(id: id, usageCount: 0, installedButUnused: false), with: singleEventUsage(id: id, timestamp: event.timestamp, reference: event.reference))
                continue
            }

            let mcpName = normalizedToolName.hasPrefix("mcp__") ? String(normalizedToolName.dropFirst(5)) : normalizedToolName
            let separator = normalizedToolName.hasPrefix("mcp__") ? "__" : "_"
            guard let matchingServer = serverNameCandidates.first(where: { mcpName.hasPrefix($0 + separator) }) else {
                continue
            }

            let suffixIndex = mcpName.index(mcpName.startIndex, offsetBy: matchingServer.count + separator.count)
            let toolName = String(mcpName[suffixIndex...])
            guard !toolName.isEmpty else { continue }

            let toolID = CapabilityID(kind: .mcpTool, namespace: matchingServer, name: toolName)
            capabilities[toolID] = merge(capabilities[toolID] ?? CapabilityUsage(id: toolID, usageCount: 0, installedButUnused: false), with: singleEventUsage(id: toolID, timestamp: event.timestamp, reference: event.reference))

            let serverID = CapabilityID(kind: .mcpServer, namespace: matchingServer, name: matchingServer)
            aggregatedServerUsage[serverID] = merge(aggregatedServerUsage[serverID] ?? CapabilityUsage(id: serverID, usageCount: 0, installedButUnused: false), with: singleEventUsage(id: serverID, timestamp: event.timestamp, reference: event.reference))
        }

        for (serverID, usage) in aggregatedServerUsage {
            capabilities[serverID] = merge(capabilities[serverID] ?? CapabilityUsage(id: serverID, usageCount: 0, installedButUnused: false), with: usage)
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
