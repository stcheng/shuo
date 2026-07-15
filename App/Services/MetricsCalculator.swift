import Foundation

enum MetricsLanguage: String, CaseIterable, Identifiable, Codable {
    case chinese
    case english
    case spanish
    case french
    case japanese
    case other

    var id: String { rawValue }
}

struct LanguageMetrics: Identifiable, Codable, Equatable {
    let language: MetricsLanguage
    let characters: Int
    let words: Int
    let estimatedTokens: Int
    let percentage: Double

    var id: MetricsLanguage { language }
}

struct TranscriptMetrics {
    let transcriptCount: Int
    let totalCharacters: Int
    let totalWords: Int
    let estimatedTokens: Int
    let languageBreakdown: [LanguageMetrics]

    var hasContent: Bool {
        totalCharacters > 0
    }
}

struct MetricsLanguageCounter: Identifiable, Codable, Equatable {
    let language: MetricsLanguage
    let characters: Int
    let words: Int
    let estimatedTokens: Int

    var id: MetricsLanguage { language }
}

struct ProviderModelUsageCounter: Identifiable, Codable, Equatable {
    let provider: TranscriptionProvider
    let model: String
    let attempts: Int

    var id: String {
        "\(provider.rawValue)|\(model)"
    }
}

struct MetricsCounters: Codable, Equatable {
    static let currentSchemaVersion = 3

    static let empty = MetricsCounters(
        transcriptCount: 0,
        totalCharacters: 0,
        totalWords: 0,
        estimatedTokens: 0,
        languageCounters: MetricsLanguage.allCases.map { language in
            MetricsLanguageCounter(
                language: language,
                characters: 0,
                words: 0,
                estimatedTokens: 0
            )
        }
    )

    let schemaVersion: Int
    let transcriptCount: Int
    let totalCharacters: Int
    let totalWords: Int
    let estimatedTokens: Int
    let languageCounters: [MetricsLanguageCounter]
    let totalAttempts: Int
    let successfulTranscriptions: Int
    let failedTranscriptions: Int
    let totalRecordedSeconds: TimeInterval
    let totalTranscriptionLatency: TimeInterval
    let latencySampleCount: Int
    let providerModelUsage: [ProviderModelUsageCounter]
    let lastErrorSummary: String?
    let appVersion: String
    let buildNumber: String
    /// Records before this timestamp remain in metrics history but are excluded
    /// from the Statistics UI. Schemas 1 and 2 omit this field and therefore
    /// continue to show lifetime statistics after migration.
    private let displayCutoffTimestamp: TimeInterval?

