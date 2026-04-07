import Foundation
import Testing
@testable import GlanceApp

@Test
func sourceDiagnosticsLabelsExposeReadiness() {
    let ready = GlanceSourceDiagnostics(readiness: .ready, supportsRollingWindows: false, artifacts: [], summary: "ok")
    let setup = GlanceSourceDiagnostics(readiness: .needsSetup, supportsRollingWindows: true, artifacts: [], summary: "setup")
    let unavailable = GlanceSourceDiagnostics(readiness: .unavailable, supportsRollingWindows: true, artifacts: [], summary: "missing")

    #expect(ready.statusLabel == "Ready")
    #expect(setup.statusLabel == "Needs setup")
    #expect(unavailable.statusLabel == "Unavailable")
}

@Test
func openCodeDiagnosticsAdvertiseRollingWindowSupport() {
    let registry = LiveGlanceSourceRegistry()
    let diagnostics = registry.diagnostics(for: GlanceSources.openCodeLocal)

    #expect(diagnostics.supportsRollingWindows == true)
}

@Test
func codexDiagnosticsAdvertiseRollingWindowSupport() {
    let registry = LiveGlanceSourceRegistry()
    let diagnostics = registry.diagnostics(for: GlanceSources.codexLocal)

    #expect(diagnostics.supportsRollingWindows == true)
}
