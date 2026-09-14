import Foundation
import GlanceCore

public final class ClaudeTranscriptUsageReader {
    private let paths: ClaudePaths
    private let fileManager: FileManager
    private let fractionalFormatter = ISO8601DateFormatter()
    private let plainFormatter = ISO8601DateFormatter()
    private var cache: [String: FileCacheEntry] = [:]

    public init(paths: ClaudePaths = .live, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    public func loadObservedEvents(since cutoffDate: Date) throws -> ClaudeTranscriptLoadResult {
        let discovery = TranscriptFiles.discover(in: [paths.transcriptsDirectory], extensions: ["jsonl"], fileManager: fileManager)
        var evidence = UsageEvidence(sources: [paths.transcriptsDirectory.path], skippedFiles: discovery.errors)
        let currentPaths = Set(discovery.files.map(\.path))
        cache = cache.filter { currentPaths.contains($0.key) }
        var events: [ClaudeObservedToolEvent] = []
        var malformedFiles = 0
        for file in discovery.files {
            do {
                // Hash bytes as well as metadata: rewritten files can retain size and mtime.
                let data = try Data(contentsOf: file)
                let digest = UsageEventIdentity.fingerprint(data: data)
                let entry: FileCacheEntry
                if let cached = cache[file.path], cached.digest == digest {
                    entry = cached
                } else {
                    guard let text = String(data: data, encoding: .utf8) else { throw ClaudeDataError.unexpectedTranscript(file) }
                    entry = parse(text, file: file, digest: digest)
                    cache[file.path] = entry
                }
                evidence.filesRead += 1
                evidence.skippedRecords += entry.skippedRecords
                if entry.skippedRecords > 0 { malformedFiles += 1 }
                events.append(contentsOf: entry.events)
            } catch {
                cache[file.path] = nil
                evidence.skippedFiles += 1
            }
        }
        var seen: [String: String] = [:]
        events = events.filter { event in
            guard let id = event.toolUseID else { return true }
            let fingerprint = event.payloadFingerprint ?? ""
            if let previous = seen[id] {
                evidence.duplicates += 1
                if previous != fingerprint { evidence.skippedRecords += 1 }
                return false
            }
            seen[id] = fingerprint
            if event.inferredIdentity { evidence.inferredIdentities += 1 }
            return true
        }
        evidence.finish(timestamps: events.map(\.timestamp))
        return ClaudeTranscriptLoadResult(events: events.filter { $0.timestamp >= cutoffDate },
            skippedFilesCount: evidence.skippedFiles + malformedFiles, evidence: evidence)
    }

    private func parse(_ text: String, file: URL, digest: String) -> FileCacheEntry {
        var events: [ClaudeObservedToolEvent] = []
        var skipped = 0
        for (lineIndex, line) in text.components(separatedBy: "\n").enumerated() {
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let type = object["type"] as? String else { skipped += 1; continue }
            let blocks: [Any]
            if type == "assistant" {
                guard let message = object["message"] as? [String: Any],
                      let content = message["content"] as? [Any] else { skipped += 1; continue }
                blocks = content
            } else if type == "tool_use" {
                guard let name = object["tool_name"] as? String else { skipped += 1; continue }
                blocks = [["type": "tool_use", "name": name]]
            } else { continue }

            for (index, rawBlock) in blocks.enumerated() {
                guard let block = rawBlock as? [String: Any], let blockType = block["type"] as? String else { skipped += 1; continue }
                guard blockType == "tool_use" else { continue }
                guard let name = block["name"] as? String, !name.isEmpty,
                      let rawTimestamp = object["timestamp"] as? String,
                      let timestamp = fractionalFormatter.date(from: rawTimestamp) ?? plainFormatter.date(from: rawTimestamp) else {
                    skipped += 1; continue
                }
                var skillName: String?
                if name.lowercased() == "skill" {
                    guard let input = block["input"] as? [String: Any],
                          let skill = input["skill"] as? String, !skill.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        skipped += 1; continue
                    }
                    skillName = skill
                }
                let nativeID = (block["id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                let id = nativeID ?? UsageEventIdentity.fingerprint(["timestamp": rawTimestamp, "block": block, "index": index])
                events.append(ClaudeObservedToolEvent(timestamp: timestamp, toolName: name, skillName: skillName,
                    toolUseID: id, reference: UsageRecordReference(file: file.path, record: "line \(lineIndex + 1), block \(index + 1)"),
                    inferredIdentity: nativeID == nil,
                    payloadFingerprint: UsageEventIdentity.fingerprint(["timestamp": rawTimestamp, "block": block])))
            }
        }
        return FileCacheEntry(digest: digest, events: events, skippedRecords: skipped)
    }
}

private struct FileCacheEntry {
    let digest: String
    let events: [ClaudeObservedToolEvent]
    let skippedRecords: Int
}
