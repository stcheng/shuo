import AVFoundation
import ApplicationServices
import CoreAudio
import XCTest
@testable import Shuo

final class AppSettingsTests: XCTestCase {
    func testLegacyAutomaticVoiceEditModeMigratesToLocal() throws {
        let settings = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(#"{"voiceEditCommandMode":"automatic"}"#.utf8)
        )

        XCTAssertEqual(settings.voiceEditCommandMode, .localOnly)
    }

    func testFreshSettingsRequireOnboarding() {
        XCTAssertFalse(AppSettings().hasCompletedOnboarding)
    }

    func testFreshSettingsFollowTheSystemLanguage() {
        XCTAssertEqual(AppSettings().appLanguage, .system)
        XCTAssertEqual(
            AppLanguage.resolvedSystemLanguage(
                preferredLanguages: ["zh-Hant-TW", "en-US"]
            ),
            .traditionalChinese
        )
        XCTAssertEqual(
            AppLanguage.resolvedSystemLanguage(
                preferredLanguages: ["zh-CN", "en-US"]
            ),
            .simplifiedChinese
        )
        XCTAssertEqual(
            AppLanguage.resolvedSystemLanguage(
                preferredLanguages: ["fr-FR", "ja-JP"]
            ),
            .japanese
        )
        XCTAssertEqual(
            AppLanguage.resolvedSystemLanguage(preferredLanguages: ["fr-FR"]),
            .english
        )
    }

    func testSystemLanguagePickerNameIsLocalized() {
        XCTAssertEqual(
            AppLocalizer(language: .english).appLanguageName(.system),
            "System"
        )
        XCTAssertEqual(
            AppLocalizer(language: .simplifiedChinese).appLanguageName(.system),
            "跟随系统"
        )
        XCTAssertEqual(
            AppLocalizer(language: .traditionalChinese).appLanguageName(.system),
            "跟隨系統"
        )
        XCTAssertEqual(
            AppLocalizer(language: .japanese).appLanguageName(.system),
            "システム設定"
        )
    }

    func testExistingSettingsWithoutOnboardingFlagDoNotReopenWelcome() throws {
        let data = Data(#"{"appLanguage":"english"}"#.utf8)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertTrue(decoded.hasCompletedOnboarding)
    }

    func testOnboardingStatePersists() throws {
        var settings = AppSettings()
        settings.hasCompletedOnboarding = true

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertTrue(decoded.hasCompletedOnboarding)
    }

    func testDockIconIsHiddenByDefaultAndPersists() throws {
        XCTAssertFalse(AppSettings().showDockIcon)

        var settings = AppSettings()
        settings.showDockIcon = true

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertTrue(decoded.showDockIcon)
    }

    func testCustomCloudBaseURLPersistsForServiceSwitching() throws {
        var settings = AppSettings()
        settings.provider = .openAI
        settings.openAIBaseURL = "https://relay.example.com/v1"
        settings.lastCustomOpenAIBaseURL = settings.openAIBaseURL

        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: JSONEncoder().encode(settings)
        )

        XCTAssertEqual(decoded.lastCustomOpenAIBaseURL, "https://relay.example.com/v1")
    }

    func testLegacyTerminologyPresetIDsMigrateIntoEditableVocabularies() throws {
        let legacyData = Data(
            #"{"appLanguage":"english","enabledTerminologyPresetIDs":["coding","future-specialty"]}"#.utf8
        )
        let migrated = try JSONDecoder().decode(AppSettings.self, from: legacyData)

        XCTAssertEqual(
            migrated.namedVocabularies.first {
                $0.presetID == TerminologyPresetCatalog.codingID
            }?.isEnabled,
            true
        )
        XCTAssertFalse(migrated.namedVocabularies.contains { $0.presetID == "future-specialty" })

        let roundTripped = try JSONDecoder().decode(
            AppSettings.self,
            from: JSONEncoder().encode(migrated)
        )
        XCTAssertEqual(roundTripped.namedVocabularies, migrated.namedVocabularies)
    }

    func testOnboardingRequiresPermissionsAndAConfiguredProvider() {
        let ready = OnboardingReadiness.evaluate(
            provider: .openAI,
            openAIAPIKey: "sk-test",
            elevenLabsAPIKey: "",
            localModelIsReady: false,
            microphonePermissionGranted: true,
            accessibilityPermissionGranted: true
        )
        XCTAssertTrue(ready.canStart)

        let missingKey = OnboardingReadiness.evaluate(
            provider: .openAI,
            openAIAPIKey: "  ",
            elevenLabsAPIKey: "",
            localModelIsReady: true,
            microphonePermissionGranted: true,
            accessibilityPermissionGranted: true
        )
        XCTAssertFalse(missingKey.providerIsReady)
        XCTAssertFalse(missingKey.canStart)

        let missingPermission = OnboardingReadiness.evaluate(
            provider: .local,
            openAIAPIKey: "",
            elevenLabsAPIKey: "",
            localModelIsReady: true,
            microphonePermissionGranted: true,
            accessibilityPermissionGranted: false
        )
        XCTAssertTrue(missingPermission.providerIsReady)
        XCTAssertFalse(missingPermission.permissionsAreReady)
        XCTAssertFalse(missingPermission.canStart)

        let missingMicrophone = OnboardingReadiness.evaluate(
            provider: .local,
            openAIAPIKey: "",
            elevenLabsAPIKey: "",
            localModelIsReady: true,
            microphonePermissionGranted: false,
            accessibilityPermissionGranted: true
        )
        XCTAssertFalse(missingMicrophone.permissionsAreReady)
        XCTAssertFalse(missingMicrophone.canStart)
    }

    func testOnboardingRejectsAnUnsupportedCustomProvider() {
        let readiness = OnboardingReadiness.evaluate(
            provider: .custom,
            openAIAPIKey: "sk-test",
            elevenLabsAPIKey: "xi-test",
            localModelIsReady: true,
            microphonePermissionGranted: true,
            accessibilityPermissionGranted: true
        )

        XCTAssertFalse(readiness.providerIsReady)
        XCTAssertFalse(readiness.canStart)
    }

    func testOnboardingRequiresAlibabaKeyAndProviderGuidesUseHTTPS() {
        let missingKey = OnboardingReadiness.evaluate(
            provider: .alibaba,
            openAIAPIKey: "sk-other",
            elevenLabsAPIKey: "xi-other",
            localModelIsReady: true,
            microphonePermissionGranted: true,
            accessibilityPermissionGranted: true,
            alibabaAPIKey: " "
        )
        let ready = OnboardingReadiness.evaluate(
            provider: .alibaba,
            openAIAPIKey: "",
            elevenLabsAPIKey: "",
            localModelIsReady: false,
            microphonePermissionGranted: true,
            accessibilityPermissionGranted: true,
            alibabaAPIKey: "dashscope-key"
        )

        XCTAssertFalse(missingKey.providerIsReady)
        XCTAssertTrue(ready.canStart)
        for provider in [TranscriptionProvider.openAI, .elevenLabs, .alibaba] {
            XCTAssertEqual(provider.apiKeyGuideURL?.scheme, "https")
        }
        XCTAssertNil(TranscriptionProvider.local.apiKeyGuideURL)
    }

    func testPushToTalkShortcutChoicesPersistAndUseRightSideKeyCodes() throws {
        XCTAssertEqual(PushToTalkShortcut.rightOption.keyCode, 0x3D)
        XCTAssertEqual(PushToTalkShortcut.rightCommand.keyCode, 0x36)
        XCTAssertEqual(PushToTalkShortcut.pickerCases, [.rightCommand, .rightOption, .custom])

        var settings = AppSettings()
        let customShortcut = CustomPushToTalkShortcut(keyCode: 0x31, modifiers: [.control])
        settings.pushToTalkShortcut = .custom
        settings.customPushToTalkShortcut = customShortcut
        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: JSONEncoder().encode(settings)
        )

