import Foundation

/// Documented global skill roots for the stable Devin CLI channel, including Fusion.
/// Project/plugin discovery requires an explicit workspace or CLI context and is not inferred.
public struct DevinPaths: Sendable {
    public let homeDirectory: URL
    public let configurationDirectory: URL

    public init(homeDirectory: URL, environment: [String: String] = [:]) {
        self.homeDirectory = homeDirectory
        let configHome = environment["XDG_CONFIG_HOME"].flatMap {
            $0.hasPrefix("/") ? URL(fileURLWithPath: $0, isDirectory: true) : nil
        } ?? homeDirectory.appendingPathComponent(".config", isDirectory: true)
        configurationDirectory = configHome.appendingPathComponent("devin", isDirectory: true)
    }

    public static var live: DevinPaths {
        DevinPaths(homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
                   environment: ProcessInfo.processInfo.environment)
    }

    public var skillDirectories: [URL] {
        [
            configurationDirectory.appendingPathComponent("skills", isDirectory: true),
            homeDirectory.appendingPathComponent(".agents/skills", isDirectory: true),
            homeDirectory.appendingPathComponent(".codeium/windsurf/skills", isDirectory: true),
        ]
    }
}