    var displayCutoff: Date? {
        displayCutoffTimestamp.map(Date.init(timeIntervalSince1970:))
    }

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        transcriptCount: Int,
        totalCharacters: Int,
        totalWords: Int,
        estimatedTokens: Int,
        languageCounters: [MetricsLanguageCounter],
        totalAttempts: Int? = nil,
        successfulTranscriptions: Int? = nil,
        failedTranscriptions: Int = 0,
        totalRecordedSeconds: TimeInterval = 0,
        totalTranscriptionLatency: TimeInterval = 0,
        latencySampleCount: Int = 0,
        providerModelUsage: [ProviderModelUsageCounter] = [],
        lastErrorSummary: String? = nil,
        appVersion: String = "unknown",
        buildNumber: String = "unknown",
        displayCutoff: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.transcriptCount = transcriptCount
        self.totalCharacters = totalCharacters
        self.totalWords = totalWords
        self.estimatedTokens = estimatedTokens
        self.languageCounters = languageCounters
        self.totalAttempts = totalAttempts ?? transcriptCount
        self.successfulTranscriptions = successfulTranscriptions ?? transcriptCount
        self.failedTranscriptions = failedTranscriptions
        self.totalRecordedSeconds = totalRecordedSeconds
        self.totalTranscriptionLatency = totalTranscriptionLatency
        self.latencySampleCount = latencySampleCount
        self.providerModelUsage = providerModelUsage
        self.lastErrorSummary = lastErrorSummary
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        displayCutoffTimestamp = displayCutoff?.timeIntervalSince1970
    }

    var transcriptMetrics: TranscriptMetrics {
        let countersByLanguage = Dictionary(
            uniqueKeysWithValues: languageCounters.map { item in
                (item.language, item)
            }
        )
        let denominator = languageCounters.reduce(0) { $0 + $1.characters }

        let breakdown = MetricsLanguage.allCases.map { language in
            let counter = countersByLanguage[language]
            let characters = counter?.characters ?? 0

            return LanguageMetrics(
                language: language,
                characters: characters,
                words: counter?.words ?? 0,
                estimatedTokens: counter?.estimatedTokens ?? 0,
                percentage: denominator > 0 ? Double(characters) / Double(denominator) : 0
            )
        }

        return TranscriptMetrics(
            transcriptCount: transcriptCount,
            totalCharacters: totalCharacters,
            totalWords: totalWords,
            estimatedTokens: estimatedTokens,
            languageBreakdown: breakdown
        )
    }

    var averageTranscriptionLatency: TimeInterval? {
        guard latencySampleCount > 0 else {
            return nil
        }
        return totalTranscriptionLatency / Double(latencySampleCount)
    }

    func resettingDisplay(at cutoff: Date) -> MetricsCounters {
        MetricsCounters(
            transcriptCount: transcriptCount,
            totalCharacters: totalCharacters,
            totalWords: totalWords,
            estimatedTokens: estimatedTokens,
            languageCounters: languageCounters,
            totalAttempts: totalAttempts,
            successfulTranscriptions: successfulTranscriptions,
            failedTranscriptions: failedTranscriptions,
            totalRecordedSeconds: totalRecordedSeconds,
            totalTranscriptionLatency: totalTranscriptionLatency,
            latencySampleCount: latencySampleCount,
            providerModelUsage: providerModelUsage,
            lastErrorSummary: lastErrorSummary,
            appVersion: appVersion,
            buildNumber: buildNumber,
            // Never move the reporting window backwards and accidentally reveal
            // records hidden by an earlier reset after a system-clock change.
            displayCutoff: max(displayCutoff ?? cutoff, cutoff)
        )
    }

    func mergedMonotonic(with other: MetricsCounters) -> MetricsCounters {
        let currentLanguageCounters = Dictionary(
            uniqueKeysWithValues: languageCounters.map { ($0.language, $0) }
        )
        let otherLanguageCounters = Dictionary(
            uniqueKeysWithValues: other.languageCounters.map { ($0.language, $0) }
        )
        let mergedLanguageCounters = MetricsLanguage.allCases.map { language in
            let current = currentLanguageCounters[language]
            let other = otherLanguageCounters[language]

            return MetricsLanguageCounter(
                language: language,
                characters: max(current?.characters ?? 0, other?.characters ?? 0),
                words: max(current?.words ?? 0, other?.words ?? 0),
                estimatedTokens: max(current?.estimatedTokens ?? 0, other?.estimatedTokens ?? 0)
            )
        }
        let currentProviderModelUsage = Dictionary(
            uniqueKeysWithValues: providerModelUsage.map { ($0.id, $0) }
        )
        let otherProviderModelUsage = Dictionary(
            uniqueKeysWithValues: other.providerModelUsage.map { ($0.id, $0) }
        )
        let mergedProviderModelUsage = Set(currentProviderModelUsage.keys)
            .union(otherProviderModelUsage.keys)
            .compactMap { key -> ProviderModelUsageCounter? in
                guard let item = currentProviderModelUsage[key] ?? otherProviderModelUsage[key] else {
                    return nil
                }
                return ProviderModelUsageCounter(
                    provider: item.provider,
                    model: item.model,
                    attempts: max(
                        currentProviderModelUsage[key]?.attempts ?? 0,
                        otherProviderModelUsage[key]?.attempts ?? 0
                    )
                )
            }
            .sorted { $0.id < $1.id }
        let preferOtherMetadata = other.totalAttempts >= totalAttempts

        return MetricsCounters(
            transcriptCount: max(transcriptCount, other.transcriptCount),
            totalCharacters: max(totalCharacters, other.totalCharacters),
            totalWords: max(totalWords, other.totalWords),
            estimatedTokens: max(estimatedTokens, other.estimatedTokens),
            languageCounters: mergedLanguageCounters,
            totalAttempts: max(totalAttempts, other.totalAttempts),
            successfulTranscriptions: max(successfulTranscriptions, other.successfulTranscriptions),
            failedTranscriptions: max(failedTranscriptions, other.failedTranscriptions),
            totalRecordedSeconds: max(totalRecordedSeconds, other.totalRecordedSeconds),
            totalTranscriptionLatency: max(totalTranscriptionLatency, other.totalTranscriptionLatency),
            latencySampleCount: max(latencySampleCount, other.latencySampleCount),
            providerModelUsage: mergedProviderModelUsage,
            lastErrorSummary: preferOtherMetadata
                ? (other.lastErrorSummary ?? lastErrorSummary)
                : (lastErrorSummary ?? other.lastErrorSummary),
            appVersion: preferOtherMetadata ? other.appVersion : appVersion,
            buildNumber: preferOtherMetadata ? other.buildNumber : buildNumber,
            displayCutoff: [displayCutoff, other.displayCutoff]
                .compactMap { $0 }
                .max()
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case transcriptCount
        case totalCharacters
        case totalWords
        case estimatedTokens
        case languageCounters
        case totalAttempts
        case successfulTranscriptions
        case failedTranscriptions
        case totalRecordedSeconds
        case totalTranscriptionLatency
        case latencySampleCount
        case providerModelUsage
        case lastErrorSummary
        case appVersion
        case buildNumber
        case displayCutoffTimestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyTranscriptCount = try container.decode(Int.self, forKey: .transcriptCount)

        self.init(
            schemaVersion: try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1,
            transcriptCount: legacyTranscriptCount,
            totalCharacters: try container.decode(Int.self, forKey: .totalCharacters),
            totalWords: try container.decode(Int.self, forKey: .totalWords),
            estimatedTokens: try container.decode(Int.self, forKey: .estimatedTokens),
            languageCounters: try container.decode([MetricsLanguageCounter].self, forKey: .languageCounters),
            totalAttempts: try container.decodeIfPresent(Int.self, forKey: .totalAttempts) ?? legacyTranscriptCount,
            successfulTranscriptions: try container.decodeIfPresent(Int.self, forKey: .successfulTranscriptions) ?? legacyTranscriptCount,
            failedTranscriptions: try container.decodeIfPresent(Int.self, forKey: .failedTranscriptions) ?? 0,
            totalRecordedSeconds: try container.decodeIfPresent(TimeInterval.self, forKey: .totalRecordedSeconds) ?? 0,
            totalTranscriptionLatency: try container.decodeIfPresent(TimeInterval.self, forKey: .totalTranscriptionLatency) ?? 0,
            latencySampleCount: try container.decodeIfPresent(Int.self, forKey: .latencySampleCount) ?? 0,
            providerModelUsage: try container.decodeIfPresent([ProviderModelUsageCounter].self, forKey: .providerModelUsage) ?? [],
            lastErrorSummary: try container.decodeIfPresent(String.self, forKey: .lastErrorSummary),
            appVersion: try container.decodeIfPresent(String.self, forKey: .appVersion) ?? "unknown",
            buildNumber: try container.decodeIfPresent(String.self, forKey: .buildNumber) ?? "unknown",
            displayCutoff: try container
                .decodeIfPresent(TimeInterval.self, forKey: .displayCutoffTimestamp)
                .map(Date.init(timeIntervalSince1970:))
        )
    }
}

