import Foundation

struct AdaptiveRecognitionState: Codable, Equatable {
    var feedbackEvents: [AdaptiveRecognitionFeedbackEvent] = []
    var correctionEvents: [CorrectionCaptureEvent] = []
    var learnedPreferences: [AdaptiveRecognitionPreference] = []
    var enabledCorrectionPatternIDs: Set<CorrectionLearningPattern.ID> = []
    var learningResetAt: Date?

    init(
        feedbackEvents: [AdaptiveRecognitionFeedbackEvent] = [],
        correctionEvents: [CorrectionCaptureEvent] = [],
        learnedPreferences: [AdaptiveRecognitionPreference] = [],
        enabledCorrectionPatternIDs: Set<CorrectionLearningPattern.ID> = [],
        learningResetAt: Date? = nil
    ) {
        self.feedbackEvents = feedbackEvents
        self.correctionEvents = correctionEvents
        self.learnedPreferences = learnedPreferences
        self.enabledCorrectionPatternIDs = enabledCorrectionPatternIDs
        self.learningResetAt = learningResetAt
    }

    private enum CodingKeys: String, CodingKey {
        case feedbackEvents
        case correctionEvents
        case learnedPreferences
        case enabledCorrectionPatternIDs
        case learningResetAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        feedbackEvents = try container.decodeIfPresent(
            [AdaptiveRecognitionFeedbackEvent].self,
            forKey: .feedbackEvents
        ) ?? []
        correctionEvents = try container.decodeIfPresent(
            [CorrectionCaptureEvent].self,
            forKey: .correctionEvents
        ) ?? []
        learnedPreferences = try container.decodeIfPresent(
            [AdaptiveRecognitionPreference].self,
            forKey: .learnedPreferences
        ) ?? []
        enabledCorrectionPatternIDs = try container.decodeIfPresent(
            Set<CorrectionLearningPattern.ID>.self,
            forKey: .enabledCorrectionPatternIDs
        ) ?? []
        learningResetAt = try container.decodeIfPresent(Date.self, forKey: .learningResetAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(feedbackEvents, forKey: .feedbackEvents)
        try container.encode(correctionEvents, forKey: .correctionEvents)
        try container.encode(learnedPreferences, forKey: .learnedPreferences)
        try container.encode(
            enabledCorrectionPatternIDs.sorted {
                if $0.observedKey != $1.observedKey {
                    return $0.observedKey < $1.observedKey
                }
                return $0.preferredKey < $1.preferredKey
            },
            forKey: .enabledCorrectionPatternIDs
        )
        try container.encodeIfPresent(learningResetAt, forKey: .learningResetAt)
    }

    var enabledPreferences: [AdaptiveRecognitionPreference] {
        learnedPreferences.filter(\.isEnabled)
    }
}

/// Controls how captured corrections may affect future transcriptions.
///
/// Capturing correction data is intentionally independent from execution. The
/// enclosing `adaptiveRecognitionEnabled` switch remains the explicit opt-in;
/// this value only chooses what the enabled feature is allowed to do.
enum AdaptiveRecognitionMode: String, Codable, CaseIterable, Equatable {
    /// Apply only repeated, conflict-free local replacements during
    /// post-processing.
    case highConfidenceReplacement

    /// Add repeatedly preferred spellings to the transcription vocabulary
    /// without rewriting the result locally.
    case vocabularyHints

    var usesVocabularyHints: Bool {
        self == .vocabularyHints
    }

    var usesLocalReplacement: Bool {
        self == .highConfidenceReplacement
    }
}

/// A derived, non-persisted view of one local A -> B correction pattern.
/// Raw evidence remains the source of truth so deleting History or correction
/// data immediately changes the next snapshot.
struct CorrectionLearningPattern: Identifiable, Equatable {
    struct ID: Codable, Hashable {
        let observedKey: String
        let preferredKey: String
    }

    let id: ID
    let observedText: String
    let preferredText: String
    let observationCount: Int
    let trustedObservationCount: Int
    let trustedSessionCount: Int
    let historyObservationCount: Int
    let explicitObservationCount: Int
    let totalObservedSourceCount: Int
    let alternativeCount: Int
    let hasReverseMapping: Bool
    let runnerUpObservationCount: Int
    let confidence: Double
    let isVocabularyHintEligible: Bool
    let isHighConfidenceReplacementEligible: Bool

