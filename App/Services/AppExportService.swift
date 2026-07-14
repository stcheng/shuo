import Foundation

struct SettingsExportDocument: Codable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let exportedAt: Date
    let settings: AppSettings
}

struct MetricsExportDocument: Codable, Equatable {
    static let currentSchemaVersion = 3

    let schemaVersion: Int
    let exportedAt: Date
    let summary: MetricsSummaryExport
    let languageBreakdown: [LanguageMetricsExport]
    let hourlyTimeline: [MetricsTimelineBucketExport]
    let dailyTimeline: [MetricsTimelineBucketExport]
    let transcripts: [TranscriptMetricsExport]
}

struct CorrectionDataExportDocument: Codable, Equatable {
    static let currentSchemaVersion = 5

    let schemaVersion: Int
    let exportedAt: Date
    let learningResetAt: Date?
    let corrections: [CorrectionCaptureEvent]
    let historyCorrections: [CorrectionHistoryEvidenceExport]
    let derivedPatterns: [CorrectionLearningPatternExport]
    let legacyFeedbackEvents: [AdaptiveRecognitionFeedbackEvent]
    let legacyLearnedPreferences: [AdaptiveRecognitionPreference]
}

struct CorrectionHistoryEvidenceExport: Codable, Equatable {
    enum Baseline: String, Codable, Equatable {
        case initialOutput
        case rawTranscription
    }

    let historyID: UUID
    let createdAt: Date
    let baseline: Baseline
    let beforeText: String
    let afterText: String
    let provider: TranscriptionProvider
    let model: String
    let languageHint: LanguageHint
    let audioFileName: String?
}

struct CorrectionLearningPatternExport: Codable, Equatable {
    let observedText: String
    let preferredText: String
    let observationCount: Int
    let trustedSessionCount: Int
    let historyObservationCount: Int
    let explicitObservationCount: Int
    let confidence: Double
    let hasConflict: Bool
    let isEnabled: Bool
    let isVocabularyHintEligible: Bool
    let isHighConfidenceReplacementEligible: Bool

    init(_ pattern: CorrectionLearningPattern, isEnabled: Bool) {
        observedText = pattern.observedText
        preferredText = pattern.preferredText
        observationCount = pattern.observationCount
        trustedSessionCount = pattern.trustedSessionCount
        historyObservationCount = pattern.historyObservationCount
        explicitObservationCount = pattern.explicitObservationCount
        confidence = pattern.confidence
        hasConflict = pattern.hasReverseMapping || pattern.isAmbiguous
        self.isEnabled = isEnabled
        isVocabularyHintEligible = pattern.isVocabularyHintEligible
        isHighConfidenceReplacementEligible = pattern.isHighConfidenceReplacementEligible
    }
}

struct MetricsSummaryExport: Codable, Equatable {
    let transcriptCount: Int
    let totalAttempts: Int
    let successfulTranscriptions: Int
    let failedTranscriptions: Int
    let totalCharacters: Int
    let totalWords: Int
    let estimatedTokens: Int
    let totalRecordedSeconds: TimeInterval
    let averageTranscriptionLatency: TimeInterval?
    let lastErrorSummary: String?
    let appVersion: String
    let buildNumber: String
}

struct LanguageMetricsExport: Codable, Equatable {
    let language: String
    let characters: Int
    let words: Int
    let estimatedTokens: Int
    let percentage: Double

    init(_ metrics: LanguageMetrics) {
        language = metrics.language.rawValue
        characters = metrics.characters
        words = metrics.words
        estimatedTokens = metrics.estimatedTokens
        percentage = metrics.percentage
    }
}

struct MetricsTimelineBucketExport: Codable, Equatable {
    let startDate: Date
    let endDate: Date
    let transcriptCount: Int
    let totalCharacters: Int
    let totalWords: Int
    let estimatedTokens: Int
    let languageBreakdown: [LanguageMetricsExport]

    init(_ bucket: MetricsTimelineBucket) {
        startDate = bucket.startDate
        endDate = bucket.endDate
        transcriptCount = bucket.transcriptCount
        totalCharacters = bucket.totalCharacters
        totalWords = bucket.totalWords
        estimatedTokens = bucket.estimatedTokens
        languageBreakdown = bucket.languageBreakdown.map(LanguageMetricsExport.init)
    }
}

struct TranscriptMetricsExport: Codable, Equatable {
    let id: UUID
    let createdAt: Date
    let provider: String
    let model: String
    let languageHint: String
    let outcome: String
    let errorSummary: String?
    let recordingDuration: TimeInterval?
    let transcriptionLatency: TimeInterval?
    let appVersion: String
    let buildNumber: String
    let characters: Int
    let words: Int
    let estimatedTokens: Int
    let languageBreakdown: [LanguageMetricsExport]

    init(record: TranscriptMetricsRecord) {
        id = record.id
        createdAt = record.createdAt
        provider = record.provider.rawValue
        model = record.model
        languageHint = record.languageHint.rawValue
        outcome = record.outcome.rawValue
        errorSummary = record.errorSummary
        recordingDuration = record.recordingDuration
        transcriptionLatency = record.transcriptionLatency
        appVersion = record.appVersion
        buildNumber = record.buildNumber
        characters = record.totalCharacters
        words = record.totalWords
        estimatedTokens = record.estimatedTokens
        languageBreakdown = record.languageBreakdown.map(LanguageMetricsExport.init)
    }
}