struct TranscriptMetricsRecord: Identifiable, Codable, Equatable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let id: UUID
    let createdAt: Date
    let provider: TranscriptionProvider
    let model: String
    let languageHint: LanguageHint
    let languageBreakdown: [LanguageMetrics]
    let outcome: TranscriptionAttemptOutcome
    let errorSummary: String?
    let recordingDuration: TimeInterval?
    let transcriptionLatency: TimeInterval?
    let appVersion: String
    let buildNumber: String

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        id: UUID,
        createdAt: Date,
        provider: TranscriptionProvider,
        model: String,
        languageHint: LanguageHint,
        languageBreakdown: [LanguageMetrics],
        outcome: TranscriptionAttemptOutcome = .succeeded,
        errorSummary: String? = nil,
        recordingDuration: TimeInterval? = nil,
        transcriptionLatency: TimeInterval? = nil,
        appVersion: String = AppBuildMetadata.version,
        buildNumber: String = AppBuildMetadata.buildNumber
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.createdAt = createdAt
        self.provider = provider
        self.model = model
        self.languageHint = languageHint
        self.languageBreakdown = languageBreakdown
        self.outcome = outcome
        self.errorSummary = errorSummary
        self.recordingDuration = recordingDuration
        self.transcriptionLatency = transcriptionLatency
        self.appVersion = appVersion
        self.buildNumber = buildNumber
    }

    var totalCharacters: Int {
        languageBreakdown.reduce(0) { $0 + $1.characters }
    }

    var totalWords: Int {
        languageBreakdown.reduce(0) { $0 + $1.words }
    }

    var estimatedTokens: Int {
        languageBreakdown.reduce(0) { $0 + $1.estimatedTokens }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case createdAt
        case provider
        case model
        case languageHint
        case languageBreakdown
        case outcome
        case errorSummary
        case recordingDuration
        case transcriptionLatency
        case appVersion
        case buildNumber
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        provider = try container.decode(TranscriptionProvider.self, forKey: .provider)
        model = try container.decode(String.self, forKey: .model)
        languageHint = try container.decode(LanguageHint.self, forKey: .languageHint)
        languageBreakdown = try container.decode([LanguageMetrics].self, forKey: .languageBreakdown)
        outcome = try container.decodeIfPresent(TranscriptionAttemptOutcome.self, forKey: .outcome) ?? .succeeded
        errorSummary = try container.decodeIfPresent(String.self, forKey: .errorSummary)
        recordingDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .recordingDuration)
        transcriptionLatency = try container.decodeIfPresent(TimeInterval.self, forKey: .transcriptionLatency)
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion) ?? "unknown"
        buildNumber = try container.decodeIfPresent(String.self, forKey: .buildNumber) ?? "unknown"
    }

    func upgradedToCurrentSchema() -> TranscriptMetricsRecord {
        guard schemaVersion < Self.currentSchemaVersion else {
            return self
        }

        return TranscriptMetricsRecord(
            id: id,
            createdAt: createdAt,
            provider: provider,
            model: model,
            languageHint: languageHint,
            languageBreakdown: languageBreakdown,
            outcome: outcome,
            errorSummary: errorSummary,
            recordingDuration: recordingDuration,
            transcriptionLatency: transcriptionLatency,
            appVersion: appVersion,
            buildNumber: buildNumber
        )
    }
}

