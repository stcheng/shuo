import Foundation

enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case english
    case simplifiedChinese
    case traditionalChinese
    case japanese

    var id: String { rawValue }

    var nativeDisplayName: String {
        switch self {
        case .english:
            return "English"
        case .simplifiedChinese:
            return "简体中文"
        case .traditionalChinese:
            return "繁體中文"
        case .japanese:
            return "日本語"
        }
    }
}

enum TranscriptionProvider: String, CaseIterable, Codable, Identifiable {
    case local
    case openAI
    case elevenLabs
    case alibaba
    case custom

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        switch rawValue {
        case "local":
            self = .local
        case "cloud", "openAI":
            self = .openAI
        case "elevenLabs":
            self = .elevenLabs
        case "alibaba":
            self = .alibaba
        case "custom":
            self = .custom
        default:
            self = .local
        }
    }

    var displayName: String {
        switch self {
        case .local:
            return "Local"
        case .openAI:
            return "OpenAI-compatible"
        case .elevenLabs:
            return "ElevenLabs"
        case .alibaba:
            return "Alibaba Cloud"
        case .custom:
            return "Custom"
        }
    }

    var modelOptions: [String] {
        switch self {
        case .local:
            return ["local.small", "local.medium", "local.large", "custom"]
        case .openAI:
            return OpenAIModelCatalog.transcriptionModelIDs
        case .elevenLabs:
            return ["scribe_v2"]
        case .alibaba:
            return [AlibabaTranscriptionService.modelID]
        case .custom:
            return ["custom"]
        }
    }

    var apiKeyGuideURL: URL? {
        switch self {
        case .openAI:
            return URL(string: "https://help.openai.com/en/articles/4936850-where-do-i-find-my-openai-api-key")
        case .elevenLabs:
            return URL(string: "https://elevenlabs.io/docs/overview/administration/workspaces/api-keys")
        case .alibaba:
            return URL(string: "https://www.alibabacloud.com/help/en/model-studio/get-api-key")
        case .local, .custom:
            return nil
        }
    }
}

enum LanguageHint: String, CaseIterable, Codable, Identifiable {
    case automatic
    case chinese
    case english
    case spanish
    case french
    case japanese
    case mixed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .chinese:
            return "Chinese"
        case .english:
            return "English"
        case .spanish:
            return "Spanish"
        case .french:
            return "French"
        case .japanese:
            return "Japanese"
        case .mixed:
            return "Multiple languages"
        }
    }
}

enum TranscriptionLanguage: String, CaseIterable, Codable, Identifiable, Hashable {
    case chinese
    case english
    case spanish
    case french
    case japanese

    var id: String { rawValue }
}

enum TranscriptInsertionBoundaryMode: String, CaseIterable, Identifiable, Equatable {
    case newline
    case smartSpace
    case none

    var id: String { rawValue }
}

extension LanguageHint {
    var transcriptionLanguages: Set<TranscriptionLanguage> {
        switch self {
        case .chinese:
            return [.chinese]
        case .english:
            return [.english]
        case .spanish:
            return [.spanish]
        case .french:
            return [.french]
        case .japanese:
            return [.japanese]
        case .automatic, .mixed:
            return Set(TranscriptionLanguage.allCases)
        }
    }

    init(transcriptionLanguages: Set<TranscriptionLanguage>) {
        if transcriptionLanguages.isEmpty {
            self = .automatic
        } else if transcriptionLanguages.count == 1,
                  let language = transcriptionLanguages.first {
            switch language {
            case .chinese:
                self = .chinese
            case .english:
                self = .english
            case .spanish:
                self = .spanish
            case .french:
                self = .french
            case .japanese:
                self = .japanese
            }
        } else {
            // Provider APIs accept at most one language code. For a multi-
            // language selection, omit that code and let the model detect the
            // spoken language while the explicit set still drives the UI.
            self = .mixed
        }
    }
}

/// Keeps language selection valid when the chosen local model has a narrower
/// language capability. The policy is deliberately independent of storage and
/// UI so model downloads, manual paths, Codable migration, and settings views
/// all enforce the same result.
enum TranscriptionLanguageSelectionPolicy {
    static func normalized(
        _ selection: Set<TranscriptionLanguage>,
        provider: TranscriptionProvider,
        localCapability: LocalWhisperLanguageCapability
    ) -> Set<TranscriptionLanguage> {
        guard provider == .local else {
            return nonEmptySelection(selection, allowed: Set(TranscriptionLanguage.allCases))
        }

        switch localCapability {
        case .englishOnly:
            return [.english]
        case .unknown, .multilingual:
            return nonEmptySelection(selection, allowed: Set(TranscriptionLanguage.allCases))
        }
    }

    private static func nonEmptySelection(
        _ selection: Set<TranscriptionLanguage>,
        allowed: Set<TranscriptionLanguage>
    ) -> Set<TranscriptionLanguage> {
        let filtered = selection.intersection(allowed)
        return filtered.isEmpty ? allowed : filtered
    }
}

extension LanguageHint {
    var localWhisperLanguageCode: String? {
        switch self {
        case .automatic, .mixed:
            return "auto"
        case .chinese:
            return "zh"
        case .english:
            return "en"
        case .spanish:
            return "es"
        case .french:
            return "fr"
        case .japanese:
            return "ja"
        }
    }

