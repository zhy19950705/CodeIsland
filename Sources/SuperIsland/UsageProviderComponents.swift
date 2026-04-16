import SwiftUI
import AppKit
import SuperIslandCore

// UsageProviderRow and its frozen table implementation are shared usage UI components for the AI settings page.
struct UsageProviderRow: View {
    @ObservedObject private var l10n = L10n.shared
    let provider: UsageProviderSnapshot
    var showHeader: Bool = true
    @State private var selectedHistoryPreset: UsageHistoryRangePreset = .recent30Days

    private var availableHistories: [UsageHistoryRangeSnapshot] {
        (provider.history ?? []).sorted { $0.preset.sortOrder < $1.preset.sortOrder }
    }

    private var selectedHistory: UsageHistoryRangeSnapshot? {
        availableHistories.first(where: { $0.preset == selectedHistoryPreset }) ?? availableHistories.first
    }

    private var selectedHistoryBinding: Binding<UsageHistoryRangePreset> {
        Binding(
            get: {
                availableHistories.contains(where: { $0.preset == selectedHistoryPreset })
                    ? selectedHistoryPreset
                    : (availableHistories.first?.preset ?? .recent30Days)
            },
            set: { selectedHistoryPreset = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showHeader {
                HStack {
                    Text(provider.source.title)
                    Spacer()
                    if let updatedAtUnix = provider.updatedAtUnix {
                        Text(relativeTime(updatedAtUnix))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if provider.hasQuotaMetrics {
                HStack(spacing: 10) {
                    usageBadge(title: provider.primary.badgeTitle(), percentage: provider.primary.percentage, detail: provider.primary.detail)
                    usageBadge(title: provider.secondary.badgeTitle(), percentage: provider.secondary.percentage, detail: provider.secondary.detail)
                }
            }
            if let summary = provider.summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if availableHistories.count > 1 {
                Picker("", selection: selectedHistoryBinding) {
                    ForEach(availableHistories.map(\.preset), id: \.self) { preset in
                        Text(historyTitle(for: preset))
                            .tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if let selectedHistory {
                Text(historySummary(selectedHistory))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                usageHistoryTable(selectedHistory)
                    .padding(.top, 4)
            } else if let monthly = provider.monthly {
                Text(monthlySummary(monthly))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func usageHistoryTable(_ history: UsageHistoryRangeSnapshot) -> some View {
        if history.rows.isEmpty {
            Text(l10n["usage_breakdown_empty"])
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            FrozenUsageHistoryTable(
                rows: displayRows(for: history),
                titles: UsageHistoryHeaderTitles(
                    date: l10n["usage_table_date"],
                    model: l10n["usage_table_model"],
                    input: l10n["usage_table_input"],
                    output: l10n["usage_table_output"],
                    total: l10n["usage_table_total"],
                    cost: l10n["usage_table_cost"]
                ),
                metrics: tableMetrics
            )
            .frame(height: tableHeight(for: history.rows.count))
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func usageBadge(title: String, percentage: Int, detail: String) -> some View {
        let isRemaining = provider.source == .codex
        let secondaryLabel = isRemaining ? l10n["usage_remaining"] : l10n["usage_used"]
        let primaryValue = isRemaining ? 100 - percentage : percentage
        let primaryLabel = l10n["usage_used"]

        return VStack(alignment: .leading, spacing: 2) {
            if isRemaining {
                Text("\(title) · \(primaryLabel) \(primaryValue)% / \(secondaryLabel) \(percentage)%")
                    .font(.system(size: 12, weight: .medium))
            } else {
                Text("\(title) · \(percentage)% \(secondaryLabel)")
                    .font(.system(size: 12, weight: .medium))
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func relativeTime(_ unix: TimeInterval) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: Date(timeIntervalSince1970: unix), relativeTo: Date())
    }

    private func historyTitle(for preset: UsageHistoryRangePreset) -> String {
        switch preset {
        case .thisWeek:
            l10n["usage_range_this_week"]
        case .thisMonth:
            l10n["usage_range_this_month"]
        case .recent30Days:
            l10n["usage_range_recent_30_days"]
        }
    }

    private func historySummary(_ history: UsageHistoryRangeSnapshot) -> String {
        let label = history.label ?? inferredHistoryLabel(history)
        let tokens = tokenSummary(history.totalTokens)
        if let costUSD = history.costUSD {
            return "\(historyTitle(for: history.preset)) · \(label) · \(tokens) · \(formatCurrency(costUSD))"
        }
        return "\(historyTitle(for: history.preset)) · \(label) · \(tokens)"
    }

    private func displayRows(for history: UsageHistoryRangeSnapshot) -> [UsageHistoryDisplayRow] {
        history.rows.enumerated().map { index, row in
            UsageHistoryDisplayRow(
                id: row.id,
                date: shortDate(row.dayStartUnix),
                model: row.model,
                input: compactMetric(row.inputTokens),
                output: compactMetric(row.outputTokens),
                total: compactMetric(row.totalTokens),
                cost: row.costUSD.map(formatCurrency) ?? "—",
                striped: index.isMultiple(of: 2)
            )
        }
    }

    private func monthlySummary(_ monthly: UsageMonthlyStat) -> String {
        let tokens = tokenSummary(monthly.totalTokens)
        if let costUSD = monthly.costUSD {
            return "\(l10n["usage_recent_30_days"]) · \(monthly.label) · \(tokens) · \(formatCurrency(costUSD))"
        }
        return "\(l10n["usage_recent_30_days"]) · \(monthly.label) · \(tokens)"
    }

    private func tokenSummary(_ totalTokens: Int) -> String {
        let value = Double(totalTokens)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0

        if value >= 1_000_000 {
            let number = formatter.string(from: NSNumber(value: value / 1_000_000)) ?? "0"
            return "\(number)M \(l10n["usage_tokens"])"
        }
        if value >= 1_000 {
            let number = formatter.string(from: NSNumber(value: value / 1_000)) ?? "0"
            return "\(number)K \(l10n["usage_tokens"])"
        }
        let number = formatter.string(from: NSNumber(value: totalTokens)) ?? "\(totalTokens)"
        return "\(number) \(l10n["usage_tokens"])"
    }

    private func compactMetric(_ totalTokens: Int) -> String {
        let value = Double(totalTokens)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0

        if value >= 1_000_000 {
            let number = formatter.string(from: NSNumber(value: value / 1_000_000)) ?? "0"
            return "\(number)M"
        }
        if value >= 1_000 {
            let number = formatter.string(from: NSNumber(value: value / 1_000)) ?? "0"
            return "\(number)K"
        }
        return formatter.string(from: NSNumber(value: totalTokens)) ?? "\(totalTokens)"
    }

    private func shortDate(_ unix: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: Date(timeIntervalSince1970: unix))
    }

    private var tableMetrics: UsageHistoryTableMetrics {
        UsageHistoryTableMetrics(
            dateWidth: historyDateColumnWidth,
            modelWidth: historyModelColumnWidth,
            metricWidth: historyMetricColumnWidth,
            costWidth: historyCostColumnWidth
        )
    }

    private var historyDateColumnWidth: CGFloat { 80 }
    private var historyModelColumnWidth: CGFloat { 70 }
    private var historyMetricColumnWidth: CGFloat { 80 }
    private var historyCostColumnWidth: CGFloat { 80 }

    private func inferredHistoryLabel(_ history: UsageHistoryRangeSnapshot) -> String {
        guard let first = history.rows.first?.dayStartUnix,
              let last = history.rows.last?.dayStartUnix else {
            return ""
        }
        return "\(shortDate(last)) - \(shortDate(first))"
    }

    private func tableHeight(for rowCount: Int) -> CGFloat {
        min(max(CGFloat(rowCount) * tableMetrics.rowHeight + tableMetrics.headerHeight + 1, 180), 320)
    }

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }
}

private struct UsageHistoryHeaderTitles: Equatable {
    var date: String
    var model: String
    var input: String
    var output: String
    var total: String
    var cost: String
}

private struct UsageHistoryDisplayRow: Identifiable, Equatable {
    var id: String
    var date: String
    var model: String
    var input: String
    var output: String
    var total: String
    var cost: String
    var striped: Bool
}

private struct UsageHistoryTableMetrics: Equatable {
    var dateWidth: CGFloat
    var modelWidth: CGFloat
    var metricWidth: CGFloat
    var costWidth: CGFloat
    var horizontalPadding: CGFloat = 8
    var headerHeight: CGFloat = 36
    var rowHeight: CGFloat = 34

    var leftContentWidth: CGFloat { dateWidth + modelWidth }
    var leftViewportWidth: CGFloat { leftContentWidth + (horizontalPadding * 2) }
    var rightContentWidth: CGFloat { (metricWidth * 3) + costWidth }
    var rightDocumentWidth: CGFloat { rightContentWidth + (horizontalPadding * 2) }
}

private struct FrozenUsageHistoryTable: NSViewRepresentable {
    let rows: [UsageHistoryDisplayRow]
    let titles: UsageHistoryHeaderTitles
    let metrics: UsageHistoryTableMetrics

    func makeNSView(context: Context) -> FrozenUsageHistoryTableContainer {
        let container = FrozenUsageHistoryTableContainer(metrics: metrics)
        container.update(rows: rows, titles: titles, metrics: metrics)
        return container
    }

    func updateNSView(_ nsView: FrozenUsageHistoryTableContainer, context: Context) {
        nsView.update(rows: rows, titles: titles, metrics: metrics)
    }
}

private final class FrozenUsageForwardingViewport: NSView {
    weak var targetScrollView: NSScrollView?

    override var isFlipped: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        if let targetScrollView {
            targetScrollView.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

private final class FrozenUsageHistoryTableContainer: NSView {
    private let headerLeftViewport = FrozenUsageForwardingViewport()
    private let headerRightViewport = FrozenUsageForwardingViewport()
    private let leftBodyViewport = FrozenUsageForwardingViewport()
    private let rightBodyScrollView = NSScrollView()

    private let headerLeftHost = NSHostingView(rootView: AnyView(EmptyView()))
    private let headerRightHost = NSHostingView(rootView: AnyView(EmptyView()))
    private let leftBodyHost = NSHostingView(rootView: AnyView(EmptyView()))
    private let rightBodyHost = NSHostingView(rootView: AnyView(EmptyView()))

    private var metrics: UsageHistoryTableMetrics
    private var rows: [UsageHistoryDisplayRow] = []
    private var boundsObserver: NSObjectProtocol?

    override var isFlipped: Bool { true }

    init(metrics: UsageHistoryTableMetrics) {
        self.metrics = metrics
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
    }

    func update(rows: [UsageHistoryDisplayRow], titles: UsageHistoryHeaderTitles, metrics: UsageHistoryTableMetrics) {
        self.rows = rows
        self.metrics = metrics

        headerLeftHost.rootView = AnyView(
            FrozenUsageHeaderLeftView(titles: titles, metrics: metrics)
        )
        headerRightHost.rootView = AnyView(
            FrozenUsageHeaderRightView(titles: titles, metrics: metrics)
        )
        leftBodyHost.rootView = AnyView(
            FrozenUsageBodyLeftView(rows: rows, metrics: metrics)
        )
        rightBodyHost.rootView = AnyView(
            FrozenUsageBodyRightView(rows: rows, metrics: metrics)
        )

        needsLayout = true
        layoutSubtreeIfNeeded()
        syncFrozenOffsets()
    }

    override func layout() {
        super.layout()

        let leftWidth = metrics.leftViewportWidth
        let headerHeight = metrics.headerHeight
        let totalWidth = bounds.width
        let totalHeight = bounds.height
        let bodyHeight = max(totalHeight - headerHeight, 0)
        let rightWidth = max(totalWidth - leftWidth, 0)
        let contentHeight = max(CGFloat(rows.count) * metrics.rowHeight, bodyHeight)

        headerLeftViewport.frame = CGRect(x: 0, y: 0, width: leftWidth, height: headerHeight)
        headerRightViewport.frame = CGRect(x: leftWidth, y: 0, width: rightWidth, height: headerHeight)
        leftBodyViewport.frame = CGRect(x: 0, y: headerHeight, width: leftWidth, height: bodyHeight)
        rightBodyScrollView.frame = CGRect(x: leftWidth, y: headerHeight, width: rightWidth, height: bodyHeight)

        headerLeftHost.frame = CGRect(x: 0, y: 0, width: leftWidth, height: headerHeight)
        headerRightHost.frame = CGRect(x: -rightBodyScrollView.contentView.bounds.origin.x, y: 0, width: metrics.rightDocumentWidth, height: headerHeight)
        leftBodyHost.frame = CGRect(x: 0, y: -rightBodyScrollView.contentView.bounds.origin.y, width: leftWidth, height: contentHeight)
        rightBodyHost.frame = CGRect(x: 0, y: 0, width: metrics.rightDocumentWidth, height: contentHeight)
    }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.clear.cgColor

        // Force a top-origin coordinate system so long tables do not start underneath the frozen header.
        [headerLeftHost, headerRightHost, leftBodyHost, rightBodyHost].forEach { $0.isFlipped = true }

        [headerLeftViewport, headerRightViewport, leftBodyViewport].forEach { viewport in
            viewport.wantsLayer = true
            viewport.layer?.masksToBounds = true
            viewport.layer?.backgroundColor = NSColor.clear.cgColor
            addSubview(viewport)
        }

        rightBodyScrollView.wantsLayer = true
        rightBodyScrollView.layer?.backgroundColor = NSColor.clear.cgColor
        rightBodyScrollView.drawsBackground = false
        rightBodyScrollView.borderType = .noBorder
        rightBodyScrollView.hasVerticalScroller = true
        rightBodyScrollView.hasHorizontalScroller = true
        rightBodyScrollView.autohidesScrollers = true
        rightBodyScrollView.scrollerStyle = .overlay
        rightBodyScrollView.contentView.postsBoundsChangedNotifications = true
        rightBodyScrollView.contentView.wantsLayer = true
        rightBodyScrollView.contentView.layer?.backgroundColor = NSColor.clear.cgColor
        rightBodyScrollView.documentView = rightBodyHost
        rightBodyScrollView.verticalScroller?.knobStyle = .light
        rightBodyScrollView.horizontalScroller?.knobStyle = .light
        rightBodyHost.wantsLayer = true
        rightBodyHost.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(rightBodyScrollView)

        headerRightViewport.targetScrollView = rightBodyScrollView
        leftBodyViewport.targetScrollView = rightBodyScrollView

        headerLeftViewport.addSubview(headerLeftHost)
        headerRightViewport.addSubview(headerRightHost)
        leftBodyViewport.addSubview(leftBodyHost)

        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: rightBodyScrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.syncFrozenOffsets()
        }
    }

    private func syncFrozenOffsets() {
        let bounds = rightBodyScrollView.contentView.bounds
        headerRightHost.frame.origin.x = -bounds.origin.x
        leftBodyHost.frame.origin.y = -bounds.origin.y
    }
}

private struct FrozenUsageHeaderLeftView: View {
    let titles: UsageHistoryHeaderTitles
    let metrics: UsageHistoryTableMetrics

    var body: some View {
        HStack(spacing: 0) {
            headerCell(titles.date, width: metrics.dateWidth, alignment: .leading)
            headerCell(titles.model, width: metrics.modelWidth, alignment: .leading)
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .frame(width: metrics.leftViewportWidth, height: metrics.headerHeight, alignment: .leading)
        .background(Color.white.opacity(0.05))
    }
}

private struct FrozenUsageHeaderRightView: View {
    let titles: UsageHistoryHeaderTitles
    let metrics: UsageHistoryTableMetrics

    var body: some View {
        HStack(spacing: 0) {
            headerCell(titles.input, width: metrics.metricWidth, alignment: .trailing)
            headerCell(titles.output, width: metrics.metricWidth, alignment: .trailing)
            headerCell(titles.total, width: metrics.metricWidth, alignment: .trailing)
            headerCell(titles.cost, width: metrics.costWidth, alignment: .trailing)
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .frame(width: metrics.rightDocumentWidth, height: metrics.headerHeight, alignment: .leading)
        .background(Color.white.opacity(0.05))
    }
}

private struct FrozenUsageBodyLeftView: View {
    let rows: [UsageHistoryDisplayRow]
    let metrics: UsageHistoryTableMetrics

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(spacing: 0) {
                    valueCell(row.date, width: metrics.dateWidth, alignment: .leading, weight: .medium)
                    valueCell(row.model, width: metrics.modelWidth, alignment: .leading)
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .frame(width: metrics.leftViewportWidth, height: metrics.rowHeight, alignment: .leading)
                .background(row.striped ? Color.white.opacity(0.025) : Color.clear)

                if index < rows.count - 1 {
                    Divider()
                        .overlay(Color.white.opacity(0.04))
                }
            }
        }
        .frame(width: metrics.leftViewportWidth, alignment: .topLeading)
    }
}

private struct FrozenUsageBodyRightView: View {
    let rows: [UsageHistoryDisplayRow]
    let metrics: UsageHistoryTableMetrics

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(spacing: 0) {
                    valueCell(row.input, width: metrics.metricWidth, alignment: .trailing, weight: .medium)
                    valueCell(row.output, width: metrics.metricWidth, alignment: .trailing, weight: .medium)
                    valueCell(row.total, width: metrics.metricWidth, alignment: .trailing, weight: .semibold)
                    valueCell(row.cost, width: metrics.costWidth, alignment: .trailing, weight: .medium)
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .frame(width: metrics.rightDocumentWidth, height: metrics.rowHeight, alignment: .leading)
                .background(row.striped ? Color.white.opacity(0.025) : Color.clear)

                if index < rows.count - 1 {
                    Divider()
                        .overlay(Color.white.opacity(0.04))
                }
            }
        }
        .frame(width: metrics.rightDocumentWidth, alignment: .topLeading)
    }
}

private func headerCell(_ title: String, width: CGFloat, alignment: Alignment) -> some View {
    Text(title)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(width: width, alignment: alignment)
}

private func valueCell(
    _ value: String,
    width: CGFloat,
    alignment: Alignment,
    weight: Font.Weight = .regular
) -> some View {
    Text(value)
        .font(.system(size: 11, weight: weight, design: .monospaced))
        .lineLimit(1)
        .truncationMode(alignment == .leading ? .middle : .head)
        .frame(width: width, alignment: alignment)
}