struct AppExportService {
    static func settingsExportData(
        settings: AppSettings,
        exportedAt: Date = Date()
    ) throws -> Data {
        let document = SettingsExportDocument(
            schemaVersion: SettingsExportDocument.currentSchemaVersion,
            exportedAt: exportedAt,
            settings: settings
        )
        return try makeEncoder().encode(document)
    }

    static func metricsExportData(
        records: [TranscriptMetricsRecord],
        exportedAt: Date = Date(),
        calendar: Calendar = .current
    ) throws -> Data {
        let calculator = MetricsCalculator()
        let summary = calculator.calculate(records: records)
        let counters = calculator.counters(from: records)
        let transcripts = records
            .sorted { $0.createdAt < $1.createdAt }
            .map(TranscriptMetricsExport.init(record:))

        let document = MetricsExportDocument(
            schemaVersion: MetricsExportDocument.currentSchemaVersion,
            exportedAt: exportedAt,
            summary: MetricsSummaryExport(summary, counters: counters),
            languageBreakdown: summary.languageBreakdown.map(LanguageMetricsExport.init),
            hourlyTimeline: calculator
                .timeline(
                    records: records,
                    granularity: .hourly,
                    now: exportedAt,
                    calendar: calendar
                )
                .map(MetricsTimelineBucketExport.init),
            dailyTimeline: calculator
                .timeline(
                    records: records,
                    granularity: .daily,
                    now: exportedAt,
                    calendar: calendar
                )
                .map(MetricsTimelineBucketExport.init),
            transcripts: transcripts
        )

        return try makeEncoder().encode(document)
    }

    static func correctionDataExportData(
        state: AdaptiveRecognitionState,
        history: [TranscriptItem] = [],
        learningSnapshot: CorrectionLearningSnapshot = .empty,
        exportedAt: Date = Date()
    ) throws -> Data {
        let document = CorrectionDataExportDocument(
            schemaVersion: CorrectionDataExportDocument.currentSchemaVersion,
            exportedAt: exportedAt,
            learningResetAt: state.learningResetAt,
            corrections: state.correctionEvents,
            historyCorrections: correctionHistoryEvidence(
                history: history,
                state: state
            ),
            derivedPatterns: learningSnapshot.patterns.map { pattern in
                CorrectionLearningPatternExport(
                    pattern,
                    isEnabled: state.enabledCorrectionPatternIDs.contains(pattern.id)
                )
            },
            legacyFeedbackEvents: state.feedbackEvents,
            legacyLearnedPreferences: state.learnedPreferences
        )
        return try makeEncoder().encode(document)
    }

    private static func correctionHistoryEvidence(
        history: [TranscriptItem],
        state: AdaptiveRecognitionState
    ) -> [CorrectionHistoryEvidenceExport] {
        let eligibleEvents = state.correctionEvents.filter { event in
            event.source != .voiceEditCommand
                && state.learningResetAt.map { event.createdAt > $0 } != false
        }
        let linkedFinalTextByHistoryID = Dictionary(grouping: eligibleEvents.compactMap { event in
            event.historyID.map { ($0, comparisonText(event.afterText)) }
        }, by: \.0)
        let cutoff = state.learningResetAt

        return history.compactMap { item in
            guard item.outcome.isSuccessful,
                  cutoff.map({ item.createdAt > $0 }) != false else {
                return nil
            }

            let baseline: CorrectionHistoryEvidenceExport.Baseline
            let beforeText: String
            if let initialText = item.initialText {
                baseline = .initialOutput
                beforeText = initialText
            } else {
                let finalText = comparisonText(item.text)
                let hasMatchingExplicitEdit = linkedFinalTextByHistoryID[item.id]?.contains {
                    $0.1 == finalText
                } == true
                guard hasMatchingExplicitEdit else {
                    return nil
                }
                baseline = .rawTranscription
                beforeText = item.rawText
            }

            guard comparisonText(beforeText) != comparisonText(item.text),
                  !comparisonText(beforeText).isEmpty,
                  !comparisonText(item.text).isEmpty else {
                return nil
            }
            return CorrectionHistoryEvidenceExport(
                historyID: item.id,
                createdAt: item.createdAt,
                baseline: baseline,
                beforeText: beforeText,
                afterText: item.text,
                provider: item.provider,
                model: item.model,
                languageHint: item.languageHint,
                audioFileName: item.audioFileName
            )
        }
    }

    private static func comparisonText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

private extension MetricsSummaryExport {
    init(_ metrics: TranscriptMetrics, counters: MetricsCounters) {
        transcriptCount = metrics.transcriptCount
        totalAttempts = counters.totalAttempts
        successfulTranscriptions = counters.successfulTranscriptions
        failedTranscriptions = counters.failedTranscriptions
        totalCharacters = metrics.totalCharacters
        totalWords = metrics.totalWords
        estimatedTokens = metrics.estimatedTokens
        totalRecordedSeconds = counters.totalRecordedSeconds
        averageTranscriptionLatency = counters.averageTranscriptionLatency
        lastErrorSummary = counters.lastErrorSummary
        appVersion = counters.appVersion
        buildNumber = counters.buildNumber
    }
}
