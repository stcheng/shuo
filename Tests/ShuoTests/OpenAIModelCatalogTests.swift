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

    func testAutomaticAndFixedTranscriptionSelectionRemainDistinct() {
        var settings = AppSettings()
        settings.provider = .openAI
        settings.selectedModel = "whisper-1"
        settings.automaticOpenAITranscriptionModel = "gpt-4o-mini-transcribe"

        settings.openAITranscriptionModelSelectionMode = .automatic
        XCTAssertEqual(settings.effectiveModel, "gpt-4o-mini-transcribe")

        settings.openAITranscriptionModelSelectionMode = .fixed
        XCTAssertEqual(settings.effectiveModel, "whisper-1")
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
        XCTAssertEqual(decoded.fixedOpenAITextModel, OpenAIModelCatalog.defaultTextModelID)
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
