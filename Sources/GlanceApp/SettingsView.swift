import AppKit
import SwiftUI
import UniformTypeIdentifiers
import GlanceCore

struct GlanceSettingsView: View {
    @ObservedObject var store: GlanceStore
    @ObservedObject var updater: GlanceUpdater
    private let appMetadata = GlanceAppMetadata()
    @State private var supportStatus: String?
    @State private var supportStatusIsError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                currentSourceSection
                overviewSection
                sourcePathsSection
                supportSection
                aboutSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Metrics.outerPadding)
        }
        .frame(
            minWidth: Metrics.windowMinWidth,
            idealWidth: Metrics.windowIdealWidth,
            minHeight: Metrics.windowMinHeight,
            idealHeight: Metrics.windowIdealHeight,
            alignment: .topLeading
        )
        .background(GlanceVisualStyle.canvas.ignoresSafeArea())
    }

    private var currentSourceSection: AnyView {
        AnyView(settingsSection(
            title: "Current Source",
            detail: "Glance reads from the selected source in place and keeps the source read-only."
        ) {
            settingRow {
                Picker("Source", selection: sourceSelection) {
                    ForEach(store.availableSources) { source in
                        Text(source.displayName)
                            .tag(source.id)
                    }
                }
                .disabled(store.availableSources.count <= 1)
            }

            settingRow {
                HStack {
                    Text("Status")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(store.currentDiagnostics.statusLabel)
                        .fontWeight(.medium)
                }
            }

            settingRow {
                Text(store.currentDiagnostics.summary)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        })
    }

    private var overviewSection: AnyView {
        AnyView(settingsSection(
            title: "Overview",
            detail: "Glance surfaces skills, MCPs, and cleanup candidates from the current source. These controls apply globally across sources. Rolling windows currently affect windowed sources only."
        ) {
            settingRow {
                Picker("Default window", selection: windowSelection) {
                    ForEach(store.availableWindows, id: \.rawValue) { window in
                        Text(window.title)
                            .tag(window as GlanceCore.RollingWindow)
                    }
                }
            }

            settingRow {
                Stepper(value: refreshInterval, in: 60 ... 3_600, step: 60) {
                    Text("Refresh interval: \(Int(store.policy.refreshIntervalSeconds))s")
                }
            }

            settingRow {
                Stepper(value: staleThreshold, in: 1 ... 90, step: 1) {
                    Text("Stale threshold: \(store.policy.staleAfterDays) days")
                }
            }

            settingRow {
                Stepper(value: removalThreshold, in: store.policy.staleAfterDays ... 120, step: 1) {
                    Text("Removal threshold: \(store.policy.removalAfterDays) days")
                }
            }

            settingRow {
                Stepper(value: minimumUsageToKeep, in: 1 ... 20, step: 1) {
                    Text("Rarely-used threshold: < \(store.policy.minimumUsageToKeep) uses")
                }
            }

            settingRow {
                Toggle("Treat never-used items as stale", isOn: neverUsedCountsAsStale)
            }
        })
    }

    private var sourcePathsSection: AnyView {
        AnyView(settingsSection(title: "Source Paths", detail: "Paths are shown for the active source so it stays clear what Glance is reading.") {
            ForEach(store.currentDiagnostics.artifacts) { artifact in
                settingRow {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle()
                            .fill(artifact.isPresent ? Color.green.opacity(0.8) : Color.orange.opacity(0.75))
                            .frame(width: 8, height: 8)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(artifact.label)
                                .font(.callout.weight(.medium))
                            Text(artifact.displayPath)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }

                        Spacer(minLength: 8)

                        Text(artifact.isPresent ? "Found" : "Missing")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(artifact.isPresent ? Color.secondary : Color.orange)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        })
    }

    private var aboutSection: AnyView {
        AnyView(settingsSection(title: "About", detail: "Version details and update checks for this copy of Glance.") {
            settingRow {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.inlinePadding) {
                    Text("Version")

                    Spacer(minLength: Metrics.inlinePadding)

                    Text(appMetadata.versionDescription)
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            settingRow {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.inlinePadding) {
                    Text("Check for Updates…")

                    Spacer(minLength: Metrics.inlinePadding)

                    Button("Check Now") {
                        updater.checkForUpdates()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!updater.canCheckForUpdates)
                }
            }
        })
    }

    private var supportSection: AnyView {
        AnyView(settingsSection(title: "Support", detail: "Copy or export the current app diagnostics when you need help troubleshooting a source or environment issue.") {
            settingRow {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.inlinePadding) {
                    Text("Copy Support Report")

                    Spacer(minLength: Metrics.inlinePadding)

                    Button("Copy") {
                        copySupportReport()
                    }
                    .buttonStyle(.bordered)
                }
            }

            settingRow {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.inlinePadding) {
                    Text("Export Support Report…")

                    Spacer(minLength: Metrics.inlinePadding)

                    Button("Export…") {
                        exportSupportReport()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let supportStatus {
                settingRow {
                    Text(supportStatus)
                        .foregroundStyle(supportStatusIsError ? Color.orange : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        })
    }

    private func settingsSection<Content: View>(
        title: String,
        detail: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Metrics.sectionContentSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.semibold))

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metrics.sectionPadding)
        .background(
            GlanceCardBackground(tone: .primary, cornerRadius: Metrics.sectionCornerRadius)
        )
    }

    private func settingRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Metrics.inlinePadding)
            .padding(.vertical, Metrics.rowVerticalPadding)
            .background(
                GlanceCardBackground(tone: .subtle, cornerRadius: Metrics.rowCornerRadius)
            )
    }

    private var sourceSelection: Binding<String> {
        Binding(
            get: { store.currentSource.id },
            set: { store.selectSource(id: $0) }
        )
    }

    private var windowSelection: Binding<GlanceCore.RollingWindow> {
        Binding(
            get: { store.selectedWindow },
            set: { store.setSelectedWindow($0) }
        )
    }

    private var refreshInterval: Binding<Double> {
        Binding(
            get: { store.policy.refreshIntervalSeconds },
            set: { newValue in
                store.updatePolicy { policy in
                    var updated = policy
                    updated.refreshIntervalSeconds = newValue
                    return updated
                }
            }
        )
    }

    private var staleThreshold: Binding<Int> {
        Binding(
            get: { store.policy.staleAfterDays },
            set: { newValue in
                store.updatePolicy { policy in
                    var updated = policy
                    updated.staleAfterDays = newValue
                    updated.removalAfterDays = max(updated.removalAfterDays, newValue)
                    return updated
                }
            }
        )
    }

    private var removalThreshold: Binding<Int> {
        Binding(
            get: { store.policy.removalAfterDays },
            set: { newValue in
                store.updatePolicy { policy in
                    var updated = policy
                    updated.removalAfterDays = newValue
                    return updated
                }
            }
        )
    }

    private var minimumUsageToKeep: Binding<Int> {
        Binding(
            get: { store.policy.minimumUsageToKeep },
            set: { newValue in
                store.updatePolicy { policy in
                    var updated = policy
                    updated.minimumUsageToKeep = newValue
                    return updated
                }
            }
        )
    }

    private var neverUsedCountsAsStale: Binding<Bool> {
        Binding(
            get: { store.policy.neverUsedCountsAsStale },
            set: { newValue in
                store.updatePolicy { policy in
                    var updated = policy
                    updated.neverUsedCountsAsStale = newValue
                    return updated
                }
            }
        )
    }

    private func makeSupportReport(now: Date = Date()) -> GlanceSupportReport {
        GlanceSupportReport(
            generatedAt: now,
            app: .init(
                name: appMetadata.applicationName,
                version: appMetadata.versionDescription,
                bundleIdentifier: Bundle.main.bundleIdentifier
            ),
            system: .init(
                operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                localeIdentifier: Locale.current.identifier,
                timeZoneIdentifier: TimeZone.current.identifier
            ),
            environment: GlanceSupportReport.filteredEnvironment(ProcessInfo.processInfo.environment),
            source: store.currentSource,
            diagnostics: store.currentDiagnostics,
            selectedWindow: store.selectedWindow,
            policy: store.policy,
            lastRefreshAt: store.lastRefreshAt,
            errorMessage: store.errorMessage,
            noticeMessage: store.noticeMessage
        )
    }

    private func copySupportReport() {
        do {
            let json = try makeSupportReport().jsonString()
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(json, forType: .string)
            supportStatus = "Support report copied."
            supportStatusIsError = false
        } catch {
            supportStatus = "Could not copy support report."
            supportStatusIsError = true
        }
    }

    private func exportSupportReport() {
        do {
            let report = makeSupportReport()
            let reportData = try report.jsonData()
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = report.suggestedFilename()
            guard panel.runModal() == .OK, let url = panel.url else {
                return
            }

            try reportData.write(to: url, options: .atomic)
            supportStatus = "Support report exported as \(url.lastPathComponent)."
            supportStatusIsError = false
        } catch {
            supportStatus = "Could not export support report."
            supportStatusIsError = true
        }
    }
}

private enum Metrics {
    static let windowMinWidth: CGFloat = 500
    static let windowIdealWidth: CGFloat = 520
    static let windowMinHeight: CGFloat = 404
    static let windowIdealHeight: CGFloat = 420
    static let outerPadding: CGFloat = 18
    static let sectionSpacing: CGFloat = 14
    static let sectionPadding: CGFloat = 14
    static let sectionCornerRadius: CGFloat = 14
    static let sectionContentSpacing: CGFloat = 12
    static let rowSpacing: CGFloat = 10
    static let rowCornerRadius: CGFloat = 10
    static let rowVerticalPadding: CGFloat = 10
    static let inlinePadding: CGFloat = 12
}
