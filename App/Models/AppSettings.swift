import Foundation

/// Stores model choices and successful protocol checks for a user-entered
/// OpenAI-compatible endpoint. Credentials deliberately stay in the Keychain,
/// scoped by endpoint, rather than in this persisted settings contract.
struct CustomOpenAIEndpointProfile: Codable, Equatable {
    var transcriptionModelSelectionMode: OpenAIModelSelectionMode = .automatic
    var automaticTranscriptionModelID = OpenAIModelCatalog.defaultTranscriptionModelID
    var fixedTranscriptionModelID = OpenAIModelCatalog.defaultTranscriptionModelID
    var verifiedTranscriptionModelID: String?
    var textModelSelectionMode: OpenAITextModelSelectionMode = .automatic
    var automaticTextModelID = OpenAIModelCatalog.defaultTextModelID
    var fixedTextModelID = OpenAIModelCatalog.defaultTextModelID
    var verifiedTextModelID: String?

    init() {}
}

struct AppSettings: Codable, Equatable {
    static let defaultOpenAIBaseURL = "https://api.openai.com/v1"

    var hasCompletedOnboarding = false
    var appLanguage: AppLanguage = .system
    var showDockIcon = false
    var provider: TranscriptionProvider = .local
    var selectedModel: String = "local.medium"
    var openAITranscriptionModelSelectionMode: OpenAIModelSelectionMode = .automatic
    var automaticOpenAITranscriptionModel = OpenAIModelCatalog.defaultTranscriptionModelID
    var fixedOpenAITranscriptionModel = OpenAIModelCatalog.defaultTranscriptionModelID
    var openAITextModelSelectionMode: OpenAITextModelSelectionMode = .automatic
    var automaticOpenAITextModel = OpenAIModelCatalog.defaultTextModelID
    var fixedOpenAITextModel = OpenAIModelCatalog.defaultTextModelID
    // Text processing may reuse the transcription service or use its own
    // cloud connection. The existing OpenAI text model fields above remain
    // the model selection for every OpenAI-compatible text connection.
    var cloudTextUsesTranscriptionService = true
    var cloudTextServicePreset: CloudTextServicePreset = .openAI
    var cloudTextOpenAIBaseURL = Self.defaultOpenAIBaseURL
    var lastCustomCloudTextOpenAIBaseURL = ""
    var cloudTextGeminiModel = GeminiTranscriptionService.defaultModelID
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
    var lastCustomOpenAIBaseURL = ""
    /// Keeps an explicitly chosen Custom service distinct from a built-in
    /// service, even before the user finishes entering its endpoint URL.
    var openAIUsesCustomEndpoint = false
    /// User-entered endpoints keep their own model selections and verification
    /// results, so switching to a built-in provider and back is lossless.
    var customOpenAIEndpointProfiles: [String: CustomOpenAIEndpointProfile] = [:]
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
    var customPushToTalkShortcut: CustomPushToTalkShortcut?
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

