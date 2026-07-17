import Foundation

extension AppSettings {
    enum CodingKeys: String, CodingKey {
        case hasCompletedOnboarding
        case appLanguage
        case showDockIcon
        case provider
        case selectedModel
        case openAITranscriptionModelSelectionMode
        case automaticOpenAITranscriptionModel
        case openAITextModelSelectionMode
        case automaticOpenAITextModel
        case fixedOpenAITextModel
        case customModelName
        case languageHint
        case selectedTranscriptionLanguages
        case chineseScriptPreference
        case openAIBaseURL
        case openAIOrganizationID
        case openAIProjectID
        case localWhisperExecutablePath
        case localWhisperModelDirectoryPath
        case localWhisperModelPath
        case localWhisperPerformanceMode
        case audioInputDeviceID
        case sendContextPrompt
        case pushToTalkEnabled
        case pushToTalkShortcut
        case customPushToTalkShortcut
        case recordingStartSoundEnabled
        case recordingStartSound
        case rightOptionPushToTalkEnabled
        case voiceActivityGateEnabled
        case whisperModeEnabled
        case minimumRecordingDuration
        case minimumSpeechDuration
        case silenceThresholdDBFS
        case restoreClipboardAfterPaste
        case voiceEditCommandsEnabled
        case voiceEditCommandMode
        case voiceEditLLMModel
        case promptContextItems
        case transcriptRetouchEnabled
        case transcriptRetouchLLMModel
        case adaptiveRecognitionEnabled
        case adaptiveRecognitionMode
        case punctuationOutputMode
        case punctuationPostProcessingMode
        case chineseTextConversionMode
        case emojiPostProcessingEnabled
        case replaceEmojiPhrasesAfterTranscription
        case smartEmojiMatchingAfterTranscription
        case aiEmojiResolverEnabled
        case emojiResolverLLMModel
        case emojiReplacementRules
        case collapseWhitespaceAfterTranscription
        case trimWhitespaceAfterTranscription
        case lowercaseEnglishAfterTranscription
        case insertSpaceBetweenChineseAndEnglish
        case appendNewlineAfterTranscription
        case appendSpaceAfterTranscription
        case automaticUpdateChecksEnabled
        case automaticUpdatesEnabled
        case useDeveloperGlossary
        case developerGlossary
        case namedVocabularies
        case deletedTerminologyPresetIDs
        case enabledTerminologyPresetIDs
        case useCustomCorrections
        case customCorrections
        case contextPrompt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let persistedLanguages = TranscriptionLanguageSelectionPolicy.normalized(
            selectedTranscriptionLanguages,
            provider: provider,
            localCapability: localWhisperLanguageCapability
        )
        try container.encode(hasCompletedOnboarding, forKey: .hasCompletedOnboarding)
        try container.encode(appLanguage, forKey: .appLanguage)
        try container.encode(showDockIcon, forKey: .showDockIcon)
        try container.encode(provider, forKey: .provider)
        try container.encode(selectedModel, forKey: .selectedModel)
        try container.encode(
            openAITranscriptionModelSelectionMode,
            forKey: .openAITranscriptionModelSelectionMode
        )
        try container.encode(
            automaticOpenAITranscriptionModel,
            forKey: .automaticOpenAITranscriptionModel
        )
        try container.encode(openAITextModelSelectionMode, forKey: .openAITextModelSelectionMode)
        try container.encode(automaticOpenAITextModel, forKey: .automaticOpenAITextModel)
        try container.encode(fixedOpenAITextModel, forKey: .fixedOpenAITextModel)
        try container.encode(customModelName, forKey: .customModelName)
        try container.encode(
            LanguageHint(transcriptionLanguages: persistedLanguages),
            forKey: .languageHint
        )
        try container.encode(
            TranscriptionLanguage.allCases.filter(persistedLanguages.contains),
            forKey: .selectedTranscriptionLanguages
        )
        try container.encode(chineseScriptPreference, forKey: .chineseScriptPreference)
        try container.encode(openAIBaseURL, forKey: .openAIBaseURL)
        try container.encode(openAIOrganizationID, forKey: .openAIOrganizationID)
        try container.encode(openAIProjectID, forKey: .openAIProjectID)
        try container.encode(localWhisperExecutablePath, forKey: .localWhisperExecutablePath)
        try container.encode(localWhisperModelDirectoryPath, forKey: .localWhisperModelDirectoryPath)
        try container.encode(localWhisperModelPath, forKey: .localWhisperModelPath)
        try container.encode(localWhisperPerformanceMode, forKey: .localWhisperPerformanceMode)
        try container.encode(audioInputDeviceID, forKey: .audioInputDeviceID)
        try container.encode(sendContextPrompt, forKey: .sendContextPrompt)
        try container.encode(pushToTalkEnabled, forKey: .pushToTalkEnabled)
        try container.encode(pushToTalkShortcut, forKey: .pushToTalkShortcut)
        try container.encodeIfPresent(customPushToTalkShortcut, forKey: .customPushToTalkShortcut)
        try container.encode(recordingStartSoundEnabled, forKey: .recordingStartSoundEnabled)
        try container.encode(recordingStartSound, forKey: .recordingStartSound)
        try container.encode(voiceActivityGateEnabled, forKey: .voiceActivityGateEnabled)
        try container.encode(whisperModeEnabled, forKey: .whisperModeEnabled)
        try container.encode(minimumRecordingDuration, forKey: .minimumRecordingDuration)
        try container.encode(minimumSpeechDuration, forKey: .minimumSpeechDuration)
        try container.encode(silenceThresholdDBFS, forKey: .silenceThresholdDBFS)
        try container.encode(restoreClipboardAfterPaste, forKey: .restoreClipboardAfterPaste)
        try container.encode(voiceEditCommandsEnabled, forKey: .voiceEditCommandsEnabled)
        try container.encode(voiceEditCommandMode, forKey: .voiceEditCommandMode)
        try container.encode(promptContextItems, forKey: .promptContextItems)
        try container.encode(transcriptRetouchEnabled, forKey: .transcriptRetouchEnabled)
        try container.encode(adaptiveRecognitionEnabled, forKey: .adaptiveRecognitionEnabled)
        try container.encode(adaptiveRecognitionMode, forKey: .adaptiveRecognitionMode)
        try container.encode(punctuationPostProcessingMode, forKey: .punctuationOutputMode)
        let legacyCompatiblePunctuationMode: PunctuationPostProcessingMode =
            punctuationPostProcessingMode == .automatic ? .keep : punctuationPostProcessingMode
        try container.encode(
            legacyCompatiblePunctuationMode,
            forKey: .punctuationPostProcessingMode
        )
        try container.encode(chineseTextConversionMode, forKey: .chineseTextConversionMode)
        try container.encode(emojiPostProcessingEnabled, forKey: .emojiPostProcessingEnabled)
        try container.encode(smartEmojiMatchingAfterTranscription, forKey: .smartEmojiMatchingAfterTranscription)
        try container.encode(aiEmojiResolverEnabled, forKey: .aiEmojiResolverEnabled)
        try container.encode(true, forKey: .collapseWhitespaceAfterTranscription)
        try container.encode(true, forKey: .trimWhitespaceAfterTranscription)
        try container.encode(lowercaseEnglishAfterTranscription, forKey: .lowercaseEnglishAfterTranscription)
        try container.encode(insertSpaceBetweenChineseAndEnglish, forKey: .insertSpaceBetweenChineseAndEnglish)
        try container.encode(appendNewlineAfterTranscription, forKey: .appendNewlineAfterTranscription)
        try container.encode(appendSpaceAfterTranscription, forKey: .appendSpaceAfterTranscription)
        try container.encode(automaticUpdateChecksEnabled, forKey: .automaticUpdateChecksEnabled)
        try container.encode(automaticUpdatesEnabled, forKey: .automaticUpdatesEnabled)
        try container.encode(useDeveloperGlossary, forKey: .useDeveloperGlossary)
        try container.encode(developerGlossary, forKey: .developerGlossary)
        try container.encode(namedVocabularies, forKey: .namedVocabularies)
        try container.encode(
            deletedTerminologyPresetIDs.sorted(),
            forKey: .deletedTerminologyPresetIDs
        )
        try container.encode(useCustomCorrections, forKey: .useCustomCorrections)
        try container.encode(customCorrections, forKey: .customCorrections)
        try container.encode(contextPrompt, forKey: .contextPrompt)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()

