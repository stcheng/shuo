import Foundation

enum VoiceEditLLMError: LocalizedError {
    case missingAPIKey
    case unavailableInLocalMode
    case disabledInSettings
    case invalidBaseURL(String)
    case requestFailed(statusCode: Int, message: String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add an API key for the selected cloud provider in Settings before using LLM voice edit."
        case .unavailableInLocalMode:
            return "Cloud AI text processing is unavailable while Local transcription is selected."
        case .disabledInSettings:
            return "Cloud AI text processing is disabled in Settings."
        case .invalidBaseURL(let baseURL):
            return OpenAICompatibleRequestBuilder.endpointValidationMessage(
                baseURLString: baseURL
            )
        case .requestFailed(let statusCode, let message):
            return "LLM voice edit failed (\(statusCode)): \(message)"
        case .emptyResponse:
            return "LLM voice edit returned an empty response."
        }
    }
}

struct VoiceEditLLMRequest {
    let previousText: String
    let commandText: String
    let settings: AppSettings
    let apiKey: String?
    /// Protocol tests intentionally exercise a custom endpoint before it has
    /// earned runtime permission to process user text.
    let allowsUnverifiedCustomEndpointTesting: Bool

    init(
        previousText: String,
        commandText: String,
        settings: AppSettings,
        apiKey: String?,
        allowsUnverifiedCustomEndpointTesting: Bool = false
    ) {
        self.previousText = previousText
        self.commandText = commandText
        self.settings = settings
        self.apiKey = apiKey
        self.allowsUnverifiedCustomEndpointTesting = allowsUnverifiedCustomEndpointTesting
    }
}

struct TranscriptRetouchLLMRequest {
    let text: String
    let settings: AppSettings
    let apiKey: String?
}

struct VoiceEditLLMService {
    func rewrite(_ request: VoiceEditLLMRequest) async throws -> String {
        guard CloudTextAICapabilityPolicy.isCloudTextAIAvailable(for: request.settings)
                || request.allowsUnverifiedCustomEndpointTesting else {
            throw request.settings.provider == .local
                ? VoiceEditLLMError.unavailableInLocalMode
                : VoiceEditLLMError.disabledInSettings
        }

        let systemInstruction = """
        You edit exactly one previously inserted dictation transcript according to a voice edit command.
        Return only the complete corrected transcript.
        Do not explain, quote, format as Markdown, translate, summarize, or improve unrelated wording.
        Preserve the original language, spacing style, punctuation style, and casing unless the command explicitly changes them.
        If the command is underspecified or cannot be applied safely, return the original transcript unchanged.
        """
        let userContent = """
        Previous transcript:
        \(request.previousText)

        Voice edit command:
        \(request.commandText)

        Corrected transcript:
        """

        let executionSettings = request.settings.cloudTextExecutionSettings
        let rewritten: String
        if executionSettings.provider == .gemini {
            rewritten = try await GeminiTextCompletionService().complete(
                systemInstruction: systemInstruction,
                userContent: userContent,
                settings: executionSettings,
                apiKey: request.apiKey
            )
        } else {
            rewritten = try await completeWithOpenAICompatibleAPI(
                systemInstruction: systemInstruction,
                userContent: userContent,
                settings: executionSettings,
                apiKey: request.apiKey,
                model: request.settings.effectiveCloudTextModel
            )
        }

        guard !rewritten.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VoiceEditLLMError.emptyResponse
        }

        return rewritten
    }
}

struct TranscriptRetouchLLMService {
    func retouch(_ request: TranscriptRetouchLLMRequest) async throws -> String {
        guard CloudTextAICapabilityPolicy.isCloudTextAIAvailable(for: request.settings) else {
            throw request.settings.provider == .local
                ? VoiceEditLLMError.unavailableInLocalMode
                : VoiceEditLLMError.disabledInSettings
        }

        let systemInstruction = """
        You conservatively retouch one raw speech-to-text transcript.
        Fix only obvious ASR mistakes: misspellings, missing possessive apostrophes, contractions, casing, spacing, and punctuation.
        Preserve the speaker's wording, meaning, language mix, names, code, numbers, slang, and style.
        Do not translate, summarize, rewrite for style, add new facts, remove content, or make uncertain corrections.
        If unsure, return the original transcript unchanged.
        Return only the complete retouched transcript.
        """
        let userContent = """
        Raw transcript:
        \(request.text)

        Retouched transcript:
        """

        let executionSettings = request.settings.cloudTextExecutionSettings
        let retouched: String
        if executionSettings.provider == .gemini {
            retouched = try await GeminiTextCompletionService().complete(
                systemInstruction: systemInstruction,
                userContent: userContent,
                settings: executionSettings,
                apiKey: request.apiKey
            )
        } else {
            retouched = try await completeWithOpenAICompatibleAPI(
                systemInstruction: systemInstruction,
                userContent: userContent,
                settings: executionSettings,
                apiKey: request.apiKey,
                model: request.settings.effectiveCloudTextModel
            )
        }

        guard !retouched.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VoiceEditLLMError.emptyResponse
        }

        return retouched
    }
}

private func completeWithOpenAICompatibleAPI(
    systemInstruction: String,
    userContent: String,
    settings: AppSettings,
    apiKey: String?,
    model: String
) async throws -> String {
    guard let apiKey = OpenAICompatibleRequestBuilder.normalizedAPIKey(apiKey) else {
        throw VoiceEditLLMError.missingAPIKey
    }

    guard let endpoint = OpenAICompatibleRequestBuilder.endpoint(
        baseURLString: settings.openAIBaseURL,
        path: "chat/completions"
    ) else {
        throw VoiceEditLLMError.invalidBaseURL(settings.openAIBaseURL)
    }
    var urlRequest = OpenAICompatibleRequestBuilder.authenticatedPOSTRequest(
        endpoint: endpoint,
        apiKey: apiKey,
        settings: settings,
        contentType: "application/json"
    )
    urlRequest.httpBody = try JSONEncoder().encode(
        ChatCompletionRequest(
            model: model,
            messages: [
                .init(role: "system", content: systemInstruction),
                .init(role: "user", content: userContent)
            ]
        )
    )

    let (data, response) = try await SensitiveRequestURLSession.shared.data(for: urlRequest)
    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
    let bodyText = String(data: data, encoding: .utf8) ?? ""

    guard (200 ..< 300).contains(statusCode) else {
        throw VoiceEditLLMError.requestFailed(
            statusCode: statusCode,
            message: OpenAICompatibleRequestBuilder.errorMessage(from: data, fallback: bodyText)
        )
    }

    let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
    let content = decoded.choices.first?.message.content ?? ""
    return OpenAICompatibleRequestBuilder.cleanedModelOutput(content)
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: ChatMessage
    }
}
