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
            return "Add an OpenAI API key in Settings before using LLM voice edit."
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
}

struct TranscriptRetouchLLMRequest {
    let text: String
    let settings: AppSettings
    let apiKey: String?
}

struct VoiceEditLLMService {
    func rewrite(_ request: VoiceEditLLMRequest) async throws -> String {
        guard CloudTextAICapabilityPolicy.isCloudTextAIAvailable(for: request.settings) else {
            throw request.settings.provider == .local
                ? VoiceEditLLMError.unavailableInLocalMode
                : VoiceEditLLMError.disabledInSettings
        }
        guard let apiKey = OpenAICompatibleRequestBuilder.normalizedAPIKey(request.apiKey) else {
            throw VoiceEditLLMError.missingAPIKey
        }

        guard let endpoint = OpenAICompatibleRequestBuilder.endpoint(
            baseURLString: request.settings.openAIBaseURL,
            path: "chat/completions"
        ) else {
            throw VoiceEditLLMError.invalidBaseURL(request.settings.openAIBaseURL)
        }
        var urlRequest = OpenAICompatibleRequestBuilder.authenticatedPOSTRequest(
            endpoint: endpoint,
            apiKey: apiKey,
            settings: request.settings,
            contentType: "application/json"
        )

        urlRequest.httpBody = try JSONEncoder().encode(makePayload(for: request))

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
        let rewritten = OpenAICompatibleRequestBuilder.cleanedModelOutput(content)

        guard !rewritten.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VoiceEditLLMError.emptyResponse
        }

        return rewritten
    }

    private func makePayload(for request: VoiceEditLLMRequest) -> ChatCompletionRequest {
        return ChatCompletionRequest(
            model: request.settings.effectiveVoiceEditLLMModel,
            messages: [
                ChatMessage(
                    role: "system",
                    content: """
                    You edit exactly one previously inserted dictation transcript according to a voice edit command.
                    Return only the complete corrected transcript.
                    Do not explain, quote, format as Markdown, translate, summarize, or improve unrelated wording.
                    Preserve the original language, spacing style, punctuation style, and casing unless the command explicitly changes them.
                    If the command is underspecified or cannot be applied safely, return the original transcript unchanged.
                    """
                ),
                ChatMessage(
                    role: "user",
                    content: """
                    Previous transcript:
                    \(request.previousText)

                    Voice edit command:
                    \(request.commandText)

                    Corrected transcript:
                    """
                )
            ]
        )
    }

}

struct TranscriptRetouchLLMService {
    func retouch(_ request: TranscriptRetouchLLMRequest) async throws -> String {
        guard CloudTextAICapabilityPolicy.isCloudTextAIAvailable(for: request.settings) else {
            throw request.settings.provider == .local
                ? VoiceEditLLMError.unavailableInLocalMode
                : VoiceEditLLMError.disabledInSettings
        }
        guard let apiKey = OpenAICompatibleRequestBuilder.normalizedAPIKey(request.apiKey) else {
            throw VoiceEditLLMError.missingAPIKey
        }

        guard let endpoint = OpenAICompatibleRequestBuilder.endpoint(
            baseURLString: request.settings.openAIBaseURL,
            path: "chat/completions"
        ) else {
            throw VoiceEditLLMError.invalidBaseURL(request.settings.openAIBaseURL)
        }
        var urlRequest = OpenAICompatibleRequestBuilder.authenticatedPOSTRequest(
            endpoint: endpoint,
            apiKey: apiKey,
            settings: request.settings,
            contentType: "application/json"
        )

        urlRequest.httpBody = try JSONEncoder().encode(makePayload(for: request))

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
        let retouched = OpenAICompatibleRequestBuilder.cleanedModelOutput(content)

        guard !retouched.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VoiceEditLLMError.emptyResponse
        }

        return retouched
    }

    private func makePayload(for request: TranscriptRetouchLLMRequest) -> ChatCompletionRequest {
        return ChatCompletionRequest(
            model: request.settings.effectiveTranscriptRetouchLLMModel,
            messages: [
                ChatMessage(
                    role: "system",
                    content: """
                    You conservatively retouch one raw speech-to-text transcript.
                    Fix only obvious ASR mistakes: misspellings, missing possessive apostrophes, contractions, casing, spacing, and punctuation.
                    Preserve the speaker's wording, meaning, language mix, names, code, numbers, slang, and style.
                    Do not translate, summarize, rewrite for style, add new facts, remove content, or make uncertain corrections.
                    If unsure, return the original transcript unchanged.
                    Return only the complete retouched transcript.
                    """
                ),
                ChatMessage(
                    role: "user",
                    content: """
                    Raw transcript:
                    \(request.text)

                    Retouched transcript:
                    """
                )
            ]
        )
    }

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
