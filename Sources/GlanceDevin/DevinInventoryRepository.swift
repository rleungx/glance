import Foundation
import GlanceCore

public struct DevinSkillDefinition: Hashable, Sendable {
    /// Devin's slash-command identifier is the directory name, not frontmatter's display name.
    public let name: String
    public let file: URL

    public var id: CapabilityID {
        CapabilityID(kind: .skill, namespace: file.path, name: name)
    }
}

public struct DevinInventory: Sendable {
    public let skills: [DevinSkillDefinition]
    public let unreadableLocations: Int
}

public struct DevinInventoryLoader: Sendable {
    public let paths: DevinPaths

    public init(paths: DevinPaths = .live) { self.paths = paths }

    /// Discovers definitions only. It does not execute skills, parse their prompts, or assert
    /// that Devin has loaded/enabled them. Same-name definitions in different roots are retained.
    public func loadInventory() -> DevinInventory {
        let manager = FileManager.default
        var skills: [CapabilityID: DevinSkillDefinition] = [:]
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
                        let skill = DevinSkillDefinition(name: entry.lastPathComponent,
                                                        file: file.resolvingSymlinksInPath())
                        skills[skill.id] = skill
                    } catch { issues += 1 }
                }
            } catch {
                // An absent optional root is normal; an unreadable root is not an empty inventory.
                if !isMissing(error) || isSymbolicLink(root) { issues += 1 }
            }
        }

        return DevinInventory(skills: skills.values.sorted {
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

/// No transcript format has been validated for Devin CLI yet. An inventory is not usage history.
public struct DevinInventoryRepository: EvidenceReportingRepository {
    public static let scopeNotice = "Global skill definitions only (stable channel). Project and plugin skills, enabled state, and usage statistics are not available. Shared definitions do not confirm that Devin CLI is installed."
    private let loader: DevinInventoryLoader

    public init(paths: DevinPaths = .live) { loader = DevinInventoryLoader(paths: paths) }

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
