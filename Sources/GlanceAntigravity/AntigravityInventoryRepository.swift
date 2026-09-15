import Foundation
import GlanceCore

public struct AntigravitySkillDefinition: Hashable, Sendable {
    /// Filesystem folder label, not a parsed frontmatter name or confirmed invocation identifier.
    public let name: String
    public let file: URL

    public var id: CapabilityID {
        CapabilityID(kind: .skill, namespace: file.path, name: name)
    }
}

public struct AntigravityInventory: Sendable {
    public let skills: [AntigravitySkillDefinition]
    public let unreadableLocations: Int
}

public struct AntigravityInventoryLoader: Sendable {
    public let paths: AntigravityPaths

    public init(paths: AntigravityPaths = .live) { self.paths = paths }

    /// Discovers definitions only. It does not execute skills, parse their prompts, or assert
    /// that Antigravity has loaded/enabled them. Same-name definitions in different roots are retained.
    public func loadInventory() -> AntigravityInventory {
        let manager = FileManager.default
        var skills: [CapabilityID: AntigravitySkillDefinition] = [:]
        var visitedRoots = Set<String>()
        var issues = 0

        for root in paths.skillDirectories {
            guard visitedRoots.insert(root.resolvingSymlinksInPath().path).inserted else { continue }
            do {
                guard try fileType(root) == .typeDirectory else { issues += 1; continue }
                let entries = try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil,
                                                              options: [.skipsHiddenFiles])
                for entry in entries.sorted(by: { $0.path < $1.path }) {
                    do {
                        let entryType = try fileType(entry)
                        guard entryType == .typeDirectory else {
                            if entryType == .typeSymbolicLink { issues += 1 }
                            continue
                        }
                        let file = entry.appendingPathComponent("SKILL.md")
                        let type: FileAttributeType?
                        do { type = try fileType(file) }
                        catch {
                            if !isMissing(error) || isSymbolicLink(file) { issues += 1 }
                            continue
                        }
                        guard type == .typeRegular, manager.isReadableFile(atPath: file.path) else {
                            issues += 1
                            continue
                        }
                        let skill = AntigravitySkillDefinition(name: entry.lastPathComponent,
                                                        file: file.resolvingSymlinksInPath())
                        skills[skill.id] = skill
                    } catch { issues += 1 }
                }
            } catch {
                // An absent optional root is normal; an unreadable root is not an empty inventory.
                if !isMissing(error) || isSymbolicLink(root) { issues += 1 }
            }
        }

        return AntigravityInventory(skills: skills.values.sorted {
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame ? $0.file.path < $1.file.path : order == .orderedAscending
        }, unreadableLocations: issues)
    }

    private func fileType(_ url: URL) throws -> FileAttributeType? {
        try FileManager.default.attributesOfItem(atPath: url.resolvingSymlinksInPath().path)[.type] as? FileAttributeType
    }

    private func isMissing(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain
            && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code)
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }
}

/// An inventory is not usage history; no Antigravity activation format has been validated.
public struct AntigravityInventoryRepository: EvidenceReportingRepository {
    public static let scopeNotice = "Global application and IDE skill files only, labeled by folder name. CLI, SDK, project and plugin skills, enabled state, and usage statistics are not covered. Files do not confirm that Antigravity is installed."
    private let loader: AntigravityInventoryLoader

    public init(paths: AntigravityPaths = .live) { loader = AntigravityInventoryLoader(paths: paths) }

    public func loadCapabilities() async throws -> [CapabilityUsage] {
        try await loadUsage(windows: [.allTime], now: .now).windows[.allTime] ?? []
    }

    public func loadUsage(windows: [RollingWindow], now: Date) async throws -> UsageLoadResult {
        let inventory = loader.loadInventory()
        let definitions = inventory.skills.map {
            CapabilityUsage(id: $0.id, usageCount: 0, installedButUnused: false)
        }
        var warnings = [Self.scopeNotice]
        if inventory.unreadableLocations > 0 {
            warnings.append("Could not inspect \(inventory.unreadableLocations) skill locations. The inventory may be incomplete.")
        }
        // Never call evidence.finish here: reading definitions cannot establish observed usage.
        return UsageLoadResult(windows: [.allTime: definitions],
                               evidence: UsageEvidence(sources: loader.paths.skillDirectories.map(\.path),
                                                       skippedFiles: inventory.unreadableLocations),
                               warnings: warnings)
    }
}