        XCTAssertEqual(decoded.pushToTalkShortcut, .custom)
        XCTAssertEqual(decoded.customPushToTalkShortcut, customShortcut)
    }

    func testCustomPushToTalkShortcutValidationAvoidsBareTextKeys() {
        XCTAssertFalse(CustomPushToTalkShortcut(keyCode: 0x00).isValidHoldShortcut)
        XCTAssertFalse(CustomPushToTalkShortcut(keyCode: 0x31).isValidHoldShortcut)

        XCTAssertTrue(CustomPushToTalkShortcut(keyCode: 0x00, modifiers: [.control]).isValidHoldShortcut)
        XCTAssertTrue(CustomPushToTalkShortcut(keyCode: 0x31, modifiers: [.control]).isValidHoldShortcut)
        XCTAssertTrue(CustomPushToTalkShortcut(keyCode: 0x69).isValidHoldShortcut)
        XCTAssertTrue(CustomPushToTalkShortcut(keyCode: 0x3E).isValidHoldShortcut)
        XCTAssertFalse(CustomPushToTalkShortcut(keyCode: 0x32).isValidHoldShortcut)
        XCTAssertEqual(
            CustomPushToTalkShortcut(keyCode: 0x32, modifiers: [.command]).displayName,
            "Command + `"
        )
    }

    func testCustomPushToTalkShortcutNameUsesRecordedShortcut() {
        let localizer = AppLocalizer(language: .english)
        let customShortcut = CustomPushToTalkShortcut(keyCode: 0x31, modifiers: [.control])

        XCTAssertEqual(
            localizer.shortcutName(.custom, customShortcut: customShortcut),
            "Control + Space"
        )
        XCTAssertEqual(localizer.shortcutName(.custom), "Custom")
    }

    func testModifierShortcutStateFallsBackToEventFlags() {
        let rightCommand = ResolvedPushToTalkShortcut(
            keyCode: PushToTalkShortcut.rightCommand.keyCode
        )

        XCTAssertTrue(
            rightCommand.downState(
                keyStateDown: false,
                eventFlags: .maskCommand,
                previousDown: false
            )
        )
        XCTAssertFalse(
            rightCommand.downState(
                keyStateDown: false,
                eventFlags: [],
                previousDown: true
            )
        )
    }

    func testModifierComboShortcutStateRequiresBothKeyAndModifiers() {
        let rightOptionWithControl = ResolvedPushToTalkShortcut(
            keyCode: PushToTalkShortcut.rightOption.keyCode,
            modifiers: [.control]
        )

        XCTAssertTrue(
            rightOptionWithControl.downState(
                keyStateDown: false,
                eventFlags: [.maskAlternate, .maskControl],
                previousDown: false
            )
        )
        XCTAssertFalse(
            rightOptionWithControl.downState(
                keyStateDown: true,
                eventFlags: .maskAlternate,
                previousDown: false
            )
        )
    }

    func testFreshLanguageSelectionPrioritizesChineseAndEnglish() {
        let settings = AppSettings()

        XCTAssertEqual(
            settings.selectedTranscriptionLanguages,
            Set([.chinese, .english])
        )
        XCTAssertFalse(settings.selectedTranscriptionLanguages.contains(.japanese))
    }

    func testTranscriptionLanguageCatalogIncludesSpanishAndFrench() {
        XCTAssertEqual(
            TranscriptionLanguage.allCases,
            [.chinese, .english, .spanish, .french, .japanese]
        )
    }

    func testProviderLanguageCodesCoverSpanishAndFrench() {
        XCTAssertEqual(LanguageHint.spanish.localWhisperLanguageCode, "es")
        XCTAssertEqual(LanguageHint.spanish.openAILanguageCode, "es")
        XCTAssertEqual(LanguageHint.spanish.elevenLabsLanguageCode, "spa")
        XCTAssertEqual(LanguageHint.french.localWhisperLanguageCode, "fr")
        XCTAssertEqual(LanguageHint.french.openAILanguageCode, "fr")
        XCTAssertEqual(LanguageHint.french.elevenLabsLanguageCode, "fra")
        XCTAssertEqual(LanguageHint.mixed.localWhisperLanguageCode, "auto")
        XCTAssertNil(LanguageHint.mixed.openAILanguageCode)
        XCTAssertNil(LanguageHint.mixed.elevenLabsLanguageCode)
    }

    func testChineseScriptResolutionPrefersActiveModeThenLegacyPreference() {
        var settings = AppSettings()
        settings.appLanguage = .traditionalChinese

        XCTAssertEqual(settings.resolvedChineseTextConversionMode, .traditional)

        settings.chineseScriptPreference = .simplified
        XCTAssertEqual(settings.resolvedChineseTextConversionMode, .simplified)

        settings.chineseTextConversionMode = .traditional
        XCTAssertEqual(settings.resolvedChineseTextConversionMode, .traditional)
    }

    func testSettingPreferredChineseScriptSynchronizesPersistedFields() {
        var settings = AppSettings()

        settings.setPreferredChineseTextConversionMode(.traditional)

        XCTAssertEqual(settings.chineseTextConversionMode, .traditional)
        XCTAssertEqual(settings.chineseScriptPreference, .traditional)

        settings.setPreferredChineseTextConversionMode(.keep)
        XCTAssertEqual(settings.chineseTextConversionMode, .traditional)
        XCTAssertEqual(settings.chineseScriptPreference, .traditional)
    }

    func testResetOpenAIConnectionDetailsRestoresOfficialDefaults() {
        var settings = AppSettings()
        settings.openAIBaseURL = "https://example.com/v1"
        settings.openAIOrganizationID = "org-test"
        settings.openAIProjectID = "project-test"

        settings.resetOpenAIConnectionDetails()

        XCTAssertEqual(settings.openAIBaseURL, AppSettings.defaultOpenAIBaseURL)
        XCTAssertEqual(settings.openAIOrganizationID, "")
        XCTAssertEqual(settings.openAIProjectID, "")
    }

    func testErrorSummaryCompactsAndTruncatesLongMessages() {
        let message = """
        OpenAI transcription failed (400):
        {
          "error": {
            "message": "This is a long provider response that should not take over the menu bar popover."
          }
        }
        """

        let summary = AppState.summarizedErrorMessage(message, maxLength: 80)

        XCTAssertLessThanOrEqual(summary.count, 80)
        XCTAssertFalse(summary.contains("\n"))
        XCTAssertTrue(summary.hasSuffix("..."))
    }

    func testOpenAISelectionNormalizesAwayFromCustomModel() {
        var settings = AppSettings()
        settings.provider = .openAI
        settings.selectedModel = "custom"
        settings.customModelName = "not-used"

        settings.normalizeSelections()

        XCTAssertEqual(settings.selectedModel, "gpt-4o-transcribe")
        XCTAssertEqual(settings.effectiveModel, "gpt-4o-transcribe")
    }

    func testWhisperModeIsOptInAndDoesNotOverwriteManualThreshold() {
        var settings = AppSettings()
        settings.silenceThresholdDBFS = -42

        XCTAssertFalse(settings.whisperModeEnabled)

        settings.whisperModeEnabled = true

        XCTAssertTrue(settings.whisperModeEnabled)
        XCTAssertEqual(settings.silenceThresholdDBFS, -42)
    }

    func testWhisperModePersistsInSettingsCodable() throws {
        var settings = AppSettings()
        settings.whisperModeEnabled = true

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertTrue(decoded.whisperModeEnabled)
    }

    func testAdaptiveRecognitionPersistsInSettingsCodable() throws {
        var settings = AppSettings()
        settings.adaptiveRecognitionEnabled = true

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertTrue(decoded.adaptiveRecognitionEnabled)
    }

    func testTranscriptionLanguageSelectionRoundTripsWithoutLosingSubset() throws {
        var settings = AppSettings()
        settings.selectedTranscriptionLanguages = [.chinese, .english]

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.selectedTranscriptionLanguages, [.chinese, .english])
        XCTAssertEqual(decoded.languageHint, .mixed)
    }

    func testSpanishAndFrenchLanguageSelectionRoundTripsWithoutLosingSubset() throws {
        var settings = AppSettings()
        settings.provider = .openAI
        settings.selectedTranscriptionLanguages = [.spanish, .french]

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.selectedTranscriptionLanguages, [.spanish, .french])
        XCTAssertEqual(decoded.languageHint, .mixed)
    }

    func testEnglishOnlySelectionPolicyAlwaysReturnsEnglish() {
        let selection = TranscriptionLanguageSelectionPolicy.normalized(
            [.chinese, .spanish, .french],
            provider: .local,
            localCapability: .englishOnly
        )

        XCTAssertEqual(selection, [.english])
    }

    func testEnglishOnlyLocalModelCannotPersistMultipleLanguages() throws {
        var settings = AppSettings()
        settings.provider = .local
        settings.localWhisperModelPath = "/tmp/ggml-base.en.bin"
        settings.selectedTranscriptionLanguages = [.chinese, .english, .spanish]

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.selectedTranscriptionLanguages, [.english])
        XCTAssertEqual(decoded.languageHint, .english)
    }

    func testLegacyLanguageHintMigratesToLanguageSelection() throws {
        let data = Data(#"{"languageHint":"english"}"#.utf8)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.selectedTranscriptionLanguages, [.english])
        XCTAssertEqual(decoded.languageHint, .english)
    }

    func testTranscriptionLanguageSelectionAlwaysKeepsOneLanguage() {
        var settings = AppSettings()
        settings.selectedTranscriptionLanguages = [.japanese]

        settings.setTranscriptionLanguage(.japanese, isEnabled: false)

        XCTAssertEqual(settings.selectedTranscriptionLanguages, [.japanese])
    }

    func testClipboardRestorationCannotBeDisabledByLegacySettings() throws {
        let data = Data(#"{"restoreClipboardAfterPaste":false}"#.utf8)

        var decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertTrue(decoded.restoreClipboardAfterPaste)

        decoded.restoreClipboardAfterPaste = false
        decoded.normalizeSelections()
        XCTAssertTrue(decoded.restoreClipboardAfterPaste)
    }

    func testWhitespaceCleanupCannotBeDisabledByLegacySettings() throws {
        let data = Data(
            #"{"collapseWhitespaceAfterTranscription":false,"trimWhitespaceAfterTranscription":false}"#.utf8
        )

        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertTrue(decoded.collapseWhitespaceAfterTranscription)
        XCTAssertTrue(decoded.trimWhitespaceAfterTranscription)
    }

    func testSmartTrailingSpaceIsEnabledForFreshAndLegacySettings() throws {
        XCTAssertTrue(AppSettings().appendSpaceAfterTranscription)
        XCTAssertEqual(AppSettings().transcriptInsertionBoundaryMode, .smartSpace)

        let legacyData = Data(#"{"appendNewlineAfterTranscription":false}"#.utf8)
        let migrated = try JSONDecoder().decode(AppSettings.self, from: legacyData)

        XCTAssertTrue(migrated.appendSpaceAfterTranscription)
        XCTAssertEqual(migrated.transcriptInsertionBoundaryMode, .smartSpace)
    }

    func testAutomaticPunctuationIsTheFreshDefaultAndMigratesRemovedModeSafely() throws {
        XCTAssertEqual(AppSettings().punctuationPostProcessingMode, .automatic)
        XCTAssertEqual(
            PunctuationPostProcessingMode.allCases.map(\.rawValue),
            ["automatic", "keep", "replaceWithSpaces"]
        )

        let legacyKeep = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(#"{"punctuationPostProcessingMode":"keep"}"#.utf8)
        )
        let legacyRemove = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(#"{"punctuationPostProcessingMode":"remove"}"#.utf8)
        )

        XCTAssertEqual(legacyKeep.punctuationPostProcessingMode, .keep)
        XCTAssertEqual(legacyRemove.punctuationPostProcessingMode, .keep)
    }

    func testNewPunctuationOutputModePreservesExplicitKeep() throws {
        var settings = AppSettings()
        settings.punctuationPostProcessingMode = .keep

        let data = try JSONEncoder().encode(settings)
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(payload["punctuationOutputMode"] as? String, "keep")
        XCTAssertEqual(payload["punctuationPostProcessingMode"] as? String, "keep")
        XCTAssertEqual(decoded.punctuationPostProcessingMode, .keep)
    }

    func testAutomaticPunctuationWritesLegacyCompatibleKeep() throws {
        let data = try JSONEncoder().encode(AppSettings())
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(payload["punctuationOutputMode"] as? String, "automatic")
        XCTAssertEqual(payload["punctuationPostProcessingMode"] as? String, "keep")
    }

    func testTrailingSpaceCanBeDisabledAndNewlineTakesPriority() throws {
        var settings = AppSettings()
        settings.appendSpaceAfterTranscription = false

        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: JSONEncoder().encode(settings)
        )
        XCTAssertFalse(decoded.appendSpaceAfterTranscription)
        XCTAssertEqual(decoded.transcriptInsertionBoundaryMode, .none)

        settings.appendSpaceAfterTranscription = true
        settings.appendNewlineAfterTranscription = true
        XCTAssertEqual(settings.transcriptInsertionBoundaryMode, .newline)
    }

    func testInsertionBoundarySetterKeepsLegacyFlagsMutuallyExclusive() {
        var settings = AppSettings()

        settings.setTranscriptInsertionBoundaryMode(.newline)
        XCTAssertTrue(settings.appendNewlineAfterTranscription)
        XCTAssertFalse(settings.appendSpaceAfterTranscription)

        settings.setTranscriptInsertionBoundaryMode(.smartSpace)
        XCTAssertFalse(settings.appendNewlineAfterTranscription)
        XCTAssertTrue(settings.appendSpaceAfterTranscription)

        settings.setTranscriptInsertionBoundaryMode(.none)
        XCTAssertFalse(settings.appendNewlineAfterTranscription)
        XCTAssertFalse(settings.appendSpaceAfterTranscription)
    }

    func testUpdatePreferencesPersistInSettingsCodable() throws {
        var settings = AppSettings()
        settings.automaticUpdateChecksEnabled = false
        settings.automaticUpdatesEnabled = true

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertFalse(decoded.automaticUpdateChecksEnabled)
        XCTAssertTrue(decoded.automaticUpdatesEnabled)
    }

    func testDisablingUpdateChecksDisablesAutomaticUpdates() {
        var settings = AppSettings()
        settings.automaticUpdateChecksEnabled = false
        settings.automaticUpdatesEnabled = true

        settings.normalizeSelections()

        XCTAssertFalse(settings.automaticUpdateChecksEnabled)
        XCTAssertFalse(settings.automaticUpdatesEnabled)
    }

    func testAudioInputDevicePersistsInSettingsCodable() throws {
        var settings = AppSettings()
        settings.audioInputDeviceID = "headset-mic-id"

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.audioInputDeviceID, "headset-mic-id")
    }

    func testAudioInputDeviceDefaultsToSystemDefault() {
        XCTAssertEqual(AppSettings().audioInputDeviceID, AudioInputDeviceCatalog.systemDefaultDeviceID)
    }

    func testAudioRouteExposesResolvedOutputDeviceID() {
        let route = AudioRoute(
            inputDevice: AudioInputDeviceOption(id: "airpods-input", name: "AirPods Microphone"),
            outputDevice: AudioOutputDeviceOption(
                id: "airpods-output",
                name: "AirPods",
                audioObjectID: AudioDeviceID(42)
            ),
            resolvedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(route.outputDeviceID, "airpods-output")
    }

    func testAudioRouteAllowsSystemDefaultOutputFallback() {
        let route = AudioRoute(
            inputDevice: AudioInputDeviceOption(id: "built-in-input", name: "MacBook Pro Microphone"),
            outputDevice: nil,
            resolvedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertNil(route.outputDeviceID)
    }

    func testRecordingStartSoundPersistsInSettingsCodable() throws {
        var settings = AppSettings()
        settings.recordingStartSoundEnabled = false
        settings.recordingStartSound = .brightChime

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertFalse(decoded.recordingStartSoundEnabled)
        XCTAssertEqual(decoded.recordingStartSound, .brightChime)
    }

    func testLegacyEmptyAudioInputDeviceMigratesToSystemDefault() throws {
        let json = #"{"audioInputDeviceID":""}"#.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(decoded.audioInputDeviceID, AudioInputDeviceCatalog.systemDefaultDeviceID)
    }

    func testLegacyAutomaticAudioInputMigratesToSystemDefault() throws {
        let json = #"{"audioInputDeviceID":"__automatic__"}"#.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(decoded.audioInputDeviceID, AudioInputDeviceCatalog.systemDefaultDeviceID)
    }

    func testAudioInputSelectionNormalizationKeepsExplicitDevice() {
        XCTAssertEqual(
            AudioInputDeviceCatalog.normalizedSelectionID("headset-mic-id"),
            "headset-mic-id"
        )
        XCTAssertEqual(
            AudioInputDeviceCatalog.normalizedSelectionID(AudioInputDeviceCatalog.automaticDeviceID),
            AudioInputDeviceCatalog.systemDefaultDeviceID
        )
    }

    func testLegacyTranscriptItemWithoutAudioFileNameDecodes() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "text": "hello",
          "createdAt": 0,
          "provider": "local",
          "model": "local.medium",
          "languageHint": "english"
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(TranscriptItem.self, from: json)

        XCTAssertEqual(item.schemaVersion, 1)
        XCTAssertEqual(item.text, "hello")
        XCTAssertEqual(item.rawText, "hello")
        XCTAssertEqual(item.locallyProcessedText, "hello")
        XCTAssertNil(item.initialText)
        XCTAssertEqual(item.outcome, .succeeded)
        XCTAssertEqual(item.appVersion, "unknown")
        XCTAssertNil(item.audioFileName)
    }

    func testRichTranscriptItemRoundTripsRawFinalAndAttemptMetadata() throws {
        let item = TranscriptItem(
            text: "final text",
            rawText: "raw text",
            locallyProcessedText: "local text",
            initialText: "initial output",
            provider: .openAI,
            model: "gpt-4o-transcribe",
            languageHint: .english,
            selectedTranscriptionLanguages: [.chinese, .english],
            detectedLanguageCode: "en",
            outcome: .failed,
            errorSummary: "network failed",
            recordingDuration: 2.5,
            transcriptionLatency: 0.8,
            appVersion: "0.1.0",
            buildNumber: "2"
        )

        let decoded = try JSONDecoder().decode(
            TranscriptItem.self,
            from: JSONEncoder().encode(item)
        )

        XCTAssertEqual(decoded, item)
        XCTAssertEqual(decoded.schemaVersion, TranscriptItem.currentSchemaVersion)
    }

    func testTranscriptItemPreservesFirstOutputAcrossMultipleUserCorrections() {
        var item = TranscriptItem(
            text: "first output",
            provider: .local,
            model: "local.medium",
            languageHint: .english
        )

        item.applyUserCorrection("second output")
        item.applyUserCorrection("third output")

        XCTAssertEqual(item.initialText, "first output")
        XCTAssertEqual(item.text, "third output")
    }

    func testTranscriptAudioStoreArchivesAndDeletesRecording() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.wav")
        try Data([0, 1, 2, 3]).write(to: sourceURL)

        let transcriptID = try XCTUnwrap(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let store = TranscriptAudioStore(baseDirectory: directory)
        let fileName = try store.storeRecording(at: sourceURL, for: transcriptID)
        let item = TranscriptItem(
            id: transcriptID,
            text: "hello",
            provider: .local,
            model: "local.medium",
            languageHint: .english,
            audioFileName: fileName
        )
        let storedURL = try XCTUnwrap(store.url(for: item))

        XCTAssertEqual(fileName, "\(transcriptID.uuidString).wav")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))
        XCTAssertTrue(store.audioExists(for: item))

        try store.deleteAudio(for: item)

        XCTAssertFalse(FileManager.default.fileExists(atPath: storedURL.path))
    }

    func testEnglishOnlyLocalWhisperModelRestrictsLanguageHints() {
        var settings = AppSettings()
        settings.provider = .local
        settings.localWhisperModelPath = "/tmp/models/ggml-base.en.bin"
        settings.languageHint = .mixed

        settings.normalizeLanguageSelection()

        XCTAssertEqual(settings.availableLanguageHints, [.english])
        XCTAssertEqual(settings.languageHint, .english)
    }

    func testLocalWhisperCatalogFindsSupportedVisibleLocalModelFilesInStableOrder() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data().write(to: directory.appendingPathComponent("ggml-small.bin"))
        try Data().write(to: directory.appendingPathComponent("ggml-base.en.bin"))
        try Data().write(to: directory.appendingPathComponent("sensevoice-small-q8.gguf"))
        try makeSparseFile(
            at: LocalWhisperModelCatalog.senseVoiceVADAsset.destinationURL(in: directory.path),
            byteCount: LocalWhisperModelCatalog.senseVoiceVADAsset.expectedByteCount
        )
        try Data().write(to: directory.appendingPathComponent("unrelated-model.gguf"))
        try Data().write(to: directory.appendingPathComponent("notes.txt"))
        try Data().write(to: directory.appendingPathComponent(".hidden.bin"))

        let names = LocalWhisperModelCatalog.modelURLs(in: directory.path)
            .map(\.lastPathComponent)

        XCTAssertEqual(
            names,
            ["ggml-base.en.bin", "ggml-small.bin", "sensevoice-small-q8.gguf"]
        )
    }

    func testManagedLocalModelsUsePinnedSupportedEngineContracts() {
        let models = LocalWhisperModelCatalog.managedModels

        XCTAssertEqual(models.count, 3)
        XCTAssertTrue(models.contains { $0.tier == .balanced })
        XCTAssertTrue(models.contains { $0.tier == .large })
        XCTAssertEqual(Set(models.map(\.id)).count, models.count)
        XCTAssertEqual(Set(models.map(\.filename)).count, models.count)

        for model in models {
            XCTAssertEqual(model.downloadURL.host(), "huggingface.co")
            XCTAssertTrue(model.downloadURL.path().hasSuffix(model.filename))
            XCTAssertGreaterThan(model.expectedByteCount, 1_000_000)
            XCTAssertEqual(model.expectedSHA256.count, 64)

            switch model.engine {
            case .whisper:
                XCTAssertTrue(model.filename.hasPrefix("ggml-"))
                XCTAssertEqual(URL(fileURLWithPath: model.filename).pathExtension, "bin")
                XCTAssertTrue(
                    model.downloadURL.path().contains("/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/")
                )
            case .senseVoice:
                XCTAssertEqual(model.filename, "sensevoice-small-q8.gguf")
                XCTAssertEqual(URL(fileURLWithPath: model.filename).pathExtension, "gguf")
                XCTAssertTrue(
                    model.downloadURL.path().contains("/resolve/90c1c61912018b70ada0fcc024ea24aca62f2e63/")
                )
                XCTAssertEqual(model.supportingAssets, [LocalWhisperModelCatalog.senseVoiceVADAsset])
            }
        }
    }

    func testOnboardingOffersThreeMultilingualLocalModelSteps() {
        let models = LocalWhisperModelCatalog.onboardingModels

        XCTAssertEqual(
            models.map(\.id),
            ["sensevoice-small-q8", "small", "large-v3-turbo-q5_0"]
        )
        XCTAssertTrue(
            models.map(\.id).contains(LocalWhisperModelCatalog.defaultOnboardingModelID)
        )
        XCTAssertEqual(models.first?.languageCapability, .senseVoice)
        XCTAssertTrue(models.dropFirst().allSatisfy { $0.languageCapability == .multilingual })
    }

    func testLocalModelRecommendationAdaptsToHardwareCapacity() {
        let threshold = LocalWhisperModelCatalog.largeModelRecommendedMemoryBytes

        XCTAssertEqual(
            LocalWhisperModelCatalog.recommendedOnboardingModelID(
                for: [.chinese, .english],
                isAppleSilicon: true,
                physicalMemoryBytes: threshold
            ),
            "sensevoice-small-q8"
        )
        XCTAssertEqual(
            LocalWhisperModelCatalog.recommendedOnboardingModelID(
                for: [.english],
                isAppleSilicon: true,
                physicalMemoryBytes: threshold - 1
            ),
            "small"
        )
        XCTAssertEqual(
            LocalWhisperModelCatalog.recommendedOnboardingModelID(
                for: [.english],
                isAppleSilicon: true,
                physicalMemoryBytes: threshold
            ),
            "large-v3-turbo-q5_0"
        )
        XCTAssertEqual(
            LocalWhisperModelCatalog.recommendedOnboardingModelID(
                for: [.spanish, .french],
                isAppleSilicon: false,
                physicalMemoryBytes: 64 * 1_024 * 1_024 * 1_024
            ),
            "small"
        )
    }

    func testManagedWhisperCatalogIncludesCuratedQualityStepsWithVerifiedMetadata() throws {
        let modelsByID = Dictionary(
            uniqueKeysWithValues: LocalWhisperModelCatalog.managedModels.map { ($0.id, $0) }
        )
        let expectedMetadata: [String: (filename: String, byteCount: Int64, sha256: String)] = [
            "sensevoice-small-q8": (
                "sensevoice-small-q8.gguf",
                254_208_320,
                "4ae45c94422de949b387e2e0fb10d7e14e4c42c69db30c3444ecc7d4b844b7c5"
            ),
            "small": (
                "ggml-small.bin",
                487_601_967,
                "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b"
            ),
            "large-v3-turbo-q5_0": (
                "ggml-large-v3-turbo-q5_0.bin",
                574_041_195,
                "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2"
            )
        ]

        for (id, expected) in expectedMetadata {
            let model = try XCTUnwrap(modelsByID[id])
            XCTAssertEqual(model.filename, expected.filename)
            XCTAssertEqual(model.expectedByteCount, expected.byteCount)
            XCTAssertEqual(model.expectedSHA256, expected.sha256)
        }

        XCTAssertEqual(modelsByID["sensevoice-small-q8"]?.languageCapability, .senseVoice)
        XCTAssertEqual(modelsByID["small"]?.languageCapability, .multilingual)
        XCTAssertEqual(modelsByID["large-v3-turbo-q5_0"]?.languageCapability, .multilingual)
        XCTAssertEqual(Set(modelsByID.keys), Set(expectedMetadata.keys))
        XCTAssertEqual(
            LocalWhisperModelCatalog.senseVoiceVADAsset.expectedByteCount,
            1_720_512
        )
        XCTAssertEqual(
            LocalWhisperModelCatalog.senseVoiceVADAsset.expectedSHA256,
            "1270f2559c495f4e7b6e739541151027d360761a3fda43fc147034f5719f5479"
        )
    }

    func testSelectingSenseVoiceModelRetainsOnlyItsSupportedLanguages() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = try XCTUnwrap(
            LocalWhisperModelCatalog.managedModels.first { $0.id == "sensevoice-small-q8" }
        )
        try makeSparseFile(
            at: model.destinationURL(in: directory.path),
            byteCount: model.expectedByteCount
        )
        for asset in model.supportingAssets {
            try makeSparseFile(
                at: asset.destinationURL(in: directory.path),
                byteCount: asset.expectedByteCount
            )
        }

        var settings = AppSettings()
        settings.provider = .openAI
        settings.localWhisperModelDirectoryPath = directory.path
        settings.selectedTranscriptionLanguages = [.chinese, .english, .spanish, .french]

        let updatedSettings = try XCTUnwrap(
            LocalWhisperSetupService().settingsSelectingInstalledModel(
                model,
                currentSettings: settings
            )
        )

        XCTAssertEqual(updatedSettings.selectedTranscriptionLanguages, [.chinese, .english])
        XCTAssertEqual(updatedSettings.availableTranscriptionLanguages, [.chinese, .english, .japanese])
    }

    func testSenseVoiceLocalSettingsIdentifyUnavailableRecognitionHints() {
        var settings = AppSettings()
        settings.provider = .local
        settings.localWhisperModelPath = "/tmp/sensevoice-small-q8.gguf"

        XCTAssertTrue(settings.usesSenseVoiceLocalTranscription)

        settings.localWhisperModelPath = "/tmp/ggml-large-v3-turbo-q5_0.bin"

        XCTAssertFalse(settings.usesSenseVoiceLocalTranscription)
    }

    func testLocalWhisperExecutableResolverUsesBundledRuntimeWithoutHomebrew() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let executable = directory.appendingPathComponent("whisper-cli")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: executable.path, contents: Data()))
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: executable.path
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let resolved = LocalWhisperExecutableResolver.resolvedExecutableURL(
            configuredPath: "",
            bundledExecutableURL: executable,
            commonPaths: []
        )

        XCTAssertEqual(resolved, executable.standardizedFileURL)
    }

    func testManagedWhisperModelInstallDetectionUsesSelectedDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = try XCTUnwrap(
            LocalWhisperModelCatalog.managedModels.first { $0.id == "small" }
        )
        XCTAssertFalse(LocalWhisperModelCatalog.isInstalled(model, in: directory.path))

        try makeSparseFile(
            at: model.destinationURL(in: directory.path),
            byteCount: model.expectedByteCount
        )

        XCTAssertTrue(LocalWhisperModelCatalog.isInstalled(model, in: directory.path))
    }

    func testSenseVoiceRequiresVADBeforeItIsSelectableOrInstalled() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = try XCTUnwrap(
            LocalWhisperModelCatalog.managedModels.first { $0.id == "sensevoice-small-q8" }
        )
        let modelURL = model.destinationURL(in: directory.path)
        try makeSparseFile(at: modelURL, byteCount: model.expectedByteCount)

        XCTAssertFalse(LocalWhisperModelCatalog.isInstalled(model, in: directory.path))
        XCTAssertFalse(
            LocalWhisperModelCatalog.modelURLs(in: directory.path).contains(modelURL)
        )

        for asset in model.supportingAssets {
            try makeSparseFile(
                at: asset.destinationURL(in: directory.path),
                byteCount: asset.expectedByteCount
            )
        }
        LocalWhisperModelCatalog.invalidateCache(for: directory.path)

        XCTAssertTrue(LocalWhisperModelCatalog.isInstalled(model, in: directory.path))
        XCTAssertTrue(
            LocalWhisperModelCatalog.modelURLs(in: directory.path).contains(modelURL)
        )
    }

    func testDeletingSenseVoiceKeepsSharedVADForAnotherSenseVoiceModel() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = try XCTUnwrap(
            LocalWhisperModelCatalog.managedModels.first { $0.id == "sensevoice-small-q8" }
        )
        let modelURL = model.destinationURL(in: directory.path)
        try makeSparseFile(at: modelURL, byteCount: model.expectedByteCount)
        for asset in model.supportingAssets {
            try makeSparseFile(
                at: asset.destinationURL(in: directory.path),
                byteCount: asset.expectedByteCount
            )
        }
        let alternateModelURL = directory.appendingPathComponent("sensevoice-custom-q8.gguf")
        try Data([0x01]).write(to: alternateModelURL)

        var settings = AppSettings()
        settings.provider = .local
        settings.localWhisperModelDirectoryPath = directory.path
        settings.localWhisperModelPath = modelURL.path

        _ = try LocalWhisperSetupService().deleteModel(model, currentSettings: settings)

        XCTAssertFalse(FileManager.default.fileExists(atPath: modelURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: LocalWhisperModelCatalog.senseVoiceVADURL(in: directory.path).path
            )
        )
    }

    func testLocalWhisperSetupServiceSelectsOnlyAnInstalledManagedModel() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = try XCTUnwrap(
            LocalWhisperModelCatalog.managedModels.first { $0.id == "small" }
        )
        var settings = AppSettings()
        settings.provider = .openAI
        settings.localWhisperModelDirectoryPath = directory.path
        let service = LocalWhisperSetupService()

        XCTAssertNil(service.settingsSelectingInstalledModel(model, currentSettings: settings))

        let modelURL = model.destinationURL(in: directory.path)
        try makeSparseFile(at: modelURL, byteCount: model.expectedByteCount)
        let updatedSettings = try XCTUnwrap(
            service.settingsSelectingInstalledModel(model, currentSettings: settings)
        )

        XCTAssertEqual(updatedSettings.provider, .local)
        XCTAssertEqual(updatedSettings.localWhisperModelDirectoryPath, directory.standardizedFileURL.path)
        XCTAssertEqual(updatedSettings.localWhisperModelPath, modelURL.path)
    }

    func testSelectingRetiredEnglishOnlyModelManuallyNormalizesLanguages() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let modelURL = directory.appendingPathComponent("ggml-base.en.bin")
        try Data([0x00]).write(to: modelURL)

        var settings = AppSettings()
        settings.provider = .openAI
        settings.localWhisperModelDirectoryPath = directory.path
        settings.selectedTranscriptionLanguages = [.chinese, .english, .spanish, .french]

        let updatedSettings = LocalWhisperSetupService().settingsSelectingModel(
            at: modelURL,
            currentSettings: settings
        )

        XCTAssertEqual(updatedSettings.provider, .local)
        XCTAssertEqual(updatedSettings.localWhisperModelPath, modelURL.path)
        XCTAssertEqual(updatedSettings.selectedTranscriptionLanguages, [.english])
        XCTAssertEqual(updatedSettings.availableTranscriptionLanguages, [.english])
    }

    func testSelectingManualEnglishOnlyModelNormalizesLanguages() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let modelURL = directory.appendingPathComponent("ggml-custom.en.bin")
        try Data([0x00]).write(to: modelURL)

        var settings = AppSettings()
        settings.provider = .elevenLabs
        settings.selectedTranscriptionLanguages = [.spanish, .french]

        let updatedSettings = LocalWhisperSetupService().settingsSelectingModel(
            at: modelURL,
            currentSettings: settings
        )

        XCTAssertEqual(updatedSettings.provider, .local)
        XCTAssertEqual(updatedSettings.localWhisperModelPath, modelURL.standardizedFileURL.path)
        XCTAssertEqual(updatedSettings.selectedTranscriptionLanguages, [.english])
    }

    func testRetiredLocalModelPathSurvivesSelectionNormalization() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let retiredModelURL = directory.appendingPathComponent("ggml-medium.bin")
        try Data([0x00]).write(to: retiredModelURL)

        var settings = AppSettings()
        settings.provider = .local
        settings.localWhisperModelDirectoryPath = directory.path
        settings.localWhisperModelPath = retiredModelURL.path

        settings.normalizeSelections()

        XCTAssertEqual(settings.localWhisperModelPath, retiredModelURL.standardizedFileURL.path)
    }

    func testLocalWhisperSetupServiceClearsSelectionWhenDeletingSelectedModel() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = try XCTUnwrap(
            LocalWhisperModelCatalog.managedModels.first { $0.id == "small" }
        )
        let modelURL = model.destinationURL(in: directory.path)
        try Data().write(to: modelURL)
        var settings = AppSettings()
        settings.provider = .local
        settings.localWhisperModelDirectoryPath = directory.path
        settings.localWhisperModelPath = modelURL.path

        let updatedSettings = try LocalWhisperSetupService().deleteModel(
            model,
            currentSettings: settings
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: modelURL.path))
        XCTAssertEqual(updatedSettings.localWhisperModelPath, "")
    }

    func testDeletingSelectedManagedModelFallsBackToAnotherInstalledModel() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let selectedModel = try XCTUnwrap(
            LocalWhisperModelCatalog.managedModels.first { $0.id == "small" }
        )
        let fallbackModel = try XCTUnwrap(
            LocalWhisperModelCatalog.managedModels.first { $0.id == "large-v3-turbo-q5_0" }
        )
        let selectedURL = selectedModel.destinationURL(in: directory.path)
        let fallbackURL = fallbackModel.destinationURL(in: directory.path)
        try makeSparseFile(at: selectedURL, byteCount: selectedModel.expectedByteCount)
        try makeSparseFile(at: fallbackURL, byteCount: fallbackModel.expectedByteCount)

        var settings = AppSettings()
        settings.provider = .local
        settings.localWhisperModelDirectoryPath = directory.path
        settings.localWhisperModelPath = selectedURL.path

        let updatedSettings = try LocalWhisperSetupService().deleteModel(
            selectedModel,
            currentSettings: settings
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: selectedURL.path))
        XCTAssertEqual(updatedSettings.localWhisperModelPath, fallbackURL.path)
    }

    func testBalancedLocalWhisperCommandUsesDefaultDecoderSettings() {
        let arguments = LocalWhisperCommandArguments.make(
            modelURL: URL(fileURLWithPath: "/tmp/ggml-small.bin"),
            audioFileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            outputBaseURL: URL(fileURLWithPath: "/tmp/output"),
            languageHint: .chinese,
            performanceMode: .balanced,
            activeProcessorCount: 10
        )

        XCTAssertFalse(arguments.contains("-t"))
        XCTAssertFalse(arguments.contains("-bo"))
        XCTAssertFalse(arguments.contains("-bs"))
        XCTAssertFalse(arguments.contains("-nf"))
        XCTAssertFalse(arguments.contains("-np"))
        XCTAssertEqual(argumentValue(after: "-l", in: arguments), "zh")
    }

    func testFastLocalWhisperCommandAddsSpeedArguments() {
        let arguments = LocalWhisperCommandArguments.make(
            modelURL: URL(fileURLWithPath: "/tmp/ggml-small.bin"),
            audioFileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            outputBaseURL: URL(fileURLWithPath: "/tmp/output"),
            languageHint: .mixed,
            performanceMode: .fast,
            activeProcessorCount: 10
        )

        XCTAssertEqual(argumentValue(after: "-t", in: arguments), "8")
        XCTAssertEqual(argumentValue(after: "-bo", in: arguments), "1")
        XCTAssertEqual(argumentValue(after: "-bs", in: arguments), "1")
        XCTAssertTrue(arguments.contains("-nf"))
        XCTAssertTrue(arguments.contains("-np"))
        XCTAssertEqual(argumentValue(after: "-l", in: arguments), "auto")
    }

    func testLocalWhisperCommandIncludesPreferredTermsPrompt() {
        let prompt = LocalWhisperCommandArguments.preferredTermsPrompt(
            from: "API\nSwiftUI\n\nShuo"
        )
        let arguments = LocalWhisperCommandArguments.make(
            modelURL: URL(fileURLWithPath: "/tmp/ggml-small.bin"),
            audioFileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            outputBaseURL: URL(fileURLWithPath: "/tmp/output"),
            languageHint: .mixed,
            performanceMode: .balanced,
            initialPrompt: prompt
        )

        XCTAssertEqual(prompt, "API, SwiftUI, Shuo")
        XCTAssertEqual(argumentValue(after: "--prompt", in: arguments), prompt)
    }

    func testSenseVoiceCommandUsesVADOnlyWhenRequested() {
        let longRecordingArguments = LocalSenseVoiceCommandArguments.make(
            modelURL: URL(fileURLWithPath: "/tmp/sensevoice-small-q8.gguf"),
            audioFileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            vadURL: URL(fileURLWithPath: "/tmp/fsmn-vad.gguf")
        )
        let shortRecordingArguments = LocalSenseVoiceCommandArguments.make(
            modelURL: URL(fileURLWithPath: "/tmp/sensevoice-small-q8.gguf"),
            audioFileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            vadURL: nil
        )

        XCTAssertEqual(argumentValue(after: "-m", in: longRecordingArguments), "/tmp/sensevoice-small-q8.gguf")
        XCTAssertEqual(argumentValue(after: "-a", in: longRecordingArguments), "/tmp/audio.wav")
        XCTAssertEqual(argumentValue(after: "--vad", in: longRecordingArguments), "/tmp/fsmn-vad.gguf")
        XCTAssertEqual(argumentValue(after: "--vad-maxseg", in: longRecordingArguments), "30000")
        XCTAssertNil(argumentValue(after: "--vad", in: shortRecordingArguments))
        XCTAssertNil(argumentValue(after: "--vad-maxseg", in: shortRecordingArguments))
    }

    func testSenseVoiceUsesDirectRecognitionForShortAudioAndVADForLongAudio() {
        XCTAssertFalse(LocalSenseVoiceSegmentationPolicy.shouldUseVAD(forDuration: 0.5))
        XCTAssertFalse(LocalSenseVoiceSegmentationPolicy.shouldUseVAD(forDuration: 29.99))
        XCTAssertTrue(LocalSenseVoiceSegmentationPolicy.shouldUseVAD(forDuration: 30))
        XCTAssertTrue(LocalSenseVoiceSegmentationPolicy.shouldUseVAD(forDuration: nil))
    }

    func testSenseVoiceOutputDropsRuntimeLogsWithoutChangingTranscript() {
        let text = LocalSenseVoiceTranscriptionService.transcriptText(
            from: "我想问我在滨海新区有房。\n[sensevoice] 2 vad segments\n[sensevoice] done 0.51s\n"
        )

        XCTAssertEqual(text, "我想问我在滨海新区有房。")
    }

    func testSenseVoiceOutputRestoresLatinBoundariesWithoutAddingCJKSpaces() {
        XCTAssertEqual(
            LocalSenseVoiceTranscriptionService.transcriptText(
                from: "Hello.\nWorld.\n"
            ),
            "Hello. World."
        )
        XCTAssertEqual(
            LocalSenseVoiceTranscriptionService.transcriptText(
                from: "你好。\n世界。\n"
            ),
            "你好。世界。"
        )
    }

    func testLocalWhisperPromptDoesNotInjectLanguageSamplesForMixedInput() {
        var settings = AppSettings()
        settings.selectedTranscriptionLanguages = [.chinese, .english]
        settings.setPreferredChineseTextConversionMode(.simplified)

        let prompt = LocalWhisperInitialPrompt.make(
            settings: settings,
            vocabularyPrompt: "Shuo, SwiftUI"
        )

        XCTAssertEqual(prompt, "Shuo, SwiftUI.")
        XCTAssertFalse(prompt.contains("今天我们来试一下。效果不错，我们继续。"))
        XCTAssertFalse(prompt.contains("Let's try this."))
    }

    func testLocalWhisperPromptOmitsBuiltInShuoMarkerForMixedInput() {
        var settings = AppSettings()
        settings.selectedTranscriptionLanguages = [.chinese, .english]

        XCTAssertEqual(
            LocalWhisperInitialPrompt.make(settings: settings, vocabularyPrompt: "Shuo"),
            ""
        )
    }

    func testLocalWhisperPromptUsesEnglishStyleForEnglishOnlyInput() {
        var settings = AppSettings()
        settings.selectedTranscriptionLanguages = [.english]

        let prompt = LocalWhisperInitialPrompt.make(
            settings: settings,
            vocabularyPrompt: "Shuo, SwiftUI"
        )

        XCTAssertTrue(prompt.hasPrefix("Shuo, SwiftUI. "))
        XCTAssertTrue(prompt.contains("Let's try this."))
    }

    func testLocalWhisperPromptUsesTraditionalChineseStyleWhenSelected() {
        var settings = AppSettings()
        settings.selectedTranscriptionLanguages = [.chinese]
        settings.setPreferredChineseTextConversionMode(.traditional)

        let prompt = LocalWhisperInitialPrompt.make(
            settings: settings,
            vocabularyPrompt: ""
        )

        XCTAssertEqual(prompt, "今天我們來試一下。效果不錯，我們繼續。")
    }

    func testLocalWhisperPromptDoesNotInjectSamplesForAnyMixedLanguageSelection() {
        var settings = AppSettings()
        settings.selectedTranscriptionLanguages = [.spanish, .french]

        let prompt = LocalWhisperInitialPrompt.make(
            settings: settings,
            vocabularyPrompt: ""
        )

        XCTAssertEqual(prompt, "")
    }

    func testLegacyContextToggleCannotSilentlyDisablePromptContext() {
        var settings = AppSettings()
        settings.sendContextPrompt = false
        settings.useDeveloperGlossary = true
        settings.developerGlossary = "Shuo\ngpt-4o-transcribe"

        let prompt = OpenAITranscriptionService().buildPrompt(
            settings: settings,
            context: "explicit context",
            vocabulary: TranscriptionVocabularySnapshot(
                terms: ["Shuo", "gpt-4o-transcribe"]
            )
        )

        XCTAssertTrue(prompt.contains("Shuo, gpt-4o-transcribe"))
        XCTAssertTrue(prompt.contains("explicit context"))
        XCTAssertTrue(prompt.contains("下方上下文和拼写提示仅作参考"))
    }

    private func argumentValue(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.index(after: index) < arguments.endIndex else {
            return nil
        }

        return arguments[arguments.index(after: index)]
    }

    private func makeSparseFile(at url: URL, byteCount: Int64) throws {
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(byteCount))
    }
}

final class AppExportServiceTests: XCTestCase {
    func testSettingsExportRoundTripsSettingsDocument() throws {
        var settings = AppSettings()
        settings.appLanguage = .simplifiedChinese
        settings.provider = .openAI
        settings.selectedModel = "whisper-1"
        let exportedAt = Date(timeIntervalSince1970: 1_780_000_000)

        let data = try AppExportService.settingsExportData(
            settings: settings,
            exportedAt: exportedAt
        )
        let document = try decode(SettingsExportDocument.self, from: data)

        XCTAssertEqual(document.schemaVersion, SettingsExportDocument.currentSchemaVersion)
        XCTAssertEqual(document.exportedAt, exportedAt)
        XCTAssertEqual(document.settings, settings)
    }

    func testMetricsExportIncludesHistoricalMetricsWithoutTranscriptText() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let exportedAt = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 6,
            day: 7,
            hour: 12,
            minute: 30
        )))
        let createdAt = try XCTUnwrap(calendar.date(byAdding: .hour, value: -2, to: exportedAt))
        let item = TranscriptItem(
            id: try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111")),
            text: "Private Hello 你好",
            createdAt: createdAt,
            provider: .local,
            model: "local.medium",
            languageHint: .mixed
        )

        let record = MetricsCalculator().record(for: item)
        let data = try AppExportService.metricsExportData(
            records: [record],
            exportedAt: exportedAt,
            calendar: calendar
        )
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let document = try decode(MetricsExportDocument.self, from: data)

        XCTAssertFalse(json.contains("Private Hello"))
        XCTAssertEqual(document.schemaVersion, MetricsExportDocument.currentSchemaVersion)
        XCTAssertEqual(document.summary.transcriptCount, 1)
        XCTAssertEqual(document.summary.totalAttempts, 1)
        XCTAssertEqual(document.summary.successfulTranscriptions, 1)
        XCTAssertEqual(document.summary.failedTranscriptions, 0)
        XCTAssertEqual(document.summary.totalCharacters, 14)
        XCTAssertEqual(document.summary.totalWords, 2)
        XCTAssertEqual(document.summary.estimatedTokens, 5)
        XCTAssertEqual(document.hourlyTimeline.count, 24)
        XCTAssertEqual(document.dailyTimeline.count, 14)
        XCTAssertEqual(document.transcripts.count, 1)
        XCTAssertEqual(document.transcripts[0].id, item.id)
        XCTAssertEqual(document.transcripts[0].provider, "local")
        XCTAssertEqual(document.transcripts[0].languageHint, "mixed")
        XCTAssertEqual(document.transcripts[0].outcome, "succeeded")
        XCTAssertEqual(document.transcripts[0].characters, 14)
    }

    func testCorrectionDataExportPreservesFullAndLegacyRecords() throws {
        let exportedAt = Date(timeIntervalSince1970: 1_780_000_000)
        let correction = CorrectionCaptureEvent(
            createdAt: exportedAt,
            source: .floatingCorrection,
            beforeText: "Use whisper one",
            afterText: "Use WhisperKit",
            provider: .local,
            model: "large-v3-turbo",
            languageHint: .mixed
        )
        let legacyEvent = AdaptiveRecognitionFeedbackEvent(
            createdAt: exportedAt,
            source: .historyEdit,
            observedText: "whisper one",
            preferredText: "WhisperKit",
            provider: .local,
            model: "large-v3-turbo",
            languageHint: .mixed
        )
        var state = AdaptiveRecognitionState(
            feedbackEvents: [legacyEvent],
            correctionEvents: [correction]
        )
        let service = AdaptiveRecognitionService()
        var learningSnapshot = service.learningSnapshot(
            history: [],
            state: state
        )
        let patternID = try XCTUnwrap(learningSnapshot.patterns.first?.id)
        state.enabledCorrectionPatternIDs = [patternID]
        learningSnapshot = service.learningSnapshot(history: [], state: state)

        let data = try AppExportService.correctionDataExportData(
            state: state,
            learningSnapshot: learningSnapshot,
            exportedAt: exportedAt
        )
        let document = try decode(CorrectionDataExportDocument.self, from: data)

        XCTAssertEqual(document.schemaVersion, CorrectionDataExportDocument.currentSchemaVersion)
        XCTAssertEqual(document.exportedAt, exportedAt)
        XCTAssertNil(document.learningResetAt)
        XCTAssertEqual(document.corrections, [correction])
        XCTAssertTrue(document.historyCorrections.isEmpty)
        XCTAssertEqual(document.derivedPatterns.count, 1)
        XCTAssertEqual(document.derivedPatterns.first?.observedText, "whisper one")
        XCTAssertEqual(document.derivedPatterns.first?.preferredText, "WhisperKit")
        XCTAssertEqual(document.derivedPatterns.first?.observationCount, 1)
        XCTAssertEqual(document.derivedPatterns.first?.isEnabled, true)
        XCTAssertEqual(document.legacyFeedbackEvents, [legacyEvent])
        XCTAssertTrue(document.legacyLearnedPreferences.isEmpty)
    }

    func testCorrectionDataExportIncludesHistoryTrainingEvidence() throws {
        let createdAt = Date(timeIntervalSince1970: 1_780_000_100)
        let item = TranscriptItem(
            text: "Use WhisperKit",
            rawText: "Use whisper one",
            locallyProcessedText: "Use whisper one",
            initialText: "Use whisper one",
            createdAt: createdAt,
            provider: .local,
            model: "large-v3-turbo",
            languageHint: .mixed,
            audioFileName: "sample.wav"
        )

        let data = try AppExportService.correctionDataExportData(
            state: AdaptiveRecognitionState(),
            history: [item],
            exportedAt: createdAt
        )
        let document = try decode(CorrectionDataExportDocument.self, from: data)
        let evidence = try XCTUnwrap(document.historyCorrections.first)

        XCTAssertEqual(document.historyCorrections.count, 1)
        XCTAssertEqual(evidence.historyID, item.id)
        XCTAssertEqual(evidence.baseline, .initialOutput)
        XCTAssertEqual(evidence.beforeText, "Use whisper one")
        XCTAssertEqual(evidence.afterText, "Use WhisperKit")
        XCTAssertEqual(evidence.audioFileName, "sample.wav")
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}

