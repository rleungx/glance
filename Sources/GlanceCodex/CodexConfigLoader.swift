import Foundation
import GlanceCore

public struct CodexConfigLoader {
    private let paths: CodexPaths
    public init(paths: CodexPaths = .live) { self.paths = paths }

    public func loadInstalledSkills() -> [CodexInstalledSkill] { loadInventory().skills }

    public func loadInventory() -> (skills: [CodexInstalledSkill], errors: Int, sources: [String]) {
        var visited = Set<String>()
        var skills: [String: CodexInstalledSkill] = [:]
        var errors = 0
        func visit(_ directory: URL) {
            let canonical = directory.resolvingSymlinksInPath()
            guard visited.insert(canonical.path).inserted else { return }
            do {
                let skillFile = directory.appendingPathComponent("SKILL.md")
                if FileManager.default.fileExists(atPath: skillFile.path) {
                    let text = try String(contentsOf: skillFile, encoding: .utf8)
                    var name = directory.lastPathComponent
                    let lines = text.components(separatedBy: .newlines)
                    if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
                        for line in lines.dropFirst() {
                            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
                            if line.hasPrefix("name:") {
                                let value = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                                if value == "|" || value == ">" || value.isEmpty { errors += 1 }
                                else { name = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
                                break
                            }
                        }
                    }
                    // Explicit additional roots precede shared and legacy roots.
                    if skills[name.lowercased()] == nil {
                        skills[name.lowercased()] = CodexInstalledSkill(name: name, builtIn: canonical.path.contains("/.system/"))
                    }
                    return
                }
                for child in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) {
                    if try child.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                        visit(child)
                    }
                }
            } catch { errors += 1 }
        }
        for root in paths.skillDirectories where FileManager.default.fileExists(atPath: root.path) { visit(root) }
        return (skills.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
                errors, paths.skillDirectories.map(\.path))
    }

    public func existingPaths() -> [String] {
        ([paths.configURL.path] + paths.sessionDirectories.map(\.path) + paths.skillDirectories.map(\.path))
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { ($0 as NSString).abbreviatingWithTildeInPath }
    }
}
