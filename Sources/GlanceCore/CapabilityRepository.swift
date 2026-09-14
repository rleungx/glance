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

public protocol EvidenceReportingRepository: WindowedCapabilityRepository {
    func loadUsage(windows: [RollingWindow], now: Date) async throws -> UsageLoadResult
}

extension EvidenceReportingRepository {
    public func loadCapabilities(windows: [RollingWindow], now: Date) async throws -> [RollingWindow: [CapabilityUsage]] {
        try await loadUsage(windows: windows, now: now).windows
    }
}