    var effectiveModel: String {
        if provider == .local {
            let trimmedModelPath = localWhisperModelPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedModelPath.isEmpty else {
                return selectedModel
            }
            return URL(fileURLWithPath: trimmedModelPath).lastPathComponent
        }

        if provider == .openAI {
            if openAITranscriptionModelSelectionMode == .automatic {
                return OpenAIModelCatalog.normalizedAutomaticTranscriptionModelID(
                    automaticOpenAITranscriptionModel
                )
            }
            return fixedOpenAITranscriptionModel.trimmingCharacters(in: .whitespacesAndNewlines)
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
            return appLanguage.resolved == .traditionalChinese ? .traditional : .simplified
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
        openAIUsesCustomEndpoint = false
        openAIOrganizationID = ""
        openAIProjectID = ""
    }

    var isCustomOpenAITranscriptionService: Bool {
        provider == .openAI
            && (openAIUsesCustomEndpoint
                || CloudServiceCatalog.inferred(
                    backendProvider: provider,
                    compatibleBaseURL: openAIBaseURL
                ).id == .custom)
    }

    var effectiveCloudTranscriptionPreset: CloudTranscriptionPreset {
        guard provider == .openAI else {
            return CloudServiceCatalog.inferred(
                backendProvider: provider,
                compatibleBaseURL: openAIBaseURL
            ).preset
        }
        return isCustomOpenAITranscriptionService
            ? .custom
            : CloudServiceCatalog.inferred(
                backendProvider: provider,
                compatibleBaseURL: openAIBaseURL
            ).preset
    }

    var requiresCustomOpenAITranscriptionVerification: Bool {
        resolvedCloudTranscriptionConnection?.verification == .required
    }

    mutating func saveCurrentCustomOpenAITranscriptionProfile() {
        guard isCustomOpenAITranscriptionService else {
            return
        }

        let identity = customEndpointIdentity(openAIBaseURL)
        var profile = customOpenAIEndpointProfiles[identity] ?? CustomOpenAIEndpointProfile()
        profile.transcriptionModelSelectionMode = openAITranscriptionModelSelectionMode
        profile.automaticTranscriptionModelID = automaticOpenAITranscriptionModel
        profile.fixedTranscriptionModelID = fixedOpenAITranscriptionModel
        customOpenAIEndpointProfiles[identity] = profile
    }

    mutating func restoreCustomOpenAITranscriptionProfile() {
        guard isCustomOpenAITranscriptionService else {
            return
        }

        let profile = customOpenAIEndpointProfiles[customEndpointIdentity(openAIBaseURL)]
            ?? CustomOpenAIEndpointProfile()
        openAITranscriptionModelSelectionMode = profile.transcriptionModelSelectionMode
        automaticOpenAITranscriptionModel = profile.automaticTranscriptionModelID
        fixedOpenAITranscriptionModel = profile.fixedTranscriptionModelID
        saveCurrentCustomOpenAITranscriptionProfile()
    }

    mutating func markCurrentCustomOpenAITranscriptionModelVerified() {
        guard isCustomOpenAITranscriptionService,
              let modelID = try? OpenAIModelCatalog.validatedFixedTranscriptionModelID(
                  effectiveModel
              ) else {
            return
        }

        let identity = customEndpointIdentity(openAIBaseURL)
        var profile = customOpenAIEndpointProfiles[identity] ?? CustomOpenAIEndpointProfile()
        profile.transcriptionModelSelectionMode = openAITranscriptionModelSelectionMode
        profile.automaticTranscriptionModelID = automaticOpenAITranscriptionModel
        profile.fixedTranscriptionModelID = fixedOpenAITranscriptionModel
        profile.verifiedTranscriptionModelID = modelID
        customOpenAIEndpointProfiles[identity] = profile
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
        effectiveCloudTextModel
    }

    var effectiveTranscriptRetouchLLMModel: String {
        effectiveCloudTextModel
    }

    var effectiveEmojiResolverLLMModel: String {
        effectiveCloudTextModel
    }

    /// The selected OpenAI-compatible text model after the existing automatic
    /// and fixed-mode normalization. Cloud connection resolution consumes this
    /// value without exposing the private normalization implementation.
    var effectiveOpenAICompatibleTextModel: String {
        effectiveTextModel
    }

    var effectiveCloudTextBaseURL: String? {
        guard let connection = resolvedCloudTextConnection,
              connection.isOpenAICompatible else {
            return nil
        }
        return connection.endpoint
    }

    var effectiveCloudTextModel: String {
        resolvedCloudTextConnection?.modelSelection.modelID ?? effectiveTextModel
    }

    var isCustomOpenAICloudTextService: Bool {
        resolvedCloudTextConnection?.service.id == .custom
    }

    var requiresCustomOpenAICloudTextVerification: Bool {
        resolvedCloudTextConnection?.verification == .required
    }

    mutating func saveCurrentCustomOpenAICloudTextProfile() {
        guard isCustomOpenAICloudTextService,
              let baseURL = effectiveCloudTextBaseURL else {
            return
        }

        let identity = customEndpointIdentity(baseURL)
        var profile = customOpenAIEndpointProfiles[identity] ?? CustomOpenAIEndpointProfile()
        profile.textModelSelectionMode = openAITextModelSelectionMode
        profile.automaticTextModelID = automaticOpenAITextModel
        profile.fixedTextModelID = fixedOpenAITextModel
        customOpenAIEndpointProfiles[identity] = profile
    }

    mutating func restoreCustomOpenAICloudTextProfile() {
        guard isCustomOpenAICloudTextService,
              let baseURL = effectiveCloudTextBaseURL else {
            return
        }

        let profile = customOpenAIEndpointProfiles[customEndpointIdentity(baseURL)]
            ?? CustomOpenAIEndpointProfile()
        openAITextModelSelectionMode = profile.textModelSelectionMode
        automaticOpenAITextModel = profile.automaticTextModelID
        fixedOpenAITextModel = profile.fixedTextModelID
        saveCurrentCustomOpenAICloudTextProfile()
    }

    mutating func markCurrentCustomOpenAICloudTextModelVerified() {
        guard isCustomOpenAICloudTextService,
              let baseURL = effectiveCloudTextBaseURL else {
            return
        }

        let identity = customEndpointIdentity(baseURL)
        var profile = customOpenAIEndpointProfiles[identity] ?? CustomOpenAIEndpointProfile()
        profile.textModelSelectionMode = openAITextModelSelectionMode
        profile.automaticTextModelID = automaticOpenAITextModel
        profile.fixedTextModelID = fixedOpenAITextModel
        profile.verifiedTextModelID = effectiveCloudTextModel
        customOpenAIEndpointProfiles[identity] = profile
    }

    var cloudTextExecutionSettings: AppSettings {
        var executionSettings = self
        guard let connection = resolvedCloudTextConnection else {
            return executionSettings
        }

        executionSettings.provider = connection.backendProvider
        if connection.backendProvider == .gemini {
            executionSettings.selectedModel = connection.modelSelection.modelID
                ?? GeminiTranscriptionService.defaultModelID
        } else if connection.isOpenAICompatible {
            executionSettings.openAIBaseURL = connection.endpoint
        }
        return executionSettings
    }

    private func customEndpointIdentity(_ baseURL: String) -> String {
        OpenAICompatibleRequestBuilder.connectionIdentity(baseURLString: baseURL)
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
        if !GeminiTranscriptionService.modelIDs.contains(cloudTextGeminiModel) {
            cloudTextGeminiModel = GeminiTranscriptionService.defaultModelID
        }
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
        guard let connection = settings.resolvedCloudTextConnection else {
            return false
        }

        // A user-entered endpoint must first prove that its selected text
        // model accepts Shuo's request contract. Built-in providers are
        // deliberately not subject to this gate.
        guard connection.verification.permitsRealRequests else {
            return false
        }

        // This persisted field predates Gemini, but `.disabled` is the
        // provider-neutral, explicit opt-out for every optional cloud text
        // feature. Gemini still uses its own credential and selected model;
        // this switch only controls whether optional text is sent at all.
        return connection.modelSelection.isEnabled
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
