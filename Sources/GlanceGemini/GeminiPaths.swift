import Foundation

public struct GeminiPaths: Sendable {
    public let homeDirectory: URL

    public init(homeDirectory: URL) {
        self.homeDirectory = homeDirectory
    }

    public static var live: GeminiPaths {
        GeminiPaths(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }

    public var geminiDirectory: URL {
        homeDirectory.appending(path: ".gemini", directoryHint: .isDirectory)
    }

    public var settingsURL: URL {
        geminiDirectory.appending(path: "settings.json", directoryHint: .notDirectory)
    }

    public var projectsURL: URL {
        geminiDirectory.appending(path: "projects.json", directoryHint: .notDirectory)
    }

    public var historyDirectory: URL {
        geminiDirectory.appending(path: "history", directoryHint: .isDirectory)
    }

    public var tmpDirectory: URL {
        geminiDirectory.appending(path: "tmp", directoryHint: .isDirectory)
    }
}
