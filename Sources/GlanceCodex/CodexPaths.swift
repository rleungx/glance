import Foundation

public struct CodexPaths: Sendable {
    public let homeDirectory: URL

    public init(homeDirectory: URL) {
        self.homeDirectory = homeDirectory
    }

    public static var live: CodexPaths {
        CodexPaths(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }

    public var codexDirectory: URL {
        homeDirectory.appending(path: ".codex", directoryHint: .isDirectory)
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
}
