import Foundation

struct AppSettings: Codable, Equatable {
    static let defaultOpenAIBaseURL = "https://api.openai.com/v1"

    var hasCompletedOnboarding = false
    var appLanguage: AppLanguage = .english
    var showDockIcon = false
    var provider: TranscriptionProvider = .local
    var selectedModel: String = "local.medium"
    var openAITranscriptionModelSelectionMode: OpenAIModelSelectionMode = .automatic
    var automaticOpenAITranscriptionModel = OpenAIModelCatalog.defaultTranscriptionModelID
    var openAITextModelSelectionMode: OpenAITextModelSelectionMode = .automatic
    var automaticOpenAITextModel = OpenAIModelCatalog.defaultTextModelID
    var fixedOpenAITextModel = OpenAIModelCatalog.defaultTextModelID
    var customModelName = ""
    // Chinese + English covers Shuo's primary mixed-language path while
    // avoiding accidental Chinese-script conversion of Japanese kanji. Users
    // who need Japanese can still opt in beside these two during onboarding.
    var selectedTranscriptionLanguages: Set<TranscriptionLanguage> = [
        .chinese,
        .english
    ]
    var chineseScriptPreference: ChineseScriptPreference = .automatic
    var openAIBaseURL = Self.defaultOpenAIBaseURL
    var openAIOrganizationID = ""
    var openAIProjectID = ""
    var localWhisperExecutablePath = ""
    var localWhisperModelDirectoryPath = Self.defaultLocalWhisperModelDirectoryPath
    var localWhisperModelPath = ""
    var localWhisperPerformanceMode: LocalWhisperPerformanceMode = .balanced
    var audioInputDeviceID = AudioInputDeviceCatalog.systemDefaultDeviceID
    // Legacy decode/export field. Prompt Context's plugin switch is now the
    // single product control; disabled plugins provide an empty context.
    var sendContextPrompt = true
    var pushToTalkEnabled = true
    var pushToTalkShortcut: PushToTalkShortcut = .rightOption
    var recordingStartSoundEnabled = true
    var recordingStartSound: RecordingCueSound = .doubleTap
    var voiceActivityGateEnabled = true
    var whisperModeEnabled = false
    var minimumRecordingDuration = 0.35
    var minimumSpeechDuration = 0.18
    var silenceThresholdDBFS = -42.0
    var restoreClipboardAfterPaste = true
    var voiceEditCommandsEnabled = false
    var voiceEditCommandMode: VoiceEditCommandMode = .localOnly
    var promptContextItems = PromptContextItem.defaultItems
    var transcriptRetouchEnabled = false
    // Correction evidence is always captured locally. Execution remains an
    // explicit opt-in and starts with vocabulary hints, the safer mode.
    var adaptiveRecognitionEnabled = false
    var adaptiveRecognitionMode: AdaptiveRecognitionMode = .vocabularyHints
    var punctuationPostProcessingMode: PunctuationPostProcessingMode = .automatic
    var chineseTextConversionMode: ChineseTextConversionMode = .keep
    var emojiPostProcessingEnabled = true
    var smartEmojiMatchingAfterTranscription = true
    var aiEmojiResolverEnabled = false
    // Legacy persisted fields. Whitespace cleanup is now always enabled.
    var collapseWhitespaceAfterTranscription = true
    var trimWhitespaceAfterTranscription = true
    var lowercaseEnglishAfterTranscription = false
    var insertSpaceBetweenChineseAndEnglish = false
    var appendNewlineAfterTranscription = false
    var appendSpaceAfterTranscription = true
    var automaticUpdateChecksEnabled = true
    var automaticUpdatesEnabled = false
    var useDeveloperGlossary = true
    var developerGlossary = ""
    var namedVocabularies: [NamedVocabularyItem] = TerminologyPresetCatalog.seedItems
    var deletedTerminologyPresetIDs: Set<String> = []
    var useCustomCorrections = true
    var customCorrections = ""
    var contextPrompt = "Prefer verbatim transcription. Do not translate. Preserve mixed Chinese, English, Spanish, French, and Japanese."

    init() {}

    static let audibleAudioPeakFloorDBFS = -65.0
    static let audibleAudioRMSFloorDBFS = -72.0

    var effectiveModel: String {
        if provider == .local {
            let trimmedModelPath = localWhisperModelPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedModelPath.isEmpty else {
                return selectedModel
            }
            return URL(fileURLWithPath: trimmedModelPath).lastPathComponent
        }

        if provider == .openAI,
           openAITranscriptionModelSelectionMode == .automatic {
            return OpenAIModelCatalog.normalizedAutomaticTranscriptionModelID(
                automaticOpenAITranscriptionModel
            )
        }

        if selectedModel == "custom" {
            let trimmed = customModelName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "custom" : trimmed
        }
        return selectedModel
    }

