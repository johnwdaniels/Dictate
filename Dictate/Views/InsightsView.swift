import AppKit
import SwiftData
import SwiftUI

struct InsightsView: View {
    @Query(sort: \DictationEntry.createdAt, order: .forward) private var entries: [DictationEntry]
    @State private var range: InsightRange = .all

    private var summary: InsightSummary {
        InsightsMath.summarize(samples, range: range, now: .now)
    }

    private var samples: [InsightSample] {
        entries.map {
            InsightSample(
                date: $0.createdAt,
                wordCount: $0.wordCount,
                durationSeconds: $0.durationSeconds,
                appName: $0.destinationAppName,
                bundleID: $0.destinationBundleID
            )
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                totals
                chart
                mostUsed
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Range", selection: $range) {
                    ForEach(InsightRange.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    private var totals: some View {
        let saved = InsightsMath.timeSavedLabel(seconds: summary.timeSavedSeconds)
        return HStack(alignment: .firstTextBaseline, spacing: 48) {
            metric(title: "Time saved", value: saved.value, unit: saved.unit, caption: "compared to typing")
            metric(title: "Words dictated", value: formatted(summary.words), unit: "", caption: "")
        }
    }

    private func metric(title: String, value: String, unit: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                if !unit.isEmpty {
                    Text(unit)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            if !caption.isEmpty {
                Text(caption)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(range == .all ? "All time" : range.rawValue)
                .font(.headline)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(summary.buckets) { bucket in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(bucket.words > 0 ? Color.green.opacity(0.55) : Color.primary.opacity(0.08))
                            .frame(maxWidth: 48)
                            .frame(height: barHeight(bucket.words))
                        Text(bucket.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(height: 14)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 150)
        }
    }

    private var mostUsed: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Most used")
                .font(.headline)
            if summary.apps.isEmpty {
                Text(summary.words == 0 ? "No dictations in this range." : "No destination app was recorded for these dictations.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                let peak = summary.apps.map(\.words).max() ?? 1
                ForEach(summary.apps.prefix(8)) { app in
                    HStack(spacing: 10) {
                        appIcon(app.bundleID)
                        Text(app.name)
                            .lineLimit(1)
                            .frame(width: 140, alignment: .leading)
                        GeometryReader { geometry in
                            Capsule()
                                .fill(Color.green.opacity(0.7))
                                .frame(width: max(4, geometry.size.width * CGFloat(app.words) / CGFloat(peak)))
                                .frame(maxHeight: .infinity, alignment: .leading)
                        }
                        .frame(height: 6)
                        Text(formatted(app.words))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func barHeight(_ words: Int) -> CGFloat {
        let peak = summary.buckets.map(\.words).max() ?? 0
        guard peak > 0, words > 0 else { return 3 }
        return max(8, 110 * CGFloat(words) / CGFloat(peak))
    }

    private func appIcon(_ bundleID: String) -> some View {
        let image: NSImage = {
            guard !bundleID.isEmpty,
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
            }
            return NSWorkspace.shared.icon(forFile: url.path)
        }()
        return Image(nsImage: image)
            .resizable()
            .frame(width: 22, height: 22)
    }

    private func formatted(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
