import Foundation
import XCTest
@testable import Shuo

final class OpenAIModelCatalogTests: XCTestCase {
    func testManagedLocalModelListContainsOnlyThreeCuratedChoices() {
        XCTAssertEqual(
            LocalWhisperModelCatalog.managedModels.map(\.id),
            ["sensevoice-small-q8", "small", "large-v3-turbo-q5_0"]
        )
        XCTAssertEqual(LocalWhisperModelCatalog.featuredModels, LocalWhisperModelCatalog.managedModels)
        XCTAssertTrue(LocalWhisperModelCatalog.additionalModels.isEmpty)
        XCTAssertFalse(LocalWhisperModelCatalog.managedModels.contains { $0.id == "base" })
        XCTAssertFalse(LocalWhisperModelCatalog.managedModels.contains { $0.id == "medium" })
        XCTAssertFalse(LocalWhisperModelCatalog.managedModels.contains { $0.id == "large-v3-turbo-q8_0" })
    }

    func testLocalModelNotesAndRecommendationsExplainTheThreeChoices() throws {
        let senseVoice = try XCTUnwrap(
            LocalWhisperModelCatalog.managedModels.first { $0.id == "sensevoice-small-q8" }
        )
        let small = try XCTUnwrap(
            LocalWhisperModelCatalog.managedModels.first { $0.id == "small" }
        )
        let large = try XCTUnwrap(
            LocalWhisperModelCatalog.managedModels.first { $0.id == "large-v3-turbo-q5_0" }
        )
        let english = AppLocalizer(language: .english)
        let simplifiedChinese = AppLocalizer(language: .simplifiedChinese)

        XCTAssertEqual(
            english.localWhisperManagedModelSummary(senseVoice),
            "242 MiB · Chinese, English & Japanese"
        )
        XCTAssertTrue(english.localWhisperManagedModelNote(senseVoice).contains("unavailable"))
        XCTAssertTrue(english.localWhisperManagedModelNote(small).contains("Lightweight"))
        XCTAssertTrue(english.localWhisperManagedModelNote(large).contains("Best accuracy"))
        XCTAssertEqual(
            simplifiedChinese.localWhisperManagedModelPickerNote(large),
            "最佳准确度 · 英文 + 全部语言"
        )

        let largeEnglish = LocalWhisperModelCatalog.recommendedOnboardingModel(
            for: [.english],
            isAppleSilicon: true,
            physicalMemoryBytes: LocalWhisperModelCatalog.largeModelRecommendedMemoryBytes
        )
        XCTAssertEqual(largeEnglish.modelID, large.id)
        XCTAssertEqual(largeEnglish.reason, .englishBestAccuracy)
        XCTAssertEqual(
            english.localModelRecommendationLabel(largeEnglish),
            "Recommended for English · Best accuracy"
        )
    }

    func testWhisperLabelMakesCloudExecutionExplicit() throws {
        let whisper = try XCTUnwrap(
            OpenAIModelCatalog.transcriptionModels.first { $0.id == "whisper-1" }
        )

        XCTAssertTrue(whisper.displayName.contains("Cloud API"))
    }

    func testRecommendationUsesCuratedPriorityAndAccountAvailability() {
        XCTAssertEqual(
            OpenAIModelCatalog.recommendedTranscriptionModelID(availableModelIDs: nil),
            "gpt-4o-transcribe"
        )
        XCTAssertEqual(
            OpenAIModelCatalog.recommendedTranscriptionModelID(
                availableModelIDs: ["gpt-4o-mini-transcribe", "whisper-1"]
            ),
            "gpt-4o-mini-transcribe"
        )
        XCTAssertEqual(
            OpenAIModelCatalog.recommendedTranscriptionModelID(availableModelIDs: ["whisper-1"]),
            "whisper-1"
        )
        XCTAssertNil(
            OpenAIModelCatalog.recommendedTranscriptionModelID(availableModelIDs: ["gpt-5.4-mini"])
        )
        XCTAssertEqual(
            OpenAIModelCatalog.recommendedTextModelID(availableModelIDs: ["gpt-4.1-mini"]),
            "gpt-4.1-mini"
        )
        XCTAssertNil(
            OpenAIModelCatalog.recommendedTextModelID(availableModelIDs: ["whisper-1"])
        )
    }

