import Foundation

/// Documented Antigravity application and IDE global roots. CLI and SDK paths
/// are separate and are not inferred from Gemini CLI data or the current project.
public struct AntigravityPaths: Sendable {
    public let homeDirectory: URL

    public init(homeDirectory: URL) { self.homeDirectory = homeDirectory }

    public static var live: AntigravityPaths {
        AntigravityPaths(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }

    public var applicationSkillsDirectory: URL {
        homeDirectory.appendingPathComponent(".gemini/config/skills", isDirectory: true)
    }

    public var ideSkillsDirectory: URL {
        homeDirectory.appendingPathComponent(".gemini/antigravity/skills", isDirectory: true)
    }

    public var skillDirectories: [URL] {
        [applicationSkillsDirectory, ideSkillsDirectory]
    }
}