        // Settings written before onboarding existed belong to an existing user and
        // must not unexpectedly reopen the welcome screen after an upgrade.
        hasCompletedOnboarding = try container.decodeIfPresent(
            Bool.self,
            forKey: .hasCompletedOnboarding
        ) ?? true
        appLanguage = try container.decodeIfPresent(AppLanguage.self, forKey: .appLanguage) ?? defaults.appLanguage
        showDockIcon = try container.decodeIfPresent(Bool.self, forKey: .showDockIcon)
            ?? defaults.showDockIcon
        provider = try container.decodeIfPresent(TranscriptionProvider.self, forKey: .provider) ?? defaults.provider
        selectedModel = try container.decodeIfPresent(String.self, forKey: .selectedModel) ?? defaults.selectedModel
        openAITranscriptionModelSelectionMode = try container.decodeIfPresent(
            OpenAIModelSelectionMode.self,
            forKey: .openAITranscriptionModelSelectionMode
        ) ?? (OpenAIModelCatalog.transcriptionModelIDs.contains(selectedModel) ? .fixed : .automatic)
        automaticOpenAITranscriptionModel = OpenAIModelCatalog.normalizedAutomaticTranscriptionModelID(
            try container.decodeIfPresent(
                String.self,
                forKey: .automaticOpenAITranscriptionModel
            ) ?? defaults.automaticOpenAITranscriptionModel
        )
        let decodedVoiceEditLLMModel = try container.decodeIfPresent(String.self, forKey: .voiceEditLLMModel)
        let decodedTranscriptRetouchLLMModel = try container.decodeIfPresent(
            String.self,
            forKey: .transcriptRetouchLLMModel
        )
        let decodedEmojiResolverLLMModel = try container.decodeIfPresent(
            String.self,
            forKey: .emojiResolverLLMModel
        )
        let legacyTextModels = [
            decodedVoiceEditLLMModel,
            decodedTranscriptRetouchLLMModel,
            decodedEmojiResolverLLMModel
        ].compactMap { $0 }
        let decodedFixedOpenAITextModel = try container.decodeIfPresent(
            String.self,
            forKey: .fixedOpenAITextModel
        )
        let migratedLegacyFixedModel = legacyTextModels
            .map(OpenAIModelCatalog.normalizedTextModelID)
            .first { $0 != OpenAIModelCatalog.defaultTextModelID }
            ?? legacyTextModels.first.map(OpenAIModelCatalog.normalizedTextModelID)
            ?? defaults.fixedOpenAITextModel
        fixedOpenAITextModel = OpenAIModelCatalog.normalizedTextModelID(
            decodedFixedOpenAITextModel ?? migratedLegacyFixedModel
        )
        let hasExplicitLegacyTextModel = legacyTextModels.contains { modelID in
            let normalized = OpenAIModelCatalog.normalizedTextModelID(modelID)
            return normalized != OpenAIModelCatalog.defaultTextModelID
        }
        let hasExplicitFixedTextModel =
            fixedOpenAITextModel != OpenAIModelCatalog.defaultTextModelID
        openAITextModelSelectionMode = try container.decodeIfPresent(
            OpenAITextModelSelectionMode.self,
            forKey: .openAITextModelSelectionMode
        ) ?? (hasExplicitLegacyTextModel || hasExplicitFixedTextModel ? .fixed : .automatic)
        automaticOpenAITextModel = OpenAIModelCatalog.normalizedAutomaticTextModelID(
            try container.decodeIfPresent(String.self, forKey: .automaticOpenAITextModel)
                ?? defaults.automaticOpenAITextModel
        )
        customModelName = try container.decodeIfPresent(String.self, forKey: .customModelName) ?? defaults.customModelName
        let legacyLanguageHint = try container.decodeIfPresent(LanguageHint.self, forKey: .languageHint)
            ?? defaults.languageHint
        let decodedTranscriptionLanguages = try container.decodeIfPresent(
            [TranscriptionLanguage].self,
            forKey: .selectedTranscriptionLanguages
        )
        if let decodedTranscriptionLanguages {
            selectedTranscriptionLanguages = Set(decodedTranscriptionLanguages)
        } else {
            selectedTranscriptionLanguages = legacyLanguageHint.transcriptionLanguages
        }
        if selectedTranscriptionLanguages.isEmpty {
            selectedTranscriptionLanguages = defaults.selectedTranscriptionLanguages
        }
        chineseScriptPreference = try container.decodeIfPresent(ChineseScriptPreference.self, forKey: .chineseScriptPreference) ?? defaults.chineseScriptPreference
        openAIBaseURL = try container.decodeIfPresent(String.self, forKey: .openAIBaseURL) ?? defaults.openAIBaseURL
        openAIOrganizationID = try container.decodeIfPresent(String.self, forKey: .openAIOrganizationID) ?? defaults.openAIOrganizationID
        openAIProjectID = try container.decodeIfPresent(String.self, forKey: .openAIProjectID) ?? defaults.openAIProjectID
        localWhisperExecutablePath = try container.decodeIfPresent(String.self, forKey: .localWhisperExecutablePath) ?? defaults.localWhisperExecutablePath
        localWhisperModelPath = try container.decodeIfPresent(String.self, forKey: .localWhisperModelPath) ?? defaults.localWhisperModelPath
        localWhisperModelDirectoryPath = try container.decodeIfPresent(
            String.self,
            forKey: .localWhisperModelDirectoryPath
        ) ?? Self.modelDirectoryPath(fromModelPath: localWhisperModelPath, fallback: defaults.localWhisperModelDirectoryPath)
        localWhisperPerformanceMode = try container.decodeIfPresent(
            LocalWhisperPerformanceMode.self,
            forKey: .localWhisperPerformanceMode
        ) ?? defaults.localWhisperPerformanceMode
        let decodedAudioInputDeviceID = try container.decodeIfPresent(String.self, forKey: .audioInputDeviceID)
            ?? defaults.audioInputDeviceID
        audioInputDeviceID = AudioInputDeviceCatalog.normalizedSelectionID(decodedAudioInputDeviceID)
        sendContextPrompt = try container.decodeIfPresent(Bool.self, forKey: .sendContextPrompt) ?? defaults.sendContextPrompt
        pushToTalkEnabled = try container.decodeIfPresent(Bool.self, forKey: .pushToTalkEnabled)
            ?? container.decodeIfPresent(Bool.self, forKey: .rightOptionPushToTalkEnabled)
            ?? defaults.pushToTalkEnabled
        pushToTalkShortcut = try container.decodeIfPresent(PushToTalkShortcut.self, forKey: .pushToTalkShortcut) ?? defaults.pushToTalkShortcut
        customPushToTalkShortcut = try container.decodeIfPresent(
            CustomPushToTalkShortcut.self,
            forKey: .customPushToTalkShortcut
        )
        recordingStartSoundEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .recordingStartSoundEnabled
        ) ?? defaults.recordingStartSoundEnabled
        recordingStartSound = try container.decodeIfPresent(
            RecordingCueSound.self,
            forKey: .recordingStartSound
        ) ?? defaults.recordingStartSound
        voiceActivityGateEnabled = try container.decodeIfPresent(Bool.self, forKey: .voiceActivityGateEnabled) ?? defaults.voiceActivityGateEnabled
        whisperModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .whisperModeEnabled) ?? defaults.whisperModeEnabled
        minimumRecordingDuration = try container.decodeIfPresent(Double.self, forKey: .minimumRecordingDuration) ?? defaults.minimumRecordingDuration
        minimumSpeechDuration = try container.decodeIfPresent(Double.self, forKey: .minimumSpeechDuration) ?? defaults.minimumSpeechDuration
        silenceThresholdDBFS = try container.decodeIfPresent(Double.self, forKey: .silenceThresholdDBFS) ?? defaults.silenceThresholdDBFS
        // Clipboard restoration is now unconditional. Decode the legacy key
        // only for file compatibility; a stored false value is intentionally
        // migrated to true.
        _ = try container.decodeIfPresent(Bool.self, forKey: .restoreClipboardAfterPaste)
        restoreClipboardAfterPaste = true
        voiceEditCommandsEnabled = try container.decodeIfPresent(Bool.self, forKey: .voiceEditCommandsEnabled) ?? defaults.voiceEditCommandsEnabled
        voiceEditCommandMode = try container.decodeIfPresent(VoiceEditCommandMode.self, forKey: .voiceEditCommandMode) ?? defaults.voiceEditCommandMode
        transcriptRetouchEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .transcriptRetouchEnabled
        ) ?? defaults.transcriptRetouchEnabled
        adaptiveRecognitionEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .adaptiveRecognitionEnabled
        ) ?? defaults.adaptiveRecognitionEnabled
        adaptiveRecognitionMode = try container.decodeIfPresent(
            AdaptiveRecognitionMode.self,
            forKey: .adaptiveRecognitionMode
        ) ?? defaults.adaptiveRecognitionMode
        contextPrompt = try container.decodeIfPresent(String.self, forKey: .contextPrompt) ?? defaults.contextPrompt
        let decodedPromptContextItems = try container.decodeIfPresent([PromptContextItem].self, forKey: .promptContextItems)
            ?? PromptContextItem.migratedItems(from: contextPrompt)
        let legacyPromptRequestedNoPunctuation = decodedPromptContextItems.contains {
            $0.isEnabled && $0.requestsNoPunctuation
        }
        promptContextItems = PromptContextItem.removingLegacyPostProcessingItems(from: decodedPromptContextItems)
        let decodedPunctuationOutputMode = try container.decodeIfPresent(
            PunctuationPostProcessingMode.self,
            forKey: .punctuationOutputMode
        )
        let decodedLegacyPunctuationMode = try container.decodeIfPresent(
            PunctuationPostProcessingMode.self,
            forKey: .punctuationPostProcessingMode
        )
        if let decodedPunctuationOutputMode {
            punctuationPostProcessingMode = decodedPunctuationOutputMode
        } else if let decodedLegacyPunctuationMode {
            switch decodedLegacyPunctuationMode {
            case .automatic:
                punctuationPostProcessingMode = .automatic
            case .keep:
                // Fresh installs use the new automatic default, but an
                // existing user's explicit "keep as transcribed" behavior
                // must not change silently during an upgrade.
                punctuationPostProcessingMode = .keep
            case .replaceWithSpaces:
                punctuationPostProcessingMode = decodedLegacyPunctuationMode
            }
        } else if legacyPromptRequestedNoPunctuation {
            punctuationPostProcessingMode = .replaceWithSpaces
        } else {
            punctuationPostProcessingMode = defaults.punctuationPostProcessingMode
        }
        chineseTextConversionMode = try container.decodeIfPresent(
            ChineseTextConversionMode.self,
            forKey: .chineseTextConversionMode
        ) ?? defaults.chineseTextConversionMode
        emojiPostProcessingEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .emojiPostProcessingEnabled
        ) ?? defaults.emojiPostProcessingEnabled
        // The retired fixed-rule mode was enabled by default. Move those
        // installs to the remaining on-device matcher so Emoji replacement
        // does not silently become a no-op after the UI is simplified.
        let legacyFixedEmojiRulesEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .replaceEmojiPhrasesAfterTranscription
        ) ?? false
        smartEmojiMatchingAfterTranscription = try container.decodeIfPresent(
            Bool.self,
            forKey: .smartEmojiMatchingAfterTranscription
        ) ?? defaults.smartEmojiMatchingAfterTranscription
        if emojiPostProcessingEnabled, legacyFixedEmojiRulesEnabled {
            smartEmojiMatchingAfterTranscription = true
        }
        aiEmojiResolverEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .aiEmojiResolverEnabled
        ) ?? defaults.aiEmojiResolverEnabled
        _ = try container.decodeIfPresent(
            String.self,
            forKey: .emojiReplacementRules
        )
        collapseWhitespaceAfterTranscription = true
        trimWhitespaceAfterTranscription = true
        lowercaseEnglishAfterTranscription = try container.decodeIfPresent(
            Bool.self,
            forKey: .lowercaseEnglishAfterTranscription
        ) ?? defaults.lowercaseEnglishAfterTranscription
        insertSpaceBetweenChineseAndEnglish = try container.decodeIfPresent(
            Bool.self,
            forKey: .insertSpaceBetweenChineseAndEnglish
        ) ?? defaults.insertSpaceBetweenChineseAndEnglish
        appendNewlineAfterTranscription = try container.decodeIfPresent(
            Bool.self,
            forKey: .appendNewlineAfterTranscription
        ) ?? defaults.appendNewlineAfterTranscription
        // Before this setting was exposed, disabling automatic newlines still
        // applied a smart trailing space. Preserve that behavior for every
        // existing settings document that does not contain the new key.
        appendSpaceAfterTranscription = try container.decodeIfPresent(
            Bool.self,
            forKey: .appendSpaceAfterTranscription
        ) ?? true
        automaticUpdateChecksEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .automaticUpdateChecksEnabled
        ) ?? defaults.automaticUpdateChecksEnabled
        automaticUpdatesEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .automaticUpdatesEnabled
        ) ?? defaults.automaticUpdatesEnabled
        useDeveloperGlossary = try container.decodeIfPresent(Bool.self, forKey: .useDeveloperGlossary) ?? defaults.useDeveloperGlossary
        let decodedLegacyGlossary = try container.decodeIfPresent(
            String.self,
            forKey: .developerGlossary
        ) ?? defaults.developerGlossary
        var decodedNamedVocabularies = try container.decodeIfPresent(
            [NamedVocabularyItem].self,
            forKey: .namedVocabularies
        ) ?? []
        let decodedDeletedPresetIDs = try container.decodeIfPresent(
            Set<String>.self,
            forKey: .deletedTerminologyPresetIDs
        ) ?? []
        let decodedLegacyEnabledPresetIDs = try container.decodeIfPresent(
            Set<String>.self,
            forKey: .enabledTerminologyPresetIDs
        ) ?? []

        let legacyTerms = decodedLegacyGlossary.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if !legacyTerms.isEmpty {
            let importedID = NamedVocabularyItem.importedLegacyGlossaryID
            if let index = decodedNamedVocabularies.firstIndex(where: { $0.id == importedID }) {
                if decodedNamedVocabularies[index].terms
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    decodedNamedVocabularies[index].terms = legacyTerms
                }
            } else {
                decodedNamedVocabularies.insert(
                    NamedVocabularyItem(
                        id: importedID,
                        name: NamedVocabularyItem.importedLegacyGlossaryName,
                        terms: legacyTerms,
                        isEnabled: true
                    ),
                    at: 0
                )
            }
        }
        developerGlossary = ""
        deletedTerminologyPresetIDs = decodedDeletedPresetIDs
        namedVocabularies = TerminologyPresetCatalog.mergedItems(
            existing: decodedNamedVocabularies,
            deletedPresetIDs: decodedDeletedPresetIDs,
            legacyEnabledPresetIDs: decodedLegacyEnabledPresetIDs
        )
        useCustomCorrections = try container.decodeIfPresent(Bool.self, forKey: .useCustomCorrections) ?? defaults.useCustomCorrections
        customCorrections = try container.decodeIfPresent(String.self, forKey: .customCorrections) ?? defaults.customCorrections

        // A persisted multi-language selection cannot survive choosing an
        // English-only local model. This is intentionally narrower than full
        // settings normalization so decoding never scans or mutates model files.
        normalizeLanguageSelection()
    }

    private static func modelDirectoryPath(fromModelPath modelPath: String, fallback: String) -> String {
        let trimmedPath = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return fallback
        }

        return URL(fileURLWithPath: trimmedPath).deletingLastPathComponent().standardizedFileURL.path
    }
}
