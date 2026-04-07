import Foundation

public struct OpenCodePaths: Sendable {
    public let homeDirectory: URL
    public let configDirectory: URL
    public let dataDirectory: URL
    public let skillsDirectory: URL

    public init(
        homeDirectory: URL,
        configDirectory: URL? = nil,
        dataDirectory: URL? = nil,
        skillsDirectory: URL? = nil
    ) {
        self.homeDirectory = homeDirectory
        self.configDirectory = configDirectory ?? homeDirectory.appending(path: ".config/opencode", directoryHint: .isDirectory)
        self.dataDirectory = dataDirectory ?? homeDirectory.appending(path: ".local/share/opencode", directoryHint: .isDirectory)
        self.skillsDirectory = skillsDirectory ?? homeDirectory.appending(path: ".agents/skills", directoryHint: .isDirectory)
    }

    public static var live: OpenCodePaths {
        OpenCodePaths(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }

    public var databaseURL: URL {
        dataDirectory.appending(path: "opencode.db", directoryHint: .notDirectory)
    }

    public var logDirectory: URL {
        dataDirectory.appending(path: "log", directoryHint: .isDirectory)
    }

    public var opencodeConfigURL: URL {
        configDirectory.appending(path: "opencode.json", directoryHint: .notDirectory)
    }

    public var ohMyOpenCodeConfigURL: URL {
        configDirectory.appending(path: "oh-my-opencode.json", directoryHint: .notDirectory)
    }
}
