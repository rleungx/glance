import Foundation
import GlanceCore

public actor ClaudeUsageRepository: WindowedCapabilityRepository, WarningReportingRepository {
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

    public func loadCapabilities(windows: [RollingWindow], now: Date) async throws -> [RollingWindow: [CapabilityUsage]] {
        let installedSkills = try configLoader.loadInstalledSkills()
        let configuredServers = try configLoader.loadConfiguredMCPServers().filter(\.enabled)
        let installedSkillMap = Dictionary(uniqueKeysWithValues: installedSkills.map { ($0.name.lowercased(), $0.name) })
        let serverNames = Set(configuredServers.map { $0.name.lowercased() })
        let serverNameCandidates = serverNames.sorted { $0.count > $1.count }
        let maxWindow = windows.map(\.rawValue).max() ?? 30
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -maxWindow, to: now) ?? now
        let loadResult = try transcriptReader.loadObservedEvents(since: cutoffDate)
        warnings = loadResult.skippedFilesCount > 0 ? ["Some Claude transcripts were skipped, so these results may be incomplete."] : []
        let eventsByWindow = bucket(events: loadResult.events, windows: windows, now: now)

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
        return output
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
            capabilities[id] = CapabilityUsage(id: id, usageCount: 0, installedButUnused: true)
        }

        for server in configuredServers {
            let normalized = server.name.lowercased()
            let id = CapabilityID(kind: .mcpServer, namespace: normalized, name: normalized)
            capabilities[id] = CapabilityUsage(id: id, usageCount: 0, installedButUnused: true)
        }

        var aggregatedServerUsage: [CapabilityID: CapabilityUsage] = [:]

        for event in events {
            let normalizedToolName = event.toolName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            if let canonicalSkill = installedSkillMap[normalizedToolName] {
                let id = CapabilityID(kind: .skill, name: canonicalSkill)
                capabilities[id] = merge(capabilities[id] ?? CapabilityUsage(id: id, usageCount: 0, installedButUnused: true), with: singleEventUsage(id: id, timestamp: event.timestamp))
                continue
            }

            guard let matchingServer = serverNameCandidates.first(where: { normalizedToolName.hasPrefix($0 + "_") }) else {
                continue
            }

            let suffixIndex = normalizedToolName.index(normalizedToolName.startIndex, offsetBy: matchingServer.count + 1)
            let toolName = String(normalizedToolName[suffixIndex...])
            guard !toolName.isEmpty else { continue }

            let toolID = CapabilityID(kind: .mcpTool, namespace: matchingServer, name: toolName)
            capabilities[toolID] = merge(capabilities[toolID] ?? CapabilityUsage(id: toolID, usageCount: 0, installedButUnused: true), with: singleEventUsage(id: toolID, timestamp: event.timestamp))

            let serverID = CapabilityID(kind: .mcpServer, namespace: matchingServer, name: matchingServer)
            aggregatedServerUsage[serverID] = merge(aggregatedServerUsage[serverID] ?? CapabilityUsage(id: serverID, usageCount: 0, installedButUnused: true), with: singleEventUsage(id: serverID, timestamp: event.timestamp))
        }

        for (serverID, usage) in aggregatedServerUsage {
            capabilities[serverID] = merge(capabilities[serverID] ?? CapabilityUsage(id: serverID, usageCount: 0, installedButUnused: true), with: usage)
        }

        return Array(capabilities.values)
    }

    private func bucket(
        events: [ClaudeObservedToolEvent],
        windows: [RollingWindow],
        now: Date
    ) -> [RollingWindow: [ClaudeObservedToolEvent]] {
        let sortedWindows = windows.sorted { $0.rawValue < $1.rawValue }
        let cutoffs = Dictionary(uniqueKeysWithValues: sortedWindows.map { window in
            (window, Calendar.current.date(byAdding: .day, value: -window.rawValue, to: now) ?? now)
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

    private func singleEventUsage(id: CapabilityID, timestamp: Date) -> CapabilityUsage {
        CapabilityUsage(id: id, usageCount: 1, firstUsedAt: timestamp, lastUsedAt: timestamp, installedButUnused: false)
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
