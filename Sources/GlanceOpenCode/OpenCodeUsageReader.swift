import Foundation
import GlanceCore

public final class OpenCodeUsageReader {
    private let paths: OpenCodePaths
    private let fileManager: FileManager

    public init(paths: OpenCodePaths = .live, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    public func loadObservedCapabilities() throws -> [ObservedCapabilityUsage] {
        try loadObservedCapabilities(since: nil)
    }

    public var databaseExists: Bool { fileManager.fileExists(atPath: paths.databaseURL.path) }

    public func loadObservedCapabilities(windows: [RollingWindow], now: Date) throws -> [RollingWindow: [ObservedCapabilityUsage]] {
        guard databaseExists else { return Dictionary(uniqueKeysWithValues: Set(windows).map { ($0, []) }) }
        let connection = try SQLiteConnection(url: paths.databaseURL, mode: .readOnly)
        try connection.execute("BEGIN")
        defer { try? connection.execute("ROLLBACK") }
        try validateSchema(using: connection)
        let hasID = try connection.columnNames(for: "part").contains("id")
        var result: [RollingWindow: [ObservedCapabilityUsage]] = [:]
        for window in Set(windows) {
            let cutoff = window == .allTime ? nil : window.cutoffDate(relativeTo: now)
            let rows = try connection.query(Self.usageQuery(cutoffDate: cutoff, through: now, hasID: hasID))
            result[window] = rows.compactMap { Self.parseObservedUsage(from: $0, file: paths.databaseURL.path) }
        }
        return result
    }

    public func loadObservedCapabilities(since cutoffDate: Date?) throws -> [ObservedCapabilityUsage] {
        guard fileManager.fileExists(atPath: paths.databaseURL.path) else {
            return []
        }

        let connection = try SQLiteConnection(url: paths.databaseURL, mode: .readOnly)
        try validateSchema(using: connection)
        let hasID = try connection.columnNames(for: "part").contains("id")
        let rows = try connection.query(Self.usageQuery(cutoffDate: cutoffDate, hasID: hasID))
        return rows.compactMap { Self.parseObservedUsage(from: $0, file: paths.databaseURL.path) }
    }

    private static func parseObservedUsage(
        from row: [String: SQLiteValue],
        file: String
    ) -> ObservedCapabilityUsage? {
        let rawTool = row["raw_tool"]?.stringValue ?? ""
        let usageCount = row["usage_count"]?.intValue ?? 0
        let firstUsedAt = row["first_used_ms"]?.int64Value.map(dateFromMilliseconds)
        let lastUsedAt = row["last_used_ms"]?.int64Value.map(dateFromMilliseconds)
        let successCount = row["success_count"]?.intValue ?? 0
        let failureCount = row["failure_count"]?.intValue ?? 0
        let avgLatencyMs = row["avg_latency_ms"]?.doubleValue
        let samples = row["sample_record"]?.stringValue.map { [UsageRecordReference(file: file, record: "part.id=\($0)")] }

        if rawTool == "skill" {
            guard let skillName = row["skill_name"]?.stringValue, !skillName.isEmpty else {
                return nil
            }
            let usage = CapabilityUsage(
                id: CapabilityID(kind: .skill, name: skillName),
                usageCount: usageCount,
                firstUsedAt: firstUsedAt,
                lastUsedAt: lastUsedAt,
                successCount: successCount,
                failureCount: failureCount,
                avgLatencyMs: avgLatencyMs,
                installedButUnused: false,
                evidenceSamples: samples
            )
            return ObservedCapabilityUsage(usage: usage)
        }
        return nil
    }

    private static func dateFromMilliseconds(_ milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
    }

    private func validateSchema(using connection: SQLiteConnection) throws {
        guard try connection.tableExists("part") else {
            throw OpenCodeDataError.unexpectedData("Expected OpenCode SQLite table 'part'")
        }

        let columns = try connection.columnNames(for: "part")
        let requiredColumns: Set<String> = ["data", "time_created"]
        let missingColumns = requiredColumns.subtracting(columns)
        if !missingColumns.isEmpty {
            throw OpenCodeDataError.unexpectedData(
                "OpenCode table 'part' is missing columns: \(missingColumns.sorted().joined(separator: ", "))"
            )
        }
    }

    private static func usageQuery(cutoffDate: Date?, through: Date? = nil, hasID: Bool = false) -> String {
        let cutoffMilliseconds = cutoffDate.map { Int64(($0.timeIntervalSince1970 * 1_000).rounded(.down)) }
        let cutoffClause = cutoffMilliseconds.map { "\n      AND time_created >= \($0)" } ?? ""
        let endClause = through.map { "AND time_created <= \(Int64(($0.timeIntervalSince1970 * 1_000).rounded(.down)))" } ?? ""

        return """
    SELECT
      \(hasID ? "MIN(id)" : "NULL") AS sample_record,
      json_extract(data, '$.tool') AS raw_tool,
      json_extract(data, '$.state.input.name') AS skill_name,
      COUNT(*) AS usage_count,
      MIN(time_created) AS first_used_ms,
      MAX(time_created) AS last_used_ms,
      SUM(CASE WHEN json_extract(data, '$.state.status') = 'completed' THEN 1 ELSE 0 END) AS success_count,
      SUM(CASE WHEN json_extract(data, '$.state.status') = 'error' THEN 1 ELSE 0 END) AS failure_count,
      AVG(
        CASE
          WHEN json_extract(data, '$.state.time.start') IS NOT NULL
           AND json_extract(data, '$.state.time.end') IS NOT NULL
          THEN CAST(json_extract(data, '$.state.time.end') AS REAL) - CAST(json_extract(data, '$.state.time.start') AS REAL)
          ELSE NULL
        END
      ) AS avg_latency_ms
    FROM part
    WHERE json_extract(data, '$.type') = 'tool'
      \(cutoffClause)
      \(endClause)
      AND json_extract(data, '$.tool') = 'skill'
    GROUP BY skill_name
    ORDER BY last_used_ms DESC
    """
    }
}