final class CrashReportServiceTests: XCTestCase {
    func testDetectsUncleanPreviousSessionAndWritesReport() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstService = CrashReportService(baseDirectory: directory)
        let firstReport = firstService.startSession(now: Date(timeIntervalSince1970: 1_780_000_000))
        XCTAssertNil(firstReport)

        let secondService = CrashReportService(baseDirectory: directory)
        let secondReport = try XCTUnwrap(
            secondService.startSession(now: Date(timeIntervalSince1970: 1_780_000_060))
        )
        let reportText = try String(contentsOf: secondReport.reportURL, encoding: .utf8)

        XCTAssertTrue(FileManager.default.fileExists(atPath: secondReport.reportURL.path))
        XCTAssertTrue(reportText.contains("Previous Shuo session did not exit cleanly."))
        XCTAssertTrue(reportText.contains("Shuo Crash Recovery Report"))

        secondService.markCleanExit()

        let thirdService = CrashReportService(baseDirectory: directory)
        XCTAssertNil(thirdService.startSession(now: Date(timeIntervalSince1970: 1_780_000_120)))
    }

    func testExpectedRestartMarkerSuppressesRecoveryReport() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstService = CrashReportService(baseDirectory: directory)
        XCTAssertNil(firstService.startSession(now: Date(timeIntervalSince1970: 1_780_000_000)))

        let restartMarkerService = CrashReportService(baseDirectory: directory)
        restartMarkerService.markExpectedRestart(
            reason: "dev-install",
            now: Date(timeIntervalSince1970: 1_780_000_060)
        )

        let secondService = CrashReportService(baseDirectory: directory)
        XCTAssertNil(secondService.startSession(now: Date(timeIntervalSince1970: 1_780_000_070)))

        let crashReportsDirectory = directory.appendingPathComponent("CrashReports", isDirectory: true)
        let crashReports = (try? FileManager.default.contentsOfDirectory(
            at: crashReportsDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        XCTAssertTrue(crashReports.isEmpty)

        let expectedRestartMarker = directory
            .appendingPathComponent("Runtime", isDirectory: true)
            .appendingPathComponent("expected-restart.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: expectedRestartMarker.path))
    }
}

final class TranscriptHistoryStoreTests: XCTestCase {
    func testMigratesLegacyUserDefaultsHistoryIntoDedicatedHistoryFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let suiteName = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacyItem = TranscriptItem(
            id: try XCTUnwrap(UUID(uuidString: "33333333-3333-3333-3333-333333333333")),
            text: "legacy transcript",
            createdAt: Date(timeIntervalSince1970: 100),
            provider: .local,
            model: "local.medium",
            languageHint: .mixed
        )
        defaults.set(try JSONEncoder().encode([legacyItem]), forKey: "history")

        let store = TranscriptHistoryStore(baseDirectory: directory, userDefaults: defaults)
        let loadedHistory = store.load()

        XCTAssertEqual(loadedHistory, [legacyItem])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.historyFileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.backupFileURL.path))
        XCTAssertNil(defaults.data(forKey: "history"))
    }

    func testLegacyMigrationRunsOnceAndDeletedItemDoesNotReturnAfterRestart() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let suiteName = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacyItem = TranscriptItem(
            text: "legacy transcript",
            provider: .local,
            model: "local.medium",
            languageHint: .mixed
        )
        defaults.set(try JSONEncoder().encode([legacyItem]), forKey: "history")

        let store = TranscriptHistoryStore(baseDirectory: directory, userDefaults: defaults)
        XCTAssertEqual(store.load(), [legacyItem])
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: store.legacyMigrationMarkerURL.path)
        )

        XCTAssertNil(
            try store.deleteHistoryItems(ids: Set([legacyItem.id]), remainingItems: [])
        )

        let restartedStore = TranscriptHistoryStore(
            baseDirectory: directory,
            userDefaults: defaults
        )
        XCTAssertTrue(restartedStore.load().isEmpty)
        XCTAssertNil(defaults.data(forKey: "history"))
    }

    func testUnreadableLegacyHistoryIsLeftUntouchedAndMigrationDoesNotComplete() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let unreadableLegacyData = Data("not-history-json".utf8)
        defaults.set(unreadableLegacyData, forKey: "history")
        let store = TranscriptHistoryStore(baseDirectory: directory, userDefaults: defaults)

        let result = store.loadResult()

        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(result.issue, .unreadableFiles(["UserDefaults:history"]))
        XCTAssertEqual(defaults.data(forKey: "history"), unreadableLegacyData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.legacyMigrationMarkerURL.path))
    }

    func testDeletionTransactionCommitsBeforeTouchingAudioAndRetriesCleanup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyStore = TranscriptHistoryStore(baseDirectory: directory)
        _ = historyStore.loadResult()
        let itemID = UUID()
        let temporaryAudioURL = directory.appendingPathComponent("source.wav")
        try Data("audio".utf8).write(to: temporaryAudioURL)
        let normalAudioStore = TranscriptAudioStore(baseDirectory: directory)
        let fileName = try normalAudioStore.storeRecording(
            at: temporaryAudioURL,
            for: itemID
        )
        let item = TranscriptItem(
            id: itemID,
            text: "delete me",
            provider: .local,
            model: "local.medium",
            languageHint: .mixed,
            audioFileName: fileName
        )
        try historyStore.save([item])
        let failingAudioStore = TranscriptAudioStore(
            baseDirectory: directory,
            removeItem: { _ in
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
            }
        )

        let result = try TranscriptHistoryDeletionTransaction(
            historyStore: historyStore,
            audioStore: failingAudioStore
        ).commit(deletedItems: [item], remainingItems: [])

        XCTAssertFalse(result.audioCleanupErrors.isEmpty)
        XCTAssertTrue(normalAudioStore.audioExists(for: item))
        let committed = historyStore.loadResult()
        XCTAssertTrue(committed.items.isEmpty)
        XCTAssertTrue(committed.deletedItemIDs.contains(itemID))
        XCTAssertEqual(committed.pendingAudioFileNames, Set([fileName]))

        let retryErrors = TranscriptHistoryDeletionTransaction(
            historyStore: historyStore,
            audioStore: normalAudioStore
        ).resumePendingAudioCleanup(fileNames: committed.pendingAudioFileNames)
        XCTAssertTrue(retryErrors.isEmpty)
        XCTAssertFalse(normalAudioStore.audioExists(for: item))
        XCTAssertTrue(historyStore.loadResult().pendingAudioFileNames.isEmpty)
    }

    func testDeletionLedgerFailureLeavesRecordingAndHistoryUntouched() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyStore = TranscriptHistoryStore(baseDirectory: directory)
        _ = historyStore.loadResult()
        let itemID = UUID()
        let temporaryAudioURL = directory.appendingPathComponent("source.wav")
        try Data("audio".utf8).write(to: temporaryAudioURL)
        let audioStore = TranscriptAudioStore(baseDirectory: directory)
        let fileName = try audioStore.storeRecording(at: temporaryAudioURL, for: itemID)
        let item = TranscriptItem(
            id: itemID,
            text: "keep me",
            provider: .local,
            model: "local.medium",
            languageHint: .mixed,
            audioFileName: fileName
        )
        try historyStore.save([item])
        try Data("corrupt-ledger".utf8).write(
            to: historyStore.deletionLedgerFileURL,
            options: .atomic
        )

        XCTAssertThrowsError(
            try TranscriptHistoryDeletionTransaction(
                historyStore: historyStore,
                audioStore: audioStore
            ).commit(deletedItems: [item], remainingItems: [])
        )
        XCTAssertTrue(audioStore.audioExists(for: item))
        let persisted = try JSONDecoder().decode(
            [TranscriptItem].self,
            from: Data(contentsOf: historyStore.historyFileURL)
        )
        XCTAssertEqual(persisted, [item])
    }

    func testDeletionCleansBothSnapshotsAndJournalFinishesInterruptedCleanup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = TranscriptHistoryStore(baseDirectory: directory)
        _ = store.loadResult()
        let retainedItem = TranscriptItem(
            text: "keep",
            provider: .local,
            model: "local.medium",
            languageHint: .mixed
        )
        let deletedItem = TranscriptItem(
            text: "delete",
            provider: .local,
            model: "local.medium",
            languageHint: .mixed
        )
        try store.save([deletedItem, retainedItem])

        XCTAssertNil(
            try store.deleteHistoryItems(
                ids: Set([deletedItem.id]),
                remainingItems: [retainedItem]
            )
        )
        for url in [store.historyFileURL, store.backupFileURL] {
            let items = try JSONDecoder().decode(
                [TranscriptItem].self,
                from: Data(contentsOf: url)
            )
            XCTAssertEqual(items, [retainedItem])
        }

        // Simulate a crash after the deletion journal committed but before the
        // old backup was cleaned.
        try JSONEncoder().encode([deletedItem, retainedItem]).write(
            to: store.backupFileURL,
            options: .atomic
        )
        let recovered = store.loadResult()

        XCTAssertEqual(recovered.items, [retainedItem])
        XCTAssertEqual(recovered.issue, .completedPendingDeletion)
        let repairedBackup = try JSONDecoder().decode(
            [TranscriptItem].self,
            from: Data(contentsOf: store.backupFileURL)
        )
        XCTAssertEqual(repairedBackup, [retainedItem])
    }

    func testCorruptPrimaryCannotRecoverAnItemRecordedAsDeleted() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = TranscriptHistoryStore(baseDirectory: directory)
        _ = store.loadResult()
        let retainedItem = TranscriptItem(
            text: "keep",
            provider: .local,
            model: "local.medium",
            languageHint: .mixed
        )
        let deletedItem = TranscriptItem(
            text: "never revive",
            provider: .local,
            model: "local.medium",
            languageHint: .mixed
        )
        try store.save([deletedItem, retainedItem])
        _ = try store.deleteHistoryItems(
            ids: Set([deletedItem.id]),
            remainingItems: [retainedItem]
        )

        // Recreate the worst crash state: corrupt primary plus a stale backup
        // that still contains the deleted record.
        try Data("corrupt-primary".utf8).write(
            to: store.historyFileURL,
            options: .atomic
        )
        try JSONEncoder().encode([deletedItem, retainedItem]).write(
            to: store.backupFileURL,
            options: .atomic
        )

        let recovered = store.loadResult()

        XCTAssertEqual(recovered.items, [retainedItem])
        guard case .recoveredFiles = recovered.issue else {
            return XCTFail("Expected successful recovery to remain visible")
        }
        for url in [store.historyFileURL, store.backupFileURL] {
            let items = try JSONDecoder().decode(
                [TranscriptItem].self,
                from: Data(contentsOf: url)
            )
            XCTAssertEqual(items, [retainedItem])
        }
    }

    func testDedicatedHistoryProvesLegacyMigrationAlreadyCompleted() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let suiteName = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let sharedID = try XCTUnwrap(UUID(uuidString: "44444444-4444-4444-4444-444444444444"))
        let legacySharedItem = TranscriptItem(
            id: sharedID,
            text: "old text",
            createdAt: Date(timeIntervalSince1970: 100),
            provider: .local,
            model: "local.medium",
            languageHint: .mixed
        )
        let dedicatedSharedItem = TranscriptItem(
            id: sharedID,
            text: "edited text",
            createdAt: Date(timeIntervalSince1970: 100),
            provider: .local,
            model: "local.medium",
            languageHint: .mixed
        )
        let legacyOnlyItem = TranscriptItem(
            id: try XCTUnwrap(UUID(uuidString: "55555555-5555-5555-5555-555555555555")),
            text: "legacy only",
            createdAt: Date(timeIntervalSince1970: 200),
            provider: .openAI,
            model: "gpt-4o-transcribe",
            languageHint: .english
        )

        defaults.set(try JSONEncoder().encode([legacySharedItem, legacyOnlyItem]), forKey: "history")

        let store = TranscriptHistoryStore(baseDirectory: directory, userDefaults: defaults)
        try store.save([dedicatedSharedItem])

        let loadedHistory = store.load()

        XCTAssertEqual(loadedHistory.map(\.id), [dedicatedSharedItem.id])
        XCTAssertEqual(loadedHistory.first(where: { $0.id == sharedID })?.text, "edited text")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.legacyMigrationMarkerURL.path))
        XCTAssertNil(defaults.data(forKey: "history"))
    }

    func testSavingHistoryCreatesBackupOfPreviousDedicatedFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = TranscriptHistoryStore(baseDirectory: directory)
        let firstItem = TranscriptItem(
            text: "first",
            provider: .local,
            model: "local.medium",
            languageHint: .mixed
        )
        let secondItem = TranscriptItem(
            text: "second",
            provider: .local,
            model: "local.medium",
            languageHint: .mixed
        )

        try store.save([firstItem])
        try store.save([secondItem])

        let backupData = try Data(contentsOf: store.backupFileURL)
        let backupHistory = try JSONDecoder().decode([TranscriptItem].self, from: backupData)

        XCTAssertEqual(backupHistory, [firstItem])
    }

    func testRecoversCorruptPrimaryHistoryFromBackupWithoutOverwritingBackup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let suiteName = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = TranscriptHistoryStore(baseDirectory: directory, userDefaults: defaults)
        let backupItem = TranscriptItem(
            text: "recover me",
            provider: .openAI,
            model: "gpt-4o-transcribe",
            languageHint: .english
        )

        try store.save([backupItem])
        try store.save([])
        try Data("not-json".utf8).write(to: store.historyFileURL, options: .atomic)

        let loadedHistory = store.load()
        let restoredPrimary = try JSONDecoder().decode(
            [TranscriptItem].self,
            from: Data(contentsOf: store.historyFileURL)
        )
        let preservedBackup = try JSONDecoder().decode(
            [TranscriptItem].self,
            from: Data(contentsOf: store.backupFileURL)
        )

        XCTAssertEqual(loadedHistory, [backupItem])
        XCTAssertEqual(restoredPrimary, [backupItem])
        XCTAssertEqual(preservedBackup, [backupItem])
    }

    func testSavePropagatesPersistenceFailure() throws {
        let baseFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try Data("not-a-directory".utf8).write(to: baseFile)
        defer { try? FileManager.default.removeItem(at: baseFile) }

        let store = TranscriptHistoryStore(baseDirectory: baseFile)

        XCTAssertThrowsError(try store.save([]))
    }
}

final class AppBuildIdentityTests: XCTestCase {
    func testCommunityIdentityIsolatesEveryPersistentNamespace() {
        let identity = AppBuildIdentity.resolve(
            bundleIdentifier: "org.shuo.community",
            infoDictionary: [
                "CFBundleName": "Shuo Community",
                "ShuoDistributionChannel": "community",
                "ShuoStorageDirectoryName": "Shuo Community",
                "ShuoCredentialServicePrefix": "org.shuo.community"
            ]
        )

        XCTAssertTrue(identity.isCommunityBuild)
        XCTAssertEqual(identity.bundleIdentifier, "org.shuo.community")
        XCTAssertEqual(identity.displayName, "Shuo Community")
        XCTAssertEqual(identity.storageDirectoryName, "Shuo Community")
        XCTAssertEqual(
            identity.credentialService("openai-api-key"),
            "org.shuo.community.openai-api-key"
        )
        XCTAssertNotEqual(identity.bundleIdentifier, AppBuildIdentity.officialBundleIdentifier)
        XCTAssertNotEqual(identity.storageDirectoryName, "Shuo")
    }

    func testMissingMetadataPreservesOfficialNamespaces() {
        let identity = AppBuildIdentity.resolve(
            bundleIdentifier: AppBuildIdentity.officialBundleIdentifier,
            infoDictionary: [:]
        )

        XCTAssertFalse(identity.isCommunityBuild)
        XCTAssertEqual(identity.displayName, "Shuo")
        XCTAssertEqual(identity.storageDirectoryName, "Shuo")
        XCTAssertEqual(
            identity.credentialService("openai-api-key"),
            "dev.shuotian.Shuo.openai-api-key"
        )
    }
}

final class OpenAIAPIKeyStoreTests: XCTestCase {
    func testMigratesLegacyDefaultsValueIntoSecureStorage() throws {
        let suiteName = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let credentialStore = InMemoryCredentialStore()
        defaults.set("  sk-legacy  ", forKey: "openAIAPIKey")

        let loaded = try OpenAIAPIKeyStore.load(
            userDefaults: defaults,
            credentialStore: credentialStore
        )

        XCTAssertEqual(loaded, "sk-legacy")
        XCTAssertNil(defaults.string(forKey: "openAIAPIKey"))
        XCTAssertEqual(credentialStore.values.count, 1)
    }

    func testSaveTrimsAndDeleteRemovesSecureValue() throws {
        let suiteName = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let credentialStore = InMemoryCredentialStore()

        try OpenAIAPIKeyStore.save(
            "  sk-secure  ",
            userDefaults: defaults,
            credentialStore: credentialStore
        )
        XCTAssertEqual(
            try OpenAIAPIKeyStore.load(userDefaults: defaults, credentialStore: credentialStore),
            "sk-secure"
        )

        try OpenAIAPIKeyStore.save(
            "   ",
            userDefaults: defaults,
            credentialStore: credentialStore
        )
        XCTAssertEqual(
            try OpenAIAPIKeyStore.load(userDefaults: defaults, credentialStore: credentialStore),
            ""
        )
        XCTAssertTrue(credentialStore.values.isEmpty)
    }

    func testOpenAICompatibleEndpointsKeepSeparateCredentials() throws {
        let suiteName = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let credentialStore = InMemoryCredentialStore()
        let customScope = OpenAICompatibleCredentialScope(
            baseURLString: "https://relay.example.com/v1"
        )

        try OpenAIAPIKeyStore.save(
            "sk-openai",
            scope: .openAI,
            userDefaults: defaults,
            credentialStore: credentialStore,
            developmentCredentialStore: nil
        )
        try OpenAIAPIKeyStore.save(
            "gsk-groq",
            scope: .groq,
            userDefaults: defaults,
            credentialStore: credentialStore,
            developmentCredentialStore: nil
        )
        try OpenAIAPIKeyStore.save(
            "relay-key",
            scope: customScope,
            userDefaults: defaults,
            credentialStore: credentialStore,
            developmentCredentialStore: nil
        )

        XCTAssertEqual(
            try OpenAIAPIKeyStore.load(
                scope: .openAI,
                userDefaults: defaults,
                credentialStore: credentialStore,
                developmentCredentialStore: nil
            ),
            "sk-openai"
        )
        XCTAssertEqual(
            try OpenAIAPIKeyStore.load(
                scope: .groq,
                userDefaults: defaults,
                credentialStore: credentialStore,
                developmentCredentialStore: nil
            ),
            "gsk-groq"
        )
        XCTAssertEqual(
            try OpenAIAPIKeyStore.load(
                scope: customScope,
                userDefaults: defaults,
                credentialStore: credentialStore,
                developmentCredentialStore: nil
            ),
            "relay-key"
        )
        XCTAssertEqual(credentialStore.values.count, 3)
    }

    func testCurrentNonOpenAIEndpointMigratesItsLegacyCredentialOnce() throws {
        let suiteName = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let credentialStore = InMemoryCredentialStore()
        try credentialStore.set(
            Data("gsk-existing".utf8),
            service: AppCredentialServices.openAI,
            account: "default"
        )

        XCTAssertEqual(
            try OpenAIAPIKeyStore.load(
                scope: .groq,
                migrateLegacyDefault: true,
                userDefaults: defaults,
                credentialStore: credentialStore,
                developmentCredentialStore: nil
            ),
            "gsk-existing"
        )
        XCTAssertEqual(
            try OpenAIAPIKeyStore.load(
                scope: .openAI,
                userDefaults: defaults,
                credentialStore: credentialStore,
                developmentCredentialStore: nil
            ),
            ""
        )
        XCTAssertEqual(credentialStore.values.count, 1)
    }

    func testNewEndpointDoesNotReuseAnExistingOpenAICredential() throws {
        let suiteName = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let credentialStore = InMemoryCredentialStore()
        try credentialStore.set(
            Data("sk-openai".utf8),
            service: AppCredentialServices.openAI,
            account: "default"
        )

        XCTAssertEqual(
            try OpenAIAPIKeyStore.load(
                scope: .groq,
                userDefaults: defaults,
                credentialStore: credentialStore,
                developmentCredentialStore: nil
            ),
            ""
        )
        XCTAssertEqual(
            try OpenAIAPIKeyStore.load(
                scope: .openAI,
                userDefaults: defaults,
                credentialStore: credentialStore,
                developmentCredentialStore: nil
            ),
            "sk-openai"
        )
    }

    func testFailedMigrationPreservesLegacyDefaultsValue() throws {
        let suiteName = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let credentialStore = InMemoryCredentialStore()
        credentialStore.shouldFailWrites = true
        defaults.set("sk-keep", forKey: "openAIAPIKey")

        XCTAssertThrowsError(
            try OpenAIAPIKeyStore.load(
                userDefaults: defaults,
                credentialStore: credentialStore
            )
        )
        XCTAssertEqual(defaults.string(forKey: "openAIAPIKey"), "sk-keep")
    }

    func testDevelopmentStorageMigratesKeychainValueThenAvoidsFurtherKeychainReads() throws {
        let suiteName = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let keychainStore = InMemoryCredentialStore()
        let developmentStore = InMemoryCredentialStore()
        try keychainStore.set(
            Data("sk-development".utf8),
            service: AppCredentialServices.openAI,
            account: "default"
        )

        XCTAssertEqual(
            try OpenAIAPIKeyStore.load(
                userDefaults: defaults,
                credentialStore: keychainStore,
                developmentCredentialStore: developmentStore
            ),
            "sk-development"
        )
        XCTAssertEqual(keychainStore.dataCallCount, 1)

        XCTAssertEqual(
            try OpenAIAPIKeyStore.load(
                userDefaults: defaults,
                credentialStore: keychainStore,
                developmentCredentialStore: developmentStore
            ),
            "sk-development"
        )
        XCTAssertEqual(keychainStore.dataCallCount, 1)
    }

    func testDevelopmentFileCredentialStoreUsesPrivatePermissions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DevelopmentFileCredentialStore(baseDirectory: directory)

        try store.set(
            Data("secret".utf8),
            service: AppCredentialServices.openAI,
            account: "default"
        )

        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        let fileURL = directory.appendingPathComponent("openai-api-key")
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertEqual((fileAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual(
            try store.data(
                service: AppCredentialServices.openAI,
                account: "default"
            ),
            Data("secret".utf8)
        )
    }

    func testDevelopmentStorageKeepsOpenAICompatibleEndpointsSeparate() throws {
        let suiteName = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let developmentStore = DevelopmentFileCredentialStore(baseDirectory: directory)

        try OpenAIAPIKeyStore.save(
            "sk-openai",
            scope: .openAI,
            userDefaults: defaults,
            developmentCredentialStore: developmentStore
        )
        try OpenAIAPIKeyStore.save(
            "gsk-groq",
            scope: .groq,
            userDefaults: defaults,
            developmentCredentialStore: developmentStore
        )

        XCTAssertEqual(
            try OpenAIAPIKeyStore.load(
                scope: .openAI,
                userDefaults: defaults,
                developmentCredentialStore: developmentStore
            ),
            "sk-openai"
        )
        XCTAssertEqual(
            try OpenAIAPIKeyStore.load(
                scope: .groq,
                userDefaults: defaults,
                developmentCredentialStore: developmentStore
            ),
            "gsk-groq"
        )
    }

    func testExistingKeyStabilizesAccessOnlyOnce() throws {
        let suiteName = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let credentialStore = InMemoryCredentialStore()
        try credentialStore.set(
            Data("sk-existing".utf8),
            service: AppCredentialServices.openAI,
            account: "default"
        )

        XCTAssertEqual(
            try OpenAIAPIKeyStore.load(userDefaults: defaults, credentialStore: credentialStore),
            "sk-existing"
        )
        XCTAssertEqual(
            try OpenAIAPIKeyStore.load(userDefaults: defaults, credentialStore: credentialStore),
            "sk-existing"
        )
        XCTAssertEqual(credentialStore.stabilizeAccessCallCount, 1)
    }

    func testFailedAccessStabilizationDoesNotDiscardKeyAndRetries() throws {
        let suiteName = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let credentialStore = InMemoryCredentialStore()
        try credentialStore.set(
            Data("sk-existing".utf8),
            service: AppCredentialServices.openAI,
            account: "default"
        )
        credentialStore.shouldFailAccessStabilization = true

        XCTAssertEqual(
            try OpenAIAPIKeyStore.load(userDefaults: defaults, credentialStore: credentialStore),
            "sk-existing"
        )

        credentialStore.shouldFailAccessStabilization = false
        XCTAssertEqual(
            try OpenAIAPIKeyStore.load(userDefaults: defaults, credentialStore: credentialStore),
            "sk-existing"
        )
        XCTAssertEqual(credentialStore.stabilizeAccessCallCount, 2)
    }
}

final class ElevenLabsAPIKeyStoreTests: XCTestCase {
    func testSaveTrimsAndDeleteRemovesSecureValue() throws {
        let credentialStore = InMemoryCredentialStore()

        try ElevenLabsAPIKeyStore.save(
            "  eleven-secret  ",
            credentialStore: credentialStore
        )
        XCTAssertEqual(
            try ElevenLabsAPIKeyStore.load(credentialStore: credentialStore),
            "eleven-secret"
        )

        try ElevenLabsAPIKeyStore.save("   ", credentialStore: credentialStore)
        XCTAssertEqual(
            try ElevenLabsAPIKeyStore.load(credentialStore: credentialStore),
            ""
        )
        XCTAssertTrue(credentialStore.values.isEmpty)
    }
}

final class AlibabaAPIKeyStoreTests: XCTestCase {
    func testSaveTrimsAndDeleteRemovesSecureValue() throws {
        let credentialStore = InMemoryCredentialStore()

        try AlibabaAPIKeyStore.save(
            "  dashscope-secret  ",
            credentialStore: credentialStore
        )
        XCTAssertEqual(
            try AlibabaAPIKeyStore.load(credentialStore: credentialStore),
            "dashscope-secret"
        )

        try AlibabaAPIKeyStore.save("   ", credentialStore: credentialStore)
        XCTAssertEqual(
            try AlibabaAPIKeyStore.load(credentialStore: credentialStore),
            ""
        )
        XCTAssertTrue(credentialStore.values.isEmpty)
    }
}

final class GeminiAPIKeyStoreTests: XCTestCase {
    func testSaveTrimsAndDeleteRemovesSecureValue() throws {
        let credentialStore = InMemoryCredentialStore()

        try GeminiAPIKeyStore.save(
            "  gemini-secret  ",
            credentialStore: credentialStore
        )
        XCTAssertEqual(
            try GeminiAPIKeyStore.load(credentialStore: credentialStore),
            "gemini-secret"
        )

        try GeminiAPIKeyStore.save("   ", credentialStore: credentialStore)
        XCTAssertEqual(
            try GeminiAPIKeyStore.load(credentialStore: credentialStore),
            ""
        )
        XCTAssertTrue(credentialStore.values.isEmpty)
    }
}

final class ElevenLabsTranscriptionServiceTests: XCTestCase {
    func testBuildsScribeMultipartRequestWithLanguageAndKeyterms() throws {
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).wav")
        try Data([0x52, 0x49, 0x46, 0x46]).write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        var settings = AppSettings()
        settings.provider = .elevenLabs
        settings.languageHint = .chinese
        settings.normalizeSelections()
        let request = TranscriptionRequest(
            audioFileURL: audioURL,
            settings: settings,
            context: "",
            vocabulary: TranscriptionVocabularySnapshot(
                terms: ["Shuo", "SwiftUI", "Shuo", "bad[term]"]
            ),
            apiKey: " secret "
        )

        let urlRequest = try ElevenLabsTranscriptionService().makeURLRequest(
            request,
            boundary: "TEST-BOUNDARY"
        )
        let body = try XCTUnwrap(String(data: try XCTUnwrap(urlRequest.httpBody), encoding: .utf8))

