import Foundation
import GlanceCore

public struct CodexInstalledSkill: Hashable, Sendable {
    public let name: String
    public let builtIn: Bool

    public init(name: String, builtIn: Bool) {
        self.name = name
        self.builtIn = builtIn
    }
}

public struct CodexObservedToolEvent: Sendable {
    public let timestamp: Date
    public let skillName: String
    public let reference: UsageRecordReference?

    public init(timestamp: Date, skillName: String, reference: UsageRecordReference? = nil) {
        self.timestamp = timestamp
        self.skillName = skillName
        self.reference = reference
    }
}

public struct CodexTranscriptLoadResult: Sendable {
    public let events: [CodexObservedToolEvent]
    public let skippedFilesCount: Int
    public let skippedEntriesCount: Int
    public let evidence: UsageEvidence

    public init(events: [CodexObservedToolEvent], skippedFilesCount: Int, skippedEntriesCount: Int, evidence: UsageEvidence = UsageEvidence()) {
        self.events = events
        self.skippedFilesCount = skippedFilesCount
        self.skippedEntriesCount = skippedEntriesCount
        self.evidence = evidence
    }
}

public enum CodexDataError: LocalizedError {
    case invalidSession(URL)

    public var errorDescription: String? {
        switch self {
        case let .invalidSession(url):
            return "Invalid Codex session file: \(url.path)"
        }
    }
}
