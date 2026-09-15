import Foundation

public final class OpenCodeConfigLoader {
    private let paths: OpenCodePaths
    private let fileManager: FileManager

    public init(paths: OpenCodePaths = .live, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    public func loadInstalledSkills() throws -> [InstalledSkill] {
        guard fileManager.fileExists(atPath: paths.skillsDirectory.path) else {
            return []
        }

        let directories = try fileManager.contentsOfDirectory(
            at: paths.skillsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return directories.compactMap { directory in
            let skillFile = directory.appending(path: "SKILL.md", directoryHint: .notDirectory)
            guard fileManager.fileExists(atPath: skillFile.path) else {
                return nil
            }
            return InstalledSkill(name: directory.lastPathComponent, directory: directory)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public var evidenceSources: [String] {
        [paths.databaseURL.path, paths.skillsDirectory.path]
    }
}