        XCTAssertEqual(urlRequest.url, ElevenLabsTranscriptionService.endpoint)
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "xi-api-key"), "secret")
        XCTAssertTrue(body.contains("name=\"model_id\"\r\n\r\nscribe_v2"))
        XCTAssertTrue(body.contains("name=\"language_code\"\r\n\r\nzho"))
        XCTAssertTrue(body.contains("\r\n\r\nShuo\r\n"))
        XCTAssertTrue(body.contains("\r\n\r\nSwiftUI\r\n"))
        XCTAssertFalse(body.contains("bad[term]"))
        XCTAssertEqual(body.components(separatedBy: "name=\"keyterms\"").count - 1, 2)
    }

    func testMixedLanguageLeavesDetectionAutomatic() throws {
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).m4a")
        try Data([0x00]).write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let body = try ElevenLabsTranscriptionService().makeMultipartBody(
            boundary: "TEST",
            audioFileURL: audioURL,
            languageHint: .mixed,
            vocabulary: .empty
        )
        let bodyText = try XCTUnwrap(String(data: body, encoding: .utf8))

        XCTAssertFalse(bodyText.contains("name=\"language_code\""))
    }

    func testSpanishAndFrenchUseElevenLabsISO6393Codes() throws {
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).wav")
        try Data([0x00]).write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        for (languageHint, expectedCode) in [
            (LanguageHint.spanish, "spa"),
            (.french, "fra")
        ] {
            let body = try ElevenLabsTranscriptionService().makeMultipartBody(
                boundary: "TEST",
                audioFileURL: audioURL,
                languageHint: languageHint,
                vocabulary: .empty
            )
            let bodyText = try XCTUnwrap(String(data: body, encoding: .utf8))

            XCTAssertTrue(
                bodyText.contains("name=\"language_code\"\r\n\r\n\(expectedCode)")
            )
        }
    }
}

final class OpenAICompatibleRequestBuilderTests: XCTestCase {
    func testBuildsValidatedEndpointAndSharedHeaders() throws {
        let endpoint = try XCTUnwrap(OpenAICompatibleRequestBuilder.endpoint(
            baseURLString: " https://example.com/v1 ",
            path: "chat/completions"
        ))
        var settings = AppSettings()
        settings.openAIOrganizationID = " org-1 "
        settings.openAIProjectID = " project-1 "
        let requestID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))

        let request = OpenAICompatibleRequestBuilder.authenticatedPOSTRequest(
            endpoint: endpoint,
            apiKey: "secret",
            settings: settings,
            contentType: "application/json",
            requestID: requestID
        )

        XCTAssertEqual(endpoint.absoluteString, "https://example.com/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        XCTAssertEqual(request.value(forHTTPHeaderField: "OpenAI-Organization"), "org-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "OpenAI-Project"), "project-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Client-Request-Id"), requestID.uuidString)
    }

    func testRejectsNonHTTPBaseURLsAndExtractsProviderErrors() {
        XCTAssertNil(OpenAICompatibleRequestBuilder.endpoint(
            baseURLString: "file:///tmp/api",
            path: "chat/completions"
        ))
        XCTAssertNil(OpenAICompatibleRequestBuilder.normalizedAPIKey("  "))

        let data = Data(#"{"error":{"message":"  invalid key  "}}"#.utf8)
        XCTAssertEqual(OpenAICompatibleRequestBuilder.errorMessage(from: data), "invalid key")
        XCTAssertEqual(
            OpenAICompatibleRequestBuilder.cleanedModelOutput("```text\n\"hello\"\n```"),
            "hello"
        )
        XCTAssertNil(OpenAICompatibleRequestBuilder.endpoint(
            baseURLString: "https://relay.example.test/v1?token=not-allowed",
            path: "audio/transcriptions"
        ))
    }

    func testRecognizesEndpointsThatNeedTheCompatibilityPayload() {
        XCTAssertFalse(
            OpenAICompatibleRequestBuilder.usesOpenAICompatibleMinimalRequestProfile(
                baseURLString: "https://api.openai.com/v1/"
            )
        )
        XCTAssertTrue(
            OpenAICompatibleRequestBuilder.usesOpenAICompatibleMinimalRequestProfile(
                baseURLString: "https://relay.example.test/v1"
            )
        )
        XCTAssertTrue(
            OpenAICompatibleRequestBuilder.usesOpenAICompatibleMinimalRequestProfile(
                baseURLString: "http://localhost:11434/v1"
            )
        )
    }

    func testAllowsHTTPOnlyForExplicitLoopbackHosts() throws {
        let allowedBaseURLs = [
            "https://api.example.com/v1",
            "http://localhost:11434/v1",
            "http://LOCALHOST:11434/v1",
            "http://127.0.0.1:8080/v1",
            "http://[::1]:8080/v1"
        ]

        for baseURL in allowedBaseURLs {
            XCTAssertNotNil(
                OpenAICompatibleRequestBuilder.endpoint(
                    baseURLString: baseURL,
                    path: "audio/transcriptions"
                ),
                baseURL
            )
        }

        let rejectedBaseURLs = [
            "http://api.example.com/v1",
            "http://localhost.example.com/v1",
            "http://127.0.0.1.example.com/v1",
            "http://127.0.0.2/v1"
        ]

        for baseURL in rejectedBaseURLs {
            XCTAssertNil(
                OpenAICompatibleRequestBuilder.endpoint(
                    baseURLString: baseURL,
                    path: "audio/transcriptions"
                ),
                baseURL
            )
            XCTAssertThrowsError(
                try OpenAICompatibleRequestBuilder.validatedEndpoint(
                    baseURLString: baseURL,
                    path: "audio/transcriptions"
                )
            ) { error in
                XCTAssertEqual(
                    error as? OpenAICompatibleEndpointValidationError,
                    .insecureRemoteHTTP,
                    baseURL
                )
            }
        }
    }

    func testRemoteHTTPFailureExplainsHowToFixTheEndpoint() {
        let message = OpenAITranscriptionError
            .invalidBaseURL("http://api.example.com/v1")
            .errorDescription

        XCTAssertTrue(message?.contains("must use HTTPS") == true)
        XCTAssertTrue(message?.contains("localhost") == true)
        XCTAssertFalse(message?.contains("api.example.com") == true)
    }

    func testSensitiveRequestsAllowOnlySameOriginRedirects() throws {
        let source = try XCTUnwrap(URL(string: "https://api.example.com/v1/audio"))
        let allowed = try XCTUnwrap(URL(string: "https://API.example.com:443/v2/audio"))
        let downgraded = try XCTUnwrap(URL(string: "http://api.example.com/v2/audio"))
        let crossHost = try XCTUnwrap(URL(string: "https://uploads.example.net/v2/audio"))
        let crossPort = try XCTUnwrap(URL(string: "https://api.example.com:8443/v2/audio"))

        XCTAssertTrue(SensitiveRequestRedirectPolicy.allowsRedirect(
            from: source,
            to: allowed
        ))
        XCTAssertFalse(SensitiveRequestRedirectPolicy.allowsRedirect(
            from: source,
            to: downgraded
        ))
        XCTAssertFalse(SensitiveRequestRedirectPolicy.allowsRedirect(
            from: source,
            to: crossHost
        ))
        XCTAssertFalse(SensitiveRequestRedirectPolicy.allowsRedirect(
            from: source,
            to: crossPort
        ))
        XCTAssertFalse(SensitiveRequestRedirectPolicy.allowsRedirect(
            from: source,
            to: URL(string: "file:///tmp/redirect")
        ))
    }

    func testSensitiveRequestsUseBoundedTimeouts() {
        XCTAssertEqual(
            SensitiveRequestURLSession.shared.configuration.timeoutIntervalForRequest,
            SensitiveRequestURLSession.requestTimeout
        )
        XCTAssertEqual(
            SensitiveRequestURLSession.shared.configuration.timeoutIntervalForResource,
            SensitiveRequestURLSession.resourceTimeout
        )
        XCTAssertLessThan(SensitiveRequestURLSession.resourceTimeout, 24 * 60 * 60)
    }
}

private final class InMemoryCredentialStore: SecureCredentialStoring {
    enum TestError: Error {
        case writeFailed
        case accessStabilizationFailed
    }

    var values: [String: Data] = [:]
    var shouldFailWrites = false
    var shouldFailAccessStabilization = false
    private(set) var stabilizeAccessCallCount = 0
    private(set) var dataCallCount = 0

    func data(service: String, account: String) throws -> Data? {
        dataCallCount += 1
        return values[key(service: service, account: account)]
    }

    func set(_ data: Data, service: String, account: String) throws {
        if shouldFailWrites {
            throw TestError.writeFailed
        }
        values[key(service: service, account: account)] = data
    }

    func remove(service: String, account: String) throws {
        values.removeValue(forKey: key(service: service, account: account))
    }

    func stabilizeAccess(service _: String, account _: String) throws {
        stabilizeAccessCallCount += 1
        if shouldFailAccessStabilization {
            throw TestError.accessStabilizationFailed
        }
    }

    private func key(service: String, account: String) -> String {
        "\(service)|\(account)"
    }
}

final class MetricsStoreTests: XCTestCase {
    func testSeedsMetricsHistoryFromExistingHistoryWhenMetricsFilesDoNotExist() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let item = TranscriptItem(
            text: "Private Hello 你好",
            createdAt: Date(timeIntervalSince1970: 100),
            provider: .local,
            model: "local.medium",
            languageHint: .mixed
        )
        let store = MetricsStore(baseDirectory: directory)

        let state = store.load(seedHistory: [item])
        let json = try XCTUnwrap(String(contentsOf: store.metricsHistoryFileURL, encoding: .utf8))

        XCTAssertEqual(state.records.map(\.id), [item.id])
        XCTAssertEqual(state.counters.transcriptCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.metricsHistoryFileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.countersFileURL.path))
        XCTAssertFalse(json.contains("Private Hello"))
    }

    func testExistingMetricsHistoryDoesNotGetRebuiltFromTranscriptHistory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let keptItem = TranscriptItem(
            text: "kept",
            createdAt: Date(timeIntervalSince1970: 200),
            provider: .local,
            model: "local.medium",
            languageHint: .english
        )
        let deletedItem = TranscriptItem(
            text: "deleted",
            createdAt: Date(timeIntervalSince1970: 100),
            provider: .local,
            model: "local.medium",
            languageHint: .english
        )
        let store = MetricsStore(baseDirectory: directory)
        let calculator = MetricsCalculator()
        let keptRecords = [calculator.record(for: keptItem)]
        try store.save(records: keptRecords, counters: calculator.counters(from: keptRecords))

        let state = store.load(seedHistory: [keptItem, deletedItem])

        XCTAssertEqual(state.records.map(\.id), [keptItem.id])
        XCTAssertEqual(state.counters.transcriptCount, 1)
        XCTAssertFalse(state.records.contains { $0.id == deletedItem.id })
    }

    func testSavingMetricsCreatesBackupOfPreviousDedicatedFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstItem = TranscriptItem(
            text: "first",
            provider: .local,
            model: "local.medium",
            languageHint: .english
        )
        let secondItem = TranscriptItem(
            text: "second",
            provider: .local,
            model: "local.medium",
            languageHint: .english
        )
        let calculator = MetricsCalculator()
        let store = MetricsStore(baseDirectory: directory)
        let firstRecords = [calculator.record(for: firstItem)]
        let secondRecords = [calculator.record(for: secondItem)]

        try store.save(records: firstRecords, counters: calculator.counters(from: firstRecords))
        try store.save(records: secondRecords, counters: calculator.counters(from: secondRecords))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backupHistoryData = try Data(contentsOf: store.metricsHistoryBackupFileURL)
        let backupRecords = try decoder.decode([TranscriptMetricsRecord].self, from: backupHistoryData)
        let backupCountersData = try Data(contentsOf: store.countersBackupFileURL)
        let backupCounters = try decoder.decode(MetricsCounters.self, from: backupCountersData)

        XCTAssertEqual(backupRecords.map(\.id), [firstItem.id])
        XCTAssertEqual(backupCounters.transcriptCount, 1)
    }

    func testDisplayCutoffPersistsWithoutRewritingMetricsHistory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let oldItem = TranscriptItem(
            text: "old",
            createdAt: Date(timeIntervalSince1970: 100),
            provider: .local,
            model: "local.medium",
            languageHint: .english
        )
        let newItem = TranscriptItem(
            text: "new",
            createdAt: Date(timeIntervalSince1970: 300),
            provider: .local,
            model: "local.medium",
            languageHint: .english
        )
        let cutoff = Date(timeIntervalSince1970: 200.125)
        let calculator = MetricsCalculator()
        let records = [oldItem, newItem].map(calculator.record(for:))
        let store = MetricsStore(baseDirectory: directory)
        let counters = calculator.counters(from: records)
        try store.save(records: records, counters: counters)
        let historyDataBeforeReset = try Data(contentsOf: store.metricsHistoryFileURL)

        try store.saveDisplayReset(counters: counters.resettingDisplay(at: cutoff))

        XCTAssertEqual(try Data(contentsOf: store.metricsHistoryFileURL), historyDataBeforeReset)
        let state = store.load(seedHistory: [])
        XCTAssertEqual(Set(state.records.map(\.id)), Set(records.map(\.id)))
        XCTAssertEqual(
            try XCTUnwrap(state.counters.displayCutoff).timeIntervalSince1970,
            cutoff.timeIntervalSince1970,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            calculator.recordsForDisplay(state.records, cutoff: state.counters.displayCutoff).map(\.id),
            [newItem.id]
        )
    }

    func testSavePropagatesPersistenceFailure() throws {
        let baseFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try Data("not-a-directory".utf8).write(to: baseFile)
        defer { try? FileManager.default.removeItem(at: baseFile) }

        let store = MetricsStore(baseDirectory: baseFile)

        XCTAssertThrowsError(
            try store.save(records: [], counters: .empty)
        )
    }

    func testMigratesLegacyMetricsFileIntoHistoryFolderAndCountersFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let item = TranscriptItem(
            text: "legacy metrics",
            createdAt: Date(timeIntervalSince1970: 100),
            provider: .local,
            model: "local.medium",
            languageHint: .english
        )
        let calculator = MetricsCalculator()
        let store = MetricsStore(baseDirectory: directory)
        try FileManager.default.createDirectory(
            at: store.metricsDirectoryURL,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([calculator.record(for: item)])
            .write(to: store.legacyMetricsFileURL, options: .atomic)

        let state = store.load(seedHistory: [])

        XCTAssertEqual(state.records.map(\.id), [item.id])
        XCTAssertEqual(state.counters.transcriptCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.metricsHistoryFileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.countersFileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.legacyMetricsFileURL.path))
    }
}

final class AudioCapturePipelineTests: XCTestCase {
    func testCaptureGraphReuseRequiresSameConnectedHealthyDevice() {
        XCTAssertTrue(
            AudioCaptureGraphReusePolicy.shouldReuse(
                cachedDeviceID: "airpods",
                cachedDeviceIsConnected: true,
                requestedDeviceID: "airpods",
                requestedDeviceIsConnected: true,
                runtimeInvalidated: false
            )
        )
        XCTAssertFalse(
            AudioCaptureGraphReusePolicy.shouldReuse(
                cachedDeviceID: "airpods",
                cachedDeviceIsConnected: true,
                requestedDeviceID: "usb-mic",
                requestedDeviceIsConnected: true,
                runtimeInvalidated: false
            )
        )
        XCTAssertFalse(
            AudioCaptureGraphReusePolicy.shouldReuse(
                cachedDeviceID: "airpods",
                cachedDeviceIsConnected: false,
                requestedDeviceID: "airpods",
                requestedDeviceIsConnected: true,
                runtimeInvalidated: false
            )
        )
        XCTAssertFalse(
            AudioCaptureGraphReusePolicy.shouldReuse(
                cachedDeviceID: "airpods",
                cachedDeviceIsConnected: true,
                requestedDeviceID: "airpods",
                requestedDeviceIsConnected: false,
                runtimeInvalidated: false
            )
        )
        XCTAssertFalse(
            AudioCaptureGraphReusePolicy.shouldReuse(
                cachedDeviceID: "airpods",
                cachedDeviceIsConnected: true,
                requestedDeviceID: "airpods",
                requestedDeviceIsConnected: true,
                runtimeInvalidated: true
            )
        )
    }

    func testUSBReadinessFailureGetsOneFreshGraphRetry() {
        XCTAssertEqual(
            AudioCaptureStartRetryPolicy.maximumAttemptCount(
                forTransportType: Int32(bitPattern: kAudioDeviceTransportTypeUSB)
            ),
            2
        )
        XCTAssertEqual(
            AudioCaptureStartRetryPolicy.maximumAttemptCount(
                forTransportType: Int32(bitPattern: kAudioDeviceTransportTypeBuiltIn)
            ),
            1
        )
    }

    func testCaptureCallbacksRequireTheCurrentActiveSegmentGeneration() {
        XCTAssertTrue(
            AudioCaptureSegmentCallbackPolicy.shouldAccept(
                activeGeneration: 2,
                callbackGeneration: 2,
                hasActiveSegment: true,
                isCurrentOutput: true
            )
        )
        XCTAssertFalse(
            AudioCaptureSegmentCallbackPolicy.shouldAccept(
                activeGeneration: 2,
                callbackGeneration: 1,
                hasActiveSegment: true,
                isCurrentOutput: true
            )
        )
        XCTAssertFalse(
            AudioCaptureSegmentCallbackPolicy.shouldAccept(
                activeGeneration: nil,
                callbackGeneration: 2,
                hasActiveSegment: false,
                isCurrentOutput: true
            )
        )
        XCTAssertFalse(
            AudioCaptureSegmentCallbackPolicy.shouldAccept(
                activeGeneration: 2,
                callbackGeneration: 2,
                hasActiveSegment: true,
                isCurrentOutput: false
            )
        )
    }

    func testExternalTransportsUseReadinessHandshake() {
        XCTAssertEqual(
            AudioCaptureReadinessPolicy.policy(
                forTransportType: Int32(bitPattern: kAudioDeviceTransportTypeBluetooth)
            ),
            .bluetooth
        )
        XCTAssertEqual(
            AudioCaptureReadinessPolicy.policy(
                forTransportType: Int32(bitPattern: kAudioDeviceTransportTypeBluetoothLE)
            ),
            .bluetooth
        )
        XCTAssertEqual(
            AudioCaptureReadinessPolicy.policy(
                forTransportType: Int32(bitPattern: kAudioDeviceTransportTypeUSB)
            ),
            .usb
        )
        XCTAssertNil(
            AudioCaptureReadinessPolicy.policy(
                forTransportType: Int32(bitPattern: kAudioDeviceTransportTypeBuiltIn)
            )
        )
    }

    func testReadinessRequiresConsecutiveLiveAudioAndResetsAfterDigitalSilence() {
        let policy = AudioCaptureReadinessPolicy(
            requiredStableFrameCount: 8,
            minimumActiveFraction: 0.5,
            digitalSilenceFloor: 0.001,
            timeout: 1,
            maximumPreRollFrameCount: 16
        )
        var gate = AudioCaptureReadinessGate(policy: policy)

        XCTAssertEqual(gate.observe(Array(repeating: 0, count: 4)), .digitalSilence)
        XCTAssertEqual(gate.observe(Array(repeating: 0.1, count: 4)), .candidate)
        XCTAssertEqual(gate.stableFrameCount, 4)
        XCTAssertEqual(gate.observe(Array(repeating: 0, count: 4)), .digitalSilence)
        XCTAssertEqual(gate.stableFrameCount, 0)
        XCTAssertEqual(gate.observe(Array(repeating: 0.1, count: 4)), .candidate)
        XCTAssertEqual(gate.observe(Array(repeating: 0.1, count: 4)), .ready)
        XCTAssertTrue(gate.isReady)
    }

    func testInitialReadinessBuffersLiveAudioUntilAtomicCommit() {
        let policy = AudioCaptureReadinessPolicy(
            requiredStableFrameCount: 4,
            minimumActiveFraction: 0.5,
            digitalSilenceFloor: 0.001,
            timeout: 1,
            maximumPreRollFrameCount: 8
        )
        var readiness = AudioCaptureReadinessBuffer(policy: policy)

        XCTAssertEqual(readiness.consume([0, 0]), [])
        XCTAssertEqual(readiness.discardedDigitalSilenceFrameCount, 2)
        XCTAssertEqual(readiness.consume([0.1, 0.2]), [])
        XCTAssertEqual(readiness.consume([0.3, 0.4]), [])
        XCTAssertEqual(readiness.phase, .readyToCommit)

        // More live input may arrive between the delegate observing readiness
        // and the waiting task's capture-queue commit. It remains uncommitted.
        XCTAssertEqual(readiness.consume([0.5]), [])
        XCTAssertEqual(
            readiness.commitInitialReadinessIfReady(),
            [0.1, 0.2, 0.3, 0.4, 0.5]
        )
        XCTAssertEqual(readiness.phase, .committed)
        XCTAssertEqual(readiness.consume([0.6]), [0.6])
    }

    func testFormatChangeBeforeInitialCommitInvalidatesPendingAudio() {
        let policy = AudioCaptureReadinessPolicy(
            requiredStableFrameCount: 4,
            minimumActiveFraction: 0.5,
            digitalSilenceFloor: 0.001,
            timeout: 1,
            maximumPreRollFrameCount: 8
        )
        var readiness = AudioCaptureReadinessBuffer(policy: policy)

        XCTAssertEqual(readiness.consume([0.1, 0.2, 0.3, 0.4]), [])
        XCTAssertEqual(readiness.phase, .readyToCommit)
        readiness.sourceFormatDidChange()

        XCTAssertEqual(readiness.phase, .warmingUp)
        XCTAssertTrue(readiness.pendingSamples.isEmpty)
        XCTAssertNil(readiness.commitInitialReadinessIfReady())
        XCTAssertEqual(readiness.consume([0.5, 0.6]), [])
        XCTAssertEqual(readiness.consume([0.7, 0.8]), [])
        XCTAssertEqual(
            readiness.commitInitialReadinessIfReady(),
            [0.5, 0.6, 0.7, 0.8]
        )
    }

    func testCommittedRecordingRegatesAfterFormatChangeWithoutKeepingDigitalZeros() {
        let policy = AudioCaptureReadinessPolicy(
            requiredStableFrameCount: 4,
            minimumActiveFraction: 0.5,
            digitalSilenceFloor: 0.001,
            timeout: 1,
            maximumPreRollFrameCount: 8
        )
        var readiness = AudioCaptureReadinessBuffer(
            policy: policy,
            initiallyCommitted: true
        )

        XCTAssertEqual(readiness.consume([0.1]), [0.1])
        readiness.sourceFormatDidChange()
        XCTAssertEqual(readiness.phase, .rewarmingAfterFormatChange)
        XCTAssertEqual(readiness.consume([0, 0]), [])
        XCTAssertEqual(readiness.consume([0.2, 0.3]), [])
        XCTAssertEqual(readiness.consume([0.4, 0.5]), [0.2, 0.3, 0.4, 0.5])
        XCTAssertEqual(readiness.phase, .committed)
        XCTAssertEqual(readiness.discardedDigitalSilenceFrameCount, 2)
    }

    func testNormalStopPreservesLiveCandidateFromPostCommitFormatChange() {
        let policy = AudioCaptureReadinessPolicy(
            requiredStableFrameCount: 4,
            minimumActiveFraction: 0.5,
            digitalSilenceFloor: 0.001,
            timeout: 1,
            maximumPreRollFrameCount: 8
        )
        var readiness = AudioCaptureReadinessBuffer(
            policy: policy,
            initiallyCommitted: true
        )

        readiness.sourceFormatDidChange()
        XCTAssertEqual(readiness.consume([0, 0]), [])
        XCTAssertEqual(readiness.consume([0.2, 0.3]), [])
        XCTAssertEqual(readiness.finishCommittedRecording(), [0.2, 0.3])
        XCTAssertEqual(readiness.phase, .committed)
    }

    func testBluetoothReadinessUsesTenthSecondLiveAudioAndHalfSecondPreRollCap() {
        XCTAssertEqual(
            AudioCaptureReadinessPolicy.bluetooth.requiredStableFrameCount,
            AudioCaptureReadinessPolicy.outputSampleRate / 10
        )
        XCTAssertEqual(
            AudioCaptureReadinessPolicy.bluetooth.maximumPreRollFrameCount,
            AudioCaptureReadinessPolicy.outputSampleRate / 2
        )
    }

    func testConverterKeepsAudioAcrossSourceSampleRateChanges() throws {
        let converter = AudioCaptureBufferConverter()
        let first = try converter.convert(
            makeInt16AudioSampleBuffer(sampleRate: 24_000, frameCount: 480)
        )
        let second = try converter.convert(
            makeInt16AudioSampleBuffer(sampleRate: 48_000, frameCount: 960)
        )
        let finalTail = try converter.finish()

        XCTAssertFalse(first.sourceFormatChanged)
        XCTAssertTrue(second.sourceFormatChanged)
        XCTAssertEqual(second.sourceFormatChange?.old.sampleRate, 24_000)
        XCTAssertEqual(second.sourceFormatChange?.old.channelCount, 1)
        XCTAssertEqual(second.sourceFormatChange?.new.sampleRate, 48_000)
        XCTAssertEqual(second.sourceFormatChange?.new.channelCount, 1)

        let oldFormatOutput = first.samples + second.previousFormatTailSamples
        let newFormatOutput = second.samples + finalTail
        XCTAssertEqual(oldFormatOutput.count, 320)
        XCTAssertEqual(newFormatOutput.count, 320)
        XCTAssertFalse(second.previousFormatTailSamples.isEmpty)
        XCTAssertFalse(finalTail.isEmpty)
        XCTAssertGreaterThan(oldFormatOutput.map(abs).max() ?? 0, 0.01)
        XCTAssertGreaterThan(newFormatOutput.map(abs).max() ?? 0, 0.01)
    }

    func testConverterDownmixesFloat32StereoInput() throws {
        let converter = AudioCaptureBufferConverter()
        let converted = try converter.convert(
            makeFloat32StereoAudioSampleBuffer(sampleRate: 48_000, frameCount: 960)
        )
        let output = converted.samples + (try converter.finish())

        XCTAssertEqual(output.count, 320)
        XCTAssertGreaterThan(output.map(abs).max() ?? 0, 0.01)
    }

    func testConverterDrainsDeterministicTailAfterMultipleInputBuffers() throws {
        let converter = AudioCaptureBufferConverter()
        let first = try converter.convert(
            makeInt16AudioSampleBuffer(sampleRate: 44_100, frameCount: 50)
        )
        let second = try converter.convert(
            makeInt16AudioSampleBuffer(sampleRate: 44_100, frameCount: 51)
        )
        let tail = try converter.finish()

        XCTAssertFalse(first.sourceFormatChanged)
        XCTAssertFalse(second.sourceFormatChanged)
        XCTAssertTrue(first.previousFormatTailSamples.isEmpty)
        XCTAssertTrue(second.previousFormatTailSamples.isEmpty)
        XCTAssertEqual(first.samples.count + second.samples.count + tail.count, 37)
        XCTAssertFalse(tail.isEmpty)
        XCTAssertTrue(try converter.finish().isEmpty)
    }

    private func makeInt16AudioSampleBuffer(
        sampleRate: Double,
        frameCount: Int
    ) throws -> CMSampleBuffer {
        var streamDescription = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var formatDescription: CMAudioFormatDescription?
        XCTAssertEqual(
            CMAudioFormatDescriptionCreate(
                allocator: kCFAllocatorDefault,
                asbd: &streamDescription,
                layoutSize: 0,
                layout: nil,
                magicCookieSize: 0,
                magicCookie: nil,
                extensions: nil,
                formatDescriptionOut: &formatDescription
            ),
            noErr
        )

        let samples = (0..<frameCount).map { index in
            Int16(sin(Double(index) * 0.1) * Double(Int16.max / 2))
        }
        let byteCount = samples.count * MemoryLayout<Int16>.size
        var blockBuffer: CMBlockBuffer?
        XCTAssertEqual(
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: byteCount,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: byteCount,
                flags: 0,
                blockBufferOut: &blockBuffer
            ),
            kCMBlockBufferNoErr
        )
        let copyStatus = samples.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(
                with: bytes.baseAddress!,
                blockBuffer: blockBuffer!,
                offsetIntoDestination: 0,
                dataLength: byteCount
            )
        }
        XCTAssertEqual(copyStatus, kCMBlockBufferNoErr)

        var sampleBuffer: CMSampleBuffer?
        XCTAssertEqual(
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                allocator: kCFAllocatorDefault,
                dataBuffer: blockBuffer!,
                formatDescription: formatDescription!,
                sampleCount: frameCount,
                presentationTimeStamp: .zero,
                packetDescriptions: nil,
                sampleBufferOut: &sampleBuffer
            ),
            noErr
        )
        return sampleBuffer!
    }

    private func makeFloat32StereoAudioSampleBuffer(
        sampleRate: Double,
        frameCount: Int
    ) throws -> CMSampleBuffer {
        let channelCount = 2
        var streamDescription = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsFloat | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: UInt32(MemoryLayout<Float>.size * channelCount),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(MemoryLayout<Float>.size * channelCount),
            mChannelsPerFrame: UInt32(channelCount),
            mBitsPerChannel: UInt32(MemoryLayout<Float>.size * 8),
            mReserved: 0
        )
        var formatDescription: CMAudioFormatDescription?
        XCTAssertEqual(
            CMAudioFormatDescriptionCreate(
                allocator: kCFAllocatorDefault,
                asbd: &streamDescription,
                layoutSize: 0,
                layout: nil,
                magicCookieSize: 0,
                magicCookie: nil,
                extensions: nil,
                formatDescriptionOut: &formatDescription
            ),
            noErr
        )

        let samples = (0..<frameCount).flatMap { index -> [Float] in
            let phase = Float(Double(index) * 0.1)
            return [sin(phase) * 0.5, cos(phase) * 0.25]
        }
        let byteCount = samples.count * MemoryLayout<Float>.size
        var blockBuffer: CMBlockBuffer?
        XCTAssertEqual(
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: byteCount,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: byteCount,
                flags: 0,
                blockBufferOut: &blockBuffer
            ),
            kCMBlockBufferNoErr
        )
        let copyStatus = samples.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(
                with: bytes.baseAddress!,
                blockBuffer: blockBuffer!,
                offsetIntoDestination: 0,
                dataLength: byteCount
            )
        }
        XCTAssertEqual(copyStatus, kCMBlockBufferNoErr)

        var sampleBuffer: CMSampleBuffer?
        XCTAssertEqual(
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                allocator: kCFAllocatorDefault,
                dataBuffer: blockBuffer!,
                formatDescription: formatDescription!,
                sampleCount: frameCount,
                presentationTimeStamp: .zero,
                packetDescriptions: nil,
                sampleBufferOut: &sampleBuffer
            ),
            noErr
        )
        return sampleBuffer!
    }
}

