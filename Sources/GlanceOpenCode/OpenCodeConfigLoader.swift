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

    public func loadConfiguredMCPServers() throws -> [ConfiguredMCPServer] {
        guard fileManager.fileExists(atPath: paths.opencodeConfigURL.path) else {
            return []
        }

        let data = try Data(contentsOf: paths.opencodeConfigURL)
        let decoder = JSONDecoder()
        let rawConfig = try decoder.decode(RawOpenCodeConfig.self, from: data)

        return rawConfig.mcp
            .map { name, config in
                ConfiguredMCPServer(name: name, enabled: config.enabled ?? true)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func hasMCPConfiguration() -> Bool {
        guard let data = try? Data(contentsOf: paths.opencodeConfigURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        // An unrelated global preference does not define the installed MCP set.
        return object["mcp"] != nil
    }

    public var evidenceSources: [String] {
        [paths.databaseURL.path, paths.opencodeConfigURL.path, paths.skillsDirectory.path]
    }
}

private struct RawOpenCodeConfig: Decodable {
    let mcp: [String: RawMCPConfiguration]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        if let key = DynamicCodingKey(stringValue: "mcp"), container.contains(key) {
            self.mcp = try container.decode([String: RawMCPConfiguration].self, forKey: key)
        } else {
            self.mcp = [:]
        }
    }
}

private struct RawMCPConfiguration: Decodable {
    let enabled: Bool?
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