    /// Compatibility bridge for providers and historical records that accept
    /// one language hint. The settings UI stores the user's actual multi-
    /// selection in `selectedTranscriptionLanguages`.
    var languageHint: LanguageHint {
        get { LanguageHint(transcriptionLanguages: selectedTranscriptionLanguages) }
        set { selectedTranscriptionLanguages = newValue.transcriptionLanguages }
    }

    var availableTranscriptionLanguages: [TranscriptionLanguage] {
        guard provider == .local else {
            return TranscriptionLanguage.allCases
        }

        return localWhisperLanguageCapability.allowedTranscriptionLanguages
    }

    var includesChineseTranscription: Bool {
        selectedTranscriptionLanguages.contains(.chinese)
    }

    var includesEnglishTranscription: Bool {
        selectedTranscriptionLanguages.contains(.english)
    }

    /// Resolves the two historical Chinese-script settings into the concrete
    /// output mode shown by onboarding. Existing explicit output behavior wins;
    /// otherwise retain the older preference before falling back to the UI
    /// language (and Simplified Chinese for non-Chinese interfaces).
    var resolvedChineseTextConversionMode: ChineseTextConversionMode {
        if chineseTextConversionMode != .keep {
            return chineseTextConversionMode
        }

        switch chineseScriptPreference {
        case .simplified:
            return .simplified
        case .traditional:
            return .traditional
        case .automatic:
            return appLanguage == .traditionalChinese ? .traditional : .simplified
        }
    }

    mutating func setPreferredChineseTextConversionMode(
        _ mode: ChineseTextConversionMode
    ) {
        guard mode != .keep else {
            return
        }

        chineseTextConversionMode = mode
        chineseScriptPreference = mode == .traditional ? .traditional : .simplified
    }

    mutating func setTranscriptionLanguage(_ language: TranscriptionLanguage, isEnabled: Bool) {
        if isEnabled {
            selectedTranscriptionLanguages.insert(language)
        } else if selectedTranscriptionLanguages.count > 1 {
            selectedTranscriptionLanguages.remove(language)
        }
        normalizeLanguageSelection()
    }

    mutating func resetOpenAIConnectionDetails() {
        openAIBaseURL = Self.defaultOpenAIBaseURL
        openAIOrganizationID = ""
        openAIProjectID = ""
    }