final class AudioActivityAnalyzerTests: XCTestCase {
    func testAdaptiveGateAdmitsQuietSpeechWithoutRequiringWhisperMode() throws {
        let url = temporaryWAVURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeSineWAV(to: url, peakDBFS: -44)

        let analyzer = AudioActivityAnalyzer()
        let standardAnalysis = try analyzer.analyze(
            url,
            silenceThresholdDBFS: AppSettings().silenceThresholdDBFS
        )

        XCTAssertEqual(standardAnalysis.activeDuration, 0, accuracy: 0.001)
        XCTAssertFalse(standardAnalysis.containsSpeech(settings: AppSettings()))

        let adaptiveAnalysis = try analyzer.analyze(
            url,
            silenceThresholdDBFS: AppSettings().silenceThresholdDBFS,
            adaptsToNoiseFloor: true
        )

        XCTAssertGreaterThan(adaptiveAnalysis.activeDuration, 0.9)
        XCTAssertTrue(adaptiveAnalysis.containsSpeech(settings: AppSettings()))
    }

    func testAdaptiveGateRejectsLowLevelNoiseEvenWhenItsWindowIsActive() throws {
        let url = temporaryWAVURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeSineWAV(to: url, peakDBFS: -49)

        let settings = AppSettings()
        let analysis = try AudioActivityAnalyzer().analyze(
            url,
            silenceThresholdDBFS: settings.silenceThresholdDBFS,
            adaptsToNoiseFloor: true
        )

        XCTAssertGreaterThan(analysis.activeDuration, 0.9)
        XCTAssertLessThan(analysis.speechLevelDBFS, -50)
        XCTAssertFalse(analysis.containsSpeech(settings: settings))
    }

    func testNearSilentRecordingIsIgnoredByDefaultGate() throws {
        let url = temporaryWAVURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeSineWAV(to: url, peakDBFS: -80)

        let analysis = try AudioActivityAnalyzer().analyze(
            url,
            silenceThresholdDBFS: AppSettings().silenceThresholdDBFS
        )

        XCTAssertFalse(analysis.containsSpeech(settings: AppSettings()))
    }

    func testAmbientNoiseWithShortPeaksDoesNotPassDefaultGate() throws {
        let samples: [(name: String, duration: TimeInterval, transientTimes: [TimeInterval])] = [
            ("opening transient", 1.8, [0.01]),
            ("late transient", 3.2, [2.9]),
            ("several short transients", 3.4, [0.7, 1.4, 2.6])
        ]

        let analyzer = AudioActivityAnalyzer()
        for sample in samples {
            let url = temporaryWAVURL()
            defer { try? FileManager.default.removeItem(at: url) }
            try writeAmbientNoiseWAV(
                to: url,
                duration: sample.duration,
                transientTimes: sample.transientTimes
            )

            let analysis = try analyzer.analyze(
                url,
                silenceThresholdDBFS: AppSettings().silenceThresholdDBFS,
                adaptsToNoiseFloor: true
            )

            XCTAssertGreaterThan(analysis.peakDBFS, -65, sample.name)
            XCTAssertFalse(analysis.containsSpeech(settings: AppSettings()), sample.name)
        }
    }

    func testWhisperAnalysisAdaptsThresholdToRecordingLevels() throws {
        let url = temporaryWAVURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeSineWAV(to: url, peakDBFS: -58)

        let analysis = try AudioActivityAnalyzer().analyze(
            url,
            silenceThresholdDBFS: -42,
            adaptsToNoiseFloor: true
        )

        XCTAssertLessThan(analysis.speechThresholdDBFS, -42)
        XCTAssertGreaterThan(analysis.activeDuration, 0.9)
    }

    func testWhisperGainIsBoundedByMaximumAndPeakHeadroom() {
        XCTAssertEqual(
            WhisperAudioNormalizer.recommendedGainDB(
                speechLevelDBFS: -60,
                peakDBFS: -58
            ),
            18,
            accuracy: 0.001
        )
        XCTAssertEqual(
            WhisperAudioNormalizer.recommendedGainDB(
                speechLevelDBFS: -30,
                peakDBFS: -3
            ),
            2,
            accuracy: 0.001
        )
        XCTAssertEqual(
            WhisperAudioNormalizer.recommendedGainDB(
                speechLevelDBFS: -18,
                peakDBFS: -2
            ),
            0,
            accuracy: 0.001
        )
    }

    func testWhisperNormalizerBoostsTemporaryCopyAndPreservesSource() throws {
        let sourceURL = temporaryWAVURL()
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        try writeSineWAV(to: sourceURL, peakDBFS: -58)

        let analyzer = AudioActivityAnalyzer()
        let sourceAnalysis = try analyzer.analyze(
            sourceURL,
            silenceThresholdDBFS: -42,
            adaptsToNoiseFloor: true
        )
        let normalizedURL = try XCTUnwrap(
            WhisperAudioNormalizer().normalizedCopy(
                of: sourceURL,
                analysis: sourceAnalysis
            )
        )
        defer { try? FileManager.default.removeItem(at: normalizedURL) }

        let normalizedAnalysis = try analyzer.analyze(
            normalizedURL,
            silenceThresholdDBFS: -42
        )
        let unchangedSourceAnalysis = try analyzer.analyze(
            sourceURL,
            silenceThresholdDBFS: -42
        )

        XCTAssertGreaterThan(normalizedAnalysis.rmsDBFS, sourceAnalysis.rmsDBFS + 17.5)
        XCTAssertEqual(unchangedSourceAnalysis.rmsDBFS, sourceAnalysis.rmsDBFS, accuracy: 0.01)
    }

    private func temporaryWAVURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
    }

    private func writeSineWAV(to url: URL, peakDBFS: Double) throws {
        let sampleRate = 16_000
        let sampleCount = sampleRate
        let amplitude = Float(pow(10, peakDBFS / 20))
        var pcmData = Data(capacity: sampleCount * 2)

        for index in 0..<sampleCount {
            let phase = Double(index) * 2 * Double.pi * 440 / Double(sampleRate)
            let sample = max(-1, min(1, Float(sin(phase)) * amplitude))
            var value = Int16(sample * Float(Int16.max)).littleEndian
            withUnsafeBytes(of: &value) { buffer in
                pcmData.append(contentsOf: buffer)
            }
        }

        var wavData = Data()
        wavData.appendASCII("RIFF")
        wavData.appendLittleEndianUInt32(UInt32(36 + pcmData.count))
        wavData.appendASCII("WAVE")
        wavData.appendASCII("fmt ")
        wavData.appendLittleEndianUInt32(16)
        wavData.appendLittleEndianUInt16(1)
        wavData.appendLittleEndianUInt16(1)
        wavData.appendLittleEndianUInt32(UInt32(sampleRate))
        wavData.appendLittleEndianUInt32(UInt32(sampleRate * 2))
        wavData.appendLittleEndianUInt16(2)
        wavData.appendLittleEndianUInt16(16)
        wavData.appendASCII("data")
        wavData.appendLittleEndianUInt32(UInt32(pcmData.count))
        wavData.append(pcmData)

        try wavData.write(to: url)
    }

    private func writeAmbientNoiseWAV(
        to url: URL,
        duration: TimeInterval,
        transientTimes: [TimeInterval]
    ) throws {
        let sampleRate = 16_000
        let ambientAmplitude = Float(pow(10.0, -49.0 / 20.0))
        let transientAmplitude = Float(pow(10.0, -38.0 / 20.0))
        let sampleCount = Int((duration * Double(sampleRate)).rounded())
        var samples = (0..<sampleCount).map { index in
            let phase = Double(index) * 2 * Double.pi * 173 / Double(sampleRate)
            return Float(sin(phase)) * ambientAmplitude
        }

        for time in transientTimes {
            let index = min(sampleCount - 1, max(0, Int((time * Double(sampleRate)).rounded())))
            samples[index] = transientAmplitude
        }

        try AudioRecorder.writeWAV(samples: samples, sampleRate: sampleRate, to: url)
    }
}

final class AppLocalizerTests: XCTestCase {
    func testTextKeysLoadFromBundledLocalizationResource() {
        let url = Bundle.main.url(forResource: "Localization", withExtension: "json")
        XCTAssertNotNil(url)

        guard let url,
              let data = try? Data(contentsOf: url),
              let resource = try? JSONDecoder().decode([String: [String: String]].self, from: data) else {
            XCTFail("Localization resource could not be decoded")
            return
        }

        let languageKeys = ["en", "zh-Hans", "zh-Hant", "ja"]
        for languageKey in languageKeys {
            for key in AppTextKey.allCases {
                XCTAssertFalse(
                    resource[languageKey]?["text.\(key.rawValue)"]?.isEmpty ?? true,
                    "Missing localized text for \(languageKey).\(key.rawValue)"
                )
            }
        }
    }

    func testSettingsTextUsesSelectedLanguage() {
        XCTAssertEqual(AppLocalizer(language: .english).text(.settings), "Settings")
        XCTAssertEqual(AppLocalizer(language: .simplifiedChinese).text(.settings), "设置")
        XCTAssertEqual(AppLocalizer(language: .traditionalChinese).text(.settings), "設定")
        XCTAssertEqual(AppLocalizer(language: .japanese).text(.settings), "設定")
    }

    func testHumanCorrectionCopyUsesMacSymbolsAndConciseHierarchy() {
        for language in AppLanguage.fixedCases {
            let localizer = AppLocalizer(language: language)
            let floatingBarDetail = localizer.floatingWindowDetail()

            XCTAssertTrue(floatingBarDetail.contains("⌘"))
            XCTAssertTrue(floatingBarDetail.contains("↩"))
            XCTAssertFalse(localizer.voiceEditCommandModeDetail(.localOnly).isEmpty)
            XCTAssertFalse(localizer.voiceEditCommandModeDetail(.llmOnly).isEmpty)
        }

        let chinese = AppLocalizer(language: .simplifiedChinese)
        XCTAssertEqual(chinese.advancedVoiceEditBetaLabel(), "高级修改 · BETA")
        XCTAssertEqual(chinese.voiceEditCommandModeName(.llmOnly), "云端 AI")
        XCTAssertEqual(chinese.correctionLearningLabel(), "人工纠正学习")
        XCTAssertEqual(chinese.correctionDataLabel(), "学习记录")
        XCTAssertEqual(chinese.adaptiveRecognitionModeTitle(.highConfidenceReplacement), "替换")
        XCTAssertEqual(chinese.adaptiveRecognitionModeTitle(.vocabularyHints), "云端 AI")
        XCTAssertEqual(
            AppLocalizer(language: .english).voiceEditCommandModeName(.llmOnly),
            "Cloud AI"
        )
        XCTAssertFalse(chinese.text(.modifyPreviousCommandHint).contains("自动模式"))
        XCTAssertFalse(chinese.text(.deletePreviousCommandHint).contains("本地规则"))
    }

    func testRecordingCueNamesUseTwoChineseCharacters() {
        for language in [AppLanguage.simplifiedChinese, .traditionalChinese] {
            let localizer = AppLocalizer(language: language)
            for sound in RecordingCueSound.allCases {
                XCTAssertEqual(
                    localizer.recordingCueSoundName(sound).count,
                    2,
                    "Unexpected cue name for \(language): \(sound.rawValue)"
                )
            }
        }
    }

    func testReleasePrivacyCopyDisclosesOptionalCloudTextProcessingInEveryLanguage() {
        let requiredPrivacyTerms: [AppLanguage: [String]] = [
            .english: [
                "LLM",
                "OpenAI-compatible endpoint",
                "preferred wording (B)",
                "Model Studio's Beijing endpoint",
                "cannot be parsed safely"
            ],
            .simplifiedChinese: [
                "LLM",
                "OpenAI-compatible 接口",
                "修正后写法（B）",
                "百炼北京地域接口",
                "无法安全解析"
            ],
            .traditionalChinese: [
                "AI/LLM",
                "「人工修正學習」",
                "OpenAI 相容端點",
                "偏好寫法（B）",
                "百煉（Model Studio）的北京端點",
                "無法安全解析"
            ],
            .japanese: [
                "AI/LLM",
                "「手動修正からの学習」",
                "OpenAI互換エンドポイント",
                "推奨表記（B）",
                "Model Studioの北京エンドポイント",
                "安全に解析できない"
            ]
        ]

        for language in AppLanguage.fixedCases {
            let localizer = AppLocalizer(language: language)
            let privacy = localizer.privacyDetail()

            for term in requiredPrivacyTerms[language, default: []] {
                XCTAssertTrue(
                    privacy.contains(term),
                    "Missing privacy disclosure '\(term)' for \(language)"
                )
            }
            XCTAssertFalse(localizer.onboardingRecordingRetentionHint().isEmpty)
            XCTAssertFalse(localizer.clipboardSnapshotUnavailable().isEmpty)
            XCTAssertFalse(localizer.recoveredInterruptedRecording().isEmpty)
            XCTAssertTrue(localizer.maximumRecordingDurationReached(minutes: 10).contains("10"))
        }

        let traditionalChinese = AppLocalizer(language: .traditionalChinese).privacyDetail()
        XCTAssertFalse(traditionalChinese.contains("crash report"))
        XCTAssertFalse(traditionalChinese.contains("History"))
        XCTAssertFalse(traditionalChinese.contains("OpenAI-compatible 介面"))
        XCTAssertFalse(traditionalChinese.contains("舊復原副本"))

        let japanese = AppLocalizer(language: .japanese).privacyDetail()
        XCTAssertFalse(japanese.contains("設定先へ"))
        XCTAssertFalse(japanese.contains("古いコピー"))
    }

    func testLocalPrivacyCopyMatchesTheRuntimeCloudTextBoundary() {
        var localSettings = AppSettings()
        localSettings.provider = .local
        localSettings.transcriptRetouchEnabled = true
        localSettings.aiEmojiResolverEnabled = true
        localSettings.voiceEditCommandMode = .llmOnly

        XCTAssertFalse(CloudTextAICapabilityPolicy.isCloudTextAIAvailable(for: localSettings))
        let effectiveSettings = CloudTextAICapabilityPolicy.applying(to: localSettings)
        XCTAssertFalse(effectiveSettings.transcriptRetouchEnabled)
        XCTAssertFalse(effectiveSettings.aiEmojiResolverEnabled)
        XCTAssertEqual(effectiveSettings.voiceEditCommandMode, .localOnly)

        let staleClaims: [AppLanguage: String] = [
            .english: "even when transcription is local",
            .simplifiedChinese: "即使使用本地转写",
            .traditionalChinese: "即使使用本機轉寫",
            .japanese: "ローカル文字起こしを使用している場合でも"
        ]
        for language in AppLanguage.fixedCases {
            let privacy = AppLocalizer(language: language).privacyDetail()
            XCTAssertFalse(
                privacy.contains(staleClaims[language, default: ""]),
                "Privacy copy contradicts Local mode for \(language)"
            )
        }
    }

    func testProductIdentityLabelsCanUseTheCommunityDisplayName() {
        let english = AppLocalizer(language: .english)
        let chinese = AppLocalizer(language: .simplifiedChinese)

        XCTAssertEqual(english.aboutAppLabel(appName: "Shuo Community"), "About Shuo Community")
        XCTAssertEqual(english.openAppLabel(appName: "Shuo Community"), "Open Shuo Community")
        XCTAssertEqual(english.quitAppLabel(appName: "Shuo Community"), "Quit Shuo Community")
        XCTAssertEqual(
            english.launchAtLoginLabel(appName: "Shuo Community"),
            "Launch Shuo Community at login"
        )
        XCTAssertEqual(chinese.aboutAppLabel(appName: "Shuo Community"), "关于 Shuo Community")
        XCTAssertEqual(chinese.openAppLabel(appName: "Shuo Community"), "打开 Shuo Community")
    }

    func testUninstallCopyExplainsCompleteDataRemovalInEveryLanguage() {
        for language in AppLanguage.fixedCases {
            let detail = AppLocalizer(language: language).uninstallAndDataDetail()
            XCTAssertTrue(detail.contains(AppBuildIdentity.bundleIdentifier))
            XCTAssertTrue(detail.contains("Application Support"))
        }

        XCTAssertTrue(
            AppLocalizer(language: .english)
                .uninstallAndDataDetail()
                .contains("Launch at Login")
        )
        XCTAssertTrue(
            AppLocalizer(language: .simplifiedChinese)
                .uninstallAndDataDetail()
                .contains("登录时启动")
        )
    }

    func testReleaseNotesDescribeOnePointTwoFourAndCurrentCapabilitiesInEveryLanguage() {
        let expectedTerms: [AppLanguage: [String]] = [
            .english: [
                "at most 60 high-priority terms",
                "60 terms and 900 characters",
                "enabled individually",
                "local Replacement",
                "Cloud AI hints",
                "Adaptive Whisper Mode",
                "New in 1.2.4",
                "Groq",
                "SiliconFlow",
                "custom OpenAI-compatible endpoint support"
            ],
            .simplifiedChinese: [
                "最多保留 60 个高优先级术语",
                "总计不超过 60 个、900 字符",
                "均需单独开启",
                "本地“替换”",
                "“云端 AI”提示",
                "自适应轻声模式",
                "1.2.4 更新",
                "Groq",
                "硅基流动",
                "自定义 OpenAI-compatible 端点支持"
            ],
            .traditionalChinese: [
                "最多保留 60 個優先術語",
                "總計不超過 60 個、900 字元",
                "均需個別啟用",
                "本機「替換」",
                "「雲端 AI」提示",
                "自適應輕聲模式",
                "1.2.4 更新",
                "Groq",
                "矽基流動",
                "自訂 OpenAI 相容端點支援"
            ],
            .japanese: [
                "最大60件保存",
                "合計60件・900文字以内",
                "各パターンを個別に有効化",
                "ローカル「置換」",
                "「クラウドAI」へのヒント",
                "適応型のささやきモード",
                "1.2.4 の新機能",
                "Groq",
                "SiliconFlow",
                "カスタム OpenAI 互換エンドポイントに対応"
            ]
        ]

        for language in AppLanguage.fixedCases {
            let releaseNotes = AppLocalizer(language: language).releaseNotesDetail()

            XCTAssertEqual(
                releaseNotes.components(separatedBy: "\n• ").count - 1,
                11,
                "Unexpected release-note bullet count for \(language)"
            )
            XCTAssertTrue(releaseNotes.contains("Beta") || releaseNotes.contains("ベータ版"))
            for term in expectedTerms[language, default: []] {
                XCTAssertTrue(
                    releaseNotes.contains(term),
                    "Missing release-note term '\(term)' for \(language)"
                )
            }
        }

        let traditionalChinese = AppLocalizer(language: .traditionalChinese).releaseNotesDetail()
        XCTAssertFalse(traditionalChinese.contains("OpenAI-compatible"))
        XCTAssertFalse(traditionalChinese.contains("Beta profile"))
        XCTAssertFalse(traditionalChinese.contains("Whisper Mode"))
        XCTAssertFalse(traditionalChinese.contains("面向"))

        let japanese = AppLocalizer(language: .japanese).releaseNotesDetail()
        XCTAssertFalse(japanese.contains("現在のリリース"))
        XCTAssertFalse(japanese.contains("任意のフローティングウインドウ"))
        XCTAssertFalse(japanese.contains("Whisper Mode"))
        XCTAssertFalse(japanese.contains("として保持"))
    }

    func testCloudOnboardingDoesNotClaimAnEnteredKeyWasVerified() {
        let message = AppLocalizer(language: .english)
            .onboardingCloudCredentialPendingVerificationLabel()

        XCTAssertTrue(message.contains("not been verified"))
        XCTAssertTrue(message.contains("first transcription"))
    }

    func testCustomServiceVerificationWarningIsLocalized() {
        for language in AppLanguage.fixedCases {
            let message = AppLocalizer(language: language)
                .customOpenAIServiceModelTestRequired()
            XCTAssertFalse(message.isEmpty)
        }

        XCTAssertTrue(
            AppLocalizer(language: .simplifiedChinese)
                .customOpenAIServiceModelTestRequired()
                .contains("尚未测试")
        )
    }

    func testUpdateStatusMessagesUseTheSelectedLanguage() {
        let simplifiedChinese = AppLocalizer(language: .simplifiedChinese)

        XCTAssertEqual(simplifiedChinese.checkingForUpdates(), "正在检查更新…")
        XCTAssertEqual(simplifiedChinese.updateCheckFinished(), "更新检查已完成。")
        XCTAssertEqual(simplifiedChinese.updateCheckUpToDate(), "已是最新版本。")
        XCTAssertEqual(simplifiedChinese.updateCheckAlreadyInProgress(), "正在检查更新。")
    }

    func testInvalidOpenAIEndpointMessageExplainsHTTPSWithoutEchoingTheURL() {
        let message = AppLocalizer(language: .english).invalidOpenAIBaseURL(
            "http://secret.example/path?token=private"
        )

        XCTAssertTrue(message.contains("HTTPS"))
        XCTAssertTrue(message.contains("localhost"))
        XCTAssertFalse(message.contains("secret.example"))
        XCTAssertFalse(message.contains("private"))

        let malformedMessage = AppLocalizer(language: .english)
            .invalidOpenAIBaseURL("not a URL with private details")
        XCTAssertTrue(malformedMessage.contains("valid HTTPS endpoint"))
        XCTAssertFalse(malformedMessage.contains("private details"))
    }

    func testFinalResultAndChineseConversionLabelsUsePreciseWording() {
        XCTAssertEqual(
            AppLocalizer(language: .english).finalResultCongratulationsTitle(),
            "Congratulations — your final result is ready."
        )
        XCTAssertEqual(
            AppLocalizer(language: .simplifiedChinese).finalResultCongratulationsTitle(),
            "恭喜，你已抵达最终结果。"
        )
        XCTAssertEqual(
            AppLocalizer(language: .traditionalChinese).finalResultCongratulationsTitle(),
            "恭喜，你已抵達最終結果。"
        )
        XCTAssertEqual(
            AppLocalizer(language: .simplifiedChinese).enableChineseConversionLabel(),
            "启用简繁字形转换"
        )
        XCTAssertEqual(
            AppLocalizer(language: .traditionalChinese).enableChineseConversionLabel(),
            "啟用簡繁字形轉換"
        )
    }

    func testSpanishAndFrenchTranscriptionLabelsAreLocalized() {
        let english = AppLocalizer(language: .english)
        XCTAssertEqual(english.languageHintName(.spanish), "Spanish")
        XCTAssertEqual(english.languageHintName(.french), "French")
        XCTAssertEqual(english.transcriptionLanguageName(.spanish), "Spanish")
        XCTAssertEqual(english.transcriptionLanguageName(.french), "French")
        XCTAssertEqual(english.metricsLanguageName(.spanish), "Spanish")
        XCTAssertEqual(english.metricsLanguageName(.french), "French")

        let chinese = AppLocalizer(language: .simplifiedChinese)
        XCTAssertEqual(chinese.transcriptionLanguageName(.spanish), "西班牙语")
        XCTAssertEqual(chinese.transcriptionLanguageName(.french), "法语")
    }

    func testPostProcessingTextUsesSelectedLanguage() {
        XCTAssertEqual(AppLocalizer(language: .english).text(.promptContext), "Prompt Context")
        XCTAssertEqual(AppLocalizer(language: .simplifiedChinese).text(.promptContext), "提示上下文")
        XCTAssertEqual(AppLocalizer(language: .traditionalChinese).text(.promptContext), "提示上下文")
        XCTAssertEqual(AppLocalizer(language: .japanese).text(.promptContext), "プロンプトコンテキスト")
    }

    func testNavigationLabelsUseTaskLanguage() {
        let english = AppLocalizer(language: .english)
        XCTAssertEqual(english.homeLabel(), "Home")
        XCTAssertEqual(english.voiceInputLabel(), "Settings")
        XCTAssertEqual(english.textOutputLabel(), "Text Output")
        XCTAssertEqual(english.aiAndCommandsLabel(), "AI & Commands")
        XCTAssertEqual(english.audioNavigationLabel(), "Audio")
        XCTAssertEqual(english.metricsLabel(), "Metrics")
        XCTAssertEqual(english.systemLabel(), "System")
        XCTAssertEqual(english.architectureLabel(), "Architecture")
        XCTAssertEqual(english.floatingWindowLabel(), "Floating Bar")
        XCTAssertEqual(english.homeShortcutInstructionPrefix(), "Hold")
        XCTAssertEqual(english.homeShortcutInstructionSuffix(), "to dictate.")

        let chinese = AppLocalizer(language: .simplifiedChinese)
        XCTAssertEqual(chinese.homeLabel(), "首页")
        XCTAssertEqual(chinese.voiceInputLabel(), "设置")
        XCTAssertEqual(chinese.textOutputLabel(), "文本输出")
        XCTAssertEqual(chinese.aiAndCommandsLabel(), "AI 与命令")
        XCTAssertEqual(chinese.audioNavigationLabel(), "音频")
        XCTAssertEqual(chinese.metricsLabel(), "统计")
        XCTAssertEqual(chinese.systemLabel(), "系统")
        XCTAssertEqual(chinese.architectureLabel(), "架构")
        XCTAssertEqual(chinese.architectureStageTitle(.contextPreparation), "上下文")
        XCTAssertEqual(chinese.textOutputNavigationLabel(), "输出")
        XCTAssertEqual(chinese.floatingWindowLabel(), "悬浮栏")
        XCTAssertEqual(chinese.floatingWindowTranscriptHint(), "点击转写内容直接修改")
        XCTAssertEqual(chinese.homeShortcutInstructionPrefix(), "按住")
        XCTAssertEqual(chinese.homeShortcutInstructionSuffix(), "开始听写。")
    }

    func testSettingsNavigationLabelUsesSelectedLanguage() {
        let expected: [(AppLanguage, String)] = [
            (.english, "Settings"),
            (.simplifiedChinese, "设置"),
            (.traditionalChinese, "設定"),
            (.japanese, "設定")
        ]

        for (language, title) in expected {
            XCTAssertEqual(AppLocalizer(language: language).voiceInputLabel(), title)
        }
    }

    func testAdvancedOverviewUsesLocalizedOperationalCopy() {
        let expected: [(AppLanguage, String)] = [
            (.english, "How Shuo processes a recording"),
            (.simplifiedChinese, "Shuo 如何处理一段录音"),
            (.traditionalChinese, "Shuo 如何處理一段錄音"),
            (.japanese, "Shuoが録音を処理する流れ")
        ]

        for (language, overviewTitle) in expected {
            let localizer = AppLocalizer(language: language)
            XCTAssertEqual(localizer.advancedOverviewTitle(), overviewTitle)
            XCTAssertFalse(localizer.advancedOverviewDetail().isEmpty)
            XCTAssertFalse(localizer.settingsSearchPlaceholder().isEmpty)
        }
    }

    func testOnboardingUsesAnExplicitTranscriptionLanguageLabel() {
        let expected: [(AppLanguage, String)] = [
            (.english, "Default transcription languages"),
            (.simplifiedChinese, "默认转写语言"),
            (.traditionalChinese, "預設轉寫語言"),
            (.japanese, "既定の文字起こし言語")
        ]

        for (language, label) in expected {
            XCTAssertEqual(AppLocalizer(language: language).onboardingLanguageLabel(), label)
        }
    }

    func testSettingsSearchTextUsesSelectedLanguage() {
        let expectedText: [(AppLanguage, String, String)] = [
            (.english, "Search settings", "No matching settings"),
            (.simplifiedChinese, "搜索设置", "没有匹配的设置"),
            (.traditionalChinese, "搜尋設定", "沒有符合的設定"),
            (.japanese, "設定を検索", "一致する設定はありません")
        ]

        for (language, placeholder, noResults) in expectedText {
            let localizer = AppLocalizer(language: language)
            XCTAssertEqual(localizer.settingsSearchPlaceholder(), placeholder)
            XCTAssertEqual(localizer.settingsSearchNoResults(), noResults)
        }
    }

