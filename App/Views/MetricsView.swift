import SwiftUI

struct MetricsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isShowingResetConfirmation = false

    private var localizer: AppLocalizer {
        AppLocalizer(language: appState.settings.appLanguage)
    }

    private var metrics: TranscriptMetrics {
        displayCounters.transcriptMetrics
    }

    private var displayCounters: MetricsCounters {
        appState.metricsCountersForDisplay
    }

    private var correctedTranscriptionCount: Int {
        MetricsCalculator().correctedTranscriptionCount(
            events: appState.adaptiveRecognitionState.correctionEvents,
            cutoff: appState.metricsCounters.displayCutoff
        )
    }

    private var timelineBuckets: [MetricsTimelineBucket] {
        MetricsCalculator().timeline(
            records: appState.metricsRecordsForDisplay,
            granularity: .daily
        )
    }

    private var resetCopy: MetricsResetCopy {
        MetricsResetCopy(language: appState.settings.appLanguage)
    }

    private var activeLanguageMetrics: [LanguageMetrics] {
        metrics.languageBreakdown.filter { $0.characters > 0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    if let cutoff = appState.metricsCounters.displayCutoff {
                        Text(resetCopy.displayScope(cutoff))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        isShowingResetConfirmation = true
                    } label: {
                        Label(resetCopy.buttonTitle, systemImage: "arrow.counterclockwise")
                    }
                    .disabled(appState.metricsRecordsForDisplay.isEmpty)
                    .help(resetCopy.help)
                }

                if !appState.metricsRecords.isEmpty {
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 14) {
                        GridRow {
                            MetricTile(
                                title: localizer.totalAttemptsLabel(),
                                value: formatted(displayCounters.totalAttempts)
                            )
                            MetricTile(
                                title: localizer.successfulTranscriptionsLabel(),
                                value: formatted(displayCounters.successfulTranscriptions)
                            )
                            MetricTile(
                                title: localizer.correctedTranscriptionsLabel(),
                                value: formatted(correctedTranscriptionCount)
                            )
                            MetricTile(
                                title: localizer.averageLatencyLabel(),
                                value: formattedLatency(displayCounters.averageTranscriptionLatency)
                            )
                        }

                        Divider()
                            .gridCellColumns(4)

                        GridRow {
                            MetricTile(
                                title: localizer.text(.totalTranscripts),
                                value: formatted(metrics.transcriptCount)
                            )
                            MetricTile(
                                title: localizer.text(.totalCharacters),
                                value: formatted(metrics.totalCharacters)
                            )
                            MetricTile(
                                title: localizer.text(.totalWords),
                                value: formatted(metrics.totalWords)
                            )
                            MetricTile(
                                title: localizer.text(.estimatedTokens),
                                value: formatted(metrics.estimatedTokens)
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if appState.metricsRecordsForDisplay.isEmpty {
                        Text(resetCopy.noActivitySinceReset)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                    }

                    if metrics.hasContent {
                        Divider()

                        timelineSection
                    }

                    if !activeLanguageMetrics.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            Text(localizer.text(.languageBreakdown))
                                .font(.headline)

                            if activeLanguageMetrics.contains(where: { $0.language == .other }) {
                                Text(localizer.text(.otherMetricsNote))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            ForEach(activeLanguageMetrics) { item in
                                languageRow(item)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(localizer.text(.noMetricsYet), systemImage: "chart.bar.xaxis")
                        .frame(maxWidth: .infinity, minHeight: 260)
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog(
            resetCopy.confirmationTitle,
            isPresented: $isShowingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button(resetCopy.confirmButtonTitle, role: .destructive) {
                appState.resetMetricsDisplay()
            }
            Button(resetCopy.cancelButtonTitle, role: .cancel) {}
        } message: {
            Text(resetCopy.confirmationMessage)
        }
    }

    private var timelineSection: some View {
        let buckets = timelineBuckets

        return VStack(alignment: .leading, spacing: 10) {
            Text(localizer.text(.usageOverTime))
                .font(.headline)

            if buckets.contains(where: \.hasContent) {
                TimelineBarChart(
                    buckets: buckets,
                    localizer: localizer
                )

                languageLegend
            } else {
                ContentUnavailableView(localizer.text(.noTimelineData), systemImage: "chart.bar")
                    .frame(maxWidth: .infinity, minHeight: 170)
            }
        }
    }

    private var languageLegend: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 96), spacing: 8)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(activeLanguageMetrics) { item in
                HStack(spacing: 6) {
                    Circle()
                        .fill(metricsLanguageColor(item.language))
                        .frame(width: 7, height: 7)

                    Text(localizer.metricsLanguageName(item.language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func languageRow(_ item: LanguageMetrics) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                HStack(spacing: 7) {
                    Circle()
                        .fill(metricsLanguageColor(item.language))
                        .frame(width: 8, height: 8)

                    Text(localizer.metricsLanguageName(item.language))
                        .font(.body)
                }

                Spacer()
                Text(percent(item.percentage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            ProgressView(value: item.percentage)
                .controlSize(.small)

            HStack(spacing: 10) {
                Text("\(formatted(item.characters)) \(localizer.text(.characters))")
                Text("\(formatted(item.estimatedTokens)) \(localizer.text(.tokens))")

                if item.words > 0 {
                    Text("\(formatted(item.words)) \(localizer.text(.words))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    private func formatted(_ value: Int) -> String {
        value.formatted(.number)
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    private func formattedLatency(_ value: TimeInterval?) -> String {
        let value = value ?? 0
        return "\(value.formatted(.number.precision(.fractionLength(2)))) s"
    }

}

private struct MetricsResetCopy {
    let buttonTitle: String
    let help: String
    let confirmationTitle: String
    let confirmationMessage: String
    let confirmButtonTitle: String
    let cancelButtonTitle: String
    let noActivitySinceReset: String
    private let displayScopePrefix: String
    private let localeIdentifier: String

    init(language: AppLanguage) {
        switch language {
        case .english:
            buttonTitle = "Reset"
            help = "Start the displayed statistics again from now"
            confirmationTitle = "Reset statistics?"
            confirmationMessage = "Statistics will start again from now. Transcript history and recordings will not be deleted, and exported metrics will still include the complete history."
            confirmButtonTitle = "Reset statistics"
            cancelButtonTitle = "Cancel"
            noActivitySinceReset = "No activity since the last reset."
            displayScopePrefix = "Showing activity since "
            localeIdentifier = "en"
        case .simplifiedChinese:
            buttonTitle = "清零"
            help = "从现在重新开始显示统计"
            confirmationTitle = "重新开始统计？"
            confirmationMessage = "统计将从现在重新开始。历史记录和录音不会被删除，导出的统计数据仍会包含完整记录。"
            confirmButtonTitle = "清零统计"
            cancelButtonTitle = "取消"
            noActivitySinceReset = "清零后暂无新的记录。"
            displayScopePrefix = "统计起点："
            localeIdentifier = "zh-Hans"
        case .traditionalChinese:
            buttonTitle = "清零"
            help = "從現在重新開始顯示統計"
            confirmationTitle = "重新開始統計？"
            confirmationMessage = "統計將從現在重新開始。歷史記錄與錄音不會被刪除，匯出的統計資料仍會包含完整記錄。"
            confirmButtonTitle = "清零統計"
            cancelButtonTitle = "取消"
            noActivitySinceReset = "清零後暫無新的記錄。"
            displayScopePrefix = "統計起點："
            localeIdentifier = "zh-Hant"
        case .japanese:
            buttonTitle = "リセット"
            help = "表示する統計を今から集計し直します"
            confirmationTitle = "統計をリセットしますか？"
            confirmationMessage = "統計は今から集計し直されます。履歴と録音は削除されず、書き出した統計には引き続き完全な記録が含まれます。"
            confirmButtonTitle = "統計をリセット"
            cancelButtonTitle = "キャンセル"
            noActivitySinceReset = "リセット後の記録はまだありません。"
            displayScopePrefix = "集計開始："
            localeIdentifier = "ja"
        }
    }

    func displayScope(_ cutoff: Date) -> String {
        let format = Date.FormatStyle(date: .abbreviated, time: .shortened)
            .locale(Locale(identifier: localeIdentifier))
        return "\(displayScopePrefix)\(cutoff.formatted(format))"
    }
}

private struct MetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

private struct TimelineBarChart: View {
    let buckets: [MetricsTimelineBucket]
    let localizer: AppLocalizer

    private let chartHeight: CGFloat = 150

    private var maxCharacters: Int {
        max(1, buckets.map(\.totalCharacters).max() ?? 0)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                VStack(spacing: 5) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.08))

                        if bucket.hasContent {
                            VStack(spacing: 0) {
                                ForEach(Array(activeSegments(for: bucket).reversed())) { item in
                                    Rectangle()
                                        .fill(metricsLanguageColor(item.language))
                                        .frame(height: segmentHeight(item, in: bucket))
                                }
                            }
                            .frame(height: barHeight(for: bucket))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: chartHeight)
                    .help(helpText(for: bucket))

                    Text(axisLabel(for: bucket.startDate, index: index))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(height: 18)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: chartHeight + 24)
    }

    private func activeSegments(for bucket: MetricsTimelineBucket) -> [LanguageMetrics] {
        bucket.languageBreakdown.filter { $0.characters > 0 }
    }

    private func barHeight(for bucket: MetricsTimelineBucket) -> CGFloat {
        guard bucket.totalCharacters > 0 else {
            return 0
        }

        return chartHeight * CGFloat(bucket.totalCharacters) / CGFloat(maxCharacters)
    }

    private func segmentHeight(_ item: LanguageMetrics, in bucket: MetricsTimelineBucket) -> CGFloat {
        guard bucket.totalCharacters > 0 else {
            return 0
        }

        return barHeight(for: bucket) * CGFloat(item.characters) / CGFloat(bucket.totalCharacters)
    }

    private func axisLabel(for date: Date, index: Int) -> String {
        guard index % 2 == 0 || index == buckets.count - 1 else {
            return ""
        }

        return Self.dayFormatter.string(from: date)
    }

    private func helpText(for bucket: MetricsTimelineBucket) -> String {
        [
            Self.tooltipFormatter.string(from: bucket.startDate),
            "\(bucket.totalCharacters.formatted(.number)) \(localizer.text(.characters))",
            "\(bucket.transcriptCount.formatted(.number)) \(localizer.text(.transcriptsUnit))",
            "\(bucket.estimatedTokens.formatted(.number)) \(localizer.text(.tokens))"
        ].joined(separator: " · ")
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("M/d")
        return formatter
    }()

    private static let tooltipFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

private func metricsLanguageColor(_ language: MetricsLanguage) -> Color {
    switch language {
    case .chinese:
        return Color(red: 0.86, green: 0.26, blue: 0.22)
    case .english:
        return Color(red: 0.16, green: 0.45, blue: 0.92)
    case .spanish:
        return Color(red: 0.92, green: 0.52, blue: 0.12)
    case .french:
        return Color(red: 0.49, green: 0.32, blue: 0.84)
    case .japanese:
        return Color(red: 0.13, green: 0.58, blue: 0.37)
    case .other:
        return Color.secondary.opacity(0.55)
    }
}

#Preview {
    MetricsView()
        .environmentObject(AppState())
}
