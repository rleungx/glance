import Foundation

public protocol CapabilityRepository: Sendable {
    func loadCapabilities() async throws -> [CapabilityUsage]
}

public protocol WindowedCapabilityRepository: CapabilityRepository {
    func loadCapabilities(windows: [RollingWindow], now: Date) async throws -> [RollingWindow: [CapabilityUsage]]
}

public protocol WarningReportingRepository: CapabilityRepository {
    func currentWarnings() async -> [String]
}
