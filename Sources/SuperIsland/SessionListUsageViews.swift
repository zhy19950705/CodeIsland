import SwiftUI
import SuperIslandCore

/// The bottom strip stays fixed under the session list and keeps multiple provider quotas visible at once.
struct SessionListUsageStrip: View {
    let snapshot: UsageSnapshot

    private var providers: [UsageProviderSnapshot] {
        snapshot.providers
            .filter(\.hasQuotaMetrics)
            .sorted { $0.source.sortOrder < $1.source.sortOrder }
    }

    var body: some View {
        if !providers.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(providers) { provider in
                        SessionUsagePill(provider: provider)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(Color.white.opacity(0.025))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)
            }
        }
    }
}

/// Each pill compresses one provider into a single line so Claude, Codex, and Cursor can fit together.
private struct SessionUsagePill: View {
    let provider: UsageProviderSnapshot
    @AppStorage("usageWarningThreshold") private var usageWarningThreshold: Int = 90

    var body: some View {
        HStack(spacing: 8) {
            Text(provider.source.title)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.68))

            SessionUsageMetric(
                title: provider.primary.label,
                usedPercentage: provider.usedPercentage(for: provider.primary),
                detail: provider.primary.detail,
                tint: tint(for: provider.usedPercentage(for: provider.primary))
            )

            SessionUsageMetric(
                title: provider.secondary.label,
                usedPercentage: provider.usedPercentage(for: provider.secondary),
                detail: provider.secondary.detail,
                tint: tint(for: provider.usedPercentage(for: provider.secondary))
            )
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    /// Severity stays normalized to used-percent so the warning color reads consistently across providers.
    private func tint(for usedPercentage: Int) -> Color {
        let threshold = max(usageWarningThreshold, 1)
        if usedPercentage >= threshold {
            return Color(red: 0.94, green: 0.27, blue: 0.27)
        }
        if usedPercentage >= max(threshold - 20, 50) {
            return Color(red: 1.0, green: 0.68, blue: 0.24)
        }
        return Color(red: 0.29, green: 0.87, blue: 0.5)
    }
}

/// The metric keeps the visible payload to label + percent while the reset hint moves into hover help.
private struct SessionUsageMetric: View {
    let title: String
    let usedPercentage: Int
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.52))

                Text("\(usedPercentage)%")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tint)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.08))

                    Capsule(style: .continuous)
                        .fill(tint)
                        .frame(width: max(2, geometry.size.width * CGFloat(usedPercentage) / 100))
                }
            }
            .frame(width: 38, height: 3)
        }
        .help("\(title) · \(usedPercentage)% · \(detail)")
    }
}
