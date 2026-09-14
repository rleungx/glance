import Foundation
import GlanceCore

public final class GeminiTranscriptUsageReader {
    private let paths: GeminiPaths
    private let fileManager: FileManager
    private let fractionalFormatter = ISO8601DateFormatter()
    private let plainFormatter = ISO8601DateFormatter()
    private var cache: [String: FileCacheEntry] = [:]

    public init(paths: GeminiPaths = .live, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    public func loadObservedEvents(since cutoffDate: Date) throws -> GeminiTranscriptLoadResult {
        let discovery = TranscriptFiles.discover(in: [paths.tmpDirectory], extensions: ["json"], fileManager: fileManager)
        let files = discovery.files.filter {
            $0.lastPathComponent.hasPrefix("session-")
                && $0.deletingLastPathComponent().lastPathComponent == "chats"
                && $0.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL.path != paths.tmpDirectory.standardizedFileURL.path
        }
        let currentPaths = Set(files.map(\.path))
        cache = cache.filter { currentPaths.contains($0.key) }
        var evidence = UsageEvidence(sources: [paths.tmpDirectory.path], skippedFiles: discovery.errors)
        var malformedFiles = 0
        var allEvents: [GeminiObservedToolEvent] = []
        for file in files {
            do {
                let data = try Data(contentsOf: file)
                let digest = UsageEventIdentity.fingerprint(data: data)
                let entry: FileCacheEntry
                if let cached = cache[file.path], cached.digest == digest {
                    entry = cached
                } else {
                    entry = parse(data, file: file, digest: digest)
                    cache[file.path] = entry
                }
                evidence.filesRead += 1
                evidence.skippedRecords += entry.skippedRecords
                if entry.skippedRecords > 0 { malformedFiles += 1 }
                allEvents.append(contentsOf: entry.events)
            } catch {
                cache[file.path] = nil
                evidence.skippedFiles += 1
            }
        }
        var unique: [String: GeminiObservedToolEvent] = [:]
        var orderedIDs: [String] = []
        for event in allEvents {
            guard let id = event.eventID else { continue }
            if let previous = unique[id] {
                evidence.duplicates += 1
                if previous.toolName != event.toolName || previous.args != event.args || previous.timestamp != event.timestamp {
                    evidence.skippedRecords += 1
                } else if previous.status != .success && previous.status != .error {
                    unique[id] = event
                } else if event.status == .success || event.status == .error, previous.status != event.status {
                    evidence.skippedRecords += 1
                }
            } else {
                unique[id] = event
                orderedIDs.append(id)
                if event.inferredIdentity { evidence.inferredIdentities += 1 }
            }
        }
        let events = orderedIDs.compactMap { unique[$0] }
        evidence.finish(timestamps: events.map(\.timestamp))
        return GeminiTranscriptLoadResult(events: events.filter { $0.timestamp >= cutoffDate },
            skippedFilesCount: evidence.skippedFiles + malformedFiles, evidence: evidence)
    }

    private func parse(_ data: Data, file: URL, digest: String) -> FileCacheEntry {
        guard let session = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = session["messages"] as? [Any] else {
            return FileCacheEntry(digest: digest, events: [], skippedRecords: 1)
        }
        var skipped = 0
        var events: [GeminiObservedToolEvent] = []
        for (messageIndex, rawMessage) in messages.enumerated() {
            guard let message = rawMessage as? [String: Any] else { skipped += 1; continue }
            guard let rawCalls = message["toolCalls"], !(rawCalls is NSNull) else { continue }
            guard let calls = rawCalls as? [Any] else { skipped += 1; continue }
            for (index, rawCall) in calls.enumerated() {
                guard let call = rawCall as? [String: Any], let name = call["name"] as? String, !name.isEmpty else {
                    skipped += 1; continue
                }
                let rawTimestamp = (call["timestamp"] as? String) ?? (message["timestamp"] as? String)
                guard let rawTimestamp, let timestamp = parseDate(rawTimestamp) else { skipped += 1; continue }
                let rawArgs: Any = call["args"] is NSNull ? [String: Any]() : (call["args"] ?? [:])
                guard let argsObject = rawArgs as? [String: Any],
                      let argsData = try? JSONSerialization.data(withJSONObject: argsObject),
                      let args = try? JSONDecoder().decode([String: GeminiJSONValue].self, from: argsData) else {
                    skipped += 1; continue
                }
                let rawStatus = (call["status"] as? String)?.lowercased()
                let status = rawStatus.flatMap(GeminiToolStatus.init(rawValue:)) ?? .unknown
                let nativeID = (call["id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                let sessionID = session["sessionId"] as? String ?? session["session_id"] as? String ?? ""
                let id = nativeID.map { "\(sessionID):\($0)" }
                    ?? UsageEventIdentity.fingerprint(["timestamp": rawTimestamp, "name": name, "args": argsObject, "index": index])
                events.append(GeminiObservedToolEvent(timestamp: timestamp, toolName: name, args: args, status: status,
                    reference: UsageRecordReference(file: file.path, record: "message \(messageIndex + 1), tool \(index + 1)"),
                    eventID: id, inferredIdentity: nativeID == nil))
            }
        }
        return FileCacheEntry(digest: digest, events: events, skippedRecords: skipped)
    }

    private func parseDate(_ value: String) -> Date? {
        fractionalFormatter.date(from: value) ?? plainFormatter.date(from: value)
    }
}

private struct FileCacheEntry {
    let digest: String
    let events: [GeminiObservedToolEvent]
    let skippedRecords: Int
}
