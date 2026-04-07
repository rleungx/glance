import Foundation
import GlanceCore

public actor OpenCodeUsageRepository: WindowedCapabilityRepository {
    private let configLoader: OpenCodeConfigLoader
    private let usageReader: OpenCodeUsageReader
    private let mcpServerNameProvider: any OpenCodeMCPServerNameProviding

    public init(
        configLoader: OpenCodeConfigLoader = OpenCodeConfigLoader(),
        usageReader: OpenCodeUsageReader = OpenCodeUsageReader(),
        mcpServerNameProvider: any OpenCodeMCPServerNameProviding = OpenCodeRuntimeMCPServerNameProvider()
    ) {
        self.configLoader = configLoader
        self.usageReader = usageReader
        self.mcpServerNameProvider = mcpServerNameProvider
    }

    public func loadCapabilities() async throws -> [CapabilityUsage] {
        try await loadCapabilities(windows: [.day30], now: .now)[.day30] ?? []
    }

    public func loadCapabilities(windows: [RollingWindow], now: Date) async throws -> [RollingWindow: [CapabilityUsage]] {
        let installedSkills = try configLoader.loadInstalledSkills()
        let installedSkillNameMap = Dictionary(
            uniqueKeysWithValues: installedSkills.map {
                ($0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), $0.name)
            }
        )
        let configuredServers = try configLoader.loadConfiguredMCPServers().filter(\.enabled)
        let fallbackServerNames = Set(configuredServers.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let effectiveServerNames: Set<String>
        if configLoader.hasMCPConfiguration() {
            effectiveServerNames = fallbackServerNames
        } else {
            effectiveServerNames = try await mcpServerNameProvider.loadServerNames()
        }

        var output: [RollingWindow: [CapabilityUsage]] = [:]
        for window in windows {
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -window.rawValue, to: now) ?? now
            let observedUsages = try usageReader.loadObservedCapabilities(mcpServerNames: effectiveServerNames, since: cutoffDate)
            output[window] = buildCapabilities(
                installedSkills: installedSkills,
                installedSkillNameMap: installedSkillNameMap,
                effectiveServerNames: effectiveServerNames,
                observedUsages: observedUsages
            )
        }

        return output
    }

    private func buildCapabilities(
        installedSkills: [InstalledSkill],
        installedSkillNameMap: [String: String],
        effectiveServerNames: Set<String>,
        observedUsages: [ObservedCapabilityUsage]
    ) -> [CapabilityUsage] {

        var capabilities: [CapabilityID: CapabilityUsage] = [:]

        for skill in installedSkills {
            let id = CapabilityID(kind: .skill, name: skill.name)
            capabilities[id] = CapabilityUsage(id: id, usageCount: 0, installedButUnused: true)
        }

        for serverName in effectiveServerNames.sorted() {
            let id = CapabilityID(kind: .mcpServer, namespace: serverName, name: serverName)
            capabilities[id] = CapabilityUsage(id: id, usageCount: 0, installedButUnused: true)
        }

        var serverAccumulators: [CapabilityID: CapabilityUsage] = [:]

        for observed in observedUsages {
            var usage = observed.usage

            if usage.id.kind == .skill {
                let normalizedSkillName = usage.id.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard let canonicalSkillName = installedSkillNameMap[normalizedSkillName] else {
                    continue
                }
                usage = CapabilityUsage(
                    id: CapabilityID(kind: .skill, name: canonicalSkillName),
                    usageCount: usage.usageCount,
                    firstUsedAt: usage.firstUsedAt,
                    lastUsedAt: usage.lastUsedAt,
                    successCount: usage.successCount,
                    failureCount: usage.failureCount,
                    avgLatencyMs: usage.avgLatencyMs,
                    installedButUnused: usage.installedButUnused
                )
            }

            if usage.id.kind == .mcpTool {
                let normalizedServerName = usage.id.namespace.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard effectiveServerNames.contains(normalizedServerName) else {
                    continue
                }
            }

            if let existing = capabilities[usage.id] {
                capabilities[usage.id] = merge(existing, with: usage)
            } else {
                capabilities[usage.id] = usage
            }

            if usage.id.kind == .mcpTool, let serverName = observed.serverName {
                let serverID = CapabilityID(kind: .mcpServer, namespace: serverName, name: serverName)
                let serverUsage = CapabilityUsage(
                    id: serverID,
                    usageCount: usage.usageCount,
                    firstUsedAt: usage.firstUsedAt,
                    lastUsedAt: usage.lastUsedAt,
                    successCount: usage.successCount,
                    failureCount: usage.failureCount,
                    avgLatencyMs: usage.avgLatencyMs,
                    installedButUnused: false
                )
                if let existing = serverAccumulators[serverID] {
                    serverAccumulators[serverID] = merge(existing, with: serverUsage)
                } else {
                    serverAccumulators[serverID] = serverUsage
                }
            }
        }

        for (serverID, aggregate) in serverAccumulators {
            if let existing = capabilities[serverID] {
                capabilities[serverID] = merge(existing, with: aggregate)
            } else {
                capabilities[serverID] = aggregate
            }
        }

        return Array(capabilities.values)
    }

    private func merge(_ lhs: CapabilityUsage, with rhs: CapabilityUsage) -> CapabilityUsage {
        precondition(lhs.id == rhs.id, "Can only merge matching capabilities")

        let totalCount = lhs.usageCount + rhs.usageCount
        let weightedLatency = averageLatency(lhs: lhs, rhs: rhs, totalCount: totalCount)

        return CapabilityUsage(
            id: lhs.id,
            usageCount: totalCount,
            firstUsedAt: minDate(lhs.firstUsedAt, rhs.firstUsedAt),
            lastUsedAt: maxDate(lhs.lastUsedAt, rhs.lastUsedAt),
            successCount: lhs.successCount + rhs.successCount,
            failureCount: lhs.failureCount + rhs.failureCount,
            avgLatencyMs: weightedLatency,
            installedButUnused: totalCount == 0 && (lhs.installedButUnused || rhs.installedButUnused)
        )
    }

    private func minDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (.some(left), .some(right)):
            return min(left, right)
        case let (.some(left), nil):
            return left
        case let (nil, .some(right)):
            return right
        case (nil, nil):
            return nil
        }
    }

    private func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (.some(left), .some(right)):
            return max(left, right)
        case let (.some(left), nil):
            return left
        case let (nil, .some(right)):
            return right
        case (nil, nil):
            return nil
        }
    }

    private func averageLatency(lhs: CapabilityUsage, rhs: CapabilityUsage, totalCount: Int) -> Double? {
        guard totalCount > 0 else { return nil }

        let lhsWeighted = (lhs.avgLatencyMs ?? 0) * Double(lhs.usageCount)
        let rhsWeighted = (rhs.avgLatencyMs ?? 0) * Double(rhs.usageCount)
        let hasLatency = lhs.avgLatencyMs != nil || rhs.avgLatencyMs != nil
        return hasLatency ? (lhsWeighted + rhsWeighted) / Double(totalCount) : nil
    }
}
