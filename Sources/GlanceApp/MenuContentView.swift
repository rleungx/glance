import AppKit
import SwiftUI
import GlanceCore

@MainActor
struct MenuContentView: View {
    @ObservedObject var store: GlanceStore
    @Environment(\.openWindow) private var openWindow
    @Namespace private var sourceSwitcherNamespace
    private let visibleItemLimit = 3

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
            overviewPanel

            capabilitySection(
                title: "Top Skills",
                systemImage: "sparkles",
                items: store.activeSnapshot.skills
            )
            capabilitySection(
                title: "Top MCPs",
                systemImage: "slider.horizontal.3",
                items: store.topMCPs
            )
            let cleanupItems = cleanupItems
            if !cleanupItems.isEmpty {
                capabilitySection(
                    title: "Insights",
                    systemImage: "trash.slash",
                    items: cleanupItems
                )
            }

            actionBar
        }
        .padding(Metrics.outerPadding)
        .frame(width: Metrics.menuWidth)
        .background(GlanceVisualStyle.canvas.opacity(0.96))
    }

    private var overviewPanel: some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            HStack(alignment: .center, spacing: Metrics.contentSpacing) {
                VStack(alignment: .leading, spacing: Metrics.compactTextSpacing) {
                    Text("Glance")
                        .font(.headline.weight(.semibold))
                    Text(store.summaryLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: Metrics.contentSpacing)

                headerStatusBadge
            }

            GlanceDivider()

            controlPanel

            if let errorMessage = store.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, Metrics.cardPadding)
                    .padding(.vertical, Metrics.rowVerticalPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Metrics.innerCornerRadius, style: .continuous)
                            .fill(GlanceVisualStyle.warningTint)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Metrics.innerCornerRadius, style: .continuous)
                            .stroke(GlanceVisualStyle.warningBorder, lineWidth: 1)
                    )
            }

            if store.errorMessage == nil, let noticeMessage = store.noticeMessage {
                Label(noticeMessage, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Metrics.cardPadding)
                    .padding(.vertical, Metrics.rowVerticalPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Metrics.innerCornerRadius, style: .continuous)
                            .fill(GlanceVisualStyle.subtleSurface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Metrics.innerCornerRadius, style: .continuous)
                            .stroke(GlanceVisualStyle.quietBorder, lineWidth: 1)
                    )
            }
        }
        .padding(Metrics.cardPadding)
        .background(sectionSurface)
    }

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: Metrics.controlGroupSpacing) {
            VStack(alignment: .leading, spacing: Metrics.tightSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.contentSpacing) {
                    Label("Source", systemImage: "square.stack.3d.up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: Metrics.contentSpacing)

                    if store.availableSources.count <= 1 {
                        sourceImage(
                            for: store.currentSource,
                            symbolFont: .caption2.weight(.medium),
                            logoSize: Metrics.accessorySourceImageSize,
                            symbolStyle: AnyShapeStyle(.tertiary)
                        )
                            .accessibilityLabel(store.currentSource.displayName)
                            .help(store.currentSource.displayName)
                    }
                }

                sourceSwitcher
            }

            HStack(spacing: Metrics.pillSpacing) {
                statusPill(title: store.effectiveWindowLabel, systemImage: "calendar")

                if store.isRefreshing {
                    statusPill(title: "Refreshing…", systemImage: "arrow.clockwise")
                }

                if let lastRefreshAt = store.lastRefreshAt {
                    HStack(spacing: Metrics.statusAccessorySpacing) {
                        statusPill(title: "Updated \(lastRefreshAt.formatted(date: .omitted, time: .shortened))", systemImage: "clock")

                        if !store.isRefreshing {
                            refreshButton
                        }
                    }
                } else if !store.isRefreshing {
                    refreshButton
                }
            }
        }
    }

    @ViewBuilder
    private func capabilitySection(title: String, systemImage: String, items: [CapabilityUsage]) -> some View {
        let visibleItems = Array(items.prefix(visibleItemLimit))

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))

                Spacer(minLength: Metrics.contentSpacing)

                Text("Top \(visibleItemLimit)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Metrics.pillHorizontalPadding)
                    .padding(.vertical, Metrics.pillVerticalPadding)
                    .background(
                        Capsule(style: .continuous)
                            .fill(GlanceVisualStyle.subtleSurface)
                    )
            }
            .padding(.horizontal, Metrics.cardPadding)
            .padding(.top, Metrics.cardPadding)
            .padding(.bottom, Metrics.sectionHeaderBottomPadding)

            if visibleItems.isEmpty {
                GlanceDivider()

                Text("No data yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Metrics.cardPadding)
                    .padding(.vertical, Metrics.rowVerticalPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                GlanceDivider()

                VStack(spacing: 0) {
                    ForEach(Array(visibleItems.indices), id: \.self) { index in
                        capabilityRow(usage: visibleItems[index])

                        if index < visibleItems.count - 1 {
                            GlanceDivider(leadingInset: Metrics.dividerInset)
                        }
                    }
                }
            }
        }
        .background(sectionSurface)
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: GlanceAppMain.settingsWindowID)
                DispatchQueue.main.async {
                    NSApp.windows
                        .first(where: { $0.identifier?.rawValue == GlanceAppMain.settingsWindowID || $0.title == "Settings" })?
                        .center()
                }
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)

            Spacer(minLength: 12)

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.small)
        .padding(Metrics.cardPadding)
        .background(sectionSurface)
    }

    private var sourceSelection: Binding<String> {
        Binding(
            get: { store.currentSource.id },
            set: { store.selectSource(id: $0) }
        )
    }

    private var cleanupItems: [CapabilityUsage] {
        var seen = Set<String>()
        return (store.visibleRemovalCandidates + store.visibleStale).filter { usage in
            let key = usage.id.id
            if seen.contains(key) {
                return false
            }
            seen.insert(key)
            return true
        }
    }

    @ViewBuilder
    private var sourceSwitcher: some View {
        if store.availableSources.count <= 4 {
            HStack(spacing: Metrics.sourceSwitcherInnerPadding) {
                ForEach(store.availableSources) { source in
                    sourceChip(for: source)
                }
            }
            .padding(Metrics.sourceSwitcherInnerPadding)
            .background(
                GlanceCardBackground(tone: .inset, cornerRadius: Metrics.sourceSwitcherCornerRadius)
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Source")
        } else {
            Menu {
                ForEach(store.availableSources) { source in
                    Button {
                        store.selectSource(id: source.id)
                    } label: {
                        HStack(spacing: Metrics.sourceChipContentSpacing) {
                            if source.id == store.currentSource.id {
                                Image(systemName: "checkmark")
                            }

                            sourceImage(
                                for: source,
                                symbolFont: .body,
                                logoSize: Metrics.menuSourceImageSize,
                                symbolStyle: AnyShapeStyle(.primary)
                            )
                        }
                        .accessibilityLabel(source.displayName)
                        .help(source.displayName)
                    }
                }
            } label: {
                HStack(spacing: Metrics.contentSpacing) {
                    sourceImage(
                        for: store.currentSource,
                        symbolFont: .caption.weight(.medium),
                        logoSize: Metrics.menuSourceImageSize,
                        symbolStyle: AnyShapeStyle(.primary)
                    )
                        .accessibilityHidden(true)

                    Spacer(minLength: Metrics.contentSpacing)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Metrics.menuPickerHorizontalPadding)
                .padding(.vertical, Metrics.menuPickerVerticalPadding)
                .background(
                    GlanceCardBackground(tone: .inset, cornerRadius: Metrics.sourceSwitcherCornerRadius)
                )
            }
            .menuStyle(.borderlessButton)
            .disabled(store.availableSources.count <= 1)
            .accessibilityLabel("Source: \(store.currentSource.displayName)")
            .help(store.currentSource.displayName)
        }
    }

    private func sourceChip(for source: GlanceSource) -> some View {
        let isSelected = source.id == store.currentSource.id
        let diagnostics = store.diagnostics(for: source)

        return Button {
            guard !isSelected else {
                return
            }

            withAnimation(SourceSwitcherAnimation.selectionSpring) {
                store.selectSource(id: source.id)
            }
        } label: {
            HStack(spacing: Metrics.sourceChipContentSpacing) {
                Circle()
                    .fill(sourceIndicatorColor(for: diagnostics, isSelected: isSelected))
                    .frame(width: Metrics.sourceChipIndicatorSize, height: Metrics.sourceChipIndicatorSize)

                sourceImage(
                    for: source,
                    symbolFont: .caption.weight(isSelected ? .semibold : .medium),
                    logoSize: Metrics.sourceChipImageSize,
                    symbolStyle: isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
                )
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Metrics.sourceChipHorizontalPadding)
            .padding(.vertical, Metrics.sourceChipVerticalPadding)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: Metrics.sourceChipCornerRadius, style: .continuous)
                        .fill(GlanceVisualStyle.activeControlSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: Metrics.sourceChipCornerRadius, style: .continuous)
                                .stroke(GlanceVisualStyle.activeControlBorder, lineWidth: 1)
                        )
                        .shadow(color: GlanceVisualStyle.controlShadow, radius: 6, y: 1)
                        .matchedGeometryEffect(id: "source-selection", in: sourceSwitcherNamespace)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Metrics.sourceChipCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(store.availableSources.count <= 1)
        .accessibilityLabel(source.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help("\(source.displayName) · \(diagnostics.summary)")
    }

    private func sourceIndicatorColor(for diagnostics: GlanceSourceDiagnostics, isSelected: Bool) -> Color {
        switch diagnostics.readiness {
        case .ready:
            return isSelected ? GlanceVisualStyle.accentForeground : Color.secondary.opacity(0.35)
        case .needsSetup:
            return Color.orange.opacity(isSelected ? 0.9 : 0.7)
        case .unavailable:
            return Color.red.opacity(isSelected ? 0.85 : 0.6)
        }
    }

    @ViewBuilder
    private func sourceImage(for source: GlanceSource, symbolFont: Font, logoSize: CGFloat, symbolStyle: AnyShapeStyle) -> some View {
        if let logoImage = sourceLogoImage(for: source) {
            Image(nsImage: logoImage)
                .renderingMode(.original)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: logoSize, height: logoSize)
        } else {
            Image(systemName: source.systemImageName)
                .font(symbolFont)
                .foregroundStyle(symbolStyle)
                .frame(width: logoSize, height: logoSize)
        }
    }

    private func sourceLogoImage(for source: GlanceSource) -> NSImage? {
        guard let assetName = source.logoAssetName else {
            return nil
        }

        return SourceLogoCache.image(named: assetName)
    }

    private var headerStatusBadge: some View {
        Image(systemName: store.statusIconName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(GlanceVisualStyle.accentForeground)
            .frame(width: Metrics.statusBadgeSize, height: Metrics.statusBadgeSize)
            .background(
                GlanceCardBackground(tone: .accent, cornerRadius: Metrics.statusBadgeCornerRadius)
            )
    }

    private func capabilityRow(usage: CapabilityUsage) -> some View {
        HStack(alignment: .center, spacing: Metrics.contentSpacing) {
            Circle()
                .fill(rowAccentColor(for: usage))
                .frame(width: Metrics.rowAccentSize, height: Metrics.rowAccentSize)

            VStack(alignment: .leading, spacing: 3) {
                Text(usage.id.displayName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(detailText(for: usage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("\(usage.usageCount)x")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, Metrics.pillHorizontalPadding)
                .padding(.vertical, Metrics.pillVerticalPadding)
                .background(
                    Capsule(style: .continuous)
                        .fill(GlanceVisualStyle.subtleSurface)
                )
        }
        .padding(.horizontal, Metrics.cardPadding)
        .padding(.vertical, Metrics.rowVerticalPadding)
    }

    private func statusPill(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Metrics.pillHorizontalPadding)
            .padding(.vertical, Metrics.pillVerticalPadding + 1)
            .background(
                Capsule(style: .continuous)
                    .fill(GlanceVisualStyle.subtleSurface)
            )
    }

    private var refreshButton: some View {
        Button {
            Task {
                await store.refresh()
            }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: Metrics.statusAccessorySize, height: Metrics.statusAccessorySize)
                .background(
                    Capsule(style: .continuous)
                        .fill(GlanceVisualStyle.subtleSurface)
                )
        }
        .buttonStyle(.plain)
        .disabled(store.isRefreshing)
        .accessibilityLabel("Refresh now")
        .accessibilityHint("Refresh the current source")
        .help(store.isRefreshing ? "Refreshing current source" : "Refresh current source")
    }

    private func rowAccentColor(for usage: CapabilityUsage) -> Color {
        if usage.installedButUnused {
            return Color.orange.opacity(0.78)
        }

        if usage.hasOutcomeData, usage.successRate >= 0.8 {
            return GlanceVisualStyle.accentForeground
        }

        return .secondary.opacity(0.6)
    }

    private func detailText(for usage: CapabilityUsage) -> String {
        if usage.installedButUnused {
            return usage.id.kind == .mcpServer ? "Configured but unused" : "Installed but unused"
        }

        let lastUsed = usage.lastUsedAt ?? usage.firstUsedAt
        let lastUsedText = lastUsed.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "never"
        if usage.hasOutcomeData {
            let successRate = Int((usage.successRate * 100).rounded())
            return "Last used \(lastUsedText) · \(successRate)% success"
        }
        return "Last used \(lastUsedText) · outcome unknown"
    }

    private var sectionSurface: some View {
        GlanceCardBackground(tone: .primary, cornerRadius: Metrics.innerCornerRadius)
    }
}

private enum Metrics {
    static let menuWidth: CGFloat = 368
    static let outerPadding: CGFloat = 14
    static let sectionSpacing: CGFloat = 12
    static let innerCornerRadius: CGFloat = 10
    static let cardPadding: CGFloat = 12
    static let headerSpacing: CGFloat = 10
    static let controlGroupSpacing: CGFloat = 12
    static let contentSpacing: CGFloat = 10
    static let compactTextSpacing: CGFloat = 2
    static let tightSpacing: CGFloat = 6
    static let rowVerticalPadding: CGFloat = 10
    static let pillHorizontalPadding: CGFloat = 8
    static let pillVerticalPadding: CGFloat = 4
    static let pillSpacing: CGFloat = 8
    static let statusAccessorySpacing: CGFloat = 6
    static let statusAccessorySize: CGFloat = 24
    static let dividerInset: CGFloat = 40
    static let sectionHeaderBottomPadding: CGFloat = 10
    static let statusBadgeSize: CGFloat = 28
    static let statusBadgeCornerRadius: CGFloat = 10
    static let rowAccentSize: CGFloat = 8
    static let sourceSwitcherCornerRadius: CGFloat = 11
    static let sourceSwitcherInnerPadding: CGFloat = 4
    static let sourceChipCornerRadius: CGFloat = 8
    static let sourceChipHorizontalPadding: CGFloat = 10
    static let sourceChipVerticalPadding: CGFloat = 7
    static let sourceChipContentSpacing: CGFloat = 6
    static let sourceChipIndicatorSize: CGFloat = 6
    static let accessorySourceImageSize: CGFloat = 12
    static let menuSourceImageSize: CGFloat = 14
    static let sourceChipImageSize: CGFloat = 14
    static let menuPickerHorizontalPadding: CGFloat = 10
    static let menuPickerVerticalPadding: CGFloat = 8
}

private enum SourceSwitcherAnimation {
    static let selectionSpring = Animation.spring(response: 0.24, dampingFraction: 0.86)
}

private enum SourceLogoResource {
    static let directory = "SourceLogos"
    static let supportedExtensions = ["pdf", "png"]
}

@MainActor
private enum SourceLogoCache {
    private static let images = NSCache<NSString, NSImage>()
    private static let normalizedImageSize = NSSize(width: 64, height: 64)

    static func image(named assetName: String) -> NSImage? {
        let cacheKey = assetName as NSString
        if let cachedImage = images.object(forKey: cacheKey) {
            return cachedImage
        }

        for bundle in [Bundle.module, Bundle.main] {
            for fileExtension in SourceLogoResource.supportedExtensions {
                if let url = bundle.url(
                    forResource: assetName,
                    withExtension: fileExtension,
                    subdirectory: SourceLogoResource.directory
                ) ?? bundle.url(forResource: assetName, withExtension: fileExtension),
                let image = NSImage(contentsOf: url),
                let normalizedImage = normalizedSquareImage(from: image) {
                    images.setObject(normalizedImage, forKey: cacheKey)
                    return normalizedImage
                }
            }
        }

        return nil
    }

    private static func normalizedSquareImage(from image: NSImage) -> NSImage? {
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return nil
        }

        let normalizedImage = NSImage(size: normalizedImageSize)
        normalizedImage.lockFocus()
        defer { normalizedImage.unlockFocus() }

        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: normalizedImageSize)).fill()

        let scale = min(normalizedImageSize.width / sourceSize.width, normalizedImageSize.height / sourceSize.height)
        let drawSize = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let drawOrigin = NSPoint(
            x: (normalizedImageSize.width - drawSize.width) / 2,
            y: (normalizedImageSize.height - drawSize.height) / 2
        )

        image.draw(
            in: NSRect(origin: drawOrigin, size: drawSize),
            from: NSRect(origin: .zero, size: sourceSize),
            operation: .sourceOver,
            fraction: 1
        )

        normalizedImage.isTemplate = false
        return normalizedImage
    }
}
