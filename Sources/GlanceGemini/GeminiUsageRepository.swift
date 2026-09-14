import Foundation
import GlanceCore

public actor GeminiUsageRepository: EvidenceReportingRepository, WarningReportingRepository {
    private let configLoader: GeminiConfigLoader
    private let transcriptReader: GeminiTranscriptUsageReader
    private var warnings: [String] = []

    public init(
        configLoader: GeminiConfigLoader = GeminiConfigLoader(),
        transcriptReader: GeminiTranscriptUsageReader = GeminiTranscriptUsageReader()
    ) {
        self.configLoader = configLoader
        self.transcriptReader = transcriptReader
    }

    public func loadCapabilities() async throws -> [CapabilityUsage] {
        try await loadCapabilities(windows: [.day30], now: .now)[.day30] ?? []
    }

    public func loadUsage(windows: [RollingWindow], now: Date) async throws -> UsageLoadResult {
        let installedSkills = try configLoader.loadInstalledSkills().filter(\.enabled)
        let configuredServers = try configLoader.loadConfiguredMCPServers().filter(\.enabled)
        let installedSkillMap = Dictionary(installedSkills.map { ($0.name.lowercased(), $0.name) }, uniquingKeysWith: { first, _ in first })
        let serverNames = Set(configuredServers.map { $0.name.lowercased() })
        let serverNameCandidates = serverNames.sorted { lhs, rhs in
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }
            return lhs < rhs
        }
        let cutoffDate = windows.map { $0.cutoffDate(relativeTo: now) }.min() ?? .distantPast
        let loadResult = try transcriptReader.loadObservedEvents(since: cutoffDate)
        warnings = loadResult.skippedFilesCount > 0 ? ["Some Gemini sessions were skipped, so these results may be incomplete."] : []
        var evidence = loadResult.evidence
        evidence.sources += configLoader.existingPaths()
        if configLoader.hasUnrecognizedOutput {
            evidence.skippedRecords += 1
            evidence.completeness = .partial
            warnings.append("Gemini inventory output was not recognized; installed capabilities may be incomplete.")
        }
        let events = loadResult.events.filter { $0.timestamp <= now }
        evidence.unmatchedRecords = events.filter { event in
            let name = event.toolName.lowercased()
            if name == "activate_skill" { return event.args["name"]?.stringValue.map { installedSkillMap[$0.lowercased()] == nil } ?? true }
            return name.hasPrefix("mcp_") && parseMcpToolName(name, serverNameCandidates: serverNameCandidates) == nil
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
        installedSkills: [GeminiInstalledSkill],
        installedSkillMap: [String: String],
        configuredServers: [GeminiConfiguredMCPServer],
        serverNameCandidates: [String],
        events: [GeminiObservedToolEvent]
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

            if normalizedToolName == "activate_skill",
               let skillName = event.args["name"]?.stringValue?.lowercased(),
               let canonical = installedSkillMap[skillName] {
                let id = CapabilityID(kind: .skill, name: canonical)
                capabilities[id] = merge(capabilities[id] ?? CapabilityUsage(id: id, usageCount: 0, installedButUnused: false), with: singleEventUsage(id: id, timestamp: event.timestamp, status: event.status, reference: event.reference))
                continue
            }

            guard let parsed = parseMcpToolName(normalizedToolName, serverNameCandidates: serverNameCandidates) else {
                continue
            }

            let toolID = CapabilityID(kind: .mcpTool, namespace: parsed.serverName, name: parsed.toolName)
            capabilities[toolID] = merge(capabilities[toolID] ?? CapabilityUsage(id: toolID, usageCount: 0, installedButUnused: false), with: singleEventUsage(id: toolID, timestamp: event.timestamp, status: event.status, reference: event.reference))

            let serverID = CapabilityID(kind: .mcpServer, namespace: parsed.serverName, name: parsed.serverName)
            aggregatedServerUsage[serverID] = merge(aggregatedServerUsage[serverID] ?? CapabilityUsage(id: serverID, usageCount: 0, installedButUnused: false), with: singleEventUsage(id: serverID, timestamp: event.timestamp, status: event.status, reference: event.reference))
        }

        for (serverID, usage) in aggregatedServerUsage {
            capabilities[serverID] = merge(capabilities[serverID] ?? CapabilityUsage(id: serverID, usageCount: 0, installedButUnused: false), with: usage)
        }

        return Array(capabilities.values)
    }

    private func bucket(
        events: [GeminiObservedToolEvent],
        windows: [RollingWindow],
        now: Date
    ) -> [RollingWindow: [GeminiObservedToolEvent]] {
        let sortedWindows = windows.sorted { $0.lookbackDays < $1.lookbackDays }
        let cutoffs = Dictionary(uniqueKeysWithValues: sortedWindows.map { window in
            (window, window.cutoffDate(relativeTo: now))
        })

        var buckets: [RollingWindow: [GeminiObservedToolEvent]] = Dictionary(uniqueKeysWithValues: windows.map { ($0, []) })

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

    private func singleEventUsage(id: CapabilityID, timestamp: Date, status: GeminiToolStatus?, reference: UsageRecordReference?) -> CapabilityUsage {
        let successCount = status == .success ? 1 : 0
        let failureCount = status == .error ? 1 : 0
        return CapabilityUsage(id: id, usageCount: 1, firstUsedAt: timestamp, lastUsedAt: timestamp, successCount: successCount, failureCount: failureCount, installedButUnused: false, evidenceSamples: reference.map { [$0] })
    }

    private func parseMcpToolName(
        _ normalizedToolName: String,
        serverNameCandidates: [String]
    ) -> (serverName: String, toolName: String)? {
        guard normalizedToolName.hasPrefix("mcp_") else {
            return nil
        }
        let withoutPrefix = String(normalizedToolName.dropFirst(4))
        guard let matchingServer = serverNameCandidates.first(where: { withoutPrefix.hasPrefix($0 + "_") }) else {
            return nil
        }
        let suffixIndex = withoutPrefix.index(withoutPrefix.startIndex, offsetBy: matchingServer.count + 1)
        let toolName = String(withoutPrefix[suffixIndex...])
        guard !toolName.isEmpty else { return nil }
        return (matchingServer, toolName)
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
