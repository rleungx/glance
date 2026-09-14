import Foundation

public enum CapabilityKind: String, Codable, CaseIterable, Sendable {
    case skill
    case mcpTool
    case mcpServer
}

public struct CapabilityID: Hashable, Codable, Identifiable, Sendable {
    public let kind: CapabilityKind
    public let namespace: String
    public let name: String

    public init(kind: CapabilityKind, namespace: String = "", name: String) {
        self.kind = kind
        self.namespace = namespace.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var rawValue: String {
        [kind.rawValue, namespace, name].joined(separator: ":")
    }

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch kind {
        case .skill:
            return name
        case .mcpTool:
            return namespace.isEmpty ? name : "\(namespace).\(name)"
        case .mcpServer:
            return namespace.isEmpty ? name : namespace
        }
    }
}

public struct CapabilityUsage: Identifiable, Codable, Hashable, Sendable {
    public let id: CapabilityID
    public let usageCount: Int
    public let firstUsedAt: Date?
    public let lastUsedAt: Date?
    public let successCount: Int
    public let failureCount: Int
    public let avgLatencyMs: Double?
    public let installedButUnused: Bool
    public let evidenceSamples: [UsageRecordReference]?

    public init(
        id: CapabilityID,
        usageCount: Int,
        firstUsedAt: Date? = nil,
        lastUsedAt: Date? = nil,
        successCount: Int = 0,
        failureCount: Int = 0,
        avgLatencyMs: Double? = nil,
        installedButUnused: Bool = false,
        evidenceSamples: [UsageRecordReference]? = nil
    ) {
        self.id = id
        self.usageCount = usageCount
        self.firstUsedAt = firstUsedAt
        self.lastUsedAt = lastUsedAt
        self.successCount = successCount
        self.failureCount = failureCount
        self.avgLatencyMs = avgLatencyMs
        self.installedButUnused = installedButUnused
        self.evidenceSamples = evidenceSamples
    }

    public var successRate: Double {
        let total = successCount + failureCount
        guard total > 0 else { return 1 }
        return Double(successCount) / Double(total)
    }

    public var knownSuccessRate: Double? { hasOutcomeData ? successRate : nil }

    public var hasOutcomeData: Bool {
        (successCount + failureCount) > 0
    }

    public var totalFailures: Int {
        failureCount
    }
}

public struct RankingPolicy: Codable, Hashable, Sendable {
    public var halfLifeDays: Double
    public var staleAfterDays: Int
    public var removalAfterDays: Int
    public var minimumUsageToKeep: Int
    public var neverUsedCountsAsStale: Bool
    public var refreshIntervalSeconds: TimeInterval

    public init(
        halfLifeDays: Double = 7,
        staleAfterDays: Int = 30,
        removalAfterDays: Int = 45,
        minimumUsageToKeep: Int = 3,
        neverUsedCountsAsStale: Bool = true,
        refreshIntervalSeconds: TimeInterval = 300
    ) {
        self.halfLifeDays = halfLifeDays
        self.staleAfterDays = staleAfterDays
        self.removalAfterDays = removalAfterDays
        self.minimumUsageToKeep = minimumUsageToKeep
        self.neverUsedCountsAsStale = neverUsedCountsAsStale
        self.refreshIntervalSeconds = refreshIntervalSeconds
    }

    public static let `default` = RankingPolicy()
}

public struct RankingSnapshot: Sendable {
    public let generatedAt: Date
    public let evidence: UsageEvidence
    public let sourceID: String?
    public let window: RollingWindow?
    public let allCapabilities: [CapabilityUsage]
    public let skills: [CapabilityUsage]
    public let mcpTools: [CapabilityUsage]
    public let mcpServers: [CapabilityUsage]
    public let stale: [CapabilityUsage]
    public let removalCandidates: [CapabilityUsage]

    public init(
        generatedAt: Date,
        allCapabilities: [CapabilityUsage],
        skills: [CapabilityUsage],
        mcpTools: [CapabilityUsage],
        mcpServers: [CapabilityUsage],
        stale: [CapabilityUsage],
        removalCandidates: [CapabilityUsage],
        evidence: UsageEvidence = UsageEvidence(),
        sourceID: String? = nil,
        window: RollingWindow? = nil
    ) {
        self.generatedAt = generatedAt
        self.evidence = evidence
        self.sourceID = sourceID
        self.window = window
        self.allCapabilities = allCapabilities
        self.skills = skills
        self.mcpTools = mcpTools
        self.mcpServers = mcpServers
        self.stale = stale
        self.removalCandidates = removalCandidates
    }

    public static let empty = RankingSnapshot(
        generatedAt: .distantPast,
        allCapabilities: [],
        skills: [],
        mcpTools: [],
        mcpServers: [],
        stale: [],
        removalCandidates: []
    )
}