enum MetricsTimelineGranularity: String, CaseIterable, Identifiable {
    case hourly
    case daily

    var id: String { rawValue }
}

struct MetricsTimelineBucket: Identifiable {
    let startDate: Date
    let endDate: Date
    let transcriptCount: Int
    let totalCharacters: Int
    let totalWords: Int
    let estimatedTokens: Int
    let languageBreakdown: [LanguageMetrics]

    var id: Date { startDate }

    var hasContent: Bool {
        totalCharacters > 0
    }
}

struct MetricsCalculator {
    func correctedTranscriptionCount(
        events: [CorrectionCaptureEvent],
        cutoff: Date? = nil
    ) -> Int {
        var linkedHistoryIDs = Set<UUID>()
        var unlinkedEventCount = 0

        for event in events {
            if let cutoff, event.createdAt < cutoff {
                continue
            }

            let before = event.beforeText.trimmingCharacters(in: .whitespacesAndNewlines)
            let after = event.afterText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !before.isEmpty, !after.isEmpty, before != after else {
                continue
            }

            if let historyID = event.historyID {
                linkedHistoryIDs.insert(historyID)
            } else {
                // Legacy and manually saved drafts may not have a History ID.
                // They still represent a real corrected transcription, but
                // cannot be safely coalesced with another event.
                unlinkedEventCount += 1
            }
        }

        return linkedHistoryIDs.count + unlinkedEventCount
    }

    func recordsForDisplay(
        _ records: [TranscriptMetricsRecord],
        cutoff: Date?
    ) -> [TranscriptMetricsRecord] {
        guard let cutoff else {
            return records
        }
        return records.filter { $0.createdAt >= cutoff }
    }

    func calculate(history: [TranscriptItem]) -> TranscriptMetrics {
        var accumulators = emptyAccumulators()
        let successfulItems = history.filter { $0.outcome.isSuccessful }

        for item in successfulItems {
            accumulate(
                text: item.text,
                languageHint: item.languageHint,
                into: &accumulators
            )
        }

        let breakdown = makeLanguageBreakdown(from: accumulators)

        return TranscriptMetrics(
            transcriptCount: successfulItems.count,
            totalCharacters: totalCharacters(in: accumulators),
            totalWords: accumulators.values.reduce(0) { $0 + $1.words },
            estimatedTokens: breakdown.reduce(0) { $0 + $1.estimatedTokens },
            languageBreakdown: breakdown
        )
    }

