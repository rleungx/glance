import Foundation
import Testing
import GlanceCore
@testable import GlanceApp

@Test
func rankingPolicyStoreRoundTripsPolicy() {
    let suiteName = "glance.policy.store.\(UUID().uuidString)"
    let userDefaults = UserDefaults(suiteName: suiteName)!
    defer { userDefaults.removePersistentDomain(forName: suiteName) }

    let store = UserDefaultsRankingPolicyStore(userDefaults: userDefaults)
    let policy = RankingPolicy(halfLifeDays: 14, staleAfterDays: 10, removalAfterDays: 20, minimumUsageToKeep: 2, neverUsedCountsAsStale: false, refreshIntervalSeconds: 120)
    store.savePolicy(policy)

    #expect(store.loadPolicy() == policy)
}
