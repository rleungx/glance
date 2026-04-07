import Foundation

public struct CodexConfigLoader {
    private let paths: CodexPaths

    public init(paths: CodexPaths = .live) {
        self.paths = paths
    }

    public func loadInstalledSkills() -> [CodexInstalledSkill] {
        guard let enumerator = FileManager.default.enumerator(at: paths.skillsDirectory, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }

        var skills: [String: CodexInstalledSkill] = [:]
        for case let url as URL in enumerator {
            guard url.lastPathComponent == "SKILL.md" else { continue }
            let skillDirectory = url.deletingLastPathComponent()
            let name = skillDirectory.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            skills[name.lowercased()] = CodexInstalledSkill(name: name, builtIn: skillDirectory.path.contains("/.system/"))
        }

        return skills.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func existingPaths() -> [String] {
        [paths.configURL.path, paths.sessionsDirectory.path, paths.skillsDirectory.path]
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { ($0 as NSString).abbreviatingWithTildeInPath }
    }
}