    func testArchitectureContextAndOutputNavigationUseSelectedLanguage() {
        let expected: [(AppLanguage, String, String)] = [
            (.english, "Context", "Output"),
            (.simplifiedChinese, "上下文", "输出"),
            (.traditionalChinese, "上下文", "輸出"),
            (.japanese, "コンテキスト", "出力")
        ]

        for (language, context, output) in expected {
            let localizer = AppLocalizer(language: language)
            XCTAssertEqual(
                localizer.architectureStageTitle(.contextPreparation),
                context
            )
            XCTAssertEqual(localizer.textOutputNavigationLabel(), output)
        }
    }

    func testCompactMenuActionLabelsUseAtMostTwoChineseCharacters() {
        for language in [AppLanguage.simplifiedChinese, .traditionalChinese] {
            let localizer = AppLocalizer(language: language)
            let labels = [
                localizer.compactCopyLabel(),
                localizer.compactReplaceLabel(),
                localizer.compactPlayLabel(),
                localizer.compactStopLabel(),
                localizer.compactRetranscribeLabel()
            ]

            XCTAssertTrue(
                labels.allSatisfy { $0.count <= 2 },
                "Compact labels must stay within two characters: \(labels)"
            )
        }
    }
}

final class AppPanelSectionTests: XCTestCase {
    func testSidebarNavigationKeepsCorePagesAndUsesArchitectureAsAdvancedEntry() {
        XCTAssertEqual(
            AppPanelSection.sidebarNavigationOrder,
            [.general, .transcription, .history, .metrics, .architecture]
        )
        XCTAssertFalse(AppPanelSection.advanced.isVisible(pluginConfiguration: .mvp))
        XCTAssertEqual(AppPanelSection.advanced.legacyNavigationDestination, .about)
    }

    func testArchitectureUsesAdvancedAsItsPageAndSidebarLabel() {
        let expected: [(AppLanguage, String)] = [
            (.english, "Advanced"),
            (.simplifiedChinese, "高级"),
            (.traditionalChinese, "進階"),
            (.japanese, "詳細設定")
        ]

        for (language, title) in expected {
            let localizer = AppLocalizer(language: language)
            XCTAssertEqual(
                AppPanelSection.architecture.sidebarTitle(
                    localizer: localizer
                ),
                title
            )
            XCTAssertEqual(
                AppPanelSection.architecture.title(localizer: localizer),
                title
            )
        }
    }

    func testAdvancedPagesRemainAvailableAsFeatureEnableSurfaces() {
        let configuration = PluginConfiguration(
            profile: "test",
            enabledPlugins: [.smartPreferredTerms]
        )

        XCTAssertTrue(AppPanelSection.vocabulary.isVisible(pluginConfiguration: configuration))
        XCTAssertTrue(AppPanelSection.postProcessing.isVisible(pluginConfiguration: configuration))
        XCTAssertTrue(AppPanelSection.aiAndLLM.isVisible(pluginConfiguration: configuration))
        XCTAssertTrue(AppPanelSection.audio.isVisible(pluginConfiguration: configuration))
        XCTAssertTrue(AppPanelSection.architecture.isVisible(pluginConfiguration: configuration))
    }

    func testOutputFeaturesExposeTextOutput() {
        for plugin in [PluginID.outputCleanup, .outputCustomCorrections] {
            let configuration = PluginConfiguration(
                profile: "test",
                enabledPlugins: [plugin]
            )

            XCTAssertTrue(AppPanelSection.postProcessing.isVisible(pluginConfiguration: configuration))
        }
    }

    func testVocabularyRemainsAvailableForExplicitAndProjectTerms() {
        XCTAssertTrue(AppPanelSection.vocabulary.isVisible(pluginConfiguration: .mvp))
    }
}

final class ArchitectureStageTests: XCTestCase {
    func testAdvancedSidebarOpensTheUnselectedOverview() {
        XCTAssertEqual(
            AppPanelSection.architecture.defaultNavigationTarget,
            .architectureOverview
        )
        XCTAssertNil(AppPanelSection.general.defaultNavigationTarget)
    }

    func testArchitectureStartsAsAnUnselectedOverview() {
        let state = ArchitectureNavigationState()

        XCTAssertNil(state.selectedStage)
        XCTAssertFalse(state.usesCompactNavigation)
    }

    func testSelectingAStageCompactsNavigationAndSecondSelectionReturnsToOverview() {
        var state = ArchitectureNavigationState()

        state.toggle(.contextPreparation)
        XCTAssertEqual(state.selectedStage, .contextPreparation)
        XCTAssertTrue(state.usesCompactNavigation)

        state.toggle(.contextPreparation)
        XCTAssertNil(state.selectedStage)
        XCTAssertFalse(state.usesCompactNavigation)
    }

    func testSearchNavigationOpensAStageWithoutTogglingItClosed() {
        var state = ArchitectureNavigationState(selectedStage: .aiInference)

        state.open(.aiInference)
        XCTAssertEqual(state.selectedStage, .aiInference)

        state.showOverview()
        XCTAssertNil(state.selectedStage)
    }

    func testSelectedStageNavigationUsesLessVerticalSpace() {
        XCTAssertLessThan(
            ArchitectureLayout.compactNavigationHeight,
            ArchitectureLayout.overviewNavigationHeight
        )
        XCTAssertLessThan(
            ArchitectureLayout.compactNodeHeight,
            ArchitectureLayout.overviewNodeHeight
        )
    }

    func testAdvancedPageUsesAFastContentFade() {
        XCTAssertGreaterThanOrEqual(ArchitectureLayout.contentFadeDuration, 0.12)
        XCTAssertLessThanOrEqual(ArchitectureLayout.contentFadeDuration, 0.16)
    }

    func testSignalChainFitsTheStandardPanelWithoutHorizontalScrolling() {
        XCTAssertLessThanOrEqual(ArchitectureLayout.minimumSignalChainWidth, 779)
    }

    func testSignalChainContainsTheSevenOrderedStages() {
        XCTAssertEqual(
            ArchitectureStage.allCases,
            [
                .voiceInput,
                .audioProcessing,
                .contextPreparation,
                .aiInference,
                .postProcessing,
                .humanCorrection,
                .finalResult
            ]
        )
    }

    func testContextStageStaysInsideArchitectureSettings() {
        XCTAssertEqual(
            ArchitectureStage.contextPreparation.destination(pluginConfiguration: .mvp),
            ArchitectureDestination(section: .architecture, target: .manualTerms)
        )
        XCTAssertEqual(
            ArchitectureStage.contextPreparation.destination(pluginConfiguration: .fullDevelopment),
            ArchitectureDestination(section: .architecture, target: .manualTerms)
        )
    }

    func testEveryStageTargetsAConcreteControlOnTheArchitecturePage() {
        for stage in ArchitectureStage.allCases where stage != .finalResult {
            let destination = stage.destination(pluginConfiguration: .fullDevelopment)
            XCTAssertEqual(destination.section, .architecture)
            let target = try? XCTUnwrap(destination.target)
            XCTAssertEqual(target?.pipelinePlacement?.stage, stage)
        }

        XCTAssertEqual(
            ArchitectureStage.finalResult.destination(pluginConfiguration: .fullDevelopment),
            ArchitectureDestination(section: .architecture, target: nil)
        )
    }

    func testMVPStageTargetsAllPointToIndexedVisibleControls() {
        let indexedTargets = Set(
            SettingsSearchIndex.items(
                localizer: AppLocalizer(language: .english),
                context: SettingsSearchContext(
                    provider: .local,
                    pluginConfiguration: .mvp
                )
            )
            .map(\.target)
        )

        for stage in ArchitectureStage.allCases where stage != .finalResult {
            guard let target = stage.destination(pluginConfiguration: .mvp).target else {
                XCTFail("\(stage) has no settings destination")
                continue
            }
            XCTAssertTrue(indexedTargets.contains(target))
        }
    }

    func testEveryPipelineSettingHasExactlyOneStageAndSearchAvoidsHiddenPages() {
        let placements = SettingsSearchTarget.allCases.compactMap(\.pipelinePlacement)
        XCTAssertEqual(
            Set(placements.map(\.stage)),
            Set(SettingsPipelineStage.allCases.filter { $0 != .finalResult })
        )

        let intentionallyOutsidePipeline: Set<SettingsSearchTarget> = [
            .appLanguage,
            .showDockIcon,
            .launchAtLogin,
            .updates,
            .exportSettings,
            .architectureOverview,
            .microphonePermission,
            .accessibilityPermission,
            .aboutInformation,
            .reportFeedback,
            .privacy,
            .releaseNotes,
            .uninstallAndData,
            .localData
        ]
        XCTAssertEqual(
            Set(SettingsSearchTarget.allCases.filter { $0.pipelinePlacement == nil }),
            intentionallyOutsidePipeline
        )

        let items = SettingsSearchIndex.items(
            localizer: AppLocalizer(language: .english),
            context: SettingsSearchContext(
                provider: .local,
                pluginConfiguration: .fullDevelopment
            )
        )
        let hiddenSections: Set<AppPanelSection> = [.audio, .vocabulary, .aiAndLLM, .postProcessing]
        XCTAssertTrue(items.allSatisfy { !hiddenSections.contains($0.section) })

        for item in items {
            guard let placement = item.target.pipelinePlacement else {
                continue
            }
            XCTAssertEqual(
                item.section,
                placement.appearsInBasicSettings ? .transcription : .architecture
            )
        }
    }
}

final class HistorySelectionResolverTests: XCTestCase {
    func testDeletingMiddleHistoryItemSelectsNextItem() {
        let first = historyItem(text: "first")
        let second = historyItem(text: "second")
        let third = historyItem(text: "third")

        XCTAssertEqual(
            HistorySelectionResolver.nextSelectionAfterDeleting(
                id: second.id,
                from: [first, second, third]
            ),
            third.id
        )
    }

    func testDeletingLastHistoryItemSelectsPreviousItem() {
        let first = historyItem(text: "first")
        let second = historyItem(text: "second")

        XCTAssertEqual(
            HistorySelectionResolver.nextSelectionAfterDeleting(
                id: second.id,
                from: [first, second]
            ),
            first.id
        )
    }

    func testDeletingOnlyHistoryItemClearsSelection() {
        let item = historyItem(text: "only")

        XCTAssertNil(
            HistorySelectionResolver.nextSelectionAfterDeleting(
                id: item.id,
                from: [item]
            )
        )
    }

    func testDeletingMultipleItemsSelectsNextSurvivingItem() {
        let first = historyItem(text: "first")
        let second = historyItem(text: "second")
        let third = historyItem(text: "third")
        let fourth = historyItem(text: "fourth")

        XCTAssertEqual(
            HistorySelectionResolver.nextSelectionAfterDeleting(
                ids: Set([second.id, third.id]),
                currentSelection: second.id,
                from: [first, second, third, fourth]
            ),
            fourth.id
        )
    }

    func testDeletingUnselectedItemsPreservesCurrentSelection() {
        let first = historyItem(text: "first")
        let second = historyItem(text: "second")
        let third = historyItem(text: "third")

        XCTAssertEqual(
            HistorySelectionResolver.nextSelectionAfterDeleting(
                ids: Set([first.id, third.id]),
                currentSelection: second.id,
                from: [first, second, third]
            ),
            second.id
        )
    }

    func testDeletingTrailingItemsSelectsPreviousSurvivingItem() {
        let first = historyItem(text: "first")
        let second = historyItem(text: "second")
        let third = historyItem(text: "third")

        XCTAssertEqual(
            HistorySelectionResolver.nextSelectionAfterDeleting(
                ids: Set([second.id, third.id]),
                currentSelection: third.id,
                from: [first, second, third]
            ),
            first.id
        )
    }

    private func historyItem(text: String) -> TranscriptItem {
        TranscriptItem(
            text: text,
            provider: .local,
            model: "base",
            languageHint: .mixed
        )
    }
}

final class HistoryTextEditorDocumentStateTests: XCTestCase {
    func testChangingDocumentIDResetsEditingContextEvenWhenTextIsIdentical() {
        let firstID = UUID()
        let secondID = UUID()
        let text = "相同内容 🎙️"
        var state = HistoryTextEditorDocumentState()

        let initialTransition = state.transition(to: firstID, documentText: text)
        let sameDocumentTransition = state.transition(to: firstID, documentText: text)
        let newDocumentTransition = state.transition(to: secondID, documentText: text)

        XCTAssertTrue(initialTransition.shouldResetEditingContext)
        XCTAssertEqual(initialTransition.resetCursorUTF16Offset, text.utf16.count)
        XCTAssertFalse(sameDocumentTransition.shouldResetEditingContext)
        XCTAssertNil(sameDocumentTransition.resetCursorUTF16Offset)
        XCTAssertTrue(newDocumentTransition.shouldResetEditingContext)
        XCTAssertEqual(newDocumentTransition.resetCursorUTF16Offset, text.utf16.count)
        XCTAssertEqual(state.documentID, secondID)
    }
}

final class HistoryPendingEditPolicyTests: XCTestCase {
    func testOnlyValidChangedSuccessfulEditsAreAutosaved() {
        let successful = TranscriptItem(
            text: "original",
            provider: .local,
            model: "base",
            languageHint: .mixed
        )
        let failed = TranscriptItem(
            text: "original",
            provider: .local,
            model: "base",
            languageHint: .mixed,
            outcome: .failed
        )

        XCTAssertTrue(
            HistoryPendingEditPolicy.shouldSave(item: successful, editedText: "revised")
        )
        XCTAssertFalse(
            HistoryPendingEditPolicy.shouldSave(item: successful, editedText: "original")
        )
        XCTAssertFalse(
            HistoryPendingEditPolicy.shouldSave(item: successful, editedText: "  \n")
        )
        XCTAssertFalse(
            HistoryPendingEditPolicy.shouldSave(item: failed, editedText: "revised")
        )
    }
}

final class DiagnosticsPrivacyPolicyTests: XCTestCase {
    func testHomePathsAreRedactedWithoutRedactingSimilarUsernames() {
        let homeURL = URL(fileURLWithPath: "/Users/alice", isDirectory: true)

        XCTAssertEqual(
            DiagnosticsPrivacyPolicy.redactedPath(
                URL(fileURLWithPath: "/Users/alice/Library/Application Support/Shuo"),
                homeDirectoryURL: homeURL
            ),
            "~/Library/Application Support/Shuo"
        )
        XCTAssertEqual(
            DiagnosticsPrivacyPolicy.redactedPath(
                URL(fileURLWithPath: "/Users/alice2/Library/Shuo"),
                homeDirectoryURL: homeURL
            ),
            "/Users/alice2/Library/Shuo"
        )
    }

    func testUSBTransportHasAReadableDiagnosticName() {
        XCTAssertEqual(
            AudioInputDeviceCatalog.transportDescription(
                for: Int32(bitPattern: kAudioDeviceTransportTypeUSB)
            ),
            "USB"
        )
    }

    func testAudioInputSummaryIncludesRedactedRouteDetails() {
        let diagnostics = AudioInputDiagnostics(
            selection: .custom,
            resolvedDevice: AudioInputDeviceDiagnostics(
                transport: "USB",
                isConnected: true
            ),
            availableDeviceCount: 3
        )

        let summary = DiagnosticsPrivacyPolicy.audioInputSelection(diagnostics)

        XCTAssertEqual(
            summary,
            "Custom (identifier omitted); resolved: yes; transport: USB; connected: yes; available inputs: 3"
        )
    }

    func testAudioInputSummaryExplainsAnUnavailableCustomDevice() {
        let diagnostics = AudioInputDiagnostics(
            selection: .custom,
            resolvedDevice: nil,
            availableDeviceCount: 2
        )

        XCTAssertEqual(
            DiagnosticsPrivacyPolicy.audioInputSelection(diagnostics),
            "Custom (identifier omitted); resolved: no; available inputs: 2"
        )
    }

    func testAudioInputSummaryNeverContainsTheDeviceIdentifierOrName() {
        let diagnostics = AudioInputDiagnostics(
            selection: .systemDefault,
            resolvedDevice: AudioInputDeviceDiagnostics(
                transport: "Built-in",
                isConnected: true
            ),
            availableDeviceCount: 1
        )
        let summary = DiagnosticsPrivacyPolicy.audioInputSelection(diagnostics)

        XCTAssertEqual(
            summary,
            "System Default; resolved: yes; transport: Built-in; connected: yes; available inputs: 1"
        )
        XCTAssertFalse(summary.contains("private-hardware-identifier"))
        XCTAssertFalse(summary.contains("Alice's USB Microphone"))
    }
}

final class HistoryComparisonBaselineTests: XCTestCase {
    func testInitialOutputTakesPriorityOverRawTranscript() {
        XCTAssertEqual(
            HistoryComparisonBaseline.resolve(
                rawText: "raw transcript",
                initialText: "initial output",
                itemText: "corrected output"
            ),
            HistoryComparisonBaseline(text: "initial output", kind: .initialOutput)
        )
    }

    func testRawTranscriptIsUsedWhenThereIsNoInitialOutput() {
        XCTAssertEqual(
            HistoryComparisonBaseline.resolve(
                rawText: "raw transcript",
                initialText: nil,
                itemText: "final output"
            ),
            HistoryComparisonBaseline(text: "raw transcript", kind: .rawTranscript)
        )
    }

    func testPersistedOutputIsFallbackWhenNoEarlierBaselineExists() {
        XCTAssertEqual(
            HistoryComparisonBaseline.resolve(
                rawText: "",
                initialText: nil,
                itemText: "final output"
            ),
            HistoryComparisonBaseline(text: "final output", kind: .rawTranscript)
        )
    }
}

final class TranscriptTextDiffTests: XCTestCase {
    func testPurePunctuationHighlightUsesPunctuationSemantic() {
        XCTAssertEqual(
            TranscriptTextDiff.highlightRuns(in: "，。！？—…"),
            [.init(text: "，。！？—…", contentKind: .punctuation)]
        )
    }

    func testMixedTextAndPunctuationSplitsSemanticRuns() {
        XCTAssertEqual(
            TranscriptTextDiff.highlightRuns(in: "Shuo，你好!"),
            [
                .init(text: "Shuo", contentKind: .text),
                .init(text: "，", contentKind: .punctuation),
                .init(text: "你好", contentKind: .text),
                .init(text: "!", contentKind: .punctuation)
            ]
        )
    }

    func testCJKPunctuationIsSeparatedWhileEmojiRemainsText() {
        XCTAssertEqual(
            TranscriptTextDiff.highlightRuns(in: "「你好」🎙️—OK…"),
            [
                .init(text: "「", contentKind: .punctuation),
                .init(text: "你好", contentKind: .text),
                .init(text: "」", contentKind: .punctuation),
                .init(text: "🎙️", contentKind: .text),
                .init(text: "—", contentKind: .punctuation),
                .init(text: "OK", contentKind: .text),
                .init(text: "…", contentKind: .punctuation)
            ]
        )
    }

    func testMixedChineseAndEnglishCorrectionOnlyMarksChangedWord() {
        let diff = TranscriptTextDiff.compare(
            original: "我想用 codec 修复这个 bug。",
            final: "我想用 Codex 修复这个 bug。"
        )

        XCTAssertEqual(changedText(in: diff.originalSegments, kind: .removed), "codec")
        XCTAssertEqual(changedText(in: diff.finalSegments, kind: .added), "Codex")
        XCTAssertEqual(reconstructedText(diff.originalSegments), "我想用 codec 修复这个 bug。")
        XCTAssertEqual(reconstructedText(diff.finalSegments), "我想用 Codex 修复这个 bug。")
    }

    func testChineseReplacementStaysLocalWithoutWhitespaceBoundaries() {
        let diff = TranscriptTextDiff.compare(
            original: "项目里的编解码器需要更新",
            final: "项目里的 Codex 需要更新"
        )

        XCTAssertEqual(changedText(in: diff.originalSegments, kind: .removed), "编解码器")
        XCTAssertEqual(changedText(in: diff.finalSegments, kind: .added), " Codex ")
        XCTAssertTrue(diff.hasChanges)
    }

    func testIdenticalTextHasNoHighlights() {
        let text = "Shuo 支持 English、中文和 emoji 🎙️。"
        let diff = TranscriptTextDiff.compare(original: text, final: text)

        XCTAssertFalse(diff.hasChanges)
        XCTAssertEqual(diff.originalSegments, [.init(text: text, kind: .unchanged)])
        XCTAssertEqual(diff.finalSegments, [.init(text: text, kind: .unchanged)])
    }

    func testSeveralDistantEditsRemainLocal() {
        let diff = TranscriptTextDiff.compare(
            original: "OpenAI 模型在 terminal 里输出旧结果。",
            final: "OpenAI 模型在 Ghostty 里输出新结果。"
        )

        XCTAssertEqual(
            changedText(in: diff.originalSegments, kind: .removed),
            "terminal旧"
        )
        XCTAssertEqual(
            changedText(in: diff.finalSegments, kind: .added),
            "Ghostty新"
        )
        XCTAssertTrue(
            diff.originalSegments.contains {
                $0.kind == .unchanged && $0.text.contains("里输出")
            }
        )
    }

    func testLargeUnrelatedTextsUseBoundedFallbackAndPreserveContent() {
        let original = (0..<1_200).map { "old\($0)" }.joined(separator: " ")
        let final = (0..<1_200).map { "new\($0)" }.joined(separator: " ")

        let diff = TranscriptTextDiff.compare(original: original, final: final)

        XCTAssertEqual(reconstructedText(diff.originalSegments), original)
        XCTAssertEqual(reconstructedText(diff.finalSegments), final)
        XCTAssertEqual(changedText(in: diff.originalSegments, kind: .removed), original)
        XCTAssertEqual(changedText(in: diff.finalSegments, kind: .added), final)
    }

    func testCanonicalEquivalentTextReconstructsEachNormalizationExactly() {
        let nfc = "Café résumé"
        let nfd = "Cafe\u{301} re\u{301}sume\u{301}"

        let diff = TranscriptTextDiff.compare(original: nfc, final: nfd)

        XCTAssertFalse(diff.hasChanges)
        XCTAssertEqual(reconstructedText(diff.originalSegments), nfc)
        XCTAssertEqual(reconstructedText(diff.finalSegments), nfd)
        XCTAssertNotEqual(
            Array(reconstructedText(diff.originalSegments).utf8),
            Array(reconstructedText(diff.finalSegments).utf8)
        )
    }

    func testCanonicalEquivalentPrefixAndSuffixSurviveSubsequentCorrection() {
        let original = "Café 旧版本 résumé"
        let final = "Cafe\u{301} 新版本 re\u{301}sume\u{301}"

        let diff = TranscriptTextDiff.compare(original: original, final: final)

        XCTAssertEqual(reconstructedText(diff.originalSegments), original)
        XCTAssertEqual(reconstructedText(diff.finalSegments), final)
        XCTAssertEqual(changedText(in: diff.originalSegments, kind: .removed), "旧")
        XCTAssertEqual(changedText(in: diff.finalSegments, kind: .added), "新")
    }

    private func changedText(
        in segments: [TranscriptTextDiff.Segment],
        kind: TranscriptTextDiff.SegmentKind
    ) -> String {
        segments.filter { $0.kind == kind }.map(\.text).joined()
    }

    private func reconstructedText(_ segments: [TranscriptTextDiff.Segment]) -> String {
        segments.map(\.text).joined()
    }
}

final class HistoryTrailingLineBreakMarkerPolicyTests: XCTestCase {
    func testLFProducesOneTrailingMarkerRange() {
        XCTAssertEqual(
            HistoryTrailingLineBreakMarkerPolicy.trailingLineBreakUTF16Range(in: "最终输出\n"),
            NSRange(location: 4, length: 1)
        )
    }

    func testCRLFProducesOneMarkerCoveringBothCodeUnits() {
        XCTAssertEqual(
            HistoryTrailingLineBreakMarkerPolicy.trailingLineBreakUTF16Range(in: "output\r\n"),
            NSRange(location: 6, length: 2)
        )
    }

    func testTextWithoutTrailingLineBreakHasNoMarker() {
        XCTAssertNil(
            HistoryTrailingLineBreakMarkerPolicy.trailingLineBreakUTF16Range(in: "output")
        )
    }
}

final class FloatingCorrectionSentenceEndingTests: XCTestCase {
    func testCorrectionHidesOnlyBoundaryAndTreatsManualPunctuationAsAuthoritative() {
        let session = FloatingCorrectionSession(
            originalText: "Hello. ",
            punctuationMode: .automatic,
            boundaryMode: .smartSpace
        )

        XCTAssertEqual(session.correctionText, "Hello.")
        XCTAssertEqual(session.replacementText(for: "Updated text"), "Updated text ")
        XCTAssertEqual(session.replacementText(for: "Updated text."), "Updated text. ")
        XCTAssertEqual(session.replacementText(for: "修正结果"), "修正结果 ")
        XCTAssertEqual(session.replacementText(for: "修正结果。"), "修正结果。")
    }

    func testCorrectionReappliesNewlineWithoutRestoringRemovedPunctuation() {
        let session = FloatingCorrectionSession(
            originalText: "Hello.\n",
            punctuationMode: .automatic,
            boundaryMode: .newline
        )

        XCTAssertEqual(session.correctionText, "Hello.")
        XCTAssertEqual(session.replacementText(for: "Updated"), "Updated\n")
    }

    func testAdvancedCorrectionSessionPreservesEndingSnapshot() throws {
        let id = UUID()
        let session = FloatingCorrectionSession(
            id: id,
            originalText: "Hello. ",
            punctuationMode: .automatic,
            boundaryMode: .smartSpace
        )

        let advanced = try XCTUnwrap(
            session.advancingAfterSuccessfulReplacement(
                from: "Hello. ",
                to: "Updated. "
            )
        )

        XCTAssertEqual(advanced.id, id)
        XCTAssertEqual(advanced.punctuationMode, .automatic)
        XCTAssertEqual(advanced.boundaryMode, .smartSpace)
        XCTAssertEqual(advanced.correctionText, "Updated.")
        XCTAssertEqual(advanced.replacementText(for: "Again"), "Again ")
    }
}

final class TranscriptPostProcessorTests: XCTestCase {
    func testAutomaticSentenceEndingUsesScriptAppropriatePunctuation() {
        XCTAssertEqual(
            TranscriptInsertionBoundaryPolicy.apply(
                to: "Hello",
                punctuationMode: .automatic,
                mode: .smartSpace
            ),
            "Hello. "
        )
        XCTAssertEqual(
            TranscriptInsertionBoundaryPolicy.apply(
                to: "café",
                punctuationMode: .automatic,
                mode: .smartSpace
            ),
            "café. "
        )
        XCTAssertEqual(
            TranscriptInsertionBoundaryPolicy.apply(
                to: "现在效果还不错",
                punctuationMode: .automatic,
                mode: .smartSpace
            ),
            "现在效果还不错。"
        )
        XCTAssertEqual(
            TranscriptInsertionBoundaryPolicy.apply(
                to: "これは良い",
                punctuationMode: .automatic,
                mode: .smartSpace
            ),
            "これは良い。"
        )
    }

    func testAutomaticSentenceEndingUsesCJKPunctuationForMixedCJKClause() {
        XCTAssertEqual(
            TranscriptInsertionBoundaryPolicy.apply(
                to: "这个先用 Cursor",
                punctuationMode: .automatic,
                mode: .smartSpace
            ),
            "这个先用 Cursor。"
        )
        XCTAssertEqual(
            TranscriptInsertionBoundaryPolicy.apply(
                to: "先 deploy 到 staging",
                punctuationMode: .automatic,
                mode: .smartSpace
            ),
            "先 deploy 到 staging。"
        )
        XCTAssertEqual(
            TranscriptInsertionBoundaryPolicy.apply(
                to: "版本 2",
                punctuationMode: .automatic,
                mode: .smartSpace
            ),
            "版本 2。"
        )
        XCTAssertEqual(
            TranscriptInsertionBoundaryPolicy.apply(
                to: "你好。Ship it",
                punctuationMode: .automatic,
                mode: .smartSpace
            ),
            "你好。Ship it. "
        )
    }

    func testAutomaticSentenceEndingPreservesPunctuationAndInsertsBeforeQuotes() {
        XCTAssertEqual(
            TranscriptInsertionBoundaryPolicy.apply(
                to: "Already done!",
                punctuationMode: .automatic,
                mode: .smartSpace
            ),
            "Already done! "
        )
        XCTAssertEqual(
            TranscriptInsertionBoundaryPolicy.apply(
                to: "你好！",
                punctuationMode: .automatic,
                mode: .smartSpace
            ),
            "你好！"
        )
        XCTAssertEqual(
            TranscriptInsertionBoundaryPolicy.apply(
                to: "“Hello”",
                punctuationMode: .automatic,
                mode: .smartSpace
            ),
            "“Hello.” "
        )
        XCTAssertEqual(
            TranscriptInsertionBoundaryPolicy.apply(
                to: "「你好」",
                punctuationMode: .automatic,
                mode: .smartSpace
            ),
            "「你好。」"
        )
    }