    func calculate(records: [TranscriptMetricsRecord]) -> TranscriptMetrics {
        let successfulRecords = records.filter { $0.outcome.isSuccessful }
        let breakdown = makeLanguageBreakdown(from: successfulRecords)

        return TranscriptMetrics(
            transcriptCount: successfulRecords.count,
            totalCharacters: breakdown.reduce(0) { $0 + $1.characters },
            totalWords: breakdown.reduce(0) { $0 + $1.words },
            estimatedTokens: breakdown.reduce(0) { $0 + $1.estimatedTokens },
            languageBreakdown: breakdown
        )
    }

    func counters(from records: [TranscriptMetricsRecord]) -> MetricsCounters {
        let metrics = calculate(records: records)
        let metricsByLanguage = Dictionary(
            uniqueKeysWithValues: metrics.languageBreakdown.map { ($0.language, $0) }
        )
        let providerModelUsage = Dictionary(grouping: records) { record in
            "\(record.provider.rawValue)|\(record.model)"
        }
        .values
        .compactMap { groupedRecords -> ProviderModelUsageCounter? in
            guard let record = groupedRecords.first else {
                return nil
            }
            return ProviderModelUsageCounter(
                provider: record.provider,
                model: record.model,
                attempts: groupedRecords.count
            )
        }
        .sorted { $0.id < $1.id }
        let lastRecord = records.max { $0.createdAt < $1.createdAt }
        let lastFailedRecord = records
            .filter { $0.outcome == .failed && $0.errorSummary != nil }
            .max { $0.createdAt < $1.createdAt }

        return MetricsCounters(
            transcriptCount: metrics.transcriptCount,
            totalCharacters: metrics.totalCharacters,
            totalWords: metrics.totalWords,
            estimatedTokens: metrics.estimatedTokens,
            languageCounters: MetricsLanguage.allCases.map { language in
                let item = metricsByLanguage[language]
                return MetricsLanguageCounter(
                    language: language,
                    characters: item?.characters ?? 0,
                    words: item?.words ?? 0,
                    estimatedTokens: item?.estimatedTokens ?? 0
                )
            },
            totalAttempts: records.count,
            successfulTranscriptions: records.filter { $0.outcome == .succeeded }.count,
            failedTranscriptions: records.filter { $0.outcome == .failed }.count,
            totalRecordedSeconds: records.compactMap(\.recordingDuration).reduce(0, +),
            totalTranscriptionLatency: records.compactMap(\.transcriptionLatency).reduce(0, +),
            latencySampleCount: records.compactMap(\.transcriptionLatency).count,
            providerModelUsage: providerModelUsage,
            lastErrorSummary: lastFailedRecord?.errorSummary,
            appVersion: lastRecord?.appVersion ?? "unknown",
            buildNumber: lastRecord?.buildNumber ?? "unknown"
        )
    }

    func record(for item: TranscriptItem) -> TranscriptMetricsRecord {
        let metrics = calculate(history: [item])

        return TranscriptMetricsRecord(
            id: item.id,
            createdAt: item.createdAt,
            provider: item.provider,
            model: item.model,
            languageHint: item.languageHint,
            languageBreakdown: metrics.languageBreakdown,
            outcome: item.outcome,
            errorSummary: item.errorSummary,
            recordingDuration: item.recordingDuration,
            transcriptionLatency: item.transcriptionLatency,
            appVersion: item.appVersion,
            buildNumber: item.buildNumber
        )
    }

