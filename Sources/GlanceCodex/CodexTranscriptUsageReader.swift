import Foundation
import GlanceCore

public struct CodexTranscriptUsageReader {
    private let paths: CodexPaths

    public init(paths: CodexPaths = .live) { self.paths = paths }

    public func loadObservedEvents(since cutoffDate: Date) throws -> CodexTranscriptLoadResult {
        let discovery = TranscriptFiles.discover(in: paths.sessionDirectories, extensions: ["jsonl"])
        var evidence = UsageEvidence(sources: paths.sessionDirectories.map(\.path), skippedFiles: discovery.errors)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        var events: [CodexObservedToolEvent] = []
        var seen: [String: String] = [:]
        for file in discovery.files {
            do {
                let text = try String(contentsOf: file, encoding: .utf8)
                evidence.filesRead += 1
                for (lineIndex, line) in text.components(separatedBy: "\n").enumerated() {
                    guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                          let entryType = object["type"] as? String else { evidence.skippedRecords += 1; continue }
                    guard entryType == "response_item" else { continue }
                    guard let payload = object["payload"] as? [String: Any], let type = payload["type"] as? String else {
                        evidence.skippedRecords += 1; continue
                    }
                    if type == "message", payload["role"] as? String == nil { evidence.skippedRecords += 1; continue }
                    let isUserMessage = type == "message" && payload["role"] as? String == "user"
                    guard isUserMessage else { continue }
                    guard let rawTimestamp = object["timestamp"] as? String,
                          let timestamp = fractional.date(from: rawTimestamp) ?? plain.date(from: rawTimestamp) else {
                        evidence.skippedRecords += 1; continue
                    }
                    let reference = UsageRecordReference(file: file.path, record: "line \(lineIndex + 1)")
                    guard let content = payload["content"] as? [Any] else { evidence.skippedRecords += 1; continue }
                    for (contentIndex, rawBlock) in content.enumerated() {
                        guard let block = rawBlock as? [String: Any] else { evidence.skippedRecords += 1; continue }
                        guard let text = block["text"] as? String else {
                            if block["type"] as? String == "input_text" { evidence.skippedRecords += 1 }
                            continue
                        }
                        let names = skillNames(in: text)
                        if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<skill>"), names.isEmpty {
                            evidence.skippedRecords += 1
                        }
                        for (index, name) in names.enumerated() {
                            // Native instruction-message IDs are optional; copies retain timestamp and content.
                            let nativeID = (payload["id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                            let messageID = nativeID ?? UsageEventIdentity.fingerprint(["timestamp": rawTimestamp, "content": text])
                            let id = "skill:\(messageID):\(contentIndex):\(index)"
                            let fingerprint = UsageEventIdentity.fingerprint(["timestamp": rawTimestamp, "content": text])
                            if let previous = seen[id] {
                                evidence.duplicates += 1
                                if previous != fingerprint { evidence.skippedRecords += 1 }
                                continue
                            }
                            seen[id] = fingerprint
                            if nativeID == nil { evidence.inferredIdentities += 1 }
                            events.append(CodexObservedToolEvent(timestamp: timestamp, skillName: name, reference: reference))
                        }
                    }
                }
            } catch { evidence.skippedFiles += 1 }
        }
        evidence.finish(timestamps: events.map(\.timestamp))
        return CodexTranscriptLoadResult(events: events.filter { $0.timestamp >= cutoffDate },
            skippedFilesCount: evidence.skippedFiles, skippedEntriesCount: evidence.skippedRecords, evidence: evidence)
    }

    private func skillNames(in text: String) -> [String] {
        let pattern = #"(?s)(?:^|\n)\s*<skill>\s*<name>([^<]+)</name>\s*<path>[^<]+</path>.*?</skill>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            guard let range = Range($0.range(at: 1), in: text) else { return nil }
            let name = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name
        }
    }
}
