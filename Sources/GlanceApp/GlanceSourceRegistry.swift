import Foundation
import GlanceClaude
import GlanceCodex
import GlanceDevin
import GlanceCore
import GlanceAntigravity
import GlanceOpenCode

protocol GlanceSourceResolving {
    var availableSources: [GlanceSource] { get }
    func makeRepository(for source: GlanceSource) -> any CapabilityRepository
    func settingsPaths(for source: GlanceSource) -> [String]
    func diagnostics(for source: GlanceSource) -> GlanceSourceDiagnostics
    func userFacingErrorMessage(for source: GlanceSource, error: Error) -> String
}

struct LiveGlanceSourceRegistry: GlanceSourceResolving {
    var devinPaths: DevinPaths = .live
    var antigravityPaths: AntigravityPaths = .live

    var availableSources: [GlanceSource] {
        GlanceSources.all
    }

    func makeRepository(for source: GlanceSource) -> any CapabilityRepository {
        switch source.id {
        case GlanceSources.openCodeLocal.id:
            return OpenCodeUsageRepository()
        case GlanceSources.codexLocal.id:
            return CodexUsageRepository()
        case GlanceSources.claudeCodeLocal.id:
            return ClaudeUsageRepository()
        case GlanceSources.antigravityLocal.id:
            return AntigravityInventoryRepository(paths: antigravityPaths)
        case GlanceSources.devinCLILocal.id:
            return DevinInventoryRepository(paths: devinPaths)
        default:
            return EmptyCapabilityRepository()
        }
    }

    func settingsPaths(for source: GlanceSource) -> [String] {
        switch source.id {
        case GlanceSources.openCodeLocal.id:
            let paths = OpenCodePaths.live
            return [
                abbreviated(paths.databaseURL.path),
                abbreviated(paths.skillsDirectory.path),
            ]
        case GlanceSources.claudeCodeLocal.id:
            return ClaudeConfigLoader().existingPaths()
        case GlanceSources.codexLocal.id:
            return CodexConfigLoader().existingPaths()
        case GlanceSources.antigravityLocal.id:
            return antigravityPaths.skillDirectories.map { abbreviated($0.path) }
        case GlanceSources.devinCLILocal.id:
            return devinPaths.skillDirectories.map { abbreviated($0.path) }
        default:
            return []
        }
    }

    func diagnostics(for source: GlanceSource) -> GlanceSourceDiagnostics {
        switch source.id {
        case GlanceSources.openCodeLocal.id:
            let paths = OpenCodePaths.live
            let artifacts = [
                artifact(label: "Database", kind: .file, path: paths.databaseURL.path),
                artifact(label: "Skills", kind: .directory, path: paths.skillsDirectory.path),
            ]
            let ready = artifacts.first(where: { $0.label == "Database" })?.isPresent == true
            return GlanceSourceDiagnostics(
                readiness: ready ? .ready : .needsSetup,
                supportsRollingWindows: true,
                artifacts: artifacts,
                summary: ready ? "OpenCode data is available." : "OpenCode needs a local database at \((paths.databaseURL.path as NSString).abbreviatingWithTildeInPath)."
            )
        case GlanceSources.claudeCodeLocal.id:
            let paths = ClaudePaths.live
            let artifacts = [
                artifact(label: "Transcripts", kind: .directory, path: paths.transcriptsDirectory.path),
                artifact(label: "Skills", kind: .directory, path: paths.globalSkillsDirectory.path),
            ]
            let ready = artifacts.contains(where: \.isPresent)
            return GlanceSourceDiagnostics(
                readiness: ready ? .ready : .needsSetup,
                supportsRollingWindows: true,
                artifacts: artifacts,
                summary: ready ? "Claude Code local data is available." : "Claude Code needs transcripts or skills under ~/.claude before Glance can show current data."
            )
        case GlanceSources.codexLocal.id:
            let paths = CodexPaths.live
            let artifacts = [
                artifact(label: "Config", kind: .file, path: paths.configURL.path),
                artifact(label: "Sessions", kind: .directory, path: paths.sessionsDirectory.path),
                artifact(label: "Skills", kind: .directory, path: paths.skillsDirectory.path),
            ]
                + paths.sessionDirectories.dropFirst().map { artifact(label: "Archived sessions", kind: .directory, path: $0.path) }
                + paths.skillDirectories.filter { $0 != paths.skillsDirectory }.map { artifact(label: "Additional skills", kind: .directory, path: $0.path) }
            let ready = artifacts.contains(where: { $0.label != "Config" && $0.isPresent })
            return GlanceSourceDiagnostics(
                readiness: ready ? .ready : .needsSetup,
                supportsRollingWindows: true,
                artifacts: artifacts,
                summary: ready ? "Codex local data is available." : "Codex needs local sessions or skills under ~/.codex before Glance can show current data."
            )
        case GlanceSources.antigravityLocal.id:
            let artifacts = [
                artifact(label: "Application skills", kind: .directory, path: antigravityPaths.applicationSkillsDirectory.path),
                artifact(label: "IDE skills", kind: .directory, path: antigravityPaths.ideSkillsDirectory.path),
            ]
            // A broken or inaccessible root must reach the loader to report an incomplete
            // inventory, rather than being mistaken for a confirmed empty setup.
            let ready = antigravityPaths.skillDirectories.contains(where: shouldInspectInventoryDirectory)
            return GlanceSourceDiagnostics(
                readiness: ready ? .ready : .needsSetup,
                supportsRollingWindows: false,
                artifacts: artifacts,
                summary: ready ? AntigravityInventoryRepository.scopeNotice
                    : "No global Antigravity skill directories found. Add a SKILL.md bundle under ~/.gemini/config/skills or ~/.gemini/antigravity/skills. Usage statistics are not supported yet.",
                usageSupport: .inventoryOnly
            )
        case GlanceSources.devinCLILocal.id:
            let artifacts = devinPaths.skillDirectories.map {
                artifact(label: "Skill definitions", kind: .directory, path: $0.path)
            }
            let ready = artifacts.contains(where: \.isPresent)
            return GlanceSourceDiagnostics(
                readiness: ready ? .ready : .needsSetup,
                supportsRollingWindows: false,
                artifacts: artifacts,
                summary: ready ? DevinInventoryRepository.scopeNotice
                    : "No global Devin CLI skill directories found. Add a skill under ~/.config/devin/skills or ~/.agents/skills. Usage statistics are not supported yet.",
                usageSupport: .inventoryOnly
            )
        default:
            return GlanceSourceDiagnostics(
                readiness: .unavailable,
                supportsRollingWindows: false,
                artifacts: [],
                summary: "This source is not supported by the current Glance build."
            )
        }
    }

