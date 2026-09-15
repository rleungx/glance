import AppKit
import SwiftUI
import GlanceCore

@MainActor
struct MenuContentView: View {
    @ObservedObject var store: GlanceStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsAllSkills = false
    @State private var showsDataDetails = false
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 60
    private let visibleItemLimit = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Picker("Assistant", selection: sourceSelection) {
                ForEach(store.availableSources) { source in
                    Text(source.displayName).tag(source.id)
                }
            }
            .pickerStyle(.menu)
            .disabled(store.availableSources.count <= 1)
            .help("Choose the assistant whose skills you want to see")

            if store.errorMessage == nil, !store.isInventoryOnly, !store.activeSnapshot.skills.isEmpty {
                activitySummary
            }

            if store.isInventoryOnly, store.errorMessage == nil {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Skill inventory only", systemImage: "info.circle")
                        .font(.subheadline.weight(.medium))
                    Text("Discover global skill files. Usage statistics and enabled state aren’t available yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if store.usageEvidence.skippedFiles > 0 {
                        Label("Some skill locations couldn’t be inspected.", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let error = store.errorMessage {
                errorNotice(error)
            }

            skillsSection

            if !cleanupItems.isEmpty {
                insightsSection
            }

            dataStatus

            Divider()

            footer
        }
        .padding(GlanceVisualStyle.contentInset)
        .frame(width: 384)
        .background(GlancePanelBackground())
        .onChange(of: store.currentSource.id) { _ in showsAllSkills = false }
        .onChange(of: store.selectedWindow) { _ in showsAllSkills = false }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Glance")
                    .font(.headline)
                Text(store.isInventoryOnly ? "Skill library" : "Skill activity")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await store.refresh() }
            } label: {
                ZStack {
                    Image(systemName: "arrow.clockwise")
                        .opacity(store.isRefreshing ? 0 : 1)
                    if store.isRefreshing {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .disabled(store.isRefreshing)
            .keyboardShortcut("r")
            .accessibilityLabel(store.isRefreshing ? "Refreshing skills" : "Refresh skills")
            .help("Refresh skills (⌘R)")
        }
    }

    private var activitySummary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(totalActivations, format: .number)
                .font(.system(.title, design: .rounded, weight: .semibold))
                .monospacedDigit()
            Text(totalActivations == 1 ? "activation" : "activations")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text("\(store.activeSnapshot.skills.count) skills")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(totalActivations) observed skill activations across \(store.activeSnapshot.skills.count) skills, \(store.effectiveWindowLabel)")
    }

