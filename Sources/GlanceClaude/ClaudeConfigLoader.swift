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

    public func loadConfiguredMCPServers() throws -> [ClaudeConfiguredMCPServer] {
        for candidate in paths.globalConfigCandidates where fileManager.fileExists(atPath: candidate.path) {
            let data = try Data(contentsOf: candidate)
            guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ClaudeDataError.invalidConfig(candidate)
            }
            return extractMCPServers(from: jsonObject)
        }

        return []
    }

    public func existingPaths() -> [String] {
        var results: [String] = []
        for candidate in paths.globalConfigCandidates where fileManager.fileExists(atPath: candidate.path) {
            results.append((candidate.path as NSString).abbreviatingWithTildeInPath)
        }
        if fileManager.fileExists(atPath: paths.transcriptsDirectory.path) {
            results.append((paths.transcriptsDirectory.path as NSString).abbreviatingWithTildeInPath)
        }
        if fileManager.fileExists(atPath: paths.globalSkillsDirectory.path) {
            results.append((paths.globalSkillsDirectory.path as NSString).abbreviatingWithTildeInPath)
        }
        return results
    }

    public var evidenceSources: [String] {
        (paths.globalConfigCandidates + [paths.globalSkillsDirectory, paths.transcriptsDirectory]).map(\.path)
    }

    private func extractMCPServers(from object: [String: Any]) -> [ClaudeConfiguredMCPServer] {
        guard let rawServers = object["mcpServers"] as? [String: Any] else {
            return []
        }

        return rawServers.compactMap { key, value in
            if let config = value as? [String: Any] {
                if let enabled = config["enabled"] as? Bool {
                    return ClaudeConfiguredMCPServer(name: key, enabled: enabled)
                }
                if let disabled = config["disabled"] as? Bool {
                    return ClaudeConfiguredMCPServer(name: key, enabled: !disabled)
                }
            }
            return ClaudeConfiguredMCPServer(name: key, enabled: true)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