    func testAutomaticSentenceEndingPreservesExistingContinuationPunctuation() {
        let cases: [(String, String)] = [
            ("Hello,", "Hello, "),
            ("Hello:", "Hello: "),
            ("Hello;", "Hello; "),
            ("你好，", "你好，"),
            ("你好：", "你好："),
            ("これは良い、", "これは良い、")
        ]

        for (input, expected) in cases {
            XCTAssertEqual(
                TranscriptInsertionBoundaryPolicy.apply(
                    to: input,
                    punctuationMode: .automatic,
                    mode: .smartSpace
                ),
                expected
            )
        }
    }

    func testAutomaticSentenceEndingPreservesExistingTerminalPunctuation() {
        XCTAssertEqual(
            TranscriptInsertionBoundaryPolicy.apply(
                to: "Hello。",
                punctuationMode: .automatic,
                mode: .smartSpace
            ),
            "Hello。"
        )
        XCTAssertEqual(
            TranscriptInsertionBoundaryPolicy.apply(
                to: "你好.",
                punctuationMode: .automatic,
                mode: .smartSpace
            ),
            "你好."
        )
        XCTAssertEqual(
            TranscriptInsertionBoundaryPolicy.apply(
                to: "这个先用 Cursor。",
                punctuationMode: .automatic,
                mode: .smartSpace
            ),
            "这个先用 Cursor。"
        )
    }

    func testAutomaticSentenceEndingPreservesQuestionExclamationAndEllipsis() {
        let unchanged = ["Really?", "Great!", "Wait...", "等等……"]

        for text in unchanged {
            XCTAssertEqual(
                TranscriptInsertionBoundaryPolicy.apply(
                    to: text,
                    punctuationMode: .automatic,
                    mode: .none
                ),
                text
            )
        }
    }

    func testAutomaticSentenceEndingDoesNotMisreadPossessiveApostropheAsQuote() {
        XCTAssertEqual(
            TranscriptInsertionBoundaryPolicy.apply(
                to: "users'",
                punctuationMode: .automatic,
                mode: .none
            ),
            "users'"
        )
        XCTAssertEqual(
            TranscriptInsertionBoundaryPolicy.apply(
                to: "James’",
                punctuationMode: .automatic,
                mode: .none
            ),
            "James’"
        )
        XCTAssertEqual(
            TranscriptInsertionBoundaryPolicy.apply(
                to: "'Hello'",
                punctuationMode: .automatic,
                mode: .none
            ),
            "'Hello.'"
        )
    }

    func testAutomaticSentenceEndingSkipsNonSentenceSingleTokens() {
        let unchanged = [
            "42",
            "https://example.com/docs",
            "name@example.com",
            "/usr/local/bin",
            "foo_bar",
            "performTask()",
            "[foo]",
            "array[0]",
            "{\"key\": \"value\"}",
            "$HOME",
            "--help",
            "😊"
        ]

        for text in unchanged {
            XCTAssertEqual(
                TranscriptInsertionBoundaryPolicy.apply(
                    to: text,
                    punctuationMode: .automatic,
                    mode: .none
                ),
                text
            )
        }
    }

    func testAutomaticSentenceEndingSkipsConservativelyRecognizedDeveloperCommands() {
        let commands = [
            "git status",
            "$ git status",
            "git status --short",
            "swift test --filter ShuoCoreTests",
            "rg --files App"
        ]

        for command in commands {
            XCTAssertEqual(
                TranscriptInsertionBoundaryPolicy.apply(
                    to: command,
                    punctuationMode: .automatic,
                    mode: .none
                ),
                command
            )
        }

        XCTAssertEqual(
            TranscriptInsertionBoundaryPolicy.apply(
                to: "Git status is useful",
                punctuationMode: .automatic,
                mode: .none
            ),
            "Git status is useful."
        )
        XCTAssertEqual(
            TranscriptInsertionBoundaryPolicy.apply(
                to: "Make this clearer",
                punctuationMode: .automatic,
                mode: .none
            ),
            "Make this clearer."
        )
    }

    func testBoundaryNormalizationPunctuatesBeforeExactlyOneSeparator() {
        XCTAssertEqual(
            TranscriptInsertionBoundaryPolicy.apply(
                to: "Hello \n\n",
                punctuationMode: .automatic,
                mode: .newline
            ),
            "Hello.\n"
        )
        XCTAssertEqual(
            TranscriptInsertionBoundaryPolicy.apply(
                to: "你好 ",
                punctuationMode: .automatic,
                mode: .none
            ),
            "你好。"
        )
    }

    func testInsertionBoundaryAddsSpaceWhenModelOmitsTerminalPunctuation() {
        XCTAssertEqual(
            TranscriptInsertionBoundaryPolicy.apply(
                to: "现在效果还不错",
                mode: .smartSpace
            ),
            "现在效果还不错 "
        )
        XCTAssertEqual(
            TranscriptInsertionBoundaryPolicy.apply(
                to: "It works.",
                mode: .smartSpace
            ),
            "It works. "
        )
    }

    func testInsertionBoundaryDoesNotAddSpaceAfterCJKPunctuationOrNewline() {
        XCTAssertEqual(
            TranscriptInsertionBoundaryPolicy.apply(
                to: "效果不错。",
                mode: .smartSpace
            ),
            "效果不错。"
        )
        XCTAssertEqual(
            TranscriptInsertionBoundaryPolicy.apply(
                to: "效果不错\n",
                mode: .newline
            ),
            "效果不错\n"
        )
    }

    func testInsertionBoundaryCanLeaveTextUnseparated() {
        XCTAssertEqual(
            TranscriptInsertionBoundaryPolicy.apply(
                to: "No separator",
                mode: .none
            ),
            "No separator"
        )
    }

    func testWhitespaceCleanupAlwaysRunsEvenWhenLegacyFlagsAreFalse() {
        var settings = AppSettings()
        settings.collapseWhitespaceAfterTranscription = false
        settings.trimWhitespaceAfterTranscription = false

        let output = TranscriptPostProcessor().process(
            "  Shuo    keeps\tspacing tidy.  ",
            settings: settings
        )

        XCTAssertEqual(output, "Shuo keeps spacing tidy.")
    }

    func testReplaceWithSpacesOnlyReplacesChineseCommaAndPeriod() {
        var settings = AppSettings()
        settings.punctuationPostProcessingMode = .replaceWithSpaces

        let output = TranscriptPostProcessor().process(
            "Stunning jewelry's prices, today. 你好，世界。It's ok!",
            settings: settings
        )

        XCTAssertEqual(output, "Stunning jewelry's prices, today. 你好 世界 It's ok!")
    }

    func testLegacyFixedEmojiRulesAreNoLongerExecuted() throws {
        let settings = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(
                #"{"emojiPostProcessingEnabled":true,"replaceEmojiPhrasesAfterTranscription":true,"smartEmojiMatchingAfterTranscription":false,"emojiReplacementRules":"private sigil emoji => 🧿"}"#.utf8
            )
        )

        let output = TranscriptPostProcessor().process(
            "Use private sigil emoji.",
            settings: settings
        )

        XCTAssertTrue(settings.smartEmojiMatchingAfterTranscription)
        XCTAssertEqual(output, "Use private sigil emoji.")
    }

    func testLocalEmojiMatchingRunsOnlyWhenEnabled() {
        var settings = AppSettings()
        settings.emojiPostProcessingEnabled = true
        settings.smartEmojiMatchingAfterTranscription = true

        XCTAssertEqual(
            TranscriptPostProcessor().process("钢琴 emoji", settings: settings),
            "🎹"
        )

        settings.smartEmojiMatchingAfterTranscription = false
        XCTAssertEqual(
            TranscriptPostProcessor().process("钢琴 emoji", settings: settings),
            "钢琴 emoji"
        )
    }

    func testCustomCorrectionsAreCaseAndDiacriticInsensitive() {
        var settings = AppSettings()
        settings.useCustomCorrections = true
        settings.customCorrections = "cafe => cafe\nshuo => Shuo"

        let output = TranscriptPostProcessor().process(
            "I said CAFE in SHUO.",
            settings: settings
        )

        XCTAssertEqual(output, "I said cafe in Shuo.")
    }

    func testCustomCorrectionsDoNotRewriteInsideLongerASCIIWords() {
        var settings = AppSettings()
        settings.useCustomCorrections = true
        settings.customCorrections = "cat => Kat"

        let output = TranscriptPostProcessor().process(
            "cat concatenate bobcat cat.",
            settings: settings
        )

        XCTAssertEqual(output, "Kat concatenate bobcat Kat.")
    }

    func testLegacyLearnedCorrectionsAreNotApplied() {
        var settings = AppSettings()
        settings.adaptiveRecognitionEnabled = true

        let output = TranscriptPostProcessor().process(
            "jewelrys prices and notjewelrys",
            settings: settings
        )

        XCTAssertEqual(output, "jewelrys prices and notjewelrys")
    }

    func testExplicitCustomCorrectionsStillApplyWhenLegacySettingIsEnabled() {
        var settings = AppSettings()
        settings.adaptiveRecognitionEnabled = true
        settings.useCustomCorrections = true
        settings.customCorrections = "jewelrys => Jewelry's"

        let output = TranscriptPostProcessor().process(
            "jewelrys prices",
            settings: settings
        )

        XCTAssertEqual(output, "Jewelry's prices")
    }

    func testChineseConversionPreservesJapaneseClausesWhenJapaneseIsEnabled() {
        var settings = AppSettings()
        settings.selectedTranscriptionLanguages = [.chinese, .japanese]
        settings.chineseTextConversionMode = .simplified

        let output = TranscriptPostProcessor().process(
            "軟體很好。今日は図書館で勉強します。",
            settings: settings
        )

        XCTAssertEqual(output, "软体很好。今日は図書館で勉強します。")
    }
}

final class FixedReplacementDocumentTests: XCTestCase {
    func testUntouchedLegacyDocumentRoundTripsExactly() {
        let raw = "# keep this comment\r\n shuo -> Shuo \r\nlegacy text\r\nremove me => \r\n"

        let document = FixedReplacementDocument(serialized: raw)

        XCTAssertEqual(document.serialized, raw)
        XCTAssertEqual(document.rules.map(\.source), ["shuo", "remove me"])
        XCTAssertEqual(document.rules.map(\.replacement), ["Shuo", ""])
        XCTAssertEqual(document.invalidLines.map(\.raw), ["legacy text"])
    }

    func testEditingOneRulePreservesCommentsInvalidLinesAndLineEndings() throws {
        let raw = "# note\r\n shuo -> Shuo \r\nlegacy text\r\n"
        var document = FixedReplacementDocument(serialized: raw)
        let ruleID = try XCTUnwrap(document.rules.first?.id)

        document.updateRule(id: ruleID, source: "shuotype", replacement: "Shuo")

        XCTAssertEqual(
            document.serialized,
            "# note\r\nshuotype => Shuo\r\nlegacy text\r\n"
        )
    }

    func testNewRuleUsesStructuredSerializationAndCanBeRemoved() {
        var document = FixedReplacementDocument(serialized: "shuo => Shuo")
        let newRuleID = document.addRule()

        document.updateRule(
            id: newRuleID,
            source: "open ai",
            replacement: "OpenAI"
        )
        XCTAssertEqual(document.serialized, "shuo => Shuo\nopen ai => OpenAI")

        document.removeRule(id: newRuleID)
        XCTAssertEqual(document.serialized, "shuo => Shuo")
    }

    func testReplacementFirstDraftDoesNotPersistAsInvalidLegacyLine() {
        var document = FixedReplacementDocument()
        let ruleID = document.addRule()

        document.updateRule(id: ruleID, replacement: "Shuo")
        XCTAssertEqual(document.serialized, "")

        document.updateRule(id: ruleID, source: "shuo")
        XCTAssertEqual(document.serialized, "shuo => Shuo")
        XCTAssertTrue(FixedReplacementDocument(serialized: document.serialized).invalidLines.isEmpty)
    }
}

final class AdaptiveRecognitionServiceTests: XCTestCase {
    func testRecordsFullCorrectionWithoutPromotingPreference() throws {
        let historyID = UUID()
        let context = AdaptiveRecognitionFeedbackContext(
            provider: .local,
            model: "local.medium",
            languageHint: .english,
            historyID: historyID,
            audioFileName: "recording.m4a"
        )
        let updatedState = AdaptiveRecognitionService().recordFeedback(
            before: "I use shuo.",
            after: "I use Shuo.",
            source: .historyEdit,
            context: context,
            state: AdaptiveRecognitionState(),
            now: Date(timeIntervalSince1970: 1_780_000_000)
        )

        let event = try XCTUnwrap(updatedState.correctionEvents.first)

        XCTAssertEqual(event.beforeText, "I use shuo.")
        XCTAssertEqual(event.afterText, "I use Shuo.")
        XCTAssertEqual(event.historyID, historyID)
        XCTAssertEqual(event.audioFileName, "recording.m4a")
        XCTAssertTrue(updatedState.feedbackEvents.isEmpty)
        XCTAssertTrue(updatedState.learnedPreferences.isEmpty)
    }

    func testRepeatedFeedbackKeepsIndependentRawEvents() throws {
        let service = AdaptiveRecognitionService()
        let context = AdaptiveRecognitionFeedbackContext(
            provider: .local,
            model: "local.medium",
            languageHint: .english
        )
        let firstState = service.recordFeedback(
            before: "open ai",
            after: "OpenAI",
            source: .voiceEditCommand,
            context: context,
            state: AdaptiveRecognitionState()
        )
        let secondState = service.recordFeedback(
            before: "open ai",
            after: "OpenAI",
            source: .historyEdit,
            context: context,
            state: firstState
        )

        XCTAssertEqual(secondState.correctionEvents.count, 2)
        XCTAssertEqual(secondState.correctionEvents.map(\.source), [.historyEdit, .voiceEditCommand])
        XCTAssertTrue(secondState.learnedPreferences.isEmpty)
    }

    func testQuickCopyIsRetainedAsAnExplicitCorrectionSource() throws {
        let service = AdaptiveRecognitionService()
        let updatedState = service.recordFeedback(
            before: "paste board injector",
            after: "PasteboardInjector",
            source: .quickCopy,
            context: AdaptiveRecognitionFeedbackContext(
                provider: .openAI,
                model: "gpt-4o-transcribe",
                languageHint: .english
            ),
            state: AdaptiveRecognitionState()
        )

        let event = try XCTUnwrap(updatedState.correctionEvents.first)
        XCTAssertEqual(event.source, .quickCopy)
        XCTAssertEqual(event.beforeText, "paste board injector")
        XCTAssertEqual(event.afterText, "PasteboardInjector")
    }

    func testPureInsertionStillRecordsFullCorrectionData() throws {
        let state = AdaptiveRecognitionService().recordFeedback(
            before: "open the project",
            after: "open the Shuo project",
            source: .floatingCorrection,
            context: AdaptiveRecognitionFeedbackContext(
                provider: .local,
                model: "local.medium",
                languageHint: .english
            ),
            state: AdaptiveRecognitionState()
        )

        XCTAssertEqual(state.correctionEvents.first?.beforeText, "open the project")
        XCTAssertEqual(state.correctionEvents.first?.afterText, "open the Shuo project")
        XCTAssertTrue(state.learnedPreferences.isEmpty)
    }

    func testCorrectionCapturePreservesExactTextAroundAMeaningfulEdit() throws {
        let state = AdaptiveRecognitionService().recordFeedback(
            before: "  open the project\n",
            after: "  open the Shuo project\n",
            source: .floatingCorrection,
            context: AdaptiveRecognitionFeedbackContext(
                provider: .local,
                model: "local.medium",
                languageHint: .english
            ),
            state: AdaptiveRecognitionState()
        )

        XCTAssertEqual(state.correctionEvents.first?.beforeText, "  open the project\n")
        XCTAssertEqual(state.correctionEvents.first?.afterText, "  open the Shuo project\n")
    }

    func testLongCorrectionIsNotSilentlyDiscarded() {
        let before = String(repeating: "a", count: 15_000)
        let after = before + " Shuo"
        let state = AdaptiveRecognitionService().recordFeedback(
            before: before,
            after: after,
            source: .historyEdit,
            context: AdaptiveRecognitionFeedbackContext(
                provider: .local,
                model: "local.medium",
                languageHint: .mixed
            ),
            state: AdaptiveRecognitionState()
        )

        XCTAssertEqual(state.correctionEvents.first?.beforeText.count, before.count)
        XCTAssertEqual(state.correctionEvents.first?.afterText.count, after.count)
    }

    func testLegacyAdaptiveStateDecodesWithoutLosingDerivedData() throws {
        let legacyData = Data(
            #"{"feedbackEvents":[],"learnedPreferences":[{"id":"00000000-0000-0000-0000-000000000001","kind":"correction","observedText":"旧句","preferredText":"新句","confidence":0.8,"observationCount":1,"createdAt":0,"updatedAt":0,"isEnabled":true}]}"#.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let state = try decoder.decode(AdaptiveRecognitionState.self, from: legacyData)

        XCTAssertEqual(state.learnedPreferences.first?.observedText, "旧句")
        XCTAssertTrue(state.correctionEvents.isEmpty)
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(string.data(using: .ascii) ?? Data())
    }

    mutating func appendLittleEndianUInt16(_ value: UInt16) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { buffer in
            append(contentsOf: buffer)
        }
    }

    mutating func appendLittleEndianUInt32(_ value: UInt32) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { buffer in
            append(contentsOf: buffer)
        }
    }
}

@MainActor
final class TranscriptProcessingWorkflowTests: XCTestCase {
    func testProcessingReturnsRawLocalAndFinalText() async {
        var settings = AppSettings()
        settings.customCorrections = "shuo => Shuo"

        let result = await TranscriptProcessingWorkflow().process(
            " shuo ",
            settings: settings,
            apiKey: nil
        )

        XCTAssertEqual(result.rawText, "shuo")
        XCTAssertEqual(result.locallyProcessedText, "Shuo")
        XCTAssertEqual(result.text, "Shuo")
    }

    func testRetouchWithoutAPIKeyFallsBackToLocalProcessing() async {
        var settings = AppSettings()
        settings.provider = .openAI
        settings.transcriptRetouchEnabled = true
        settings.customCorrections = "jewelrys => jewelry's"

        let workflow = TranscriptProcessingWorkflow()
        let result = await workflow.process(
            "jewelrys",
            settings: settings,
            apiKey: ""
        )

        XCTAssertEqual(result.locallyProcessedText, "jewelry's")
        XCTAssertEqual(result.text, "jewelry's")
        XCTAssertNotNil(workflow.lastWarning)
    }

    func testLocalModeMasksCloudTextAIWithoutOverwritingLocalProcessing() async {
        var settings = AppSettings()
        settings.provider = .local
        settings.transcriptRetouchEnabled = true
        settings.emojiPostProcessingEnabled = true
        settings.smartEmojiMatchingAfterTranscription = false
        settings.aiEmojiResolverEnabled = true
        settings.customCorrections = "jewelrys => jewelry's"

        let workflow = TranscriptProcessingWorkflow()
        let result = await workflow.process(
            "jewelrys and unknownwidget emoji",
            settings: settings,
            apiKey: "present-but-must-not-be-used"
        )

        XCTAssertEqual(result.locallyProcessedText, "jewelry's and unknownwidget emoji")
        XCTAssertEqual(result.text, "jewelry's and unknownwidget emoji")
        XCTAssertNil(workflow.lastWarning)
    }

    func testAIEmojiDoesNotSilentlyEnableLocalNameMatching() {
        var settings = AppSettings()
        settings.provider = .openAI
        settings.emojiPostProcessingEnabled = true
        settings.smartEmojiMatchingAfterTranscription = false
        settings.aiEmojiResolverEnabled = true

        let workflow = TranscriptProcessingWorkflow()
        let result = workflow.prepare(
            "钢琴 emoji",
            settings: settings
        )

        XCTAssertEqual(result.locallyProcessedText, "钢琴 emoji")
    }
}

final class CloudTextAIServiceTests: XCTestCase {
    func testCloudTextAIServicesRejectLocalModeBeforeMakingARequest() async {
        var settings = AppSettings()
        settings.provider = .local

        do {
            _ = try await VoiceEditLLMService().rewrite(
                VoiceEditLLMRequest(
                    previousText: "before",
                    commandText: "change before to after",
                    settings: settings,
                    apiKey: "present-but-must-not-be-used"
                )
            )
            XCTFail("Voice edit must reject Local mode")
        } catch {
            assertUnavailableInLocalMode(error)
        }

        do {
            _ = try await TranscriptRetouchLLMService().retouch(
                TranscriptRetouchLLMRequest(
                    text: "before",
                    settings: settings,
                    apiKey: "present-but-must-not-be-used"
                )
            )
            XCTFail("Transcript retouch must reject Local mode")
        } catch {
            assertUnavailableInLocalMode(error)
        }

        do {
            _ = try await EmojiAIResolverService().resolve(
                phrase: "unknown widget",
                settings: settings,
                apiKey: "present-but-must-not-be-used"
            )
            XCTFail("AI emoji resolution must reject Local mode")
        } catch {
            assertUnavailableInLocalMode(error)
        }
    }

