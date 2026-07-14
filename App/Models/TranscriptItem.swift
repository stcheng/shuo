import Foundation

enum TranscriptionAttemptOutcome: String, Codable, Equatable {
    case processing
    case succeeded
    case failed
    case ignoredSilence
    case ignoredEmptyTranscript
    case handledVoiceCommand
    case cancelled

    var isSuccessful: Bool {
        self == .succeeded
    }
}

enum AppBuildMetadata {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }
}

struct TranscriptItem: Identifiable, Codable, Equatable {
    static let currentSchemaVersion = 4

    let schemaVersion: Int
    let id: UUID
    var rawText: String
    var locallyProcessedText: String
    var text: String
    var initialText: String?
    let createdAt: Date
    var provider: TranscriptionProvider
    var model: String
    var languageHint: LanguageHint
    var selectedTranscriptionLanguages: [TranscriptionLanguage]?
    var detectedLanguageCode: String?
    let audioFileName: String?
    var outcome: TranscriptionAttemptOutcome
    var errorSummary: String?
    var recordingDuration: TimeInterval?
    var transcriptionLatency: TimeInterval?
    let appVersion: String
    let buildNumber: String

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        id: UUID = UUID(),
        text: String,
        rawText: String? = nil,
        locallyProcessedText: String? = nil,
        initialText: String? = nil,
        createdAt: Date = Date(),
        provider: TranscriptionProvider,
        model: String,
        languageHint: LanguageHint,
        selectedTranscriptionLanguages: [TranscriptionLanguage]? = nil,
        detectedLanguageCode: String? = nil,
        audioFileName: String? = nil,
        outcome: TranscriptionAttemptOutcome = .succeeded,
        errorSummary: String? = nil,
        recordingDuration: TimeInterval? = nil,
        transcriptionLatency: TimeInterval? = nil,
        appVersion: String = AppBuildMetadata.version,
        buildNumber: String = AppBuildMetadata.buildNumber
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.rawText = rawText ?? text
        self.locallyProcessedText = locallyProcessedText ?? text
        self.text = text
        self.initialText = initialText
        self.createdAt = createdAt
        self.provider = provider
        self.model = model
        self.languageHint = languageHint
        self.selectedTranscriptionLanguages = selectedTranscriptionLanguages
        self.detectedLanguageCode = detectedLanguageCode
        self.audioFileName = audioFileName
        self.outcome = outcome
        self.errorSummary = errorSummary
        self.recordingDuration = recordingDuration
        self.transcriptionLatency = transcriptionLatency
        self.appVersion = appVersion
        self.buildNumber = buildNumber
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case rawText
        case locallyProcessedText
        case text
        case initialText
        case createdAt
        case provider
        case model
        case languageHint
        case selectedTranscriptionLanguages
        case detectedLanguageCode
        case audioFileName
        case outcome
        case errorSummary
        case recordingDuration
        case transcriptionLatency
        case appVersion
        case buildNumber
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedText = try container.decode(String.self, forKey: .text)

        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        id = try container.decode(UUID.self, forKey: .id)
        rawText = try container.decodeIfPresent(String.self, forKey: .rawText) ?? decodedText
        locallyProcessedText = try container.decodeIfPresent(String.self, forKey: .locallyProcessedText) ?? decodedText
        text = decodedText
        initialText = try container.decodeIfPresent(String.self, forKey: .initialText)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        provider = try container.decode(TranscriptionProvider.self, forKey: .provider)
        model = try container.decode(String.self, forKey: .model)
        languageHint = try container.decode(LanguageHint.self, forKey: .languageHint)
        selectedTranscriptionLanguages = try container.decodeIfPresent(
            [TranscriptionLanguage].self,
            forKey: .selectedTranscriptionLanguages
        )
        detectedLanguageCode = try container.decodeIfPresent(
            String.self,
            forKey: .detectedLanguageCode
        )
        audioFileName = try container.decodeIfPresent(String.self, forKey: .audioFileName)
        outcome = try container.decodeIfPresent(TranscriptionAttemptOutcome.self, forKey: .outcome) ?? .succeeded
        errorSummary = try container.decodeIfPresent(String.self, forKey: .errorSummary)
        recordingDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .recordingDuration)
        transcriptionLatency = try container.decodeIfPresent(TimeInterval.self, forKey: .transcriptionLatency)
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion) ?? "unknown"
        buildNumber = try container.decodeIfPresent(String.self, forKey: .buildNumber) ?? "unknown"
    }

    func upgradedToCurrentSchema() -> TranscriptItem {
        guard schemaVersion < Self.currentSchemaVersion else {
            return self
        }

        return TranscriptItem(
            id: id,
            text: text,
            rawText: rawText,
            locallyProcessedText: locallyProcessedText,
            initialText: initialText,
            createdAt: createdAt,
            provider: provider,
            model: model,
            languageHint: languageHint,
            selectedTranscriptionLanguages: selectedTranscriptionLanguages,
            detectedLanguageCode: detectedLanguageCode,
            audioFileName: audioFileName,
            outcome: outcome,
            errorSummary: errorSummary,
            recordingDuration: recordingDuration,
            transcriptionLatency: transcriptionLatency,
            appVersion: appVersion,
            buildNumber: buildNumber
        )
    }

    mutating func applyUserCorrection(_ correctedText: String) {
        guard correctedText != text else {
            return
        }
        if initialText == nil {
            initialText = text
        }
        text = correctedText
    }
}
