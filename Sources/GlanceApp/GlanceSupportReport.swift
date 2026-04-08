import Foundation
import GlanceCore

struct GlanceSupportReport: Codable, Equatable {
    static let currentReportVersion = 1

    struct AppInfo: Codable, Equatable {
        let name: String
        let version: String
        let bundleIdentifier: String?
    }

    struct SystemInfo: Codable, Equatable {
        let operatingSystemVersion: String
        let localeIdentifier: String
        let timeZoneIdentifier: String
    }

    let reportVersion: Int
    let generatedAt: Date
    let app: AppInfo
    let system: SystemInfo
    let environment: [String: String]
    let source: GlanceSource
    let diagnostics: GlanceSourceDiagnostics
    let selectedWindow: RollingWindow
    let policy: RankingPolicy
    let lastRefreshAt: Date?
    let errorMessage: String?
    let noticeMessage: String?

    init(
        generatedAt: Date,
        app: AppInfo,
        system: SystemInfo,
        environment: [String: String],
        source: GlanceSource,
        diagnostics: GlanceSourceDiagnostics,
        selectedWindow: RollingWindow,
        policy: RankingPolicy,
        lastRefreshAt: Date?,
        errorMessage: String?,
        noticeMessage: String?
    ) {
        self.reportVersion = Self.currentReportVersion
        self.generatedAt = generatedAt
        self.app = app
        self.system = system
        self.environment = environment
        self.source = source
        self.diagnostics = diagnostics
        self.selectedWindow = selectedWindow
        self.policy = policy
        self.lastRefreshAt = lastRefreshAt
        self.errorMessage = errorMessage
        self.noticeMessage = noticeMessage
    }

    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    func jsonString() throws -> String {
        let data = try jsonData()
        guard let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return string
    }

    func suggestedFilename() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "glance-support-report-\(formatter.string(from: generatedAt)).json"
    }

    static func filteredEnvironment(_ environment: [String: String]) -> [String: String] {
        let allowedKeys = ["GLANCE_GEMINI_EXECUTABLE", "GLANCE_SPARKLE_FEED_URL"]
        return allowedKeys.reduce(into: [String: String]()) { partialResult, key in
            guard let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                return
            }
            partialResult[key] = sanitizedEnvironmentValue(key: key, value: value)
        }
    }

    private static func sanitizedEnvironmentValue(key: String, value: String) -> String {
        guard key == "GLANCE_SPARKLE_FEED_URL" else {
            return value
        }

        guard let components = URLComponents(string: value), let scheme = components.scheme, let host = components.host else {
            return "redacted-invalid-url"
        }

        return "\(scheme)://\(host)"
    }
}
