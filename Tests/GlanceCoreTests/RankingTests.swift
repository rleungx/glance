import Foundation
import Testing
@testable import GlanceCore

@Test
func rankingPrefersHigherUsageThenMoreRecentActivity() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    let newer = CapabilityUsage(
        id: CapabilityID(kind: .skill, name: "newer"),
        usageCount: 3,
        firstUsedAt: now.addingTimeInterval(-10_000),
        lastUsedAt: now.addingTimeInterval(-1_000),
        successCount: 3
    )

    let heavier = CapabilityUsage(
        id: CapabilityID(kind: .skill, name: "heavier"),
        usageCount: 5,
        firstUsedAt: now.addingTimeInterval(-20_000),
        lastUsedAt: now.addingTimeInterval(-15_000),
        successCount: 5
    )

    let ranked = CapabilityRanker.sorted([newer, heavier], now: now)
    #expect(ranked.map(\.id.name) == ["heavier", "newer"])
}

@Test
func staleAndRemovalClassificationUsePolicyThresholds() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let policy = RankingPolicy(staleAfterDays: 30, removalAfterDays: 45, minimumUsageToKeep: 3)

    let staleSkill = CapabilityUsage(
        id: CapabilityID(kind: .skill, name: "old-skill"),
        usageCount: 2,
        firstUsedAt: now.addingTimeInterval(-60 * 86_400),
        lastUsedAt: now.addingTimeInterval(-50 * 86_400),
        successCount: 2
    )

    let evidence = UsageEvidence(completeness: .verified, verifiedFrom: .distantPast, verifiedThrough: now)
    #expect(CapabilityRanker.isStale(staleSkill, policy: policy, now: now, evidence: evidence))
    #expect(CapabilityRanker.isRemovalCandidate(staleSkill, policy: policy, now: now, evidence: evidence))
}

@Test
func installedButUnusedCapabilitiesRequireVerifiedCoverage() {
    let unused = CapabilityUsage(
        id: CapabilityID(kind: .mcpServer, namespace: "mem0-mcp", name: "mem0-mcp"),
        usageCount: 0,
        installedButUnused: true
    )

    #expect(!CapabilityRanker.isStale(unused))
    #expect(!CapabilityRanker.isRemovalCandidate(unused))
    let now = Date.now
    let evidence = UsageEvidence(completeness: .verified, verifiedFrom: .distantPast, verifiedThrough: now)
    #expect(CapabilityRanker.isStale(unused, now: now, evidence: evidence))
    #expect(CapabilityRanker.isRemovalCandidate(unused, now: now, evidence: evidence))
}

@Test
func snapshotCategoryOrderingMatchesDirectSortedResults() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let capabilities = [
        CapabilityUsage(id: CapabilityID(kind: .skill, name: "beta"), usageCount: 2, firstUsedAt: now.addingTimeInterval(-20_000), lastUsedAt: now.addingTimeInterval(-10_000), successCount: 2),
        CapabilityUsage(id: CapabilityID(kind: .skill, name: "alpha"), usageCount: 5, firstUsedAt: now.addingTimeInterval(-30_000), lastUsedAt: now.addingTimeInterval(-5_000), successCount: 5),
        CapabilityUsage(id: CapabilityID(kind: .mcpServer, namespace: "mem0-mcp", name: "mem0-mcp"), usageCount: 1, firstUsedAt: now.addingTimeInterval(-4_000), lastUsedAt: now.addingTimeInterval(-4_000), successCount: 1),
        CapabilityUsage(id: CapabilityID(kind: .mcpTool, namespace: "mem0-mcp", name: "get_memories"), usageCount: 1, firstUsedAt: now.addingTimeInterval(-4_000), lastUsedAt: now.addingTimeInterval(-4_000), successCount: 1),
        CapabilityUsage(id: CapabilityID(kind: .skill, name: "unused"), usageCount: 0, installedButUnused: true),
    ]

    let snapshot = CapabilityRanker.buildSnapshot(from: capabilities, now: now)

    #expect(snapshot.skills.map(\.id.id) == CapabilityRanker.sorted(capabilities.filter { $0.id.kind == .skill }, now: now).map(\.id.id))
    #expect(snapshot.mcpServers.map(\.id.id) == CapabilityRanker.sorted(capabilities.filter { $0.id.kind == .mcpServer }, now: now).map(\.id.id))
    #expect(snapshot.mcpTools.map(\.id.id) == CapabilityRanker.sorted(capabilities.filter { $0.id.kind == .mcpTool }, now: now).map(\.id.id))
    #expect(snapshot.stale.map(\.id.id) == CapabilityRanker.sorted(capabilities.filter { CapabilityRanker.isStale($0, now: now) }, now: now).map(\.id.id))
    #expect(snapshot.removalCandidates.map(\.id.id) == CapabilityRanker.sorted(capabilities.filter { CapabilityRanker.isRemovalCandidate($0, now: now) }, now: now).map(\.id.id))
}

@Test
func rankingHandlesDuplicateCapabilityIDsWithoutCrashing() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let capabilities = [
        CapabilityUsage(id: CapabilityID(kind: .skill, name: "shared"), usageCount: 1, firstUsedAt: now.addingTimeInterval(-5_000), lastUsedAt: now.addingTimeInterval(-5_000), successCount: 1),
        CapabilityUsage(id: CapabilityID(kind: .skill, name: "shared"), usageCount: 3, firstUsedAt: now.addingTimeInterval(-2_000), lastUsedAt: now.addingTimeInterval(-2_000), successCount: 3),
    ]

    let ranked = CapabilityRanker.sorted(capabilities, now: now)
    let snapshot = CapabilityRanker.buildSnapshot(from: capabilities, now: now)

    #expect(ranked.count == 2)
    #expect(snapshot.skills.count == 2)
    #expect(ranked.first?.usageCount == 3)
}

@Test
func capabilityUsageDistinguishesUnknownOutcomeFromSuccessfulOutcome() {
    let unknown = CapabilityUsage(id: CapabilityID(kind: .skill, name: "unknown"), usageCount: 1)
    let successful = CapabilityUsage(id: CapabilityID(kind: .skill, name: "successful"), usageCount: 1, successCount: 1)

    #expect(unknown.hasOutcomeData == false)
    #expect(successful.hasOutcomeData == true)
    #expect(unknown.successRate == 1)
    #expect(successful.successRate == 1)
}
