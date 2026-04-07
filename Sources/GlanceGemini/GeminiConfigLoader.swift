import Foundation

public final class GeminiConfigLoader {
    private let paths: GeminiPaths
    private let fileManager: FileManager
    private let commandRunner: any GeminiCommandRunning
    private let nowProvider: () -> Date
    private let cacheTTL: TimeInterval
    private var skillsCache: (fetchedAt: Date, value: [GeminiInstalledSkill])?
    private var mcpCache: (fetchedAt: Date, value: [GeminiConfiguredMCPServer])?

    public init(
        paths: GeminiPaths = .live,
        fileManager: FileManager = .default,
        commandRunner: any GeminiCommandRunning = GeminiProcessRunner(),
        cacheTTL: TimeInterval = 300,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.paths = paths
        self.fileManager = fileManager
        self.commandRunner = commandRunner
        self.cacheTTL = cacheTTL
        self.nowProvider = nowProvider
    }

    public func loadInstalledSkills(forceReload: Bool = false) throws -> [GeminiInstalledSkill] {
        let now = nowProvider()
        if !forceReload, let skillsCache, now.timeIntervalSince(skillsCache.fetchedAt) < cacheTTL {
            return skillsCache.value
        }
        let output = try commandRunner.run(arguments: ["skills", "list", "--all"])
        let value = Self.parseSkillsListOutput(output)
        skillsCache = (now, value)
        return value
    }

    public func loadConfiguredMCPServers(forceReload: Bool = false) throws -> [GeminiConfiguredMCPServer] {
        let now = nowProvider()
        if !forceReload, let mcpCache, now.timeIntervalSince(mcpCache.fetchedAt) < cacheTTL {
            return mcpCache.value
        }
        let output = try commandRunner.run(arguments: ["mcp", "list"])
        let value = Self.parseMCPListOutput(output)
        mcpCache = (now, value)
        return value
    }

    public func existingPaths() -> [String] {
        var results: [String] = []
        for url in [paths.settingsURL, paths.projectsURL] where fileManager.fileExists(atPath: url.path) {
            results.append((url.path as NSString).abbreviatingWithTildeInPath)
        }
        if fileManager.fileExists(atPath: paths.historyDirectory.path) {
            results.append((paths.historyDirectory.path as NSString).abbreviatingWithTildeInPath)
        }
        if fileManager.fileExists(atPath: paths.tmpDirectory.path) {
            results.append((paths.tmpDirectory.path as NSString).abbreviatingWithTildeInPath)
        }
        return results
    }

    static func parseSkillsListOutput(_ output: String) -> [GeminiInstalledSkill] {
        let lines = output.components(separatedBy: .newlines)
        let headerPattern = try? NSRegularExpression(pattern: #"^([A-Za-z0-9._-]+)(?:\s+\[[^\]]+\])*$"#)
        var skills: [GeminiInstalledSkill] = []
        var currentName: String?
        var currentEnabled = true
        var currentBuiltIn = false
        var currentLocation: String?

        func flush() {
            guard let currentName else { return }
            skills.append(GeminiInstalledSkill(name: currentName, enabled: currentEnabled, builtIn: currentBuiltIn, location: currentLocation))
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if let range = line.range(of: "Location:") {
                currentLocation = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                continue
            }

            let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = headerPattern?.firstMatch(in: line, range: nsRange),
               let nameRange = Range(match.range(at: 1), in: line) {
                let name = String(line[nameRange])
                if !name.contains(" ") {
                    flush()
                    currentName = name
                    currentEnabled = !line.localizedCaseInsensitiveContains("[Disabled]")
                    currentBuiltIn = line.localizedCaseInsensitiveContains("[Built-in]")
                    currentLocation = nil
                }
            }
        }

        flush()
        return skills
    }

    static func parseMCPListOutput(_ output: String) -> [GeminiConfiguredMCPServer] {
        if output.localizedCaseInsensitiveContains("No MCP servers configured.") {
            return []
        }

        let lines = output.components(separatedBy: .newlines)
        var servers: [GeminiConfiguredMCPServer] = []

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let firstCharacter = line.first,
                  ["✓", "✗", "○", "…", "⛔"].contains(firstCharacter) else {
                continue
            }

            let body = line.dropFirst().trimmingCharacters(in: .whitespaces)
            guard let statusSeparator = body.range(of: " - ", options: .backwards) else {
                continue
            }

            let leftSide = String(body[..<statusSeparator.lowerBound])
            let status = String(body[statusSeparator.upperBound...])
            var name = leftSide.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
            if let extensionRange = name.range(of: " (from ") {
                name = String(name[..<extensionRange.lowerBound])
            }
            name = name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }

            let enabled = status != "Disabled" && status != "Blocked"
            servers.append(GeminiConfiguredMCPServer(name: name, enabled: enabled))
        }

        return servers
    }
}
