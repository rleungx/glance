import Foundation
import Testing
@testable import GlanceCore

@Test
func cleanupWindowIncludesAllRetainedHistoryWithoutChangingDisplayWindows() {
    #expect(RollingWindow.allTime.cutoffDate(relativeTo: .now) == .distantPast)
    #expect(RollingWindow.allTime.lookbackDays > RollingWindow.day120.lookbackDays)
    #expect(RollingWindow.displayCases == [.day1, .day7, .day14, .day30])
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    #expect(RollingWindow.day7.cutoffDate(relativeTo: now) == now.addingTimeInterval(-7 * 86_400))
}
