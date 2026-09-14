import Foundation

public struct CodexPaths: Sendable {
    public let homeDirectory: URL
    private let configuredCodexDirectory: URL?
    public let additionalSkillDirectories: [URL]

    public init(homeDirectory: URL, codexDirectory: URL? = nil, additionalSkillDirectories: [URL] = []) {
        self.homeDirectory = homeDirectory
        self.configuredCodexDirectory = codexDirectory
        self.additionalSkillDirectories = additionalSkillDirectories
    }

    public static var live: CodexPaths {
        let override = ProcessInfo.processInfo.environment["CODEX_HOME"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
        return CodexPaths(homeDirectory: FileManager.default.homeDirectoryForCurrentUser, codexDirectory: override)
    }

    public var codexDirectory: URL {
        configuredCodexDirectory ?? homeDirectory.appending(path: ".codex", directoryHint: .isDirectory)
    }

    public var configURL: URL {
        codexDirectory.appending(path: "config.toml", directoryHint: .notDirectory)
    }

    public var historyURL: URL {
        codexDirectory.appending(path: "history.jsonl", directoryHint: .notDirectory)
    }

    public var sessionsDirectory: URL {
        codexDirectory.appending(path: "sessions", directoryHint: .isDirectory)
    }

    public var skillsDirectory: URL {
        codexDirectory.appending(path: "skills", directoryHint: .isDirectory)
    }

    public var skillDirectories: [URL] {
        additionalSkillDirectories + [homeDirectory.appendingPathComponent(".agents/skills"), skillsDirectory]
    }

    public var sessionDirectories: [URL] {
        [sessionsDirectory, codexDirectory.appendingPathComponent("archived_sessions")]
    }
}
