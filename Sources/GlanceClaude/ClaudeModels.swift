import Foundation

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

    public init(timestamp: Date, toolName: String) {
        self.timestamp = timestamp
        self.toolName = toolName
    }
}

public struct ClaudeTranscriptLoadResult: Sendable {
    public let events: [ClaudeObservedToolEvent]
    public let skippedFilesCount: Int

    public init(events: [ClaudeObservedToolEvent], skippedFilesCount: Int) {
        self.events = events
        self.skippedFilesCount = skippedFilesCount
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