    var isAmbiguous: Bool {
        alternativeCount > 0
    }
}

/// UI- and runtime-ready learning state derived from retained local data.
struct CorrectionLearningSnapshot: Equatable {
    static let empty = CorrectionLearningSnapshot(
        evidenceEventCount: 0,
        historyEvidenceEventCount: 0,
        explicitEvidenceEventCount: 0,
        patterns: [],
        vocabularyHints: [],
        highConfidenceReplacements: []
    )

    let evidenceEventCount: Int
    let historyEvidenceEventCount: Int
    let explicitEvidenceEventCount: Int
    let patterns: [CorrectionLearningPattern]
    let vocabularyHints: [String]
    let highConfidenceReplacements: [CorrectionLearningPattern]
}

struct CorrectionCaptureEvent: Codable, Identifiable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var id: UUID
    var createdAt: Date
    var source: AdaptiveRecognitionFeedbackSource
    var beforeText: String
    var afterText: String
    var provider: TranscriptionProvider
    var model: String
    var languageHint: LanguageHint
    var historyID: UUID?
    var audioFileName: String?

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        id: UUID = UUID(),
        createdAt: Date = Date(),
        source: AdaptiveRecognitionFeedbackSource,
        beforeText: String,
        afterText: String,
        provider: TranscriptionProvider,
        model: String,
        languageHint: LanguageHint,
        historyID: UUID? = nil,
        audioFileName: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.createdAt = createdAt
        self.source = source
        self.beforeText = beforeText
        self.afterText = afterText
        self.provider = provider
        self.model = model
        self.languageHint = languageHint
        self.historyID = historyID
        self.audioFileName = audioFileName
    }
}

struct AdaptiveRecognitionFeedbackEvent: Codable, Identifiable, Equatable {
    var id: UUID
    var createdAt: Date
    var source: AdaptiveRecognitionFeedbackSource
    var observedText: String
    var preferredText: String
    var provider: TranscriptionProvider
    var model: String
    var languageHint: LanguageHint

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        source: AdaptiveRecognitionFeedbackSource,
        observedText: String,
        preferredText: String,
        provider: TranscriptionProvider,
        model: String,
        languageHint: LanguageHint
    ) {
        self.id = id
        self.createdAt = createdAt
        self.source = source
        self.observedText = observedText
        self.preferredText = preferredText
        self.provider = provider
        self.model = model
        self.languageHint = languageHint
    }
}

enum AdaptiveRecognitionFeedbackSource: String, Codable, Equatable {
    case manualDraftEdit
    case quickCopy
    case quickReplace
    case floatingCorrection
    case historyEdit
    case voiceEditCommand
}

struct AdaptiveRecognitionFeedbackContext: Equatable {
    var provider: TranscriptionProvider
    var model: String
    var languageHint: LanguageHint
    var historyID: UUID?
    var audioFileName: String?

    init(
        provider: TranscriptionProvider,
        model: String,
        languageHint: LanguageHint,
        historyID: UUID? = nil,
        audioFileName: String? = nil
    ) {
        self.provider = provider
        self.model = model
        self.languageHint = languageHint
        self.historyID = historyID
        self.audioFileName = audioFileName
    }
}

struct AdaptiveRecognitionPreference: Codable, Identifiable, Equatable {
    var id: UUID
    var kind: AdaptiveRecognitionPreferenceKind
    var observedText: String
    var preferredText: String
    var confidence: Double
    var observationCount: Int
    var createdAt: Date
    var updatedAt: Date
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        kind: AdaptiveRecognitionPreferenceKind,
        observedText: String,
        preferredText: String,
        confidence: Double,
        observationCount: Int,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isEnabled: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.observedText = observedText
        self.preferredText = preferredText
        self.confidence = confidence
        self.observationCount = observationCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isEnabled = isEnabled
    }
}

enum AdaptiveRecognitionPreferenceKind: String, Codable, Equatable {
    case correction
    case casing
    case phrase
}
