import Foundation
import Testing
import GlanceCore
@testable import GlanceApp

@Test
func supportReportRoundTripsThroughJSON() throws {
    let report = makeSupportReport()
    let data = try report.jsonData()

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(GlanceSupportReport.self, from: data)

    #expect(decoded.reportVersion == GlanceSupportReport.currentReportVersion)
    #expect(decoded.generatedAt == Date(timeIntervalSince1970: 0))
    #expect(decoded.source.id == "gemini-local")
    #expect(decoded.diagnostics.readiness == .ready)
    #expect(decoded.diagnostics.artifacts.map(\.label) == ["Settings", "Sessions"])
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
        "GLANCE_GEMINI_EXECUTABLE": "/opt/homebrew/bin/gemini",
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
            "GLANCE_GEMINI_EXECUTABLE": "/opt/homebrew/bin/gemini",
            "PATH": "/usr/bin:/bin",
        ]),
        source: GlanceSources.geminiCLILocal,
        diagnostics: GlanceSourceDiagnostics(
            readiness: .ready,
            supportsRollingWindows: true,
            artifacts: [
                GlanceSourceArtifact(label: "Settings", kind: .file, displayPath: "~/.gemini/settings.json", isPresent: true),
                GlanceSourceArtifact(label: "Sessions", kind: .directory, displayPath: "~/.gemini/tmp", isPresent: true),
            ],
            summary: "Gemini data is available."
        ),
        selectedWindow: .day7,
        policy: .default,
        lastRefreshAt: Date(timeIntervalSince1970: 60),
        errorMessage: nil,
        noticeMessage: "Some Gemini sessions were skipped"
    )
}
