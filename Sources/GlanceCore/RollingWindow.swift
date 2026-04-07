import Foundation

public enum RollingWindow: Int, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case day1 = 1
    case day7 = 7
    case day14 = 14
    case day30 = 30
    case day45 = 45
    case day60 = 60
    case day90 = 90
    case day120 = 120

    public var id: Int { rawValue }

    public var title: String {
        "\(rawValue)d"
    }

    public static var displayCases: [RollingWindow] {
        [.day1, .day7, .day14, .day30]
    }

    public static var hiddenCleanupCases: [RollingWindow] {
        [.day45, .day60, .day90, .day120]
    }
}
