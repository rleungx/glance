import Foundation

public final class ClaudeConfigLoader {
    private let paths: ClaudePaths
    private let fileManager: FileManager

    public init(paths: ClaudePaths = .live, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    public func loadInstalledSkills() throws -> [ClaudeInstalledSkill] {
        guard fileManager.fileExists(atPath: paths.globalSkillsDirectory.path) else {
            return []
        }

        let directories = try fileManager.contentsOfDirectory(
            at: paths.globalSkillsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return directories.compactMap { directory in
            let skillFile = directory.appending(path: "SKILL.md", directoryHint: .notDirectory)
            guard fileManager.fileExists(atPath: skillFile.path) else {
                return nil
            }
            return ClaudeInstalledSkill(name: directory.lastPathComponent, directory: directory)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func existingPaths() -> [String] {
        var results: [String] = []
        if fileManager.fileExists(atPath: paths.transcriptsDirectory.path) {
            results.append((paths.transcriptsDirectory.path as NSString).abbreviatingWithTildeInPath)
        }
        if fileManager.fileExists(atPath: paths.globalSkillsDirectory.path) {
            results.append((paths.globalSkillsDirectory.path as NSString).abbreviatingWithTildeInPath)
        }
        return results
    }

    public var evidenceSources: [String] {
        [paths.globalSkillsDirectory, paths.transcriptsDirectory].map(\.path)
    }
}
