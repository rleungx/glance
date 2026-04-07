import Foundation

enum GlanceSourceReadiness: String, Codable, Equatable {
    case ready
    case needsSetup
    case unavailable
}

enum GlanceSourceArtifactKind: Codable, Hashable {
    case file
    case directory
    case command
}

struct GlanceSourceArtifact: Identifiable, Hashable, Codable {
    let label: String
    let kind: GlanceSourceArtifactKind
    let displayPath: String
    let isPresent: Bool

    var id: String { label + ":" + displayPath }
}

struct GlanceSourceDiagnostics: Codable, Equatable {
    let readiness: GlanceSourceReadiness
    let supportsRollingWindows: Bool
    let artifacts: [GlanceSourceArtifact]
    let summary: String

    var statusLabel: String {
        switch readiness {
        case .ready: return "Ready"
        case .needsSetup: return "Needs setup"
        case .unavailable: return "Unavailable"
        }
    }
}
