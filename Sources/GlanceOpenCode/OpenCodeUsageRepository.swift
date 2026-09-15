import Foundation
import GlanceCore

public actor OpenCodeUsageRepository: EvidenceReportingRepository {
    private let configLoader: OpenCodeConfigLoader
    private let usageReader: OpenCodeUsageReader

    public init(
        configLoader: OpenCodeConfigLoader = OpenCodeConfigLoader(),
        usageReader: OpenCodeUsageReader = OpenCodeUsageReader()
    ) {
        self.configLoader = configLoader
        self.usageReader = usageReader
    }

    public func loadCapabilities() async throws -> [CapabilityUsage] {
        try await loadCapabilities(windows: [.day30], now: .now)[.day30] ?? []
    }

    public func loadUsage(windows: [RollingWindow], now: Date) async throws -> UsageLoadResult {
        let installedSkills = try configLoader.loadInstalledSkills()
        let installedSkillNameMap = Dictionary(
            installedSkills.map {
                ($0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), $0.name)
            }, uniquingKeysWith: { first, _ in first }
        )
        let observations = try usageReader.loadObservedCapabilities(windows: windows, now: now)
        var output: [RollingWindow: [CapabilityUsage]] = [:]
        for window in windows {
            let observedUsages = observations[window] ?? []
            output[window] = buildCapabilities(
                installedSkills: installedSkills,
                installedSkillNameMap: installedSkillNameMap,
                observedUsages: observedUsages
            )
        }

        var evidence = UsageEvidence(sources: configLoader.evidenceSources, filesRead: usageReader.databaseExists ? 1 : 0)
        evidence.finish(timestamps: output.values.flatMap { usages in usages.flatMap { [$0.firstUsedAt, $0.lastUsedAt].compactMap { $0 } } })
        return UsageLoadResult(windows: output, evidence: evidence)
    }

    private func buildCapabilities(
        installedSkills: [InstalledSkill],
        installedSkillNameMap: [String: String],
        observedUsages: [ObservedCapabilityUsage]
    ) -> [CapabilityUsage] {

        var capabilities: [CapabilityID: CapabilityUsage] = [:]

        for skill in installedSkills {
            let id = CapabilityID(kind: .skill, name: skill.name)
            capabilities[id] = CapabilityUsage(id: id, usageCount: 0, installedButUnused: false)
        }

        for observed in observedUsages {
            var usage = observed.usage

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
                installedButUnused: usage.installedButUnused,
                evidenceSamples: usage.evidenceSamples
            )

            if let existing = capabilities[usage.id] {
                capabilities[usage.id] = merge(existing, with: usage)
            } else {
                capabilities[usage.id] = usage
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
            installedButUnused: false,
            evidenceSamples: Array(((lhs.evidenceSamples ?? []) + (rhs.evidenceSamples ?? [])).prefix(5))
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
