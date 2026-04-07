import Foundation

public final class ClaudeTranscriptUsageReader {
    private let paths: ClaudePaths
    private let fileManager: FileManager
    private let decoder = JSONDecoder()
    private let fractionalFormatter: ISO8601DateFormatter
    private let plainFormatter: ISO8601DateFormatter
    private var cache: [String: FileCacheEntry] = [:]
    private var cachedCutoff: Date?

    public init(paths: ClaudePaths = .live, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.fractionalFormatter = fractionalFormatter

        let plainFormatter = ISO8601DateFormatter()
        plainFormatter.formatOptions = [.withInternetDateTime]
        self.plainFormatter = plainFormatter
    }

    public func loadObservedEvents(since cutoffDate: Date) throws -> ClaudeTranscriptLoadResult {
        guard fileManager.fileExists(atPath: paths.transcriptsDirectory.path) else {
            return ClaudeTranscriptLoadResult(events: [], skippedFilesCount: 0)
        }

        if let cachedCutoff, cutoffDate < cachedCutoff {
            cache = [:]
        }
        cachedCutoff = cutoffDate

        let files = try fileManager.contentsOfDirectory(
            at: paths.transcriptsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "jsonl" }

        let currentPaths = Set(files.map(\.path))
        cache = cache.filter { currentPaths.contains($0.key) }

        var events: [ClaudeObservedToolEvent] = []
        var skippedFilesCount = 0
        for file in files {
            let values = try file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let modifiedAt = values.contentModificationDate ?? .distantPast
            let fileSize = values.fileSize ?? 0

            if values.contentModificationDate != nil, modifiedAt < cutoffDate {
                cache[file.path] = nil
                continue
            }

            if let entry = cache[file.path], entry.modifiedAt == modifiedAt, entry.fileSize == fileSize {
                events.append(contentsOf: entry.events.filter { $0.timestamp >= cutoffDate })
                continue
            }

            let text = try String(contentsOf: file, encoding: .utf8)
            var parsedEvents: [ClaudeObservedToolEvent] = []
            var skippedLines = 0
            for line in text.split(separator: "\n") {
                guard let data = line.data(using: .utf8),
                      let entry = try? decoder.decode(ClaudeTranscriptEntry.self, from: data) else {
                    skippedLines += 1
                    continue
                }

                guard entry.type == "tool_use" else {
                    continue
                }

                guard let toolName = entry.toolName,
                      let timestamp = parseDate(entry.timestamp) else {
                    skippedLines += 1
                    continue
                }

                parsedEvents.append(ClaudeObservedToolEvent(timestamp: timestamp, toolName: toolName))
            }

            if skippedLines > 0 {
                skippedFilesCount += 1
            }

            cache[file.path] = FileCacheEntry(modifiedAt: modifiedAt, fileSize: fileSize, events: parsedEvents)
            events.append(contentsOf: parsedEvents.filter { $0.timestamp >= cutoffDate })
        }
        return ClaudeTranscriptLoadResult(events: events, skippedFilesCount: skippedFilesCount)
    }

    private func parseDate(_ value: String) -> Date? {
        if let date = fractionalFormatter.date(from: value) {
            return date
        }
        return plainFormatter.date(from: value)
    }
}

private struct FileCacheEntry {
    let modifiedAt: Date
    let fileSize: Int
    let events: [ClaudeObservedToolEvent]
}

private struct ClaudeTranscriptEntry: Decodable {
    let type: String
    let timestamp: String
    let toolName: String?

    enum CodingKeys: String, CodingKey {
        case type
        case timestamp
        case toolName = "tool_name"
    }
}
