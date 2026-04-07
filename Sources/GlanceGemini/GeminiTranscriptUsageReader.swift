import Foundation

public final class GeminiTranscriptUsageReader {
    private let paths: GeminiPaths
    private let fileManager: FileManager
    private let decoder = JSONDecoder()
    private let fractionalFormatter: ISO8601DateFormatter
    private let plainFormatter: ISO8601DateFormatter
    private var cache: [String: FileCacheEntry] = [:]
    private var cachedCutoff: Date?

    public init(paths: GeminiPaths = .live, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.fractionalFormatter = fractionalFormatter

        let plainFormatter = ISO8601DateFormatter()
        plainFormatter.formatOptions = [.withInternetDateTime]
        self.plainFormatter = plainFormatter
    }

    public func loadObservedEvents(since cutoffDate: Date) throws -> GeminiTranscriptLoadResult {
        guard fileManager.fileExists(atPath: paths.tmpDirectory.path) else {
            return GeminiTranscriptLoadResult(events: [], skippedFilesCount: 0)
        }

        if let cachedCutoff, cutoffDate < cachedCutoff {
            cache = [:]
        }
        cachedCutoff = cutoffDate

        var events: [GeminiObservedToolEvent] = []
        var currentPaths = Set<String>()
        var skippedFilesCount = 0

        for chatsDirectory in chatsDirectories() {
            let enumerator = fileManager.enumerator(at: chatsDirectory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])

            while let file = enumerator?.nextObject() as? URL {
                guard file.pathExtension == "json", file.lastPathComponent.hasPrefix("session-") else {
                    continue
                }

                currentPaths.insert(file.path)

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

                let data = try Data(contentsOf: file)
                guard let session = try? decoder.decode(GeminiSession.self, from: data) else {
                    skippedFilesCount += 1
                    continue
                }

                var parsedEvents: [GeminiObservedToolEvent] = []
                for message in session.messages {
                    let fallbackTimestamp = parseDate(message.timestamp)
                    for toolCall in message.toolCalls ?? [] {
                        let timestamp = toolCall.timestamp.flatMap(parseDate) ?? fallbackTimestamp
                        guard let timestamp, timestamp >= cutoffDate else { continue }
                        parsedEvents.append(GeminiObservedToolEvent(timestamp: timestamp, toolName: toolCall.name, args: toolCall.args, status: toolCall.status))
                    }
                }

                cache[file.path] = FileCacheEntry(modifiedAt: modifiedAt, fileSize: fileSize, events: parsedEvents)
                events.append(contentsOf: parsedEvents)
            }
        }

        cache = cache.filter { currentPaths.contains($0.key) }

        return GeminiTranscriptLoadResult(events: events, skippedFilesCount: skippedFilesCount)
    }

    private func parseDate(_ value: String) -> Date? {
        if let date = fractionalFormatter.date(from: value) {
            return date
        }
        return plainFormatter.date(from: value)
    }

    private func chatsDirectories() -> [URL] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: paths.tmpDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var directories: [URL] = []
        directories.reserveCapacity(entries.count)

        for entry in entries {
            guard let values = try? entry.resourceValues(forKeys: [.isDirectoryKey]), values.isDirectory == true else {
                continue
            }
            let chatsDirectory = entry.appending(path: "chats", directoryHint: .isDirectory)
            if fileManager.fileExists(atPath: chatsDirectory.path) {
                directories.append(chatsDirectory)
            }
        }

        return directories
    }
}

private struct FileCacheEntry {
    let modifiedAt: Date
    let fileSize: Int
    let events: [GeminiObservedToolEvent]
}

private struct GeminiSession: Decodable {
    let messages: [GeminiMessage]
}

private struct GeminiMessage: Decodable {
    let timestamp: String
    let toolCalls: [GeminiToolCall]?

    enum CodingKeys: String, CodingKey {
        case timestamp
        case toolCalls
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.timestamp = try container.decode(String.self, forKey: .timestamp)
        self.toolCalls = try container.decodeIfPresent([GeminiToolCall].self, forKey: .toolCalls)
    }
}

private struct GeminiToolCall: Decodable {
    let name: String
    let args: [String: GeminiJSONValue]
    let status: GeminiToolStatus?
    let timestamp: String?

    enum CodingKeys: String, CodingKey {
        case name
        case args
        case status
        case timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.args = try container.decodeIfPresent([String: GeminiJSONValue].self, forKey: .args) ?? [:]
        self.status = try container.decodeIfPresent(GeminiToolStatus.self, forKey: .status)
        self.timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp)
    }
}
