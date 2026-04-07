import Foundation

public struct CodexTranscriptUsageReader {
    private let paths: CodexPaths

    public init(paths: CodexPaths = .live) {
        self.paths = paths
    }

    public func loadObservedEvents(since cutoffDate: Date) throws -> CodexTranscriptLoadResult {
        let sessionFiles = sessionFiles()
        let decoder = JSONDecoder()
        let formatter = makeDateFormatter()
        var events: [CodexObservedToolEvent] = []
        var skippedFilesCount = 0

        for fileURL in sessionFiles {
            do {
                let lines = try String(contentsOf: fileURL, encoding: .utf8).split(separator: "\n")
                for line in lines where !line.isEmpty {
                    guard let data = line.data(using: .utf8) else { continue }
                    guard let entry = try? decoder.decode(CodexSessionEntry.self, from: data) else { continue }
                    guard let timestamp = formatter.date(from: entry.timestamp) else { continue }
                    guard timestamp >= cutoffDate else { continue }
                    guard let functionCall = entry.payload.functionCall else { continue }
                    let parsedName = parseFunctionName(functionCall.name)
                    guard let parsedName else { continue }
                    events.append(CodexObservedToolEvent(timestamp: timestamp, serverName: parsedName.serverName, toolName: parsedName.toolName))
                }
            } catch {
                skippedFilesCount += 1
            }
        }

        return CodexTranscriptLoadResult(events: events, skippedFilesCount: skippedFilesCount)
    }

    private func sessionFiles() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: paths.sessionsDirectory, includingPropertiesForKeys: nil) else {
            return []
        }

        return (enumerator.compactMap { $0 as? URL })
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.path < $1.path }
    }

    private func parseFunctionName(_ rawName: String) -> (serverName: String, toolName: String)? {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("mcp__") {
            let remainder = String(trimmed.dropFirst(5))
            guard let split = remainder.range(of: "__") else { return nil }
            let serverName = String(remainder[..<split.lowerBound]).lowercased()
            let toolName = String(remainder[split.upperBound...]).lowercased()
            guard !serverName.isEmpty, !toolName.isEmpty else { return nil }
            return (serverName, toolName)
        }

        return nil
    }

    private func makeDateFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}

private struct CodexSessionEntry: Decodable {
    let timestamp: String
    let payload: Payload

    struct Payload: Decodable {
        let name: String?
        let type: String?

        var functionCall: FunctionCall? {
            guard let type, ["function_call", "custom_tool_call"].contains(type), let name else {
                return nil
            }
            return FunctionCall(name: name)
        }
    }

    struct FunctionCall {
        let name: String
    }
}