    func userFacingErrorMessage(for source: GlanceSource, error: Error) -> String {
        switch source.id {
        case GlanceSources.openCodeLocal.id:
            if let error = error as? OpenCodeDataError {
                switch error {
                case .invalidConfig:
                    return "Glance could not read the OpenCode config. Check the config file and try again."
                case .sqlite:
                    return "Glance could not read the OpenCode database. Make sure OpenCode data is available and try again."
                case .unexpectedData:
                    return "OpenCode local data looks different than Glance expects. Updating Glance may be required."
                case .missingFile:
                    return "OpenCode is missing a required local file. Check the source paths in Settings."
                }
            }
            return "Glance could not load OpenCode right now."
        case GlanceSources.claudeCodeLocal.id:
            if let error = error as? ClaudeDataError {
                switch error {
                case .invalidConfig:
                    return "Glance could not parse the Claude Code config. Check the Claude settings file and try again."
                case .unexpectedTranscript:
                    return "One or more Claude transcripts could not be read. Glance skipped malformed files, but the transcript format may have changed."
                }
            }
            return "Glance could not load Claude Code right now."
        case GlanceSources.codexLocal.id:
            if let error = error as? CodexDataError {
                switch error {
                case .invalidSession:
                    return "A Codex session file could not be read. Glance skips malformed sessions, but Codex's local format may have changed."
                }
            }
            return "Glance could not load Codex right now."
        case GlanceSources.antigravityLocal.id:
            return "Glance could not inspect Antigravity skill definitions. Check the directories in Settings."
        case GlanceSources.devinCLILocal.id:
            return "Glance could not inspect Devin CLI skill definitions. Check the directories in Settings."
        default:
            return "This source is not supported by the current Glance build."
        }
    }

    private func abbreviated(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    private func shouldInspectInventoryDirectory(_ url: URL) -> Bool {
        do {
            _ = try FileManager.default.attributesOfItem(atPath: url.path)
            return true
        } catch {
            let error = error as NSError
            return !(error.domain == NSCocoaErrorDomain
                && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code))
        }
    }

    private func artifact(label: String, kind: GlanceSourceArtifactKind, path: String) -> GlanceSourceArtifact {
        GlanceSourceArtifact(label: label, kind: kind, displayPath: abbreviated(path), isPresent: FileManager.default.fileExists(atPath: path))
    }
}

private struct EmptyCapabilityRepository: WindowedCapabilityRepository {
    func loadCapabilities() async throws -> [CapabilityUsage] {
        []
    }

    func loadCapabilities(windows: [RollingWindow], now: Date) async throws -> [RollingWindow: [CapabilityUsage]] {
        Dictionary(uniqueKeysWithValues: windows.map { ($0, []) })
    }
}