    var effectiveContextPrompt: String {
        promptContextItems
            .filter(\.isEnabled)
            .map { $0.prompt.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    var effectiveVocabularyGlossary: String {
        NamedVocabularyItem.combinedGlossary(
            legacyGlossary: developerGlossary,
            items: namedVocabularies
        )
    }

    /// User-created sources retain priority over project extraction. Curated
    /// starter vocabularies look and edit the same in Settings, but consume
    /// only the lower-priority spare vocabulary budget at runtime.
    var effectiveManualVocabularyGlossary: String {
        NamedVocabularyItem.combinedGlossary(
            legacyGlossary: developerGlossary,
            items: namedVocabularies.filter { $0.presetID == nil }
        )
    }

    var effectivePresetVocabularyTerms: [String] {
        namedVocabularies
            .filter { $0.isEnabled && $0.presetID != nil }
            .flatMap(\.normalizedTerms)
    }

    var effectiveVocabularyTerms: [String] {
        effectiveVocabularyGlossary
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var effectiveVoiceEditLLMModel: String {
        provider == .gemini ? effectiveModel : effectiveTextModel
    }

    var effectiveTranscriptRetouchLLMModel: String {
        provider == .gemini ? effectiveModel : effectiveTextModel
    }

    var effectiveEmojiResolverLLMModel: String {
        provider == .gemini ? effectiveModel : effectiveTextModel
    }

    var appliesPunctuationPostProcessing: Bool {
        punctuationPostProcessingMode != .keep
    }

    var transcriptInsertionBoundaryMode: TranscriptInsertionBoundaryMode {
        get {
            if appendNewlineAfterTranscription {
                return .newline
            }
            if appendSpaceAfterTranscription {
                return .smartSpace
            }
            return .none
        }
        set {
            switch newValue {
            case .newline:
                appendNewlineAfterTranscription = true
                appendSpaceAfterTranscription = false
            case .smartSpace:
                appendNewlineAfterTranscription = false
                appendSpaceAfterTranscription = true
            case .none:
                appendNewlineAfterTranscription = false
                appendSpaceAfterTranscription = false
            }
        }
    }

    mutating func setTranscriptInsertionBoundaryMode(_ mode: TranscriptInsertionBoundaryMode) {
        transcriptInsertionBoundaryMode = mode
    }

    var localWhisperLanguageCapability: LocalWhisperLanguageCapability {
        LocalWhisperLanguageCapability.infer(fromModelPath: localWhisperModelPath)
    }

    var localTranscriptionEngine: LocalTranscriptionEngine? {
        LocalTranscriptionEngine.infer(fromModelPath: localWhisperModelPath)
    }

    var usesSenseVoiceLocalTranscription: Bool {
        provider == .local && localTranscriptionEngine == .senseVoice
    }

    var availableLanguageHints: [LanguageHint] {
        guard provider == .local else {
            return LanguageHint.allCases
        }

        return localWhisperLanguageCapability.allowedLanguageHints
    }

    mutating func normalizeSelections() {
        normalizeModelSelection()
        normalizeOpenAIModelSelections()
        normalizeLocalWhisperModelSelection()
        normalizeLanguageSelection()
        normalizeUpdatePreferences()
        audioInputDeviceID = AudioInputDeviceCatalog.normalizedSelectionID(audioInputDeviceID)
        // Clipboard restoration is part of Shuo's insertion safety contract,
        // not a user-selectable behavior. Preserve the legacy field only so
        // older settings files continue to decode cleanly.
        restoreClipboardAfterPaste = true
        collapseWhitespaceAfterTranscription = true
        trimWhitespaceAfterTranscription = true
    }

    mutating func normalizeModelSelection() {
        guard !provider.modelOptions.contains(selectedModel) else {
            return
        }
        selectedModel = provider.modelOptions.first ?? "custom"
    }

    private mutating func normalizeOpenAIModelSelections() {
        automaticOpenAITranscriptionModel = OpenAIModelCatalog
            .normalizedAutomaticTranscriptionModelID(automaticOpenAITranscriptionModel)
        automaticOpenAITextModel = OpenAIModelCatalog
            .normalizedAutomaticTextModelID(automaticOpenAITextModel)
        // Keep the fixed value editable. Normalizing an empty intermediate
        // value here would replace it on every TextField keystroke; runtime and
        // decode paths normalize it at their actual use boundaries instead.
    }

    private var effectiveTextModel: String {
        if openAITextModelSelectionMode == .automatic {
            return OpenAIModelCatalog.normalizedAutomaticTextModelID(automaticOpenAITextModel)
        }
        return OpenAIModelCatalog.normalizedTextModelID(fixedOpenAITextModel)
    }

    mutating func normalizeLanguageSelection() {
        selectedTranscriptionLanguages = TranscriptionLanguageSelectionPolicy.normalized(
            selectedTranscriptionLanguages,
            provider: provider,
            localCapability: localWhisperLanguageCapability
        )
    }

    private mutating func normalizeLocalWhisperModelSelection() {
        guard provider == .local else {
            return
        }

        let modelPaths = LocalWhisperModelCatalog.modelPaths(in: localWhisperModelDirectoryPath)
        guard !modelPaths.isEmpty else {
            localWhisperModelPath = ""
            return
        }

        let standardizedModelPath = Self.standardizedFilePath(localWhisperModelPath)
        guard modelPaths.contains(standardizedModelPath) else {
            localWhisperModelPath = modelPaths[0]
            return
        }

        localWhisperModelPath = standardizedModelPath
    }

    private mutating func normalizeUpdatePreferences() {
        guard automaticUpdateChecksEnabled else {
            automaticUpdatesEnabled = false
            return
        }
    }

    private static func standardizedFilePath(_ path: String) -> String {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return ""
        }

        return URL(fileURLWithPath: trimmedPath).standardizedFileURL.path
    }
}

/// Produces a runtime-only settings snapshot that honors Local mode's privacy boundary.
/// The persisted settings remain untouched so a user's cloud preferences are restored
/// when they later select a cloud transcription provider.
enum CloudTextAICapabilityPolicy {
    static func isCloudTextAIAvailable(for settings: AppSettings) -> Bool {
        guard settings.provider != .local else {
            return false
        }

        // This persisted field predates Gemini, but `.disabled` is the
        // provider-neutral, explicit opt-out for every optional cloud text
        // feature. Gemini still uses its own credential and selected model;
        // this switch only controls whether optional text is sent at all.
        return settings.openAITextModelSelectionMode != .disabled
    }

    static func applying(to source: AppSettings) -> AppSettings {
        guard !isCloudTextAIAvailable(for: source) else {
            return source
        }

        var adjusted = source
        adjusted.transcriptRetouchEnabled = false
        adjusted.aiEmojiResolverEnabled = false
        adjusted.voiceEditCommandMode = .localOnly
        return adjusted
    }
}
