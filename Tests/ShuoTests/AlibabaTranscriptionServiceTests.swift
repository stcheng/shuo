import Foundation
import XCTest
@testable import Shuo

final class AlibabaTranscriptionServiceTests: XCTestCase {
    func testBuildsOfficialQwenASRRequestWithoutLocalContext() throws {
        let audioURL = try makeTemporaryAudioFile(
            extension: "wav",
            data: Data([0x00, 0x01, 0x02, 0x03])
        )
        defer { try? FileManager.default.removeItem(at: audioURL) }

        var settings = AppSettings()
        settings.selectedTranscriptionLanguages = [.chinese]
        let transcriptionRequest = TranscriptionRequest(
            audioFileURL: audioURL,
            settings: settings,
            context: "PRIVATE HISTORY MUST NOT LEAVE THE MAC",
            vocabulary: TranscriptionVocabularySnapshot(
                terms: ["PrivateTerm", "/Users/example/private-project"]
            ),
            apiKey: "  dashscope-secret  "
        )

        let request = try AlibabaTranscriptionService().makeURLRequest(transcriptionRequest)
        let bodyData = try XCTUnwrap(request.httpBody)
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        )

        XCTAssertEqual(request.url, AlibabaTranscriptionService.endpoint)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer dashscope-secret")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(Set(body.keys), ["model", "messages", "stream", "asr_options"])
        XCTAssertEqual(body["model"] as? String, "qwen3-asr-flash")
        XCTAssertEqual(body["stream"] as? Bool, false)

        let options = try XCTUnwrap(body["asr_options"] as? [String: Any])
        XCTAssertEqual(Set(options.keys), ["language", "enable_itn"])
        XCTAssertEqual(options["language"] as? String, "zh")
        XCTAssertEqual(options["enable_itn"] as? Bool, true)

        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(Set(messages[0].keys), ["role", "content"])
        XCTAssertEqual(messages[0]["role"] as? String, "user")

