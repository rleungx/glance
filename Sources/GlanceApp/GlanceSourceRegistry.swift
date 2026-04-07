import Foundation
import GlanceClaude
import GlanceCodex
import GlanceCore
import GlanceGemini
import GlanceOpenCode

protocol GlanceSourceResolving {
    var availableSources: [GlanceSource] { get }
    func makeRepository(for source: GlanceSource) -> any CapabilityRepository
    func settingsPaths(for source: GlanceSource) -> [String]
    func diagnostics(for source: GlanceSource) -> GlanceSourceDiagnostics
    func userFacingErrorMessage(for source: GlanceSource, error: Error) -> String
}

struct LiveGlanceSourceRegistry: GlanceSourceResolving {
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
        case GlanceSources.geminiCLILocal.id:
            return GeminiUsageRepository()
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
                abbreviated(paths.opencodeConfigURL.path),
                abbreviated(paths.skillsDirectory.path),
            ]
        case GlanceSources.claudeCodeLocal.id:
            return ClaudeConfigLoader().existingPaths()
        case GlanceSources.codexLocal.id:
            return CodexConfigLoader().existingPaths()
        case GlanceSources.geminiCLILocal.id:
            return GeminiConfigLoader().existingPaths()
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
                artifact(label: "Config", kind: .file, path: paths.opencodeConfigURL.path),
                artifact(label: "Logs", kind: .directory, path: paths.logDirectory.path),
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
                artifact(label: "Global config", kind: .file, path: paths.globalConfigCandidates[0].path),
                artifact(label: "Settings", kind: .file, path: paths.globalConfigCandidates[1].path),
                artifact(label: "Skills", kind: .directory, path: paths.globalSkillsDirectory.path),
            ]
            let ready = artifacts.contains(where: \.isPresent)
            return GlanceSourceDiagnostics(
                readiness: ready ? .ready : .needsSetup,
                supportsRollingWindows: true,
                artifacts: artifacts,
                summary: ready ? "Claude Code local data is available." : "Claude Code needs transcripts or config under ~/.claude before Glance can show current data."
            )
        case GlanceSources.codexLocal.id:
            let paths = CodexPaths.live
            let artifacts = [
                artifact(label: "Config", kind: .file, path: paths.configURL.path),
                artifact(label: "Sessions", kind: .directory, path: paths.sessionsDirectory.path),
                artifact(label: "Skills", kind: .directory, path: paths.skillsDirectory.path),
            ]
            let ready = artifacts.contains(where: { $0.label == "Sessions" && $0.isPresent }) || artifacts.contains(where: { $0.label == "Skills" && $0.isPresent })
            return GlanceSourceDiagnostics(
                readiness: ready ? .ready : .needsSetup,
                supportsRollingWindows: true,
                artifacts: artifacts,
                summary: ready ? "Codex local data is available." : "Codex needs local sessions or skills under ~/.codex before Glance can show current data."
            )
        case GlanceSources.geminiCLILocal.id:
            let paths = GeminiPaths.live
            let locator = GeminiExecutableLocator()
            let commandArtifact = GlanceSourceArtifact(
                label: "Gemini",
                kind: .command,
                displayPath: abbreviated(locator.executableURL()?.path ?? "gemini"),
                isPresent: locator.isInstalled()
            )
            let artifacts = [
                commandArtifact,
                artifact(label: "Settings", kind: .file, path: paths.settingsURL.path),
                artifact(label: "Projects", kind: .file, path: paths.projectsURL.path),
                artifact(label: "History", kind: .directory, path: paths.historyDirectory.path),
                artifact(label: "Sessions", kind: .directory, path: paths.tmpDirectory.path),
            ]
            let readiness: GlanceSourceReadiness
            let summary: String
            if !commandArtifact.isPresent {
                readiness = .unavailable
                summary = "Gemini was not found in standard locations. Set GLANCE_GEMINI_EXECUTABLE if needed."
            } else if artifacts.contains(where: { $0.label == "Sessions" && $0.isPresent }) || artifacts.contains(where: { $0.label == "Settings" && $0.isPresent }) {
                readiness = .ready
                summary = "Gemini data is available."
            } else {
                readiness = .needsSetup
                summary = "Gemini is installed, but Glance needs local settings or session data under ~/.gemini."
            }
            return GlanceSourceDiagnostics(
                readiness: readiness,
                supportsRollingWindows: true,
                artifacts: artifacts,
                summary: summary
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
        case GlanceSources.geminiCLILocal.id:
            if let error = error as? GeminiDataError {
                switch error {
                case .commandFailed:
                    return "Gemini did not return the expected inventory output. Run 'gemini skills list --all' and 'gemini mcp list' manually, or set GLANCE_GEMINI_EXECUTABLE to the correct binary path."
                case .invalidSession:
                    return "A Gemini session file could not be read. Glance skips malformed sessions, but Gemini's local format may have changed."
                }
            }
            return "Glance could not load Gemini right now."
        default:
            return "This source is not supported by the current Glance build."
        }
    }

    private func abbreviated(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
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
