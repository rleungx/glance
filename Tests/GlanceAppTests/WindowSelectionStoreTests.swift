import Foundation
import Testing
@testable import GlanceApp

@Test
func windowSelectionStoreRoundTripsRawValue() {
    let suiteName = "glance.window.store.\(UUID().uuidString)"
    let userDefaults = UserDefaults(suiteName: suiteName)!
    defer { userDefaults.removePersistentDomain(forName: suiteName) }

    let store = UserDefaultsWindowSelectionStore(userDefaults: userDefaults)
    store.saveSelectedWindowRawValue(14)

    #expect(store.loadSelectedWindowRawValue() == 14)
}
