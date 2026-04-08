import Foundation

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
    public let serverName: String
    public let toolName: String

    public init(timestamp: Date, serverName: String, toolName: String) {
        self.timestamp = timestamp
        self.serverName = serverName
        self.toolName = toolName
    }
}

public struct CodexTranscriptLoadResult: Sendable {
    public let events: [CodexObservedToolEvent]
    public let skippedFilesCount: Int
    public let skippedEntriesCount: Int

    public init(events: [CodexObservedToolEvent], skippedFilesCount: Int, skippedEntriesCount: Int) {
        self.events = events
        self.skippedFilesCount = skippedFilesCount
        self.skippedEntriesCount = skippedEntriesCount
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