    func testGroqSpeechAndTextModelsAreRecognized() {
        let modelIDs: Set<String> = [
            "whisper-large-v3-turbo",
            "whisper-large-v3",
            "openai/gpt-oss-20b"
        ]

        XCTAssertEqual(
            OpenAIModelCatalog.recommendedTranscriptionModelID(availableModelIDs: modelIDs),
            "whisper-large-v3"
        )
        XCTAssertEqual(
            OpenAIModelCatalog.recommendedTextModelID(availableModelIDs: modelIDs),
            "openai/gpt-oss-20b"
        )
    }

    func testSiliconFlowSpeechAndTextModelsAreRecognized() {
        let modelIDs: Set<String> = [
            "FunAudioLLM/SenseVoiceSmall",
            "TeleAI/TeleSpeechASR",
            "Qwen/Qwen-3-8B",
            "THUDM/GLM-4-9B-0414"
        ]

        XCTAssertEqual(
            OpenAIModelCatalog.recommendedTranscriptionModelID(availableModelIDs: modelIDs),
            "FunAudioLLM/SenseVoiceSmall"
        )
        XCTAssertEqual(
            OpenAIModelCatalog.recommendedTextModelID(availableModelIDs: modelIDs),
            "Qwen/Qwen-3-8B"
        )
    }

    func testProviderModelListIsSeparatedByShuoCapabilities() {
        let modelIDs = [
            "FunAudioLLM/SenseVoiceSmall",
            "TeleAI/TeleSpeechASR",
            "Qwen/Qwen-3-8B",
            "Qwen/Qwen3-VL-32B-Instruct",
            "BAAI/bge-large-zh-v1.5",
            "netease-youdao/bce-reranker-base_v1",
            "Kwai-Kolors/Kolors",
            "Wan-AI/Wan2.1-T2V-14B"
        ]

        XCTAssertEqual(
            modelIDs.filter(OpenAIModelCatalog.supportsTranscription),
            ["FunAudioLLM/SenseVoiceSmall", "TeleAI/TeleSpeechASR"]
        )
        XCTAssertEqual(
            modelIDs.filter(OpenAIModelCatalog.supportsTextGeneration),
            ["Qwen/Qwen-3-8B", "Qwen/Qwen3-VL-32B-Instruct"]
        )
    }

    func testCloudPresetInferenceKeepsKnownEndpointsAndNativeProvidersDistinct() {
        XCTAssertEqual(
            CloudTranscriptionPreset.inferred(
                provider: .openAI,
                openAIBaseURL: AppSettings.defaultOpenAIBaseURL
            ),
            .openAI
        )
        XCTAssertEqual(
            CloudTranscriptionPreset.inferred(
                provider: .openAI,
                openAIBaseURL: CloudTranscriptionPreset.groqBaseURL
            ),
            .groq
        )
        XCTAssertEqual(
            CloudTranscriptionPreset.inferred(
                provider: .openAI,
                openAIBaseURL: CloudTranscriptionPreset.siliconFlowBaseURL
            ),
            .siliconFlow
        )
        XCTAssertEqual(
            CloudTranscriptionPreset.inferred(
                provider: .openAI,
                openAIBaseURL: "https://example.com/v1"
            ),
            .custom
        )
        XCTAssertEqual(
            CloudTranscriptionPreset.inferred(
                provider: .gemini,
                openAIBaseURL: AppSettings.defaultOpenAIBaseURL
            ),
            .gemini
        )
    }

    func testCloudProviderConfigurationOwnsPickerMetadataAndCapabilities() {
        XCTAssertEqual(
            CloudTranscriptionProviderConfiguration.all.map(\.preset),
            CloudTranscriptionPreset.allCases
        )

        let siliconFlow = CloudTranscriptionProviderConfiguration.siliconFlow
        XCTAssertEqual(siliconFlow.backendProvider, .openAI)
        XCTAssertEqual(siliconFlow.credential, .openAICompatible)
        XCTAssertEqual(siliconFlow.endpoint.defaultURLString, "https://api.siliconflow.cn/v1")
        XCTAssertTrue(siliconFlow.supportsModelDiscovery)
        XCTAssertTrue(siliconFlow.supportsTextProcessing)

        let alibaba = CloudTranscriptionProviderConfiguration.alibaba
        XCTAssertEqual(alibaba.backendProvider, .alibaba)
        XCTAssertEqual(alibaba.fixedTranscriptionModelID, "qwen3-asr-flash")
        XCTAssertEqual(alibaba.connectionDetail, .alibabaQwen3)
        XCTAssertFalse(alibaba.supportsModelDiscovery)
        XCTAssertFalse(alibaba.supportsTextProcessing)

        XCTAssertTrue(CloudTranscriptionProviderConfiguration.custom.endpoint.isEditable)
        XCTAssertEqual(
            CloudTranscriptionProviderConfiguration.enabled { $0 == .providerOpenAI }.map(\.preset),
            [.openAI, .groq, .siliconFlow, .custom]
        )
    }