        let content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 1)
        XCTAssertEqual(Set(content[0].keys), ["type", "input_audio"])
        XCTAssertEqual(content[0]["type"] as? String, "input_audio")

        let inputAudio = try XCTUnwrap(content[0]["input_audio"] as? [String: Any])
        XCTAssertEqual(Set(inputAudio.keys), ["data"])
        XCTAssertEqual(inputAudio["data"] as? String, "data:audio/wav;base64,AAECAw==")

        let bodyText = try XCTUnwrap(String(data: bodyData, encoding: .utf8))
        XCTAssertFalse(bodyText.contains("PRIVATE HISTORY"))
        XCTAssertFalse(bodyText.contains("PrivateTerm"))
        XCTAssertFalse(bodyText.contains("private-project"))
    }

    func testOmitsLanguageForMultilingualSelection() throws {
        let audioURL = try makeTemporaryAudioFile(extension: "mp3", data: Data([0x01]))
        defer { try? FileManager.default.removeItem(at: audioURL) }

        var settings = AppSettings()
        settings.selectedTranscriptionLanguages = [.chinese, .english]
        let request = try AlibabaTranscriptionService().makeURLRequest(
            makeRequest(audioURL: audioURL, settings: settings)
        )
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any]
        )
        let options = try XCTUnwrap(body["asr_options"] as? [String: Any])

        XCTAssertNil(options["language"])
        XCTAssertEqual(options["enable_itn"] as? Bool, true)
    }

    func testMapsSupportedSingleLanguages() {
        let examples: [(TranscriptionLanguage, String)] = [
            (.chinese, "zh"),
            (.english, "en"),
            (.japanese, "ja"),
            (.french, "fr"),
            (.spanish, "es")
        ]

        for (language, expectedCode) in examples {
            var settings = AppSettings()
            settings.selectedTranscriptionLanguages = [language]
            XCTAssertEqual(
                AlibabaTranscriptionService.languageCode(for: settings),
                expectedCode
            )
        }
    }

    func testUsesCorrectMIMETypesForCommonAudioFiles() {
        let examples = [
            ("recording.wav", "audio/wav"),
            ("recording.mp3", "audio/mpeg"),
            ("recording.m4a", "audio/mp4"),
            ("recording.aac", "audio/aac"),
            ("recording.flac", "audio/flac"),
            ("recording.ogg", "audio/ogg"),
            ("recording.webm", "audio/webm")
        ]

        for (filename, expectedMIMEType) in examples {
            XCTAssertEqual(
                AlibabaTranscriptionService.mimeType(
                    for: URL(fileURLWithPath: "/tmp/\(filename)")
                ),
                expectedMIMEType
            )
        }
    }

    func testRejectsMissingAPIKeyBeforeReadingAudio() {
        let request = TranscriptionRequest(
            audioFileURL: URL(fileURLWithPath: "/does/not/exist.wav"),
            settings: AppSettings(),
            context: "",
            vocabulary: .empty,
            apiKey: "   "
        )

        XCTAssertThrowsError(try AlibabaTranscriptionService().makeURLRequest(request)) { error in
            guard case AlibabaTranscriptionError.missingAPIKey = error else {
                return XCTFail("Expected missingAPIKey, got \(error)")
            }
        }
    }

    func testRejectsAudioWhoseBase64ValueWouldExceedTenMegabytes() throws {
        let maximumSourceByteCount = AlibabaTranscriptionService.maximumEncodedAudioByteCount / 4 * 3
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        XCTAssertTrue(FileManager.default.createFile(atPath: audioURL.path, contents: nil))
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let handle = try FileHandle(forWritingTo: audioURL)
        try handle.truncate(atOffset: UInt64(maximumSourceByteCount + 1))
        try handle.close()

        XCTAssertThrowsError(
            try AlibabaTranscriptionService().makeURLRequest(makeRequest(audioURL: audioURL))
        ) { error in
            guard case AlibabaTranscriptionError.audioFileTooLarge(
                let encodedByteCount,
                let maximumByteCount
            ) = error else {
                return XCTFail("Expected audioFileTooLarge, got \(error)")
            }
            XCTAssertGreaterThan(encodedByteCount, Int64(maximumByteCount))
            XCTAssertEqual(
                maximumByteCount,
                AlibabaTranscriptionService.maximumEncodedAudioByteCount
            )
        }
    }

    func testParsesContentAndDetectedLanguage() throws {
        let response = Data(
            #"{"choices":[{"message":{"content":"  你好，Shuo。\n","annotations":[{"language":"zh"}]}}]}"#.utf8
        )

        let result = try AlibabaTranscriptionService.parseResponse(response)

        XCTAssertEqual(result.text, "你好，Shuo。")
        XCTAssertEqual(result.detectedLanguage, "zh")
    }

    func testRejectsMalformedAndEmptyResponses() {
        XCTAssertThrowsError(
            try AlibabaTranscriptionService.parseResponse(Data(#"{"choices":[]}"#.utf8))
        ) { error in
            guard case AlibabaTranscriptionError.invalidResponse = error else {
                return XCTFail("Expected invalidResponse, got \(error)")
            }
        }

        let emptyResponse = Data(
            #"{"choices":[{"message":{"content":"  \n "}}]}"#.utf8
        )
        XCTAssertThrowsError(
            try AlibabaTranscriptionService.parseResponse(emptyResponse)
        ) { error in
            guard case AlibabaTranscriptionError.emptyResponse = error else {
                return XCTFail("Expected emptyResponse, got \(error)")
            }
        }
    }

    func testSurfacesProviderHTTPErrorMessage() async throws {
        let audioURL = try makeTemporaryAudioFile(extension: "wav", data: Data([0x01]))
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: AlibabaTranscriptionService.endpoint,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )
        )
        let service = AlibabaTranscriptionService { _ in
            (
                Data(#"{"error":{"code":"InvalidApiKey","message":"API key is invalid"}}"#.utf8),
                response
            )
        }

        do {
            _ = try await service.transcribe(makeRequest(audioURL: audioURL))
            XCTFail("Expected the provider error to be thrown")
        } catch let error as AlibabaTranscriptionError {
            guard case .requestFailed(let statusCode, let message) = error else {
                return XCTFail("Expected requestFailed, got \(error)")
            }
            XCTAssertEqual(statusCode, 401)
            XCTAssertEqual(message, "InvalidApiKey: API key is invalid")
        }
    }

    private func makeRequest(
        audioURL: URL,
        settings: AppSettings = AppSettings(),
        apiKey: String = "dashscope-secret"
    ) -> TranscriptionRequest {
        TranscriptionRequest(
            audioFileURL: audioURL,
            settings: settings,
            context: "",
            vocabulary: .empty,
            apiKey: apiKey
        )
    }

    private func makeTemporaryAudioFile(
        extension fileExtension: String,
        data: Data
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        try data.write(to: url, options: .atomic)
        return url
    }
}

