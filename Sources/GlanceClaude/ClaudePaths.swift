import Foundation

public struct ClaudePaths: Sendable {
    public let homeDirectory: URL

    public init(homeDirectory: URL) {
        self.homeDirectory = homeDirectory
    }

    public static var live: ClaudePaths {
        ClaudePaths(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }

    public var claudeDirectory: URL {
        homeDirectory.appending(path: ".claude", directoryHint: .isDirectory)
    }

    public var transcriptsDirectory: URL {
        claudeDirectory.appending(path: "transcripts", directoryHint: .isDirectory)
    }

    public var globalConfigCandidates: [URL] {
        [
            homeDirectory.appending(path: ".claude.json", directoryHint: .notDirectory),
            claudeDirectory.appending(path: "settings.json", directoryHint: .notDirectory),
        ]
    }

    public var globalSkillsDirectory: URL {
        claudeDirectory.appending(path: "skills", directoryHint: .isDirectory)
    }
}