    var openAILanguageCode: String? {
        switch self {
        case .automatic, .mixed:
            return nil
        case .chinese:
            return "zh"
        case .english:
            return "en"
        case .spanish:
            return "es"
        case .french:
            return "fr"
        case .japanese:
            return "ja"
        }
    }

    var elevenLabsLanguageCode: String? {
        switch self {
        case .automatic, .mixed:
            return nil
        case .chinese:
            return "zho"
        case .english:
            return "eng"
        case .spanish:
            return "spa"
        case .french:
            return "fra"
        case .japanese:
            return "jpn"
        }
    }
}

enum LocalWhisperLanguageCapability: Equatable {
    case unknown
    case englishOnly
    case multilingual

    static func infer(fromModelPath modelPath: String) -> LocalWhisperLanguageCapability {
        let trimmedPath = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return .unknown
        }

        let filename = URL(fileURLWithPath: trimmedPath).lastPathComponent.lowercased()
        guard !filename.isEmpty else {
            return .unknown
        }

        let stem = filename.hasSuffix(".bin") ? String(filename.dropLast(4)) : filename
        if stem.contains(".en") || stem.contains("-en") {
            return .englishOnly
        }

        return .multilingual
    }

    var allowedLanguageHints: [LanguageHint] {
        switch self {
        case .unknown, .multilingual:
            return LanguageHint.allCases
        case .englishOnly:
            return [.english]
        }
    }

    var allowedTranscriptionLanguages: [TranscriptionLanguage] {
        switch self {
        case .unknown, .multilingual:
            return TranscriptionLanguage.allCases
        case .englishOnly:
            return [.english]
        }
    }
}

enum LocalWhisperPerformanceMode: String, CaseIterable, Codable, Identifiable {
    case balanced
    case fast

    var id: String { rawValue }
}

enum ChineseScriptPreference: String, CaseIterable, Codable, Identifiable {
    case automatic
    case simplified
    case traditional

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .simplified:
            return "Simplified Chinese"
        case .traditional:
            return "Traditional Chinese"
        }
    }

    var promptInstruction: String? {
        switch self {
        case .automatic:
            return nil
        case .simplified:
            return "When transcribing spoken Chinese, use Simplified Chinese characters. Do not translate English, Spanish, French, or Japanese, and do not convert Japanese kanji."
        case .traditional:
            return "When transcribing spoken Chinese, use Traditional Chinese characters. Do not translate English, Spanish, French, or Japanese, and do not convert Japanese kanji."
        }
    }
}

enum PunctuationPostProcessingMode: String, CaseIterable, Codable, Identifiable {
    case automatic
    case keep
    case replaceWithSpaces

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        switch rawValue {
        case Self.automatic.rawValue:
            self = .automatic
        case Self.replaceWithSpaces.rawValue:
            self = .replaceWithSpaces
        case Self.keep.rawValue, "remove":
            // "Remove all" no longer exists. Preserve the user's text by
            // migrating that pre-release value to the non-destructive mode.
            self = .keep
        default:
            self = .keep
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum ChineseTextConversionMode: String, CaseIterable, Codable, Identifiable {
    case keep
    case simplified
    case traditional

    var id: String { rawValue }

    static let explicitCases: [ChineseTextConversionMode] = [
        .simplified,
        .traditional
    ]
}

enum PushToTalkShortcut: String, CaseIterable, Codable, Identifiable {
    case rightOption
    case rightCommand

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rightOption:
            return "Right Option"
        case .rightCommand:
            return "Right Command"
        }
    }

    var keyCode: UInt16 {
        switch self {
        case .rightOption:
            return 0x3D
        case .rightCommand:
            return 0x36
        }
    }
}

struct OnboardingReadiness: Equatable {
    let providerIsReady: Bool
    let permissionsAreReady: Bool

    var canStart: Bool {
        providerIsReady && permissionsAreReady
    }

    static func evaluate(
        provider: TranscriptionProvider,
        openAIAPIKey: String,
        elevenLabsAPIKey: String,
        localModelIsReady: Bool,
        microphonePermissionGranted: Bool,
        accessibilityPermissionGranted: Bool,
        alibabaAPIKey: String = ""
    ) -> OnboardingReadiness {
        let providerIsReady: Bool
        switch provider {
        case .local:
            providerIsReady = localModelIsReady
        case .openAI:
            providerIsReady = !openAIAPIKey
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        case .elevenLabs:
            providerIsReady = !elevenLabsAPIKey
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        case .alibaba:
            providerIsReady = !alibabaAPIKey
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        case .custom:
            providerIsReady = false
        }

        return OnboardingReadiness(
            providerIsReady: providerIsReady,
            permissionsAreReady: microphonePermissionGranted && accessibilityPermissionGranted
        )
    }
}

enum RecordingCueSound: String, CaseIterable, Codable, Hashable, Identifiable {
    case softPing
    case doubleTap
    case brightChime
    case lowPop
    case deepDrop
    case woodKnock
    case softPulse
    case lowOrbit
    case subBeacon
    case darkPulse

    var id: String { rawValue }
}

enum VoiceEditCommandMode: String, CaseIterable, Codable, Identifiable {
    case localOnly
    case llmOnly

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        // Builds before the two explicit choices used "automatic". Migrate it
        // to the local path, which is deterministic and does not send text.
        self = rawValue == Self.llmOnly.rawValue ? .llmOnly : .localOnly
    }
}
