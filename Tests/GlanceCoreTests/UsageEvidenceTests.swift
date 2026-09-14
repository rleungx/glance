import Foundation
import Testing
@testable import GlanceCore

@Test(arguments: [UsageCompleteness.unavailable, .partial, .observed])
func unverifiedEvidenceNeverProducesCleanupSuggestions(completeness: UsageCompleteness) {
    let now = Date.now
    let evidence = UsageEvidence(completeness: completeness, filesRead: 100, verifiedFrom: .distantPast, verifiedThrough: now)
    let usages = [
        CapabilityUsage(id: CapabilityID(kind: .skill, name: "zero"), usageCount: 0, installedButUnused: true),
        CapabilityUsage(id: CapabilityID(kind: .skill, name: "old"), usageCount: 1, lastUsedAt: now.addingTimeInterval(-200 * 86_400)),
    ]
    let snapshot = CapabilityRanker.buildSnapshot(from: usages, now: now, evidence: evidence)
    #expect(snapshot.allCapabilities.count == 2)
    #expect(snapshot.stale.isEmpty)
    #expect(snapshot.removalCandidates.isEmpty)
}

@Test
func verifiedEvidenceMustCoverTheDecisionIntervalAndHaveNoLoss() {
    let now = Date.now
    let usage = CapabilityUsage(id: CapabilityID(kind: .skill, name: "old"), usageCount: 0, installedButUnused: true)
    var evidence = UsageEvidence(completeness: .verified, verifiedFrom: now.addingTimeInterval(-7 * 86_400), verifiedThrough: now)
    #expect(!CapabilityRanker.isRemovalCandidate(usage, now: now, evidence: evidence))
    evidence.verifiedFrom = .distantPast
    #expect(CapabilityRanker.isRemovalCandidate(usage, now: now, evidence: evidence))
    evidence.skippedRecords = 1
    #expect(!CapabilityRanker.isRemovalCandidate(usage, now: now, evidence: evidence))
    evidence.skippedRecords = 0
    evidence.verifiedThrough = now.addingTimeInterval(-60)
    #expect(!CapabilityRanker.isRemovalCandidate(usage, now: now, evidence: evidence))
}

@Test
func absentOutcomesAreNotPresentedAsKnownSuccess() {
    let usage = CapabilityUsage(id: CapabilityID(kind: .skill, name: "demo"), usageCount: 8)
    #expect(usage.knownSuccessRate == nil)
    let mixed = CapabilityUsage(id: usage.id, usageCount: 8, successCount: 1, failureCount: 1)
    #expect(mixed.knownSuccessRate == 0.5)
}

@Test
func transcriptDiscoveryDistinguishesMissingFromInvalidRoots() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let missing = TranscriptFiles.discover(in: [root], extensions: ["jsonl"])
    #expect(missing.files.isEmpty && missing.errors == 0)
    try Data().write(to: root)
    let invalid = TranscriptFiles.discover(in: [root], extensions: ["jsonl"])
    #expect(invalid.files.isEmpty && invalid.errors == 1)
}
