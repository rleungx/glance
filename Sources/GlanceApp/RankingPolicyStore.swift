import Foundation
import GlanceCore

protocol RankingPolicyStoring: AnyObject {
    func loadPolicy() -> RankingPolicy?
    func savePolicy(_ policy: RankingPolicy)
}

final class UserDefaultsRankingPolicyStore: RankingPolicyStoring {
    private let userDefaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "glance.rankingPolicy.v1"
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func loadPolicy() -> RankingPolicy? {
        guard let data = userDefaults.data(forKey: key) else {
            return nil
        }
        return try? decoder.decode(RankingPolicy.self, from: data)
    }

    func savePolicy(_ policy: RankingPolicy) {
        guard let data = try? encoder.encode(policy) else {
            return
        }
        userDefaults.set(data, forKey: key)
    }
}