    func testAutomaticTextSelectionAppliesToEveryLLMFeature() {
        var settings = AppSettings()
        settings.fixedOpenAITextModel = "fixed-shared-model"
        settings.automaticOpenAITextModel = "gpt-4.1-mini"

        settings.openAITextModelSelectionMode = .automatic
        XCTAssertEqual(settings.effectiveVoiceEditLLMModel, "gpt-4.1-mini")
        XCTAssertEqual(settings.effectiveTranscriptRetouchLLMModel, "gpt-4.1-mini")
        XCTAssertEqual(settings.effectiveEmojiResolverLLMModel, "gpt-4.1-mini")

        settings.openAITextModelSelectionMode = .fixed
        XCTAssertEqual(settings.effectiveVoiceEditLLMModel, "fixed-shared-model")
        XCTAssertEqual(settings.effectiveTranscriptRetouchLLMModel, "fixed-shared-model")
        XCTAssertEqual(settings.effectiveEmojiResolverLLMModel, "fixed-shared-model")
    }

    func testDisabledTextSelectionClampsCloudTextFeaturesWithoutChangingPersistedPreferences() {
        var settings = AppSettings()
        settings.provider = .openAI
        settings.openAITextModelSelectionMode = .disabled
        settings.transcriptRetouchEnabled = true
        settings.aiEmojiResolverEnabled = true
        settings.voiceEditCommandMode = .llmOnly

        let runtime = CloudTextAICapabilityPolicy.applying(to: settings)

        XCTAssertFalse(CloudTextAICapabilityPolicy.isCloudTextAIAvailable(for: settings))
        XCTAssertFalse(runtime.transcriptRetouchEnabled)
        XCTAssertFalse(runtime.aiEmojiResolverEnabled)
        XCTAssertEqual(runtime.voiceEditCommandMode, .localOnly)
        XCTAssertTrue(settings.transcriptRetouchEnabled)
        XCTAssertTrue(settings.aiEmojiResolverEnabled)
        XCTAssertEqual(settings.voiceEditCommandMode, .llmOnly)
    }

    func testUnacknowledgedRelayKeepsCloudTextFeaturesLocal() {
        var settings = AppSettings()
        settings.provider = .openAI
        settings.openAIBaseURL = "https://relay.example.test/v1"
        settings.transcriptRetouchEnabled = true
        settings.aiEmojiResolverEnabled = true
        settings.voiceEditCommandMode = .llmOnly

        let runtime = CloudTextAICapabilityPolicy.applying(to: settings)

        XCTAssertFalse(settings.hasAcknowledgedOpenAICompatibleRelay)
        XCTAssertFalse(CloudTextAICapabilityPolicy.isCloudTextAIAvailable(for: settings))
        XCTAssertFalse(runtime.transcriptRetouchEnabled)
        XCTAssertFalse(runtime.aiEmojiResolverEnabled)
        XCTAssertEqual(runtime.voiceEditCommandMode, .localOnly)
    }

    func testSeparateCloudTextServiceSupportsLocalTranscription() {
        var settings = AppSettings()
        settings.provider = .local
        settings.cloudTextUsesTranscriptionService = false
        settings.cloudTextServicePreset = .groq
        settings.openAITextModelSelectionMode = .fixed
        settings.fixedOpenAITextModel = "openai/gpt-oss-20b"

        XCTAssertEqual(settings.cloudTextServiceProvider, .openAI)
        XCTAssertEqual(settings.effectiveCloudTextBaseURL, CloudTranscriptionPreset.groqBaseURL)
        XCTAssertEqual(settings.effectiveCloudTextModel, "openai/gpt-oss-20b")
        XCTAssertFalse(CloudTextAICapabilityPolicy.isCloudTextAIAvailable(for: settings))

        settings.acknowledgeCloudTextRelay()
        XCTAssertTrue(CloudTextAICapabilityPolicy.isCloudTextAIAvailable(for: settings))
        XCTAssertEqual(settings.cloudTextExecutionSettings.provider, .openAI)
        XCTAssertEqual(
            settings.cloudTextExecutionSettings.openAIBaseURL,
            CloudTranscriptionPreset.groqBaseURL
        )
    }

