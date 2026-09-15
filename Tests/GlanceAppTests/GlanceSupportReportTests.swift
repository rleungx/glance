import Foundation
import Testing
import GlanceCore
@testable import GlanceApp

@Test
func supportReportQualityOmitsTranscriptPathsAndContent() throws {
    let quality = GlanceSupportReport.DataQuality(UsageEvidence(completeness: .partial,
        sources: ["/private-transcript/session.jsonl"], filesRead: 2, skippedRecords: 3, duplicates: 1))
    let data = try JSONEncoder().encode(quality)
    let json = String(decoding: data, as: UTF8.self)
    #expect(!json.contains("private-transcript"))
    #expect(quality.skippedRecords == 3)
    #expect(try JSONDecoder().decode(GlanceSupportReport.DataQuality.self, from: data) == quality)
}

@Test
func supportReportRoundTripsThroughJSON() throws {
    let report = makeSupportReport()
    let data = try report.jsonData()

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(GlanceSupportReport.self, from: data)

    #expect(decoded.reportVersion == GlanceSupportReport.currentReportVersion)
    #expect(decoded.generatedAt == Date(timeIntervalSince1970: 0))
    #expect(decoded.source.id == "antigravity-local")
    #expect(decoded.diagnostics.readiness == .ready)
    #expect(decoded.diagnostics.artifacts.map(\.label) == ["Application skills", "IDE skills"])
    #expect(decoded.diagnostics.usageSupport == .inventoryOnly)
    #expect(!decoded.diagnostics.supportsRollingWindows)
    #expect(decoded.selectedWindow == .day7)
    #expect(decoded.policy == RankingPolicy.default)
}

@Test
func supportReportEncodesDatesAsISO8601Strings() throws {
    let json = try makeSupportReport().jsonString()
    #expect(json.contains("1970-01-01T00:00:00Z"))
}

@Test
func supportReportBuildsTimestampedSuggestedFilename() {
    let filename = makeSupportReport().suggestedFilename()
    #expect(filename == "glance-support-report-1970-01-01-000000.json")
}

@Test
func supportReportFiltersEnvironmentToAllowListOnly() {
    let filtered = GlanceSupportReport.filteredEnvironment([
        "GLANCE_GEMINI_EXECUTABLE": "/opt/homebrew/bin/gemini",
        "GLANCE_SPARKLE_FEED_URL": "https://updates.example.org/appcast.xml?channel=stable#fragment",
        "PATH": "/usr/bin:/bin",
        "SECRET": "nope",
    ])

    #expect(filtered == [
        "GLANCE_SPARKLE_FEED_URL": "https://updates.example.org",
    ])
}

@Test
func supportReportRedactsInvalidFeedURLValues() {
    let filtered = GlanceSupportReport.filteredEnvironment([
        "GLANCE_SPARKLE_FEED_URL": "not a valid url",
    ])

    #expect(filtered == [
        "GLANCE_SPARKLE_FEED_URL": "redacted-invalid-url",
    ])
}

private func makeSupportReport() -> GlanceSupportReport {
    GlanceSupportReport(
        generatedAt: Date(timeIntervalSince1970: 0),
        app: .init(name: "Glance", version: "1.0.0", bundleIdentifier: "com.example.Glance"),
        system: .init(operatingSystemVersion: "macOS 14.0", localeIdentifier: "en_US", timeZoneIdentifier: "Asia/Shanghai"),
        environment: GlanceSupportReport.filteredEnvironment([
            "GLANCE_SPARKLE_FEED_URL": "https://updates.example.org/appcast.xml",
            "PATH": "/usr/bin:/bin",
        ]),
        source: GlanceSources.antigravityLocal,
        diagnostics: GlanceSourceDiagnostics(
            readiness: .ready,
            supportsRollingWindows: false,
            artifacts: [
                GlanceSourceArtifact(label: "Application skills", kind: .directory, displayPath: "~/.gemini/config/skills", isPresent: true),
                GlanceSourceArtifact(label: "IDE skills", kind: .directory, displayPath: "~/.gemini/antigravity/skills", isPresent: true),
            ],
            summary: "Global Antigravity skill definitions only.",
            usageSupport: .inventoryOnly
        ),
        selectedWindow: .day7,
        policy: .default,
        lastRefreshAt: Date(timeIntervalSince1970: 60),
        errorMessage: nil,
        noticeMessage: "Usage statistics are not available"
    )
}
