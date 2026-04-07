import Foundation
import GlanceCore

protocol WindowSelectionStoring: AnyObject {
    func loadSelectedWindowRawValue() -> Int?
    func saveSelectedWindowRawValue(_ rawValue: Int)
}

final class UserDefaultsWindowSelectionStore: WindowSelectionStoring {
    private let userDefaults: UserDefaults
    private let key: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "glance.selectedWindowRawValue"
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func loadSelectedWindowRawValue() -> Int? {
        guard userDefaults.object(forKey: key) != nil else {
            return nil
        }
        return userDefaults.integer(forKey: key)
    }

    func saveSelectedWindowRawValue(_ rawValue: Int) {
        userDefaults.set(rawValue, forKey: key)
    }
}