    func testSiliconFlowUsesItsOwnBaseURLAndCredentialScope() {
        var settings = AppSettings()
        settings.cloudTextUsesTranscriptionService = false
        settings.cloudTextServicePreset = .siliconFlow

        XCTAssertEqual(
            settings.effectiveCloudTextBaseURL,
            CloudTranscriptionPreset.siliconFlowBaseURL
        )
        XCTAssertEqual(
            OpenAICompatibleCredentialScope(
                baseURLString: CloudTranscriptionPreset.siliconFlowBaseURL
            ).credentialAccount,
            "siliconflow"
        )
    }

    func testTextServiceCanSwitchAwayFromAUnsupportedTranscriptionProvider() {
        var settings = AppSettings()
        settings.provider = .elevenLabs
        settings.cloudTextUsesTranscriptionService = true

        XCTAssertNil(settings.cloudTextServiceProvider)
        XCTAssertFalse(CloudTextAICapabilityPolicy.isCloudTextAIAvailable(for: settings))

        settings.cloudTextUsesTranscriptionService = false
        settings.cloudTextServicePreset = .gemini

        XCTAssertEqual(settings.cloudTextServiceProvider, .gemini)
        XCTAssertEqual(
            settings.effectiveCloudTextModel,
            GeminiTranscriptionService.defaultModelID
        )
        XCTAssertTrue(CloudTextAICapabilityPolicy.isCloudTextAIAvailable(for: settings))
    }

    func testSeparateCloudTextConnectionRoundTrips() throws {
        var settings = AppSettings()
        settings.cloudTextUsesTranscriptionService = false
        settings.cloudTextServicePreset = .custom
        settings.cloudTextOpenAIBaseURL = "https://relay.example.com/v1"
        settings.lastCustomCloudTextOpenAIBaseURL = settings.cloudTextOpenAIBaseURL
        settings.acknowledgeCloudTextRelay()
        settings.openAITextModelSelectionMode = .fixed
        settings.fixedOpenAITextModel = "text-model-v1"

        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: JSONEncoder().encode(settings)
        )

