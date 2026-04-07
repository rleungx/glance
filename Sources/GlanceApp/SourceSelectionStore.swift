import Foundation

protocol SourceSelectionStoring: AnyObject {
    func loadSelectedSourceID() -> String?
    func saveSelectedSourceID(_ id: String?)
}

final class UserDefaultsSourceSelectionStore: SourceSelectionStoring {
    private let userDefaults: UserDefaults
    private let key: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "glance.selectedSourceID"
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func loadSelectedSourceID() -> String? {
        userDefaults.string(forKey: key)
    }

    func saveSelectedSourceID(_ id: String?) {
        userDefaults.set(id, forKey: key)
    }
}