final class GeminiTranscriptionServiceTests: XCTestCase {
    func testBuildsNativeGeminiAudioRequestWithSelectedModelAndCredential() throws {
        let audioURL = try makeTemporaryAudioFile(
            extension: "wav",
            data: Data([0x00, 0x01, 0x02, 0x03])
        )
        defer { try? FileManager.default.removeItem(at: audioURL) }

        var settings = AppSettings()
        settings.provider = .gemini
        settings.selectedModel = "gemini-3.1-flash-lite"
        settings.selectedTranscriptionLanguages = [.chinese]
        settings.openAIBaseURL = "https://openai.example.invalid/v1"
        let request = try GeminiTranscriptionService().makeURLRequest(
            TranscriptionRequest(
                audioFileURL: audioURL,
                settings: settings,
                context: "Project context",
                vocabulary: TranscriptionVocabularySnapshot(terms: ["ShuoTerm"]),
                apiKey: "  gemini-secret  "
            )
        )

        XCTAssertEqual(
            request.url,
            URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent")
        )
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "gemini-secret")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "x-goog-api-client"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

        let bodyData = try XCTUnwrap(request.httpBody)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["contents", "generationConfig"])
        let generationConfig = try XCTUnwrap(body["generationConfig"] as? [String: Any])
        XCTAssertEqual(generationConfig["maxOutputTokens"] as? Int, 8_192)
        let thinkingConfig = try XCTUnwrap(generationConfig["thinkingConfig"] as? [String: Any])
        XCTAssertEqual(thinkingConfig["thinkingLevel"] as? String, "minimal")
        XCTAssertNil(generationConfig["temperature"])
        let contents = try XCTUnwrap(body["contents"] as? [[String: Any]])
        let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
        let inlineData = try XCTUnwrap(parts.last?["inline_data"] as? [String: Any])
        XCTAssertEqual(inlineData["mime_type"] as? String, "audio/wav")
        XCTAssertEqual(inlineData["data"] as? String, "AAECAw==")

        let prompt = try XCTUnwrap(parts.first?["text"] as? String)
        XCTAssertTrue(prompt.contains("Project context"))
        XCTAssertTrue(prompt.contains("ShuoTerm"))
        XCTAssertFalse(String(data: bodyData, encoding: .utf8)?.contains("openai.example.invalid") ?? true)
    }

    func testGeminiTextRequestUsesSameGeminiModelAndNeverOpenAIConnection() throws {
        var settings = AppSettings()
        settings.provider = .gemini
        settings.selectedModel = "gemini-3.1-flash-lite"
        settings.openAIBaseURL = "https://openai.example.invalid/v1"
        settings.openAIOrganizationID = "org-should-not-leave"
        settings.openAIProjectID = "project-should-not-leave"

        let request = try GeminiTextCompletionService().makeURLRequest(
            systemInstruction: "Return only the edited transcript.",
            userContent: "Hello world",
            settings: settings,
            apiKey: "gemini-secret"
        )

        XCTAssertEqual(
            request.url,
            URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent")
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "gemini-secret")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let bodyData = try XCTUnwrap(request.httpBody)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertNotNil(body["systemInstruction"])
        let generationConfig = try XCTUnwrap(body["generationConfig"] as? [String: Any])
        XCTAssertEqual(generationConfig["maxOutputTokens"] as? Int, 8_192)
        let thinkingConfig = try XCTUnwrap(generationConfig["thinkingConfig"] as? [String: Any])
        XCTAssertEqual(thinkingConfig["thinkingLevel"] as? String, "minimal")
        XCTAssertNil(generationConfig["temperature"])
        let serializedBody = try XCTUnwrap(String(data: bodyData, encoding: .utf8))
        XCTAssertFalse(serializedBody.contains("openai.example.invalid"))
        XCTAssertFalse(serializedBody.contains("org-should-not-leave"))
        XCTAssertFalse(serializedBody.contains("project-should-not-leave"))
    }

    func testParsesTextAndRejectsTruncatedGeminiResponses() throws {
        let response = Data(
            #"{"candidates":[{"content":{"parts":[{"text":"  你好，Shuo。  "}]},"finishReason":"STOP"}]}"#.utf8
        )
        XCTAssertEqual(try GeminiTranscriptionService.parseResponse(response).text, "你好，Shuo。")
        XCTAssertEqual(try GeminiTextCompletionService.parseResponse(response), "你好，Shuo。")

        let truncated = Data(
            #"{"candidates":[{"content":{"parts":[{"text":"partial"}]},"finishReason":"MAX_TOKENS"}]}"#.utf8
        )
        XCTAssertThrowsError(try GeminiTranscriptionService.parseResponse(truncated)) { error in
            guard case GeminiTranscriptionError.truncatedResponse = error else {
                return XCTFail("Expected truncatedResponse, got \(error)")
            }
        }
        XCTAssertThrowsError(try GeminiTextCompletionService.parseResponse(truncated)) { error in
            guard case VoiceEditLLMError.requestFailed = error else {
                return XCTFail("Expected requestFailed, got \(error)")
            }
        }

        XCTAssertThrowsError(try GeminiTranscriptionService.parseResponse(Data("{}".utf8)))
        XCTAssertThrowsError(
            try GeminiTranscriptionService.parseResponse(
                Data(#"{"candidates":[{"content":{"parts":[{"text":"   "}]}}]}"#.utf8)
            )
        ) { error in
            guard case GeminiTranscriptionError.emptyResponse = error else {
                return XCTFail("Expected emptyResponse, got \(error)")
            }
        }
    }

    func testGeminiTextFeaturesRespectCloudTextOptOutAndReuseSelectedModelWhenEnabled() {
        var settings = AppSettings()
        settings.provider = .gemini
        settings.selectedModel = "gemini-3.1-flash-lite"
        settings.openAITextModelSelectionMode = .disabled
        settings.transcriptRetouchEnabled = true
        settings.aiEmojiResolverEnabled = true
        settings.voiceEditCommandMode = .llmOnly

        XCTAssertFalse(CloudTextAICapabilityPolicy.isCloudTextAIAvailable(for: settings))
        let disabledRuntimeSettings = CloudTextAICapabilityPolicy.applying(to: settings)
        XCTAssertFalse(disabledRuntimeSettings.transcriptRetouchEnabled)
        XCTAssertFalse(disabledRuntimeSettings.aiEmojiResolverEnabled)
        XCTAssertEqual(disabledRuntimeSettings.voiceEditCommandMode, .localOnly)

        settings.openAITextModelSelectionMode = .automatic
        XCTAssertTrue(CloudTextAICapabilityPolicy.isCloudTextAIAvailable(for: settings))
        XCTAssertEqual(settings.effectiveVoiceEditLLMModel, "gemini-3.1-flash-lite")
        XCTAssertEqual(settings.effectiveTranscriptRetouchLLMModel, "gemini-3.1-flash-lite")
        XCTAssertEqual(settings.effectiveEmojiResolverLLMModel, "gemini-3.1-flash-lite")
    }

    func testGeminiFeatureVisibilityRespectsCloudTextOptOutWithoutEnablingFeaturesByDefault() {
        let disabled = SettingsFeatureVisibility(
            pluginConfiguration: .fullDevelopment,
            provider: .gemini,
            transcriptRetouchEnabled: true,
            emojiPostProcessingEnabled: true,
            aiEmojiResolverEnabled: true,
            voiceEditCommandsEnabled: true,
            voiceEditCommandMode: .llmOnly,
            openAITextModelSelectionMode: .disabled
        )
        XCTAssertFalse(disabled.isTranscriptRetouchEnabled)
        XCTAssertFalse(disabled.isAIEmojiResolverEnabled)
        XCTAssertEqual(disabled.voiceEditCommandMode, .localOnly)

        let automaticWithFeaturesOff = SettingsFeatureVisibility(
            pluginConfiguration: .fullDevelopment,
            provider: .gemini,
            transcriptRetouchEnabled: false,
            emojiPostProcessingEnabled: false,
            aiEmojiResolverEnabled: false,
            voiceEditCommandsEnabled: false,
            voiceEditCommandMode: .localOnly,
            openAITextModelSelectionMode: .automatic
        )
        XCTAssertFalse(automaticWithFeaturesOff.isTranscriptRetouchEnabled)
        XCTAssertFalse(automaticWithFeaturesOff.isAIEmojiResolverEnabled)
        XCTAssertFalse(automaticWithFeaturesOff.isVoiceEditEnabled)
    }

    func testRejectsOversizedSerializedInlineRequestBeforeSending() throws {
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        XCTAssertTrue(FileManager.default.createFile(atPath: audioURL.path, contents: nil))
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let handle = try FileHandle(forWritingTo: audioURL)
        try handle.truncate(atOffset: 15_000_000)
        try handle.close()

        XCTAssertThrowsError(
            try GeminiTranscriptionService().makeURLRequest(
                makeTranscriptionRequest(audioURL: audioURL)
            )
        ) { error in
            guard case GeminiTranscriptionError.audioFileTooLarge(
                let actualByteCount,
                let maximumByteCount
            ) = error else {
                return XCTFail("Expected audioFileTooLarge, got \(error)")
            }
            XCTAssertGreaterThan(actualByteCount, maximumByteCount)
            XCTAssertEqual(maximumByteCount, GeminiTranscriptionService.maximumInlineRequestByteCount)
        }
    }

    func testFactorySelectsGeminiService() {
        XCTAssertTrue(
            TranscriptionServiceFactory.makeService(for: .gemini) is GeminiTranscriptionService
        )
    }

    func testGeminiSettingsMigrateOtherModelSelectionsToTheSingleSupportedModel() {
        for obsoleteModel in ["gemini-2.5-flash", "gemini-3.5-flash"] {
            var settings = AppSettings()
            settings.provider = .gemini
            settings.selectedModel = obsoleteModel

            settings.normalizeSelections()

            XCTAssertEqual(settings.selectedModel, GeminiTranscriptionService.defaultModelID)
        }

        XCTAssertEqual(GeminiTranscriptionService.defaultModelID, "gemini-3.1-flash-lite")
        XCTAssertEqual(GeminiTranscriptionService.modelIDs, ["gemini-3.1-flash-lite"])
        XCTAssertNil(GeminiTranscriptionService.endpoint(for: "gemini-3.5-flash"))
    }

    func testSettingsSearchUsesGeminiTextTargetInsteadOfOpenAITextModel() {
        let items = SettingsSearchIndex.items(
            localizer: AppLocalizer(language: .english),
            context: SettingsSearchContext(
                provider: .gemini,
                pluginConfiguration: .fullDevelopment,
                transcriptRetouchEnabled: true,
                emojiPostProcessingEnabled: true,
                aiEmojiResolverEnabled: true,
                voiceEditCommandsEnabled: true,
                voiceEditCommandMode: .llmOnly,
                openAITextModelSelectionMode: .disabled
            )
        )

        XCTAssertTrue(items.contains { $0.target == .geminiAPIKey })
        XCTAssertFalse(items.contains { $0.target == .openAITextModel })
        XCTAssertFalse(items.contains { $0.target == .openAIAPIKey })
    }

    private func makeTranscriptionRequest(audioURL: URL) -> TranscriptionRequest {
        var settings = AppSettings()
        settings.provider = .gemini
        settings.selectedModel = "gemini-3.1-flash-lite"
        return TranscriptionRequest(
            audioFileURL: audioURL,
            settings: settings,
            context: "",
            vocabulary: .empty,
            apiKey: "gemini-secret"
        )
    }

    private func makeTemporaryAudioFile(
        extension fileExtension: String,
        data: Data
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        try data.write(to: url, options: .atomic)
        return url
    }
}
