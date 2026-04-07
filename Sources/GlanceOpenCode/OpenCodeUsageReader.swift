import Foundation
import GlanceCore

public final class OpenCodeUsageReader {
    private let paths: OpenCodePaths
    private let fileManager: FileManager

    public init(paths: OpenCodePaths = .live, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    public func loadObservedCapabilities(mcpServerNames: Set<String>) throws -> [ObservedCapabilityUsage] {
        try loadObservedCapabilities(mcpServerNames: mcpServerNames, since: nil)
    }

    public func loadObservedCapabilities(mcpServerNames: Set<String>, since cutoffDate: Date?) throws -> [ObservedCapabilityUsage] {
        guard fileManager.fileExists(atPath: paths.databaseURL.path) else {
            return []
        }

        let connection = try SQLiteConnection(url: paths.databaseURL, mode: .readOnly)
        try validateSchema(using: connection)
        let rows = try connection.query(Self.usageQuery(mcpServerNames: mcpServerNames, cutoffDate: cutoffDate))
        return rows.compactMap { Self.parseObservedUsage(from: $0, mcpServerNames: mcpServerNames) }
    }

    private static func parseObservedUsage(
        from row: [String: SQLiteValue],
        mcpServerNames: Set<String>
    ) -> ObservedCapabilityUsage? {
        let rawTool = row["raw_tool"]?.stringValue ?? ""
        let usageCount = row["usage_count"]?.intValue ?? 0
        let firstUsedAt = row["first_used_ms"]?.int64Value.map(dateFromMilliseconds)
        let lastUsedAt = row["last_used_ms"]?.int64Value.map(dateFromMilliseconds)
        let successCount = row["success_count"]?.intValue ?? 0
        let failureCount = row["failure_count"]?.intValue ?? 0
        let avgLatencyMs = row["avg_latency_ms"]?.doubleValue

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
                installedButUnused: false
            )
            return ObservedCapabilityUsage(usage: usage)
        }

        guard let normalizedMCP = normalizeMCP(
            rawTool: rawTool,
            mcpName: row["mcp_name"]?.stringValue,
            mcpToolName: row["mcp_tool_name"]?.stringValue,
            mcpServerNames: mcpServerNames
        ) else {
            return nil
        }

        let usage = CapabilityUsage(
            id: CapabilityID(kind: .mcpTool, namespace: normalizedMCP.serverName, name: normalizedMCP.toolName),
            usageCount: usageCount,
            firstUsedAt: firstUsedAt,
            lastUsedAt: lastUsedAt,
            successCount: successCount,
            failureCount: failureCount,
            avgLatencyMs: avgLatencyMs,
            installedButUnused: false
        )
        return ObservedCapabilityUsage(usage: usage, serverName: normalizedMCP.serverName)
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

    private static func normalizeMCP(
        rawTool: String,
        mcpName: String?,
        mcpToolName: String?,
        mcpServerNames: Set<String>
    ) -> (serverName: String, toolName: String)? {
        if rawTool == "skill_mcp" {
            guard
                let serverName = normalizedComponent(mcpName),
                let toolName = normalizedComponent(mcpToolName),
                mcpServerNames.contains(serverName)
            else {
                return nil
            }
            return (serverName, toolName)
        }

        let normalizedRawTool = normalizedComponent(rawTool) ?? ""
        let matchingServer = mcpServerNames
            .filter { normalizedRawTool.hasPrefix($0 + "_") }
            .sorted { $0.count > $1.count }
            .first

        guard let matchingServer else {
            return nil
        }

        let suffixIndex = normalizedRawTool.index(normalizedRawTool.startIndex, offsetBy: matchingServer.count + 1)
        let toolName = String(normalizedRawTool[suffixIndex...])
        guard !toolName.isEmpty else { return nil }

        return (matchingServer, toolName)
    }

    private static func normalizedComponent(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed.lowercased()
    }

    private static func usageQuery(mcpServerNames: Set<String>, cutoffDate: Date?) -> String {
        let serverConditions = mcpServerNames.sorted().flatMap { serverName -> [String] in
            let escapedServerName = escapeSQLString(serverName)
            return [
                "lower(json_extract(data, '$.tool')) LIKE '\(escapedServerName)\\_%' ESCAPE '\\'",
            ]
        }

        let conditionalBlock = serverConditions.isEmpty ? "" : "\n        OR " + serverConditions.joined(separator: "\n        OR ")
        let cutoffMilliseconds = cutoffDate.map { Int64(($0.timeIntervalSince1970 * 1_000).rounded(.down)) }
        let cutoffClause = cutoffMilliseconds.map { "\n      AND time_created >= \($0)" } ?? ""

        return """
    SELECT
      json_extract(data, '$.tool') AS raw_tool,
      json_extract(data, '$.state.input.name') AS skill_name,
      json_extract(data, '$.state.input.mcp_name') AS mcp_name,
      json_extract(data, '$.state.input.tool_name') AS mcp_tool_name,
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
      AND (
        json_extract(data, '$.tool') = 'skill'
        OR json_extract(data, '$.tool') = 'skill_mcp'
        \(conditionalBlock)
      )
    GROUP BY raw_tool, skill_name, mcp_name, mcp_tool_name
    ORDER BY last_used_ms DESC
    """
    }

    private static func escapeSQLString(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "_", with: "\\_")
            .replacingOccurrences(of: "%", with: "\\%")
    }
}
