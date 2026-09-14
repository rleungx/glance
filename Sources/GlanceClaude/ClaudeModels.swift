import Foundation
import GlanceCore

public struct ClaudeConfiguredMCPServer: Hashable, Sendable {
    public let name: String
    public let enabled: Bool

    public init(name: String, enabled: Bool) {
        self.name = name
        self.enabled = enabled
    }
}

public struct ClaudeInstalledSkill: Hashable, Sendable {
    public let name: String
    public let directory: URL

    public init(name: String, directory: URL) {
        self.name = name
        self.directory = directory
    }
}

public struct ClaudeObservedToolEvent: Sendable {
    public let timestamp: Date
    public let toolName: String
    public let skillName: String?
    public let toolUseID: String?
    public let reference: UsageRecordReference?
    public let inferredIdentity: Bool
    public let payloadFingerprint: String?

    public init(timestamp: Date, toolName: String, skillName: String? = nil, toolUseID: String? = nil, reference: UsageRecordReference? = nil, inferredIdentity: Bool = false, payloadFingerprint: String? = nil) {
        self.timestamp = timestamp
        self.toolName = toolName
        self.skillName = skillName
        self.toolUseID = toolUseID
        self.reference = reference
        self.inferredIdentity = inferredIdentity
        self.payloadFingerprint = payloadFingerprint
    }
}

public struct ClaudeTranscriptLoadResult: Sendable {
    public let events: [ClaudeObservedToolEvent]
    public let skippedFilesCount: Int
    public let evidence: UsageEvidence

    public init(events: [ClaudeObservedToolEvent], skippedFilesCount: Int, evidence: UsageEvidence = UsageEvidence()) {
        self.events = events
        self.skippedFilesCount = skippedFilesCount
        self.evidence = evidence
    }
}

public enum ClaudeDataError: LocalizedError {
    case invalidConfig(URL)
    case unexpectedTranscript(URL)

    public var errorDescription: String? {
        switch self {
        case let .invalidConfig(url):
            return "Invalid Claude config: \(url.path)"
        case let .unexpectedTranscript(url):
            return "Unexpected Claude transcript: \(url.path)"
        }
    }
}
