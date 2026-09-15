import AppKit
import SwiftUI
import UniformTypeIdentifiers
import GlanceCore

@MainActor
struct GlanceSettingsView: View {
    @ObservedObject var store: GlanceStore
    @ObservedObject var updater: GlanceUpdater
    private let appMetadata = GlanceAppMetadata()
    @State private var supportStatus: String?
    @State private var supportStatusIsError = false
    @State private var showsDataDetails = false
    @State private var showsCleanupOptions = false

    var body: some View {
        TabView {
            generalSettings
                .tabItem { Label("General", systemImage: "gearshape") }

            sourceSettings
                .tabItem { Label("Sources", systemImage: "square.stack.3d.up") }

            aboutSettings
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(20)
        .frame(minWidth: 560, idealWidth: 600, minHeight: 460, idealHeight: 540)
        .background(GlanceVisualStyle.canvas)
    }

    private var generalSettings: some View {
        Form {
            Section {
                Picker("Time range", selection: windowSelection) {
                    ForEach(store.availableWindows) { window in
                        Text(window == .day1 ? "Last 24 hours" : "Last \(window.rawValue) days")
                            .tag(window)
                    }
                }

                Stepper(value: refreshInterval, in: 60 ... 3_600, step: 60) {
                    LabeledContent("Refresh every", value: refreshIntervalLabel)
                }
                .accessibilityValue(refreshIntervalLabel)
            } header: {
                Text("Activity")
            } footer: {
                Text("These preferences apply to all your assistants. You can also change the time range from the menu bar.")
            }

            Section {
                DisclosureGroup("Cleanup suggestions", isExpanded: $showsCleanupOptions) {
                    Stepper(value: staleThreshold, in: 1 ... 90) {
                        LabeledContent("Mark inactive after", value: "\(store.policy.staleAfterDays) days")
                    }
                    Stepper(value: removalThreshold, in: store.policy.staleAfterDays ... 120) {
                        LabeledContent("Suggest removal after", value: "\(store.policy.removalAfterDays) days")
                    }
                    Stepper(value: minimumUsageToKeep, in: 1 ... 20) {
                        LabeledContent("Rarely used", value: "Fewer than \(store.policy.minimumUsageToKeep) uses")
                    }
                    Toggle("Include unused skills", isOn: neverUsedCountsAsStale)
                }
            } header: {
                Text("Insights")
            } footer: {
                Text("Suggestions require verified history. Glance never removes a skill automatically.")
            }
        }
        .formStyle(.grouped)
    }

    private var sourceSettings: some View {
        Form {
            Section {
                Picker("Assistant", selection: sourceSelection) {
                    ForEach(store.availableSources) { source in
                        Text(source.displayName).tag(source.id)
                    }
                }
                .disabled(store.availableSources.count <= 1)

                LabeledContent("Status") {
                    Label(store.currentDiagnostics.statusLabel, systemImage: sourceStatusSymbol)
                        .foregroundStyle(.secondary)
                }

                if store.isInventoryOnly {
                    LabeledContent("Usage statistics", value: "Not supported yet")
                    Text("Only global skill definitions are shown. Files on disk do not confirm that a skill is enabled.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let error = store.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                }
            } header: {
                Text("Current Source")
            } footer: {
                Text(store.currentDiagnostics.summary)
            }

            Section("Local Data") {
                ForEach(store.currentDiagnostics.artifacts) { artifact in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: artifact.kind == .directory ? "folder" : (artifact.kind == .command ? "terminal" : "doc.text"))
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(artifact.label)
                                Spacer()
                                Label(artifact.isPresent ? "Found" : "Missing",
                                      systemImage: artifact.isPresent ? "checkmark.circle" : "exclamationmark.circle")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }

                            Text(artifact.displayPath)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if store.isInventoryOnly {
                Section("Inventory Scope") {
                    Text(store.noticeMessage ?? store.currentDiagnostics.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Section {
                    DisclosureGroup("Activity coverage", isExpanded: $showsDataDetails) {
                        LabeledContent("Files read", value: store.usageEvidence.filesRead.formatted())
                        LabeledContent("Duplicates excluded", value: store.usageEvidence.duplicates.formatted())
                        LabeledContent("Inferred event IDs", value: store.usageEvidence.inferredIdentities.formatted())
                        LabeledContent("Unreadable files", value: store.usageEvidence.skippedFiles.formatted())
                        LabeledContent("Unparsed records", value: store.usageEvidence.skippedRecords.formatted())
                        LabeledContent("Outside known inventory", value: store.usageEvidence.unmatchedRecords.formatted())

                        if let first = store.usageEvidence.observedFrom, let last = store.usageEvidence.observedThrough {
                            LabeledContent("First observed", value: first.formatted(date: .abbreviated, time: .shortened))
                            LabeledContent("Last observed", value: last.formatted(date: .abbreviated, time: .shortened))
                        }

                        ForEach(store.usageEvidence.sources, id: \.self) { source in
                            Text((source as NSString).abbreviatingWithTildeInPath)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if let notice = store.noticeMessage, notice != store.usageEvidence.summary {
                            Text(notice).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text(store.usageEvidence.summary)
                }
            }

            Section {
                LabeledContent("Support report") {
                    Button("Copy", action: copySupportReport)
                    Button("Export…", action: exportSupportReport)
                }

                if let supportStatus {
                    Label(supportStatus, systemImage: supportStatusIsError ? "exclamationmark.circle" : "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Diagnostics")
            } footer: {
                Text("Copy or export a report when troubleshooting a source.")
            }
        }
        .formStyle(.grouped)
    }

    private var aboutSettings: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 24)

            Image(systemName: "sparkles")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 80, height: 80)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 18))
                .accessibilityHidden(true)

            Text(appMetadata.applicationName)
                .font(.largeTitle.weight(.semibold))
            Text(appMetadata.versionDescription)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            Text("Skill activity across your coding assistants.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)

            Button("Check for Updates…") {
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheckForUpdates)
            .padding(.top, 12)

            if !updater.canCheckForUpdates {
                Text("Update checking is currently unavailable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var refreshIntervalLabel: String {
        let minutes = Int(store.policy.refreshIntervalSeconds / 60)
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }

    private var sourceStatusSymbol: String {
        switch store.currentDiagnostics.readiness {
        case .ready: return "checkmark.circle"
        case .needsSetup: return "exclamationmark.circle"
        case .unavailable: return "minus.circle"
        }
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
            noticeMessage: store.noticeMessage,
            evidence: store.usageEvidence
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