    private func assertUnavailableInLocalMode(
        _ error: Error,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let error = error as? VoiceEditLLMError else {
            return XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
        guard case .unavailableInLocalMode = error else {
            return XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

final class EmojiResolverServiceTests: XCTestCase {
    func testSingleEmojiAcceptsQuotedOrCodeFencedEmojiOnly() {
        XCTAssertEqual(EmojiResolverService.singleEmoji(from: "\"🎹\""), "🎹")
        XCTAssertEqual(EmojiResolverService.singleEmoji(from: "```text\n🎹\n```"), "🎹")
        XCTAssertNil(EmojiResolverService.singleEmoji(from: "NONE"))
        XCTAssertNil(EmojiResolverService.singleEmoji(from: "heart"))
        XCTAssertNil(EmojiResolverService.singleEmoji(from: "🎹🎹"))
    }

    func testLocalResolverUsesBundledEmojiAnnotations() {
        let output = EmojiResolverService.shared.resolveLocal(in: "钢琴 emoji")

        XCTAssertEqual(output, "🎹")
    }

    func testLocalResolverMatchesCompleteColloquialPhraseBeforeItsSuffix() {
        XCTAssertEqual(
            EmojiResolverService.shared.resolveLocal(in: "撒花表情"),
            "🎉"
        )
        XCTAssertEqual(
            EmojiResolverService.shared.resolveLocal(in: "发布成功，撒花表情"),
            "发布成功，🎉"
        )
    }

    func testLocalResolverMatchesThumbsUpColloquialisms() {
        XCTAssertEqual(
            EmojiResolverService.shared.resolveLocal(in: "赞表情"),
            "👍"
        )
        XCTAssertEqual(
            EmojiResolverService.shared.resolveLocal(in: "点赞表情"),
            "👍"
        )
    }
}

final class VoiceEditCommandParserTests: XCTestCase {
    func testParsesChineseReplacementCommand() {
        let command = VoiceEditCommandParser().parse("修改上一句，把刚才的价格改成價錢。")

        XCTAssertEqual(command?.source, "价格")
        XCTAssertEqual(command?.replacement, "價錢")
    }

    func testParsesEnglishReplacementCommand() {
        let command = VoiceEditCommandParser().parse("edit last sentence change jewelrys to jewelry's")

        XCTAssertEqual(command?.source, "jewelrys")
        XCTAssertEqual(command?.replacement, "jewelry's")
    }

    func testLooksLikeEditCommandDoesNotRequireValidReplacementBody() {
        let parser = VoiceEditCommandParser()

        XCTAssertTrue(parser.looksLikeEditCommand("fix previous sentence"))
        XCTAssertNil(parser.parse("fix previous sentence"))
        XCTAssertFalse(parser.looksLikeEditCommand("please fix this later"))
    }

    func testRecognizesDeletePreviousInsertionCommands() {
        let parser = VoiceEditCommandParser()

        XCTAssertTrue(parser.isDeletePreviousInsertionCommand("删除上一句。"))
        XCTAssertTrue(parser.isDeletePreviousInsertionCommand("刪掉上一段"))
        XCTAssertTrue(parser.isDeletePreviousInsertionCommand("delete last sentence"))
        XCTAssertTrue(parser.looksLikeEditCommand("remove previous text"))
        XCTAssertFalse(parser.isDeletePreviousInsertionCommand("delete this sentence"))
    }

    func testVoiceEditNoChangeMessageIsSpecific() {
        let message = AppLocalizer(language: .simplifiedChinese).voiceEditCommandMadeNoChange()

        XCTAssertTrue(message.contains("没有改变"))
        XCTAssertFalse(message.contains("无法应用"))
    }

    func testLocalResolverUsesWordBoundariesAndRelaxedCaseMatching() {
        let resolver = VoiceEditLocalResolver()

        XCTAssertEqual(
            resolver.replacing("cat", with: "dog", in: "concatenate the CAT"),
            "concatenate the dog"
        )
        XCTAssertEqual(
            resolver.replacing("cat", with: "dog", in: "concatenate"),
            "concatenate"
        )
    }

    func testVoiceEditResolutionUsesTheExplicitSelectedMethod() {
        let resolver = VoiceEditLocalResolver()

        XCTAssertFalse(resolver.shouldUseLocalResolution(
            mode: .llmOnly
        ))
        XCTAssertTrue(resolver.shouldUseLocalResolution(
            mode: .localOnly
        ))
    }
}

final class MetricsCalculatorTests: XCTestCase {
    func testCalculateBreaksDownLanguagesAndTokenEstimates() {
        let history = [
            TranscriptItem(
                text: "Hello world 你好",
                provider: .local,
                model: "local.medium",
                languageHint: .mixed
            ),
            TranscriptItem(
                text: "テスト日本語",
                provider: .openAI,
                model: "gpt-4o-transcribe",
                languageHint: .japanese
            )
        ]

        let metrics = MetricsCalculator().calculate(history: history)

        XCTAssertEqual(metrics.transcriptCount, 2)
        XCTAssertEqual(metrics.totalCharacters, 18)
        XCTAssertEqual(metrics.totalWords, 2)
        XCTAssertEqual(metrics.estimatedTokens, 11)
        XCTAssertEqual(metrics.metric(for: .english).characters, 10)
        XCTAssertEqual(metrics.metric(for: .english).words, 2)
        XCTAssertEqual(metrics.metric(for: .chinese).characters, 2)
        XCTAssertEqual(metrics.metric(for: .japanese).characters, 6)
    }

    func testCalculateUsesSingleLanguageHintForSpanishAndFrenchLatinText() {
        let history = [
            TranscriptItem(
                text: "Hola señor",
                provider: .openAI,
                model: "gpt-4o-transcribe",
                languageHint: .spanish
            ),
            TranscriptItem(
                text: "Très bien",
                provider: .elevenLabs,
                model: "scribe_v2",
                languageHint: .french
            )
        ]

        let metrics = MetricsCalculator().calculate(history: history)

        XCTAssertEqual(metrics.totalCharacters, 17)
        XCTAssertEqual(metrics.totalWords, 4)
        XCTAssertEqual(metrics.metric(for: .spanish).characters, 9)
        XCTAssertEqual(metrics.metric(for: .spanish).words, 2)
        XCTAssertEqual(metrics.metric(for: .french).characters, 8)
        XCTAssertEqual(metrics.metric(for: .french).words, 2)
        XCTAssertEqual(metrics.metric(for: .english).characters, 0)
    }

    func testCalculateFromMetricsRecordsSurvivesDeletedHistory() {
        let calculator = MetricsCalculator()
        let deletedHistoryItem = TranscriptItem(
            text: "Hello world",
            provider: .local,
            model: "local.medium",
            languageHint: .english
        )
        let remainingHistoryItem = TranscriptItem(
            text: "你好",
            provider: .local,
            model: "local.medium",
            languageHint: .chinese
        )
        let records = [
            calculator.record(for: deletedHistoryItem),
            calculator.record(for: remainingHistoryItem)
        ]

        let metrics = calculator.calculate(records: records)

        XCTAssertEqual(metrics.transcriptCount, 2)
        XCTAssertEqual(metrics.totalCharacters, 12)
        XCTAssertEqual(metrics.totalWords, 2)
        XCTAssertEqual(metrics.metric(for: .english).characters, 10)
        XCTAssertEqual(metrics.metric(for: .chinese).characters, 2)
    }

    func testMetricsCountersMergeMonotonically() {
        let storedCounters = MetricsCounters(
            transcriptCount: 5,
            totalCharacters: 100,
            totalWords: 20,
            estimatedTokens: 90,
            languageCounters: [
                MetricsLanguageCounter(language: .chinese, characters: 80, words: 0, estimatedTokens: 80),
                MetricsLanguageCounter(language: .english, characters: 20, words: 20, estimatedTokens: 10)
            ]
        )
        let rebuiltCounters = MetricsCounters(
            transcriptCount: 3,
            totalCharacters: 120,
            totalWords: 12,
            estimatedTokens: 110,
            languageCounters: [
                MetricsLanguageCounter(language: .chinese, characters: 70, words: 0, estimatedTokens: 70),
                MetricsLanguageCounter(language: .english, characters: 50, words: 12, estimatedTokens: 40)
            ]
        )

        let mergedCounters = storedCounters.mergedMonotonic(with: rebuiltCounters)

        XCTAssertEqual(mergedCounters.transcriptCount, 5)
        XCTAssertEqual(mergedCounters.totalCharacters, 120)
        XCTAssertEqual(mergedCounters.totalWords, 20)
        XCTAssertEqual(mergedCounters.estimatedTokens, 110)
        XCTAssertEqual(mergedCounters.transcriptMetrics.metric(for: .chinese).characters, 80)
        XCTAssertEqual(mergedCounters.transcriptMetrics.metric(for: .english).characters, 50)
    }

    func testResetCutoffFiltersCountersLanguagesAndFutureRecords() {
        let calculator = MetricsCalculator()
        let cutoff = Date(timeIntervalSince1970: 200)
        let oldItem = TranscriptItem(
            text: "你好",
            createdAt: Date(timeIntervalSince1970: 100),
            provider: .local,
            model: "local.medium",
            languageHint: .chinese
        )
        let futureItem = TranscriptItem(
            text: "future words",
            createdAt: Date(timeIntervalSince1970: 300),
            provider: .openAI,
            model: "gpt-4o-transcribe",
            languageHint: .english
        )
        let allRecords = [oldItem, futureItem].map(calculator.record(for:))

        let displayedRecords = calculator.recordsForDisplay(allRecords, cutoff: cutoff)
        let displayedCounters = calculator.counters(from: displayedRecords)

        XCTAssertEqual(displayedRecords.map(\.id), [futureItem.id])
        XCTAssertEqual(displayedCounters.totalAttempts, 1)
        XCTAssertEqual(displayedCounters.transcriptCount, 1)
        XCTAssertEqual(displayedCounters.transcriptMetrics.metric(for: .chinese).characters, 0)
        XCTAssertEqual(displayedCounters.transcriptMetrics.metric(for: .english).characters, 11)
    }

    func testResetCutoffSurvivesCounterRebuildAndNeverMovesBackwards() {
        let firstCutoff = Date(timeIntervalSince1970: 200)
        let laterCutoff = Date(timeIntervalSince1970: 300)
        let reset = MetricsCounters.empty.resettingDisplay(at: laterCutoff)

        XCTAssertEqual(reset.resettingDisplay(at: firstCutoff).displayCutoff, laterCutoff)
        XCTAssertEqual(
            reset.mergedMonotonic(with: .empty).displayCutoff,
            laterCutoff
        )
    }

    func testLegacyCountersDecodeWithoutDisplayCutoff() throws {
        let legacyCounters = MetricsCounters(
            schemaVersion: 2,
            transcriptCount: 1,
            totalCharacters: 4,
            totalWords: 1,
            estimatedTokens: 1,
            languageCounters: [
                MetricsLanguageCounter(
                    language: .english,
                    characters: 4,
                    words: 1,
                    estimatedTokens: 1
                )
            ]
        )
        let encoded = try JSONEncoder().encode(legacyCounters)
        let decoded = try JSONDecoder().decode(MetricsCounters.self, from: encoded)

        XCTAssertNil(decoded.displayCutoff)
        XCTAssertEqual(decoded.transcriptCount, 1)
    }

    func testAttemptCountersIncludeFailuresWithoutCountingTheirText() {
        let calculator = MetricsCalculator()
        let success = TranscriptItem(
            text: "hello",
            provider: .local,
            model: "local.medium",
            languageHint: .english,
            recordingDuration: 2,
            transcriptionLatency: 0.5,
            appVersion: "0.1.0",
            buildNumber: "2"
        )
        let failure = TranscriptItem(
            text: "",
            provider: .openAI,
            model: "gpt-4o-transcribe",
            languageHint: .english,
            outcome: .failed,
            errorSummary: "bad key",
            recordingDuration: 3,
            transcriptionLatency: 1.5,
            appVersion: "0.1.0",
            buildNumber: "2"
        )
        let records = [calculator.record(for: success), calculator.record(for: failure)]

        let metrics = calculator.calculate(records: records)
        let counters = calculator.counters(from: records)

        XCTAssertEqual(metrics.transcriptCount, 1)
        XCTAssertEqual(metrics.totalCharacters, 5)
        XCTAssertEqual(counters.totalAttempts, 2)
        XCTAssertEqual(counters.successfulTranscriptions, 1)
        XCTAssertEqual(counters.failedTranscriptions, 1)
        XCTAssertEqual(counters.totalRecordedSeconds, 5)
        XCTAssertEqual(counters.averageTranscriptionLatency, 1)
        XCTAssertEqual(counters.lastErrorSummary, "bad key")
        XCTAssertEqual(counters.providerModelUsage.map(\.attempts).reduce(0, +), 2)
    }

    func testCorrectedTranscriptionCountDeduplicatesHistoryAndRespectsResetCutoff() {
        let calculator = MetricsCalculator()
        let correctedHistoryID = UUID()
        let oldHistoryID = UUID()
        let events = [
            CorrectionCaptureEvent(
                createdAt: Date(timeIntervalSince1970: 220),
                source: .floatingCorrection,
                beforeText: "Shou",
                afterText: "Shuo",
                provider: .local,
                model: "local.small",
                languageHint: .english,
                historyID: correctedHistoryID
            ),
            CorrectionCaptureEvent(
                createdAt: Date(timeIntervalSince1970: 250),
                source: .historyEdit,
                beforeText: "Shuo app",
                afterText: "Shuo App",
                provider: .local,
                model: "local.small",
                languageHint: .english,
                historyID: correctedHistoryID
            ),
            CorrectionCaptureEvent(
                createdAt: Date(timeIntervalSince1970: 100),
                source: .quickCopy,
                beforeText: "old",
                afterText: "older",
                provider: .openAI,
                model: "gpt-4o-transcribe",
                languageHint: .english,
                historyID: oldHistoryID
            ),
            CorrectionCaptureEvent(
                createdAt: Date(timeIntervalSince1970: 230),
                source: .manualDraftEdit,
                beforeText: "bonjour",
                afterText: "Bonjour",
                provider: .elevenLabs,
                model: "scribe_v2",
                languageHint: .french
            ),
            CorrectionCaptureEvent(
                createdAt: Date(timeIntervalSince1970: 240),
                source: .quickCopy,
                beforeText: "same",
                afterText: " same ",
                provider: .local,
                model: "local.small",
                languageHint: .english
            )
        ]

        XCTAssertEqual(
            calculator.correctedTranscriptionCount(
                events: events,
                cutoff: Date(timeIntervalSince1970: 200)
            ),
            2
        )
        XCTAssertEqual(calculator.correctedTranscriptionCount(events: events), 3)
    }

    func testHourlyTimelineIncludesOnlyTheLastTwentyFourBuckets() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 6,
            day: 7,
            hour: 12,
            minute: 30
        )))
        let currentHour = try XCTUnwrap(calendar.dateInterval(of: .hour, for: now)?.start)
        let previousHour = try XCTUnwrap(calendar.date(byAdding: .hour, value: -1, to: currentHour))
        let oldHour = try XCTUnwrap(calendar.date(byAdding: .hour, value: -24, to: currentHour))

        let history = [
            TranscriptItem(text: "current", createdAt: now, provider: .local, model: "local.medium", languageHint: .english),
            TranscriptItem(text: "previous", createdAt: previousHour, provider: .local, model: "local.medium", languageHint: .english),
            TranscriptItem(text: "old", createdAt: oldHour, provider: .local, model: "local.medium", languageHint: .english)
        ]

        let buckets = MetricsCalculator().timeline(
            history: history,
            granularity: .hourly,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(buckets.count, 24)
        XCTAssertEqual(buckets[buckets.count - 1].startDate, currentHour)
        XCTAssertEqual(buckets[buckets.count - 1].transcriptCount, 1)
        XCTAssertEqual(buckets[buckets.count - 2].startDate, previousHour)
        XCTAssertEqual(buckets[buckets.count - 2].transcriptCount, 1)
        XCTAssertEqual(buckets.reduce(0) { $0 + $1.transcriptCount }, 2)
    }

    func testHourlyTimelineCanBeBuiltFromMetricsRecords() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 6,
            day: 7,
            hour: 12,
            minute: 30
        )))
        let currentHour = try XCTUnwrap(calendar.dateInterval(of: .hour, for: now)?.start)
        let previousHour = try XCTUnwrap(calendar.date(byAdding: .hour, value: -1, to: currentHour))
        let oldHour = try XCTUnwrap(calendar.date(byAdding: .hour, value: -24, to: currentHour))
        let calculator = MetricsCalculator()
        let records = [
            calculator.record(for: TranscriptItem(
                text: "current",
                createdAt: now,
                provider: .local,
                model: "local.medium",
                languageHint: .english
            )),
            calculator.record(for: TranscriptItem(
                text: "previous",
                createdAt: previousHour,
                provider: .local,
                model: "local.medium",
                languageHint: .english
            )),
            calculator.record(for: TranscriptItem(
                text: "old",
                createdAt: oldHour,
                provider: .local,
                model: "local.medium",
                languageHint: .english
            ))
        ]

        let buckets = calculator.timeline(
            records: records,
            granularity: .hourly,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(buckets.count, 24)
        XCTAssertEqual(buckets[buckets.count - 1].startDate, currentHour)
        XCTAssertEqual(buckets[buckets.count - 1].transcriptCount, 1)
        XCTAssertEqual(buckets[buckets.count - 2].startDate, previousHour)
        XCTAssertEqual(buckets[buckets.count - 2].transcriptCount, 1)
        XCTAssertEqual(buckets.reduce(0) { $0 + $1.transcriptCount }, 2)
    }
}

final class PluginConfigurationTests: XCTestCase {
    func testMVPProfileKeepsCoreFeaturesAndDisablesExtraFeatures() {
        let configuration = PluginConfiguration.mvp

        XCTAssertTrue(configuration.isEnabled(.providerOpenAI))
        XCTAssertTrue(configuration.isEnabled(.providerGemini))
        XCTAssertTrue(configuration.isEnabled(.providerLocalWhisper))
        XCTAssertTrue(configuration.isEnabled(.historyBasic))
        XCTAssertTrue(configuration.isEnabled(.metricsBasic))
        XCTAssertTrue(configuration.isEnabled(.quickRetranscribe))
        XCTAssertTrue(configuration.isEnabled(.outputCleanup))
        XCTAssertTrue(configuration.isEnabled(.smartPreferredTerms))

        XCTAssertTrue(configuration.isEnabled(.providerElevenLabs))
        XCTAssertTrue(configuration.isEnabled(.providerAlibaba))
        XCTAssertFalse(configuration.isEnabled(.outputEmoji))
        XCTAssertFalse(configuration.isEnabled(.outputLLMRetouch))
        XCTAssertFalse(configuration.isEnabled(.commandModifyPrevious))
        XCTAssertFalse(configuration.isEnabled(.commandDeletePrevious))
        XCTAssertFalse(configuration.isEnabled(.smartAdaptiveRecognition))
        XCTAssertTrue(configuration.isEnabled(.smartCorrectionWindow))
        XCTAssertFalse(configuration.isEnabled(.workflowMessageToVideo))
    }

    func testFullDevelopmentProfileEnablesKnownPlugins() {
        let configuration = PluginConfiguration.fullDevelopment

        for descriptor in PluginCatalog.allDescriptors {
            if descriptor.id == .workflowMessageToVideo {
                XCTAssertFalse(configuration.isEnabled(descriptor.id), descriptor.id.rawValue)
            } else {
                XCTAssertTrue(configuration.isEnabled(descriptor.id), descriptor.id.rawValue)
            }
        }
    }

    func testPublicReleaseProfileShowsAllCloudProviders() {
        let configuration = PluginConfiguration.publicRelease

        XCTAssertTrue(configuration.isEnabled(.providerLocalWhisper))
        XCTAssertTrue(configuration.isEnabled(.providerOpenAI))
        XCTAssertTrue(configuration.isEnabled(.providerGemini))
        XCTAssertTrue(configuration.isEnabled(.smartPreferredTerms))
        XCTAssertTrue(configuration.isEnabled(.providerElevenLabs))
        XCTAssertTrue(configuration.isEnabled(.providerAlibaba))
        XCTAssertFalse(configuration.isEnabled(.outputLLMRetouch))
        XCTAssertFalse(configuration.isEnabled(.smartAdaptiveRecognition))
        XCTAssertTrue(configuration.isEnabled(.smartCorrectionWindow))
        XCTAssertFalse(configuration.isEnabled(.workflowMessageToVideo))
    }

    func testDecodesPlainPluginConfigurationJSON() throws {
        let json = """
        {
          "schemaVersion": 1,
          "profile": "custom-test",
          "enabledPlugins": [
            "provider.openai",
            "history.basic",
            "metrics.basic"
          ],
          "disabledPlugins": [
            "output.emoji"
          ]
        }
        """.data(using: .utf8)!

        let configuration = try PluginConfigurationStore.configuration(from: json)

        XCTAssertEqual(configuration.profile, "custom-test")
        XCTAssertTrue(configuration.isEnabled(.providerOpenAI))
        XCTAssertFalse(configuration.isEnabled(.outputEmoji))
    }

    func testVersionOneMVPProfileMigratesPreferredTermsIntoCore() throws {
        let json = """
        {
          "schemaVersion": 1,
          "profile": "mvp",
          "enabledPlugins": [
            "provider.openai",
            "provider.localWhisper",
            "output.cleanup"
          ],
          "disabledPlugins": [
            "smart.preferredTerms"
          ]
        }
        """.data(using: .utf8)!

        let configuration = try PluginConfigurationStore.configuration(from: json)

        XCTAssertEqual(configuration.schemaVersion, PluginConfiguration.currentSchemaVersion)
        XCTAssertTrue(configuration.isEnabled(.smartPreferredTerms))
        XCTAssertTrue(configuration.isEnabled(.providerAlibaba))
        XCTAssertTrue(configuration.isEnabled(.providerGemini))
    }

    func testVersionThreePublicProfilePreservesExplicitlyDisabledProvider() throws {
        let json = """
        {
          "schemaVersion": 3,
          "profile": "public",
          "enabledPlugins": [
            "provider.openai",
            "provider.elevenLabs",
            "provider.localWhisper"
          ],
          "disabledPlugins": [
            "provider.alibaba"
          ]
        }
        """.data(using: .utf8)!

        let configuration = try PluginConfigurationStore.configuration(from: json)

        XCTAssertEqual(configuration.schemaVersion, PluginConfiguration.currentSchemaVersion)
        XCTAssertTrue(configuration.isEnabled(.providerElevenLabs))
        XCTAssertFalse(configuration.isEnabled(.providerAlibaba))
        XCTAssertTrue(configuration.isEnabled(.providerGemini))
    }

    func testExistingEnabledBetaProvidersRemainEnabledAcrossSchemaUpgrade() throws {
        let json = """
        {
          "schemaVersion": 3,
          "profile": "public",
          "enabledPlugins": [
            "provider.openai",
            "provider.elevenLabs",
            "provider.alibaba",
            "provider.localWhisper"
          ],
          "disabledPlugins": []
        }
        """.data(using: .utf8)!

        let configuration = try PluginConfigurationStore.configuration(from: json)

        XCTAssertEqual(configuration.schemaVersion, PluginConfiguration.currentSchemaVersion)
        XCTAssertTrue(configuration.isEnabled(.providerElevenLabs))
        XCTAssertTrue(configuration.isEnabled(.providerAlibaba))
        XCTAssertTrue(configuration.isEnabled(.providerGemini))
    }

    func testVersionFourConfigurationPreservesExplicitGeminiOptOut() throws {
        let json = """
        {
          "schemaVersion": 4,
          "profile": "public",
          "enabledPlugins": ["provider.openai", "provider.localWhisper"],
          "disabledPlugins": ["provider.gemini"]
        }
        """.data(using: .utf8)!

        let configuration = try PluginConfigurationStore.configuration(from: json)

        XCTAssertEqual(configuration.schemaVersion, PluginConfiguration.currentSchemaVersion)
        XCTAssertFalse(configuration.isEnabled(.providerGemini))
    }

    func testVersionFourCustomProfileDoesNotGainGeminiImplicitly() throws {
        let json = """
        {
          "schemaVersion": 4,
          "profile": "custom-team",
          "enabledPlugins": ["provider.openai", "provider.localWhisper"],
          "disabledPlugins": []
        }
        """.data(using: .utf8)!

        let configuration = try PluginConfigurationStore.configuration(from: json)

        XCTAssertEqual(configuration.schemaVersion, PluginConfiguration.currentSchemaVersion)
        XCTAssertFalse(configuration.isEnabled(.providerGemini))
    }

    func testFreshProfilePreservesAProviderSelectedByAnExistingUser() {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: PluginConfigurationStore.userDefaultsKey)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: PluginConfigurationStore.userDefaultsKey)
            } else {
                defaults.removeObject(forKey: PluginConfigurationStore.userDefaultsKey)
            }
        }

        for (provider, pluginID) in [
            (TranscriptionProvider.elevenLabs, PluginID.providerElevenLabs),
            (.alibaba, .providerAlibaba),
            (.gemini, .providerGemini)
        ] {
            defaults.removeObject(forKey: PluginConfigurationStore.userDefaultsKey)

            let configuration = PluginConfigurationStore.load(
                preservingConfiguredProvider: provider
            )

            XCTAssertTrue(configuration.isEnabled(pluginID), provider.rawValue)
            XCTAssertTrue(configuration.isEnabled(.providerLocalWhisper))
            XCTAssertTrue(configuration.isEnabled(.providerOpenAI))
        }
    }

    func testStoredProviderChoiceTakesPriorityOverSettingsCompatibilityFallback() {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: PluginConfigurationStore.userDefaultsKey)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: PluginConfigurationStore.userDefaultsKey)
            } else {
                defaults.removeObject(forKey: PluginConfigurationStore.userDefaultsKey)
            }
        }

        PluginConfigurationStore.save(.publicRelease)

        let configuration = PluginConfigurationStore.load(
            preservingConfiguredProvider: .alibaba
        )

        XCTAssertTrue(configuration.isEnabled(.providerAlibaba))
    }

    func testOptionalCloudProvidersAreMarkedAsPublicBetaCapabilities() throws {
        for pluginID in [PluginID.providerElevenLabs, .providerAlibaba, .providerGemini] {
            let descriptor = try XCTUnwrap(PluginCatalog.descriptor(for: pluginID))
            XCTAssertTrue(descriptor.isPublic)
            XCTAssertTrue(descriptor.isExperimental)
            XCTAssertFalse(descriptor.isCore)
        }
    }

    func testExportedPluginConfigurationRoundTrips() throws {
        let data = try PluginConfigurationStore.exportData(
            configuration: .mvp,
            exportedAt: Date(timeIntervalSince1970: 0)
        )

        let configuration = try PluginConfigurationStore.configuration(from: data)

        XCTAssertEqual(configuration.profile, PluginConfiguration.mvp.profile)
        XCTAssertTrue(configuration.isEnabled(.providerOpenAI))
        XCTAssertFalse(configuration.isEnabled(.outputLLMRetouch))
    }

    func testStatusItemsCoverAllDescriptors() {
        let items = PluginConfigurationStore.statusItems(for: .mvp)

        XCTAssertEqual(items.map(\.id), PluginCatalog.allDescriptors.map(\.id))
        XCTAssertTrue(items.contains { $0.id == .historyBasic && $0.isEnabled })
        XCTAssertTrue(items.contains { $0.id == .outputEmoji && !$0.isEnabled })
    }

    func testCapabilityPolicyDisablesSettingsForUnavailablePlugins() {
        var settings = AppSettings()
        settings.emojiPostProcessingEnabled = true
        settings.aiEmojiResolverEnabled = true
        settings.transcriptRetouchEnabled = true
        settings.adaptiveRecognitionEnabled = true
        settings.voiceEditCommandsEnabled = true

        let adjusted = PluginCapabilityPolicy(configuration: .mvp).applying(to: settings)

        XCTAssertFalse(adjusted.emojiPostProcessingEnabled)
        XCTAssertFalse(adjusted.aiEmojiResolverEnabled)
        XCTAssertFalse(adjusted.transcriptRetouchEnabled)
        XCTAssertFalse(adjusted.adaptiveRecognitionEnabled)
        XCTAssertFalse(adjusted.voiceEditCommandsEnabled)
    }

    func testLocalCloudTextAIMaskPreservesPersistedCloudPreferences() {
        var persisted = AppSettings()
        persisted.provider = .local
        persisted.transcriptRetouchEnabled = true
        persisted.aiEmojiResolverEnabled = true
        persisted.voiceEditCommandMode = .llmOnly

        let masked = CloudTextAICapabilityPolicy.applying(to: persisted)
        let pluginMasked = PluginCapabilityPolicy(configuration: .fullDevelopment)
            .applying(to: persisted)

        XCTAssertFalse(masked.transcriptRetouchEnabled)
        XCTAssertFalse(masked.aiEmojiResolverEnabled)
        XCTAssertEqual(masked.voiceEditCommandMode, .localOnly)
        XCTAssertEqual(pluginMasked, masked)

        XCTAssertTrue(persisted.transcriptRetouchEnabled)
        XCTAssertTrue(persisted.aiEmojiResolverEnabled)
        XCTAssertEqual(persisted.voiceEditCommandMode, .llmOnly)

        persisted.provider = .openAI
        let restoredForCloud = CloudTextAICapabilityPolicy.applying(to: persisted)

        XCTAssertTrue(restoredForCloud.transcriptRetouchEnabled)
        XCTAssertTrue(restoredForCloud.aiEmojiResolverEnabled)
        XCTAssertEqual(restoredForCloud.voiceEditCommandMode, .llmOnly)
    }

    func testCapabilityPolicyDisablesBothOutputBoundaryOptionsWithCleanup() {
        let configuration = PluginConfiguration(
            profile: "cleanup-disabled",
            enabledPlugins: [.providerLocalWhisper]
        )
        var settings = AppSettings()
        settings.appendNewlineAfterTranscription = true
        settings.appendSpaceAfterTranscription = true

        let adjusted = PluginCapabilityPolicy(configuration: configuration).applying(to: settings)

        XCTAssertFalse(adjusted.appendNewlineAfterTranscription)
        XCTAssertFalse(adjusted.appendSpaceAfterTranscription)
        XCTAssertEqual(adjusted.transcriptInsertionBoundaryMode, .none)
    }

    func testCapabilityPolicySelectsAnEnabledProviderFallback() {
        let openAIOnly = PluginConfiguration(
            profile: "openai-only",
            enabledPlugins: [.providerOpenAI]
        )
        let policy = PluginCapabilityPolicy(configuration: openAIOnly)

        XCTAssertEqual(policy.availableProvider(fallingBackFrom: .local), .openAI)
        XCTAssertTrue(policy.isTranscriptionProviderEnabled(.custom))
    }

    func testCapabilityPolicyKeepsConfiguredCustomEndpointAvailableWithoutBuiltInCloudPlugins() {
        let localOnly = PluginConfiguration(
            profile: "local-only",
            enabledPlugins: [.providerLocalWhisper]
        )
        let policy = PluginCapabilityPolicy(configuration: localOnly)
        var settings = AppSettings()
        CloudConnectionSettingsCoordinator.apply(
            .selectTranscriptionService(.custom),
            to: &settings
        )

        XCTAssertFalse(policy.isTranscriptionProviderEnabled(.openAI))
        XCTAssertTrue(settings.isCustomOpenAITranscriptionService)
        XCTAssertTrue(policy.isTranscriptionEnabled(for: settings))
    }
}

final class PerformanceBenchmarkTests: XCTestCase {
    func testPerformanceSnapshot() throws {
        let metrics = try [
            benchmarkHistorySave(),
            benchmarkMetricsSave(),
            benchmarkPostProcessing(),
            benchmarkLocalModelCatalogScan()
        ]
        let snapshot = PerformanceBenchmarkSnapshot(
            createdAt: ISO8601DateFormatter().string(from: Date()),
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            activeProcessorCount: ProcessInfo.processInfo.activeProcessorCount,
            metrics: metrics
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)

        if let outputURL = performanceOutputURL() {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: outputURL, options: .atomic)
        }

        let json = String(data: data, encoding: .utf8) ?? "{}"
        print("SHUO_PERF_METRICS_BEGIN")
        print(json)
        print("SHUO_PERF_METRICS_END")
    }

    private func benchmarkHistorySave() throws -> PerformanceBenchmarkMetric {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = TranscriptHistoryStore(baseDirectory: directory)
        var items = benchmarkTranscriptItems(count: 300)

        return try benchmark(name: "history_save_300_items", iterations: 7) {
            items[0].text = "updated \(UUID().uuidString) \(items[0].text)"
            try store.save(items)
        }
    }

    private func benchmarkMetricsSave() throws -> PerformanceBenchmarkMetric {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let calculator = MetricsCalculator()
        let records = benchmarkTranscriptItems(count: 300).map(calculator.record(for:))
        let counters = calculator.counters(from: records)
        let store = MetricsStore(baseDirectory: directory)

        return try benchmark(name: "metrics_save_300_records", iterations: 7) {
            try store.save(records: records, counters: counters)
        }
    }

    private func benchmarkPostProcessing() throws -> PerformanceBenchmarkMetric {
        let postProcessor = TranscriptPostProcessor()
        var settings = AppSettings()
        settings.useCustomCorrections = true
        settings.customCorrections = (0..<60)
            .map { "term\($0) => Term\($0)" }
            .joined(separator: "\n")
        settings.adaptiveRecognitionEnabled = true
        settings.emojiPostProcessingEnabled = true
        settings.smartEmojiMatchingAfterTranscription = true
        settings.insertSpaceBetweenChineseAndEnglish = true
        settings.chineseTextConversionMode = .simplified

        let text = (0..<24)
            .map { "term\($0 % 60) observed\($0 % 30) 心 emoji Shuo正在处理mixedEnglish中文内容。" }
            .joined(separator: " ")

        return try benchmark(name: "post_processing_rules_and_emoji", iterations: 5) {
            _ = postProcessor.process(text, settings: settings)
        }
    }

    private func benchmarkLocalModelCatalogScan() throws -> PerformanceBenchmarkMetric {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for index in 0..<350 {
            let extensionName = index.isMultiple(of: 2) ? "bin" : "txt"
            let url = directory.appendingPathComponent("file-\(index).\(extensionName)")
            try Data().write(to: url)
        }

        return try benchmark(name: "local_model_catalog_scan_350_files", iterations: 15) {
            _ = LocalWhisperModelCatalog.modelURLs(in: directory.path)
        }
    }

    private func benchmark(
        name: String,
        iterations: Int,
        warmups: Int = 2,
        operation: () throws -> Void
    ) throws -> PerformanceBenchmarkMetric {
        for _ in 0..<warmups {
            try operation()
        }

        var samples: [Double] = []
        samples.reserveCapacity(iterations)

        for _ in 0..<iterations {
            let start = DispatchTime.now().uptimeNanoseconds
            try operation()
            let end = DispatchTime.now().uptimeNanoseconds
            samples.append(Double(end - start) / 1_000_000.0)
        }

        let sorted = samples.sorted()
        let median: Double
        if sorted.count.isMultiple(of: 2) {
            median = (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        } else {
            median = sorted[sorted.count / 2]
        }

        return PerformanceBenchmarkMetric(
            name: name,
            iterations: iterations,
            medianMilliseconds: median,
            minimumMilliseconds: sorted.first ?? 0,
            maximumMilliseconds: sorted.last ?? 0
        )
    }

    private func benchmarkTranscriptItems(count: Int) -> [TranscriptItem] {
        (0..<count).map { index in
            TranscriptItem(
                text: "Benchmark transcript \(index): Shuo OpenAI SwiftUI API 你好 これはテストです \(String(repeating: "content ", count: 8))",
                createdAt: Date(timeIntervalSince1970: TimeInterval(1_780_000_000 + index)),
                provider: index.isMultiple(of: 3) ? .openAI : .local,
                model: index.isMultiple(of: 3) ? "gpt-4o-transcribe" : "local.medium",
                languageHint: .mixed
            )
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ShuoPerformance-\(UUID().uuidString)", isDirectory: true)
    }

    private func performanceOutputURL() -> URL? {
        if let outputPath = ProcessInfo.processInfo.environment["SHUO_PERF_OUTPUT"],
           !outputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: outputPath)
        }

        return FileManager.default.temporaryDirectory
            .appendingPathComponent("shuo-perf-latest.json")
    }
}

private struct PerformanceBenchmarkSnapshot: Encodable {
    let createdAt: String
    let osVersion: String
    let activeProcessorCount: Int
    let metrics: [PerformanceBenchmarkMetric]
}

private struct PerformanceBenchmarkMetric: Encodable {
    let name: String
    let iterations: Int
    let medianMilliseconds: Double
    let minimumMilliseconds: Double
    let maximumMilliseconds: Double
}

private extension TranscriptMetrics {
    func metric(for language: MetricsLanguage) -> LanguageMetrics {
        languageBreakdown.first { $0.language == language }!
    }
}