    private var skillsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(store.isInventoryOnly ? "Discovered Skills" : (showsAllSkills ? "All Skills" : "Top Skills"))
                    .font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                if !store.isInventoryOnly {
                    Picker("Time range", selection: windowSelection) {
                        ForEach(store.availableWindows) { window in
                            Text(windowName(window)).tag(window)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                    .controlSize(.small)
                    .disabled(!store.currentDiagnostics.supportsRollingWindows)
                    .accessibilityLabel("Time range")
                }
            }

            if store.activeSnapshot.skills.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(visibleSkills.enumerated()), id: \.element.id) { index, usage in
                            skillRow(usage, rank: index + 1)
                            if index < visibleSkills.count - 1 {
                                Divider().padding(.leading, 40)
                            }
                        }
                    }
                }
                .frame(height: min(CGFloat(visibleSkills.count) * rowHeight + CGFloat(max(0, visibleSkills.count - 1)), 320))
                .background(
                    GlanceVisualStyle.groupedBackground,
                    in: RoundedRectangle(cornerRadius: GlanceVisualStyle.cornerRadius)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: GlanceVisualStyle.cornerRadius)
                        .strokeBorder(GlanceVisualStyle.separator, lineWidth: 0.5)
                }

                if store.activeSnapshot.skills.count > visibleItemLimit {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                            showsAllSkills.toggle()
                        }
                    } label: {
                        HStack {
                            Text(showsAllSkills ? (store.isInventoryOnly ? "Show fewer" : "Show top \(visibleItemLimit)") : "Show all \(store.activeSnapshot.skills.count) skills")
                            Spacer()
                            Image(systemName: showsAllSkills ? "chevron.up" : "chevron.down")
                                .font(.caption2.weight(.semibold))
                        }
                        .frame(minHeight: 24)
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .accessibilityValue(showsAllSkills ? "Expanded" : "Collapsed")
                }
            }
        }
    }

    private func skillRow(_ usage: CapabilityUsage, rank: Int) -> some View {
        HStack(spacing: 10) {
            Group {
                if store.isInventoryOnly {
                    Image(systemName: "doc.text")
                } else {
                    Text(rank, format: .number)
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 18)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(usage.id.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(detailText(for: usage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !store.isInventoryOnly {
                Text(usage.usageCount, format: .number)
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(usage.usageCount > 0 ? Color.primary : Color.secondary)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: rowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(store.isInventoryOnly
            ? "\(usage.id.displayName), skill definition at \(usage.id.namespace). Usage statistics unavailable."
            : "\(usage.id.displayName), \(usage.usageCount) observed activations. \(detailText(for: usage))")
        .help(([usage.id.displayName, detailText(for: usage)] + (usage.evidenceSamples ?? []).map {
            "\(($0.file as NSString).abbreviatingWithTildeInPath): \($0.record)"
        }).joined(separator: "\n"))
        .contextMenu {
            Text(usage.id.displayName)
            if store.isInventoryOnly {
                Text("Usage statistics unavailable")
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: usage.id.namespace)])
                }
            } else {
                Text("\(usage.usageCount) observed activations")
                if usage.hasOutcomeData {
                    Text("\(usage.successCount) successful · \(usage.failureCount) failed")
                }
                if let usedAt = usage.lastUsedAt {
                    Text("Last observed \(usedAt.formatted(date: .abbreviated, time: .shortened))")
                }
            }
            Divider()
            Button("Copy Skill Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(usage.id.displayName, forType: .string)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            if store.isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: store.errorMessage == nil ? "sparkle.magnifyingglass" : "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            Text(emptyStateTitle)
                .font(.headline)
            Text(emptyStateDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if !store.isRefreshing {
                Button("Open Settings…", action: openSettings)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            GlanceVisualStyle.groupedBackground,
            in: RoundedRectangle(cornerRadius: GlanceVisualStyle.cornerRadius)
        )
    }

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Worth a look", systemImage: "lightbulb")
                .font(.subheadline.weight(.semibold))
            ForEach(cleanupItems.prefix(3)) { usage in
                HStack {
                    Text(usage.id.displayName).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(usage.usageCount == 0 ? "Unused" : "Inactive")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .help(usage.id.displayName)
            }
        }
    }

    private func errorNotice(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(GlanceVisualStyle.groupedBackground, in: RoundedRectangle(cornerRadius: 8))
    }

    private var dataStatus: some View {
        HStack(spacing: 6) {
            Button {
                showsDataDetails.toggle()
            } label: {
                Label(dataStatusTitle, systemImage: "info.circle")
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(.secondary)
            .help("View data coverage and any reading issues")
            .popover(isPresented: $showsDataDetails, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(store.isInventoryOnly ? "About These Skills" : "About This Activity").font(.headline)
                    Text(store.usageEvidence.summary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let notice = store.noticeMessage, notice != store.usageEvidence.summary {
                        Text(notice).foregroundStyle(.secondary)
                    }
                    if !store.isInventoryOnly {
                        Text("Counts reflect observed skill activations. They don’t confirm that every skill instruction was followed.")
                            .foregroundStyle(.secondary)
                    }
                    Button("Done") { showsDataDetails = false }
                        .keyboardShortcut(.cancelAction)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.subheadline)
                .padding(16)
                .frame(width: 300)
            }

            Spacer(minLength: 4)

            if let updated = store.lastRefreshAt {
                Text(updated, format: .dateTime.hour().minute())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Updated at \(updated.formatted(date: .omitted, time: .shortened))")
                    .help("Updated \(updated.formatted(date: .abbreviated, time: .shortened))")
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(action: openSettings) {
                Label("Settings…", systemImage: "gearshape")
            }
            .keyboardShortcut(",")

            Spacer()

            Button("Quit Glance") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .buttonStyle(.borderless)
    }

    private var sourceSelection: Binding<String> {
        Binding(get: { store.currentSource.id }, set: { store.selectSource(id: $0) })
    }

    private var windowSelection: Binding<RollingWindow> {
        Binding(get: { store.selectedWindow }, set: { store.setSelectedWindow($0) })
    }

    private var visibleSkills: [CapabilityUsage] {
        showsAllSkills ? store.activeSnapshot.skills : Array(store.activeSnapshot.skills.prefix(visibleItemLimit))
    }

    private var totalActivations: Int {
        store.activeSnapshot.skills.reduce(0) { $0 + $1.usageCount }
    }

    private var cleanupItems: [CapabilityUsage] {
        var seen = Set<CapabilityID>()
        return (store.visibleRemovalCandidates + store.visibleStale).filter { seen.insert($0.id).inserted }
    }

    private var dataStatusTitle: String {
        if store.isRefreshing { return store.isInventoryOnly ? "Reading skill definitions…" : "Reading local history…" }
        if store.isInventoryOnly {
            return store.usageEvidence.skippedFiles > 0 ? "Skill inventory may be incomplete" : "Skill inventory only"
        }
        if let notice = store.noticeMessage, notice != store.usageEvidence.summary {
            return "Some activity may be missing"
        }
        switch store.usageEvidence.completeness {
        case .unavailable: return "Activity unavailable"
        case .partial: return "Some activity may be missing"
        case .observed: return "Local history · Coverage unverified"
        case .verified: return "Verified history"
        }
    }

    private var emptyStateTitle: String {
        if store.isRefreshing { return store.isInventoryOnly ? "Reading skill definitions…" : "Reading skill activity…" }
        if store.currentDiagnostics.readiness != .ready { return store.isInventoryOnly ? "No skill directories found" : "Connect your assistant" }
        if store.errorMessage != nil { return store.isInventoryOnly ? "Inventory couldn’t be loaded" : "Activity couldn’t be loaded" }
        if store.isInventoryOnly, store.usageEvidence.skippedFiles > 0 { return "Inventory may be incomplete" }
        return store.isInventoryOnly ? "No skill definitions found" : "No skills found"
    }

    private var emptyStateDescription: String {
        if store.isRefreshing { return store.isInventoryOnly ? "Global skill files will appear here." : "Your recent activity will appear here." }
        if store.currentDiagnostics.readiness != .ready {
            return store.isInventoryOnly ? "Check the global skill directories listed in Settings."
                : "Choose a configured assistant or check its local data in Settings."
        }
        if store.errorMessage != nil { return "Try refreshing, or check this source in Settings." }
        if store.isInventoryOnly, store.usageEvidence.skippedFiles > 0 {
            return "Some skill locations could not be read. Check the details in Settings."
        }
        return store.isInventoryOnly ? "Add a skill to one of the global directories listed in Settings."
            : "Skills discovered for \(store.currentSource.displayName) will appear here."
    }

    private func detailText(for usage: CapabilityUsage) -> String {
        if store.isInventoryOnly { return (usage.id.namespace as NSString).abbreviatingWithTildeInPath }
        guard usage.usageCount > 0 else { return "No activity observed" }
        let lastUsed = usage.lastUsedAt ?? usage.firstUsedAt
        let date = lastUsed.map { $0.formatted(.relative(presentation: .named)) } ?? "date unknown"
        guard usage.hasOutcomeData else { return "Last observed \(date)" }
        let rate = Int((usage.successRate * 100).rounded())
        return "\(date) · \(rate)% success (\(usage.successCount + usage.failureCount) known)"
    }

    private func windowName(_ window: RollingWindow) -> String {
        window == .day1 ? "24 hours" : "\(window.rawValue) days"
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: GlanceAppMain.settingsWindowID)
    }
}