    func timeline(
        history: [TranscriptItem],
        granularity: MetricsTimelineGranularity,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [MetricsTimelineBucket] {
        let component: Calendar.Component
        let bucketCount: Int

        switch granularity {
        case .hourly:
            component = .hour
            bucketCount = 24
        case .daily:
            component = .day
            bucketCount = 14
        }

        guard let currentBucketStart = calendar.dateInterval(of: component, for: now)?.start,
              let firstBucketStart = calendar.date(byAdding: component, value: -(bucketCount - 1), to: currentBucketStart) else {
            return []
        }

        let bucketStarts = (0 ..< bucketCount).compactMap { offset in
            calendar.date(byAdding: component, value: offset, to: firstBucketStart)
        }
        var buckets = Dictionary(
            uniqueKeysWithValues: bucketStarts.map { startDate in
                (startDate, MetricsBucketAccumulator())
            }
        )

        for item in history where item.outcome.isSuccessful {
            guard let itemBucketStart = calendar.dateInterval(of: component, for: item.createdAt)?.start,
                  itemBucketStart >= firstBucketStart,
                  itemBucketStart <= currentBucketStart else {
                continue
            }

            var bucket = buckets[itemBucketStart] ?? MetricsBucketAccumulator()
            bucket.transcriptCount += 1
            accumulate(
                text: item.text,
                languageHint: item.languageHint,
                into: &bucket.languageAccumulators
            )
            buckets[itemBucketStart] = bucket
        }

        return bucketStarts.map { startDate in
            let accumulator = buckets[startDate] ?? MetricsBucketAccumulator()
            let breakdown = makeLanguageBreakdown(from: accumulator.languageAccumulators)
            let endDate = calendar.date(byAdding: component, value: 1, to: startDate) ?? startDate

            return MetricsTimelineBucket(
                startDate: startDate,
                endDate: endDate,
                transcriptCount: accumulator.transcriptCount,
                totalCharacters: totalCharacters(in: accumulator.languageAccumulators),
                totalWords: accumulator.languageAccumulators.values.reduce(0) { $0 + $1.words },
                estimatedTokens: breakdown.reduce(0) { $0 + $1.estimatedTokens },
                languageBreakdown: breakdown
            )
        }
    }

    func timeline(
        records: [TranscriptMetricsRecord],
        granularity: MetricsTimelineGranularity,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [MetricsTimelineBucket] {
        let component: Calendar.Component
        let bucketCount: Int

        switch granularity {
        case .hourly:
            component = .hour
            bucketCount = 24
        case .daily:
            component = .day
            bucketCount = 14
        }

        guard let currentBucketStart = calendar.dateInterval(of: component, for: now)?.start,
              let firstBucketStart = calendar.date(byAdding: component, value: -(bucketCount - 1), to: currentBucketStart) else {
            return []
        }

        let bucketStarts = (0 ..< bucketCount).compactMap { offset in
            calendar.date(byAdding: component, value: offset, to: firstBucketStart)
        }
        var buckets = Dictionary(
            uniqueKeysWithValues: bucketStarts.map { startDate in
                (startDate, MetricsBucketAccumulator())
            }
        )

        for record in records where record.outcome.isSuccessful {
            guard let recordBucketStart = calendar.dateInterval(of: component, for: record.createdAt)?.start,
                  recordBucketStart >= firstBucketStart,
                  recordBucketStart <= currentBucketStart else {
                continue
            }

            var bucket = buckets[recordBucketStart] ?? MetricsBucketAccumulator()
            bucket.transcriptCount += 1
            accumulate(record: record, into: &bucket.languageAccumulators)
            buckets[recordBucketStart] = bucket
        }

        return bucketStarts.map { startDate in
            let accumulator = buckets[startDate] ?? MetricsBucketAccumulator()
            let breakdown = makeLanguageBreakdown(from: accumulator.languageAccumulators)
            let endDate = calendar.date(byAdding: component, value: 1, to: startDate) ?? startDate

            return MetricsTimelineBucket(
                startDate: startDate,
                endDate: endDate,
                transcriptCount: accumulator.transcriptCount,
                totalCharacters: totalCharacters(in: accumulator.languageAccumulators),
                totalWords: accumulator.languageAccumulators.values.reduce(0) { $0 + $1.words },
                estimatedTokens: breakdown.reduce(0) { $0 + $1.estimatedTokens },
                languageBreakdown: breakdown
            )
        }
    }

    private func emptyAccumulators() -> [MetricsLanguage: MetricsAccumulator] {
        Dictionary(
            uniqueKeysWithValues: MetricsLanguage.allCases.map { language in
                (language, MetricsAccumulator())
            }
        )
    }

    private func makeLanguageBreakdown(from records: [TranscriptMetricsRecord]) -> [LanguageMetrics] {
        var accumulators = emptyAccumulators()

        for record in records {
            accumulate(record: record, into: &accumulators)
        }

        return makeLanguageBreakdown(from: accumulators)
    }

    private func makeLanguageBreakdown(from accumulators: [MetricsLanguage: MetricsAccumulator]) -> [LanguageMetrics] {
        let totalCharacters = accumulators.values.reduce(0) { $0 + $1.characters }

        return MetricsLanguage.allCases.map { language in
            let accumulator = accumulators[language] ?? MetricsAccumulator()
            let estimatedTokens = accumulator.estimatedTokens > 0
                ? accumulator.estimatedTokens
                : estimateTokens(language: language, accumulator: accumulator)
            let percentage = totalCharacters > 0
                ? Double(accumulator.characters) / Double(totalCharacters)
                : 0

            return LanguageMetrics(
                language: language,
                characters: accumulator.characters,
                words: accumulator.words,
                estimatedTokens: estimatedTokens,
                percentage: percentage
            )
        }
    }

    private func totalCharacters(in accumulators: [MetricsLanguage: MetricsAccumulator]) -> Int {
        accumulators.values.reduce(0) { $0 + $1.characters }
    }

    private func accumulate(
        text: String,
        languageHint: LanguageHint,
        into accumulators: inout [MetricsLanguage: MetricsAccumulator]
    ) {
        let containsKana = text.unicodeScalars.contains(where: isJapaneseKana)
        let latinLanguage = metricsLanguage(for: languageHint)
        var isInsideLatinWord = false

        for scalar in text.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                isInsideLatinWord = false
                continue
            }

            if isLatinLetterOrDigit(scalar) {
                accumulators[latinLanguage, default: MetricsAccumulator()].characters += 1

                if !isInsideLatinWord {
                    accumulators[latinLanguage, default: MetricsAccumulator()].words += 1
                    isInsideLatinWord = true
                }
                continue
            }

            isInsideLatinWord = false

            if isJapaneseKana(scalar) {
                accumulators[.japanese, default: MetricsAccumulator()].characters += 1
            } else if isHan(scalar) {
                let language: MetricsLanguage = containsKana ? .japanese : .chinese
                accumulators[language, default: MetricsAccumulator()].characters += 1
            } else {
                accumulators[.other, default: MetricsAccumulator()].characters += 1
            }
        }
    }