        XCTAssertFalse(decoded.cloudTextUsesTranscriptionService)
        XCTAssertEqual(decoded.cloudTextServicePreset, .custom)
        XCTAssertEqual(decoded.effectiveCloudTextBaseURL, "https://relay.example.com/v1")
        XCTAssertTrue(decoded.hasAcknowledgedCloudTextRelay)
        XCTAssertEqual(decoded.effectiveCloudTextModel, "text-model-v1")
    }

    func testAutomaticAndFixedTranscriptionSelectionRemainDistinct() {
        var settings = AppSettings()
        settings.provider = .openAI
        settings.automaticOpenAITranscriptionModel = "gpt-4o-mini-transcribe"
        settings.fixedOpenAITranscriptionModel = "relay-transcribe-v2"

        settings.openAITranscriptionModelSelectionMode = .automatic
        XCTAssertEqual(settings.effectiveModel, "gpt-4o-mini-transcribe")

        settings.openAITranscriptionModelSelectionMode = .fixed
        XCTAssertEqual(settings.effectiveModel, "relay-transcribe-v2")
    }

    func testLegacySettingsPreserveExplicitTranscriptionChoiceAndMigrateChatLatest() throws {
        var settings = AppSettings()
        settings.provider = .openAI
        settings.selectedModel = "gpt-4o-mini-transcribe"
        let encoded = try JSONEncoder().encode(settings)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "openAITranscriptionModelSelectionMode")
        object.removeValue(forKey: "automaticOpenAITranscriptionModel")
        object.removeValue(forKey: "fixedOpenAITranscriptionModel")
        object.removeValue(forKey: "openAITextModelSelectionMode")
        object.removeValue(forKey: "automaticOpenAITextModel")
        object.removeValue(forKey: "fixedOpenAITextModel")
        object["voiceEditLLMModel"] = "chat-latest"
        object["transcriptRetouchLLMModel"] = "chat-latest"
        object["emojiResolverLLMModel"] = "chat-latest"

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacyData)

        XCTAssertEqual(decoded.openAITranscriptionModelSelectionMode, .fixed)
        XCTAssertEqual(decoded.openAITextModelSelectionMode, .automatic)
        XCTAssertEqual(decoded.effectiveModel, "gpt-4o-mini-transcribe")
        XCTAssertEqual(decoded.fixedOpenAITranscriptionModel, "gpt-4o-mini-transcribe")
        XCTAssertEqual(decoded.fixedOpenAITextModel, OpenAIModelCatalog.defaultTextModelID)
    }

    func testCustomFixedTranscriptionModelRoundTripsWithoutCatalogNormalization() throws {
        var settings = AppSettings()
        settings.provider = .openAI
        settings.openAITranscriptionModelSelectionMode = .fixed
        settings.fixedOpenAITranscriptionModel = "company/mandarin-asr-2026"

        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: JSONEncoder().encode(settings)
        )

        XCTAssertEqual(decoded.fixedOpenAITranscriptionModel, "company/mandarin-asr-2026")
        XCTAssertEqual(decoded.effectiveModel, "company/mandarin-asr-2026")
    }

    func testFixedTranscriptionModelValidationRejectsUnsafeValues() {
        XCTAssertThrowsError(
            try OpenAIModelCatalog.validatedFixedTranscriptionModelID("  \n  ")
        ) { error in
            XCTAssertEqual(error as? OpenAITranscriptionModelIDValidationError, .empty)
        }
        XCTAssertThrowsError(
            try OpenAIModelCatalog.validatedFixedTranscriptionModelID("relay\nmodel")
        ) { error in
            XCTAssertEqual(
                error as? OpenAITranscriptionModelIDValidationError,
                .containsControlCharacter
            )
        }
        XCTAssertThrowsError(
            try OpenAIModelCatalog.validatedFixedTranscriptionModelID(
                String(repeating: "m", count: OpenAIModelCatalog.maximumTranscriptionModelIDLength + 1)
            )
        ) { error in
            XCTAssertEqual(error as? OpenAITranscriptionModelIDValidationError, .tooLong)
        }
    }

    func testLegacyExplicitTextModelIsPreservedAsFixed() throws {
        let settings = AppSettings()
        let encoded = try JSONEncoder().encode(settings)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "openAITextModelSelectionMode")
        object.removeValue(forKey: "automaticOpenAITextModel")
        object.removeValue(forKey: "fixedOpenAITextModel")
        object["voiceEditLLMModel"] = "gateway-custom-model"

        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded.openAITextModelSelectionMode, .fixed)
        XCTAssertEqual(decoded.fixedOpenAITextModel, "gateway-custom-model")
        XCTAssertEqual(decoded.effectiveVoiceEditLLMModel, "gateway-custom-model")
    }

    func testDisabledTextSelectionRoundTripsWithoutChangingTranscriptionSelection() throws {
        var settings = AppSettings()
        settings.openAITextModelSelectionMode = .disabled
        settings.openAITranscriptionModelSelectionMode = .fixed
        settings.fixedOpenAITextModel = "gateway-model"

        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: JSONEncoder().encode(settings)
        )

        XCTAssertEqual(decoded.openAITextModelSelectionMode, .disabled)
        XCTAssertEqual(decoded.openAITranscriptionModelSelectionMode, .fixed)
        XCTAssertEqual(decoded.fixedOpenAITextModel, "gateway-model")
    }

    func testUnavailableModelErrorsAreRecognizedWithoutTreatingServerErrorsAsCatalogChanges() {
        XCTAssertTrue(
            OpenAIModelCatalog.errorIndicatesUnavailableModel(
                statusCode: 404,
                message: "The model does not exist or you do not have access"
            )
        )
        XCTAssertFalse(
            OpenAIModelCatalog.errorIndicatesUnavailableModel(
                statusCode: 500,
                message: "The model service is temporarily unavailable"
            )
        )
    }
}

