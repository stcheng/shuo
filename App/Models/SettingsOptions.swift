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
    case gemini
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
        case "gemini":
            self = .gemini
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
        case .gemini:
            return "Google Gemini"
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
        case .gemini:
            return GeminiTranscriptionService.modelIDs
        case .custom:
            return ["custom"]
        }
    }

    /// Kept for call sites outside the cloud picker. The actual guide URL is
    /// defined with the provider's other connection metadata.
    var apiKeyGuideURL: URL? {
        CloudTranscriptionProviderConfiguration.apiKeyGuideURL(for: self)
    }

}

enum TranscriptionExecutionLocation: String, CaseIterable, Identifiable {
    case local
    case cloud

    var id: String { rawValue }
}

/// Cloud services that can perform Shuo's optional text processing. ElevenLabs
/// and Alibaba Cloud are intentionally absent: their Shuo integrations expose
/// speech transcription, not the chat-completions interface used for retouch.
enum CloudTextServicePreset: String, CaseIterable, Codable, Identifiable {
    case openAI
    case groq
    case siliconFlow
    case gemini
    case custom

    var id: String { rawValue }

    var provider: TranscriptionProvider {
        self == .gemini ? .gemini : .openAI
    }

    var baseURL: String? {
        switch self {
        case .openAI:
            return CloudTranscriptionProviderConfiguration.openAI.endpoint.defaultURLString
        case .groq:
            return CloudTranscriptionProviderConfiguration.groq.endpoint.defaultURLString
        case .siliconFlow:
            return CloudTranscriptionProviderConfiguration.siliconFlow.endpoint.defaultURLString
        case .gemini:
            return nil
        case .custom:
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
        case .senseVoice:
            return nonEmptySelection(
                selection,
                allowed: [.chinese, .english, .japanese]
            )
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
    case senseVoice

    static func infer(fromModelPath modelPath: String) -> LocalWhisperLanguageCapability {
        let trimmedPath = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return .unknown
        }

        guard let engine = LocalTranscriptionEngine.infer(fromModelPath: trimmedPath) else {
            return .unknown
        }
        if engine == .senseVoice {
            return .senseVoice
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
        case .senseVoice:
            return [.automatic, .chinese, .english, .japanese, .mixed]
        }
    }

    var allowedTranscriptionLanguages: [TranscriptionLanguage] {
        switch self {
        case .unknown, .multilingual:
            return TranscriptionLanguage.allCases
        case .englishOnly:
            return [.english]
        case .senseVoice:
            return [.chinese, .english, .japanese]
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
    case custom

    var id: String { rawValue }

    static let pickerCases: [PushToTalkShortcut] = [
        .rightCommand,
        .rightOption,
        .custom
    ]

    var displayName: String {
        switch self {
        case .rightOption:
            return "Right Option"
        case .rightCommand:
            return "Right Command"
        case .custom:
            return "Custom"
        }
    }

    var builtInKeyCode: UInt16? {
        switch self {
        case .rightOption:
            return 0x3D
        case .rightCommand:
            return 0x36
        case .custom:
            return nil
        }
    }

    var keyCode: UInt16 {
        builtInKeyCode ?? 0
    }
}

enum PushToTalkShortcutModifier: String, CaseIterable, Codable, Hashable {
    case control
    case option
    case shift
    case command
    case function

    static let displayOrder: [PushToTalkShortcutModifier] = [
        .control,
        .option,
        .shift,
        .command,
        .function
    ]

    var displayName: String {
        switch self {
        case .control:
            return "Control"
        case .option:
            return "Option"
        case .shift:
            return "Shift"
        case .command:
            return "Command"
        case .function:
            return "Fn"
        }
    }

    static func modifier(forKeyCode keyCode: UInt16) -> PushToTalkShortcutModifier? {
        switch keyCode {
        case 0x36, 0x37:
            return .command
        case 0x38, 0x3C:
            return .shift
        case 0x3A, 0x3D:
            return .option
        case 0x3B, 0x3E:
            return .control
        case 0x3F:
            return .function
        default:
            return nil
        }
    }
}

struct CustomPushToTalkShortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: Set<PushToTalkShortcutModifier>

    init(keyCode: UInt16, modifiers: Set<PushToTalkShortcutModifier> = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    var displayName: String {
        let modifierNames = PushToTalkShortcutModifier.displayOrder
            .filter { modifiers.contains($0) }
            .map(\.displayName)
        return (modifierNames + [Self.keyDisplayName(for: keyCode)])
            .joined(separator: " + ")
    }

    var isModifierOnly: Bool {
        Self.modifierKeyCodes.contains(keyCode) && modifiers.isEmpty
    }

    var isValidHoldShortcut: Bool {
        isModifierOnly
            || !modifiers.isEmpty
            || Self.nonTextKeyCodes.contains(keyCode)
    }

    static let modifierKeyCodes: Set<UInt16> = [
        0x36, // Right Command
        0x37, // Left Command
        0x38, // Left Shift
        0x3A, // Left Option
        0x3B, // Left Control
        0x3C, // Right Shift
        0x3D, // Right Option
        0x3E, // Right Control
        0x3F  // Fn
    ]

    static let nonTextKeyCodes: Set<UInt16> = Set(keyDisplayNames.keys)
        .subtracting(textKeyCodes)

    private static let textKeyCodes: Set<UInt16> = [
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
        0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x12, 0x13, 0x14,
        0x15, 0x16, 0x17, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F, 0x20,
        0x21, 0x22, 0x23, 0x25, 0x26, 0x28, 0x29, 0x2A, 0x2B, 0x2C,
        0x2D, 0x2E, 0x2F, 0x31, 0x32
    ]

    static func keyDisplayName(for keyCode: UInt16) -> String {
        keyDisplayNames[keyCode] ?? "Key \(keyCode)"
    }

    private static let keyDisplayNames: [UInt16: String] = [
        0x00: "A",
        0x01: "S",
        0x02: "D",
        0x03: "F",
        0x04: "H",
        0x05: "G",
        0x06: "Z",
        0x07: "X",
        0x08: "C",
        0x09: "V",
        0x0B: "B",
        0x0C: "Q",
        0x0D: "W",
        0x0E: "E",
        0x0F: "R",
        0x10: "Y",
        0x11: "T",
        0x12: "1",
        0x13: "2",
        0x14: "3",
        0x15: "4",
        0x16: "6",
        0x17: "5",
        0x18: "=",
        0x19: "9",
        0x1A: "7",
        0x1B: "-",
        0x1C: "8",
        0x1D: "0",
        0x1E: "]",
        0x1F: "O",
        0x20: "U",
        0x21: "[",
        0x22: "I",
        0x23: "P",
        0x24: "Return",
        0x25: "L",
        0x26: "J",
        0x27: "'",
        0x28: "K",
        0x29: ";",
        0x2A: "\\",
        0x2B: ",",
        0x2C: "/",
        0x2D: "N",
        0x2E: "M",
        0x2F: ".",
        0x30: "Tab",
        0x31: "Space",
        0x32: "`",
        0x33: "Delete",
        0x35: "Escape",
        0x36: "Right Command",
        0x37: "Left Command",
        0x38: "Left Shift",
        0x3A: "Left Option",
        0x3B: "Left Control",
        0x3C: "Right Shift",
        0x3D: "Right Option",
        0x3E: "Right Control",
        0x3F: "Fn",
        0x40: "F17",
        0x4F: "F18",
        0x50: "F19",
        0x5A: "F20",
        0x60: "F5",
        0x61: "F6",
        0x62: "F7",
        0x63: "F3",
        0x64: "F8",
        0x65: "F9",
        0x67: "F11",
        0x69: "F13",
        0x6A: "F16",
        0x6B: "F14",
        0x6D: "F10",
        0x6F: "F12",
        0x71: "F15",
        0x72: "Help",
        0x73: "Home",
        0x74: "Page Up",
        0x75: "Forward Delete",
        0x76: "F4",
        0x77: "End",
        0x78: "F2",
        0x79: "Page Down",
        0x7A: "F1",
        0x7B: "Left Arrow",
        0x7C: "Right Arrow",
        0x7D: "Down Arrow",
        0x7E: "Up Arrow"
    ]
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
        alibabaAPIKey: String = "",
        geminiAPIKey: String = ""
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
        case .gemini:
            providerIsReady = !geminiAPIKey
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
