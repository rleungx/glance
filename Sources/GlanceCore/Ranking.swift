import Foundation

public enum CapabilityRanker {
    public static func buildSnapshot(
        from capabilities: [CapabilityUsage],
        policy: RankingPolicy = .default,
        now: Date = .now,
        evidence: UsageEvidence = UsageEvidence(),
        sourceID: String? = nil,
        window: RollingWindow? = nil
    ) -> RankingSnapshot {
        let scoreByCapability = makeScoreLookup(for: capabilities, policy: policy, now: now)
        let allCapabilities = sorted(capabilities, scoreByCapability: scoreByCapability)
        let skills = allCapabilities.filter { $0.id.kind == .skill }
        let mcpTools = allCapabilities.filter { $0.id.kind == .mcpTool }
        let mcpServers = allCapabilities.filter { $0.id.kind == .mcpServer }
        let stale = sorted(capabilities.filter { isStale($0, policy: policy, now: now, evidence: evidence) }, scoreByCapability: scoreByCapability)
        let removalCandidates = sorted(capabilities.filter { isRemovalCandidate($0, policy: policy, now: now, evidence: evidence) }, scoreByCapability: scoreByCapability)

        return RankingSnapshot(
            generatedAt: now,
            allCapabilities: allCapabilities,
            skills: skills,
            mcpTools: mcpTools,
            mcpServers: mcpServers,
            stale: stale,
            removalCandidates: removalCandidates,
            evidence: evidence,
            sourceID: sourceID,
            window: window
        )
    }

    public static func sorted(
        _ capabilities: [CapabilityUsage],
        policy: RankingPolicy = .default,
        now: Date = .now
    ) -> [CapabilityUsage] {
        let scoreByCapability = makeScoreLookup(for: capabilities, policy: policy, now: now)
        return sorted(capabilities, scoreByCapability: scoreByCapability)
    }

    private static func sorted(
        _ capabilities: [CapabilityUsage],
        scoreByCapability: [CapabilityUsage: Double]
    ) -> [CapabilityUsage] {
        capabilities.sorted { lhs, rhs in
            let lhsScore = scoreByCapability[lhs] ?? 0
            let rhsScore = scoreByCapability[rhs] ?? 0

            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }

            if lhs.usageCount != rhs.usageCount {
                return lhs.usageCount > rhs.usageCount
            }

            switch (lhs.lastUsedAt, rhs.lastUsedAt) {
            case let (.some(left), .some(right)) where left != right:
                return left > right
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            default:
                break
            }

            return lhs.id.displayName.localizedCaseInsensitiveCompare(rhs.id.displayName) == .orderedAscending
        }
    }

    private static func makeScoreLookup(
        for capabilities: [CapabilityUsage],
        policy: RankingPolicy,
        now: Date
    ) -> [CapabilityUsage: Double] {
        var lookup: [CapabilityUsage: Double] = [:]
        lookup.reserveCapacity(capabilities.count)
        for capability in capabilities {
            lookup[capability] = score(for: capability, policy: policy, now: now)
        }
        return lookup
    }

    public static func score(
        for capability: CapabilityUsage,
        policy: RankingPolicy = .default,
        now: Date = .now
    ) -> Double {
        guard capability.usageCount > 0 else { return 0 }
        let daysSinceLastUse = max(0, daysBetween(capability.lastUsedAt ?? capability.firstUsedAt ?? now, and: now))
        let recencyFactor = pow(0.5, daysSinceLastUse / max(policy.halfLifeDays, 1))
        let qualityWeight = max(0.3, capability.successRate)
        return Double(capability.usageCount) * recencyFactor * qualityWeight
    }

    public static func isStale(
        _ capability: CapabilityUsage,
        policy: RankingPolicy = .default,
        now: Date = .now,
        evidence: UsageEvidence = UsageEvidence()
    ) -> Bool {
        guard evidence.covers(since: now.addingTimeInterval(-Double(policy.staleAfterDays) * 86_400), through: now) else { return false }
        if capability.usageCount == 0 {
            return policy.neverUsedCountsAsStale && capability.installedButUnused
        }

        guard let lastUsedAt = capability.lastUsedAt ?? capability.firstUsedAt else {
            return policy.neverUsedCountsAsStale
        }

        return daysBetween(lastUsedAt, and: now) >= Double(policy.staleAfterDays)
    }

    public static func isRemovalCandidate(
        _ capability: CapabilityUsage,
        policy: RankingPolicy = .default,
        now: Date = .now,
        evidence: UsageEvidence = UsageEvidence()
    ) -> Bool {
        guard evidence.covers(since: now.addingTimeInterval(-Double(policy.removalAfterDays) * 86_400), through: now) else { return false }
        if capability.usageCount == 0 {
            return capability.installedButUnused
        }

        guard let lastUsedAt = capability.lastUsedAt ?? capability.firstUsedAt else {
            return false
        }

        let staleForRemoval = daysBetween(lastUsedAt, and: now) >= Double(policy.removalAfterDays)
        let underUsed = capability.usageCount < policy.minimumUsageToKeep
        let failureHeavy = capability.failureCount > capability.successCount && capability.failureCount > 0
        return staleForRemoval && (underUsed || failureHeavy)
    }

    private static func daysBetween(_ start: Date, and end: Date) -> Double {
        max(0, end.timeIntervalSince(start) / 86_400)
    }
}