final class OpenAIModelAvailabilityServiceTests: XCTestCase {
    func testModelListIsCachedForOneDayAndUsesAuthenticatedAccountScope() async throws {
        let store = InMemoryOpenAIModelAvailabilityStore()
        let loader = ModelListLoader()
        let service = OpenAIModelAvailabilityService(
            store: store,
            dataLoader: { request in
                try await loader.load(request)
            }
        )
        var settings = AppSettings()
        settings.openAIBaseURL = "https://api.example.test/v1"
        settings.openAIOrganizationID = "org-test"
        settings.openAIProjectID = "project-test"
        let firstDate = Date(timeIntervalSince1970: 1_000)

        let first = try await service.models(
            settings: settings,
            apiKey: "sk-secret",
            now: firstDate
        )
        let cached = try await service.models(
            settings: settings,
            apiKey: "sk-secret",
            now: firstDate.addingTimeInterval(60 * 60)
        )
        let refreshed = try await service.models(
            settings: settings,
            apiKey: "sk-secret",
            now: firstDate.addingTimeInterval(OpenAIModelAvailabilityService.cacheTTL + 1)
        )

        XCTAssertEqual(first.source, .network)
        XCTAssertEqual(first.snapshot.modelIDs, ["gpt-4o-mini-transcribe", "gpt-4o-transcribe"])
        XCTAssertEqual(cached.source, .cache)
        XCTAssertEqual(refreshed.source, .network)
        XCTAssertEqual(loader.requests.count, 2)

        let request = try XCTUnwrap(loader.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.example.test/v1/models")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-secret")
        XCTAssertEqual(request.value(forHTTPHeaderField: "OpenAI-Organization"), "org-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "OpenAI-Project"), "project-test")
    }

    func testCacheScopeChangesWithCredentialsWithoutContainingTheSecret() {
        var settings = AppSettings()
        let first = OpenAIModelAvailabilityService.scopeID(settings: settings, apiKey: "sk-first")
        let second = OpenAIModelAvailabilityService.scopeID(settings: settings, apiKey: "sk-second")
        settings.openAIProjectID = "another-project"
        let third = OpenAIModelAvailabilityService.scopeID(settings: settings, apiKey: "sk-first")

        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(first, third)
        XCTAssertFalse(first.contains("sk-first"))
        XCTAssertEqual(first.count, 32)
    }
}

final class OpenAITranscriptionServiceTests: XCTestCase {
    func testRelayUsesMinimalMultipartRequestAndKeepsManualModelID() async throws {
        let capture = TranscriptionRequestCapture(responseData: Data(#"{"text":"relay transcript"}"#.utf8))
        let service = OpenAITranscriptionService(dataLoader: { request in
            try await capture.load(request)
        })
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("shuo-relay-test-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: audioURL) }
        try Data([0, 1, 2, 3]).write(to: audioURL)

        var settings = AppSettings()
        settings.provider = .openAI
        settings.openAIBaseURL = "https://relay.example.test/v1"
        settings.openAITranscriptionModelSelectionMode = .fixed
        settings.fixedOpenAITranscriptionModel = "company/mandarin-asr-v2"
        settings.selectedTranscriptionLanguages = [.chinese]
        settings.acknowledgeOpenAICompatibleRelay()

        let result = try await service.transcribe(
            TranscriptionRequest(
                audioFileURL: audioURL,
                settings: settings,
                context: "private project context",
                vocabulary: TranscriptionVocabularySnapshot(terms: ["Shuo"]),
                apiKey: "relay-secret"
            )
        )

        XCTAssertEqual(result.text, "relay transcript")
        let request = try XCTUnwrap(capture.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://relay.example.test/v1/audio/transcriptions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer relay-secret")
        let body = try XCTUnwrap(request.httpBody).utf8Text
        XCTAssertTrue(body.contains("name=\"model\"\r\n\r\ncompany/mandarin-asr-v2"))
        XCTAssertTrue(body.contains("name=\"file\""))
        XCTAssertFalse(body.contains("response_format"))
        XCTAssertFalse(body.contains("name=\"language\""))
        XCTAssertFalse(body.contains("name=\"prompt\""))
        XCTAssertFalse(body.contains("private project context"))
        XCTAssertFalse(body.contains("Shuo"))
    }

    func testProtocolVerificationUsesGeneratedAudioAndAcceptsEmptyTranscript() async throws {
        let capture = TranscriptionRequestCapture(responseData: Data(#"{"text":""}"#.utf8))
        let service = OpenAITranscriptionService(dataLoader: { request in
            try await capture.load(request)
        })
        var settings = AppSettings()
        settings.provider = .openAI
        settings.openAIBaseURL = "https://relay.example.test/v1"
        settings.openAITranscriptionModelSelectionMode = .fixed
        settings.fixedOpenAITranscriptionModel = "relay-asr"

        try await service.verifySelectedModel(settings: settings, apiKey: "relay-secret")

        let request = try XCTUnwrap(capture.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://relay.example.test/v1/audio/transcriptions")
        let body = try XCTUnwrap(request.httpBody).utf8Text
        XCTAssertTrue(body.contains("filename=\"shuo-protocol-test.wav\""))
        XCTAssertTrue(body.contains("name=\"model\"\r\n\r\nrelay-asr"))
        XCTAssertFalse(body.contains("response_format"))
        XCTAssertFalse(body.contains("name=\"language\""))
        XCTAssertFalse(body.contains("name=\"prompt\""))
    }

    func testRelayRejectsInvalidModelAndUnexpectedSuccessResponse() async throws {
        var settings = AppSettings()
        settings.provider = .openAI
        settings.openAIBaseURL = "https://relay.example.test/v1"
        settings.openAITranscriptionModelSelectionMode = .fixed
        settings.fixedOpenAITranscriptionModel = "invalid\nmodel"
        settings.acknowledgeOpenAICompatibleRelay()

        let service = OpenAITranscriptionService(dataLoader: { _ in
            XCTFail("An invalid model ID must not upload audio")
            throw CancellationError()
        })
        do {
            try await service.verifySelectedModel(settings: settings, apiKey: "relay-secret")
            XCTFail("Expected model validation error")
        } catch let error as OpenAITranscriptionError {
            XCTAssertEqual(
                error,
                .invalidModelID(.containsControlCharacter)
            )
        }

        settings.fixedOpenAITranscriptionModel = "relay-asr"
        let malformed = OpenAITranscriptionService(dataLoader: { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data("not-json".utf8), response)
        })
        do {
            try await malformed.verifySelectedModel(settings: settings, apiKey: "relay-secret")
            XCTFail("Expected response validation error")
        } catch let error as OpenAITranscriptionError {
            XCTAssertEqual(error, .invalidResponse)
        }
    }

    func testRelayRefusesRealAudioUntilTheEndpointIsAcknowledged() async throws {
        let service = OpenAITranscriptionService(dataLoader: { _ in
            XCTFail("An unacknowledged relay must not receive audio")
            throw CancellationError()
        })
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("shuo-unacknowledged-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: audioURL) }
        try Data([0, 1]).write(to: audioURL)

        var settings = AppSettings()
        settings.provider = .openAI
        settings.openAIBaseURL = "https://relay.example.test/v1"
        settings.openAITranscriptionModelSelectionMode = .fixed
        settings.fixedOpenAITranscriptionModel = "relay-asr"

        do {
            _ = try await service.transcribe(
                TranscriptionRequest(
                    audioFileURL: audioURL,
                    settings: settings,
                    context: "",
                    vocabulary: .empty,
                    apiKey: "relay-secret"
                )
            )
            XCTFail("Expected relay acknowledgement error")
        } catch let error as OpenAITranscriptionError {
            XCTAssertEqual(error, .relayAcknowledgementRequired)
        }
    }
}

private final class InMemoryOpenAIModelAvailabilityStore: OpenAIModelAvailabilityStoring {
    private var snapshots: [String: OpenAIModelAvailabilitySnapshot] = [:]

    func snapshot(for scopeID: String) -> OpenAIModelAvailabilitySnapshot? {
        snapshots[scopeID]
    }

    func save(_ snapshot: OpenAIModelAvailabilitySnapshot) {
        snapshots[snapshot.scopeID] = snapshot
    }
}

private final class ModelListLoader {
    private(set) var requests: [URLRequest] = []

    func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let data = Data(
            #"{"data":[{"id":"gpt-4o-transcribe"},{"id":"gpt-4o-mini-transcribe"},{"id":"gpt-4o-transcribe"}]}"#.utf8
        )
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

private final class TranscriptionRequestCapture {
    private(set) var requests: [URLRequest] = []
    private let responseData: Data

    init(responseData: Data) {
        self.responseData = responseData
    }

    func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )
        return (responseData, response)
    }
}

private extension Data {
    var utf8Text: String {
        String(decoding: self, as: UTF8.self)
    }
}