    private func metricsLanguage(for languageHint: LanguageHint) -> MetricsLanguage {
        switch languageHint {
        case .spanish:
            return .spanish
        case .french:
            return .french
        case .automatic, .chinese, .english, .japanese, .mixed:
            // Historical mixed/automatic records do not retain enough signal
            // to distinguish Latin languages reliably. Keep their established
            // English classification instead of guessing from short phrases.
            return .english
        }
    }

    private func accumulate(record: TranscriptMetricsRecord, into accumulators: inout [MetricsLanguage: MetricsAccumulator]) {
        for metrics in record.languageBreakdown {
            accumulators[metrics.language, default: MetricsAccumulator()].characters += metrics.characters
            accumulators[metrics.language, default: MetricsAccumulator()].words += metrics.words
            accumulators[metrics.language, default: MetricsAccumulator()].estimatedTokens += metrics.estimatedTokens
        }
    }

    private func estimateTokens(language: MetricsLanguage, accumulator: MetricsAccumulator) -> Int {
        guard accumulator.characters > 0 else {
            return 0
        }

        switch language {
        case .english, .spanish, .french:
            let wordEstimate = Int(ceil(Double(accumulator.words) * 1.3))
            let characterEstimate = Int(ceil(Double(accumulator.characters) / 4.0))
            return max(1, max(wordEstimate, characterEstimate))
        case .chinese, .japanese:
            return max(1, accumulator.characters)
        case .other:
            return max(1, Int(ceil(Double(accumulator.characters) / 3.0)))
        }
    }

    private func isLatinLetterOrDigit(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0030...0x0039,
             0x0041...0x005A,
             0x0061...0x007A:
            return true
        case 0x00C0...0x024F,
             0x1E00...0x1EFF:
            return CharacterSet.letters.contains(scalar)
        default:
            return false
        }
    }

    private func isHan(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF,
             0x4E00...0x9FFF,
             0xF900...0xFAFF,
             0x20000...0x2A6DF,
             0x2A700...0x2B73F,
             0x2B740...0x2B81F,
             0x2B820...0x2CEAF:
            return true
        default:
            return false
        }
    }

    private func isJapaneseKana(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x309F,
             0x30A0...0x30FF,
             0x31F0...0x31FF,
             0xFF66...0xFF9D:
            return true
        default:
            return false
        }
    }
}

private struct MetricsAccumulator {
    var characters = 0
    var words = 0
    var estimatedTokens = 0
}

private struct MetricsBucketAccumulator {
    var transcriptCount = 0
    var languageAccumulators = Dictionary(
        uniqueKeysWithValues: MetricsLanguage.allCases.map { language in
            (language, MetricsAccumulator())
        }
    )
}
