import Foundation
import OSLog

private enum GeminiAPIClient {
    static var headerValue: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "shuo/\(version ?? "development")"
    }
}

enum GeminiTranscriptionError: LocalizedError {
    case missingAPIKey
    case invalidModel(String)
    case audioFileUnavailable(String)
    case audioFileTooLarge(actualByteCount: Int, maximumByteCount: Int)
    case invalidResponse
    case emptyResponse
    case truncatedResponse
    case requestFailed(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add a Gemini API key in Settings before using Gemini transcription."
        case .invalidModel(let model):
            return "The selected Gemini model is not valid: \(model)"
        case .audioFileUnavailable(let message):
            return "Shuo could not read the audio file: \(message)"
        case .audioFileTooLarge(_, let maximumByteCount):
            return "The recording is too large for Gemini's inline audio request limit (\(maximumByteCount / 1_000_000) MB)."
        case .invalidResponse:
            return "Gemini returned a response that Shuo could not read."
        case .emptyResponse:
            return "Gemini returned an empty transcription."
        case .truncatedResponse:
            return "Gemini stopped before the transcription was complete."
        case .requestFailed(let statusCode, let message):
            return "Gemini transcription failed (\(statusCode)): \(message)"
        }
    }
}

/// Gemini 3.1 Flash-Lite is Shuo's single Gemini model. Its speed-oriented
/// thinking setting keeps the deliberately simple "return the transcript
/// only" requests responsive for both audio transcription and optional text
/// work.
private struct GeminiThinkingConfig: Encodable {
    let thinkingLevel = "minimal"

    enum CodingKeys: String, CodingKey {
        case thinkingLevel
    }
}

private struct GeminiGenerationConfig: Encodable {
    let maxOutputTokens: Int
    let thinkingConfig: GeminiThinkingConfig

    enum CodingKeys: String, CodingKey {
        case maxOutputTokens
        case thinkingConfig
    }

    init(maxOutputTokens: Int = 8_192) {
        self.maxOutputTokens = maxOutputTokens
        thinkingConfig = GeminiThinkingConfig()
    }
}

private struct GeminiGenerateContentRequest: Encodable {
    let contents: [Content]
    let generationConfig: GeminiGenerationConfig

    enum CodingKeys: String, CodingKey {
        case contents
        case generationConfig
    }

    struct Content: Encodable {
        let role: String
        let parts: [Part]
    }

    struct Part: Encodable {
        let text: String?
        let inlineData: InlineData?

        enum CodingKeys: String, CodingKey {
            case text
            case inlineData = "inline_data"
        }

        static func text(_ value: String) -> Part {
            Part(text: value, inlineData: nil)
        }

        static func audio(data: String, mimeType: String) -> Part {
            Part(
                text: nil,
                inlineData: InlineData(data: data, mimeType: mimeType)
            )
        }
    }

    struct InlineData: Encodable {
        let data: String
        let mimeType: String

        enum CodingKeys: String, CodingKey {
            case data
            case mimeType = "mime_type"
        }
    }

}

private struct GeminiGenerateContentResponse: Decodable {
    let candidates: [Candidate]

    struct Candidate: Decodable {
        let content: Content?
        let finishReason: String?
    }

    struct Content: Decodable {
        let parts: [Part]
    }

    struct Part: Decodable {
        let text: String?
    }
}

/// Gemini's native generateContent API accepts audio as an `inline_data` part.
/// Shuo records at 16 kHz mono and caps recordings at five minutes, so normal
/// recordings remain below Gemini's documented 20 MB inline request limit.
/// Larger imports fail before uploading rather than silently changing the
/// privacy/lifecycle behavior to the Files API.
struct GeminiTranscriptionService: TranscriptionService {
    typealias DataLoader = (URLRequest) async throws -> (Data, URLResponse)

    static let endpointBaseURL = CloudServiceCatalog.definition(for: .gemini).endpoint.fixedURL!
    // Keep the Gemini integration deliberately simple and responsive: one
    // audio-capable, low-latency model for transcription and optional text
    // enhancements alike.
    static let modelIDs = [CloudServiceCatalog.definition(for: .gemini).fixedTranscriptionModelID!]
    static let defaultModelID = modelIDs[0]
    static let maximumInlineRequestByteCount = 20_000_000

    private static let logger = Logger(
        subsystem: AppBuildIdentity.bundleIdentifier,
        category: "Gemini"
    )

    private let dataLoader: DataLoader

    init(session: URLSession = SensitiveRequestURLSession.shared) {
        dataLoader = { request in
            try await session.data(for: request)
        }
    }

    init(dataLoader: @escaping DataLoader) {
        self.dataLoader = dataLoader
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        let urlRequest = try makeURLRequest(request)
        let startedAt = Date()

        do {
            let (data, response) = try await dataLoader(urlRequest)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let elapsedMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
            let requestByteCount = urlRequest.httpBody?.count ?? 0
            Self.logger.info(
                "Gemini transcription response: model=\(request.settings.effectiveModel, privacy: .public) status=\(statusCode, privacy: .public) requestBytes=\(requestByteCount, privacy: .public) elapsedMs=\(elapsedMilliseconds, privacy: .public)"
            )

            guard (200 ..< 300).contains(statusCode) else {
                throw GeminiTranscriptionError.requestFailed(
                    statusCode: statusCode,
                    message: Self.providerErrorMessage(from: data)
                )
            }

            return try Self.parseResponse(
                data,
                fallbackLanguage: request.settings.languageHint.openAILanguageCode
            )
        } catch {
            let elapsedMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
            Self.logger.error(
                "Gemini transcription request failed: model=\(request.settings.effectiveModel, privacy: .public) elapsedMs=\(elapsedMilliseconds, privacy: .public)"
            )
            throw error
        }
    }

    func makeURLRequest(_ request: TranscriptionRequest) throws -> URLRequest {
        guard let apiKey = OpenAICompatibleRequestBuilder.normalizedAPIKey(request.apiKey) else {
            throw GeminiTranscriptionError.missingAPIKey
        }
        guard let endpoint = Self.endpoint(for: request.settings.effectiveModel) else {
            throw GeminiTranscriptionError.invalidModel(request.settings.effectiveModel)
        }

        let audioData: Data
        do {
            audioData = try Data(contentsOf: request.audioFileURL, options: .mappedIfSafe)
        } catch {
            throw GeminiTranscriptionError.audioFileUnavailable(error.localizedDescription)
        }
        let encodedAudio = audioData.base64EncodedString()
        let prompt = Self.transcriptionPrompt(
            settings: request.settings,
            context: request.context,
            vocabulary: request.vocabulary
        )
        let body = GeminiGenerateContentRequest(
            contents: [
                .init(
                    role: "user",
                    parts: [
                        .text(prompt),
                        .audio(
                            data: encodedAudio,
                            mimeType: Self.mimeType(for: request.audioFileURL)
                        )
                    ]
                )
            ],
            generationConfig: GeminiGenerationConfig()
        )
        let bodyData = try JSONEncoder().encode(body)
        guard bodyData.count <= Self.maximumInlineRequestByteCount else {
            throw GeminiTranscriptionError.audioFileTooLarge(
                actualByteCount: bodyData.count,
                maximumByteCount: Self.maximumInlineRequestByteCount
            )
        }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue(GeminiAPIClient.headerValue, forHTTPHeaderField: "x-goog-api-client")
        urlRequest.setValue(UUID().uuidString, forHTTPHeaderField: "X-Client-Request-Id")
        urlRequest.httpBody = bodyData
        return urlRequest
    }

    static func endpoint(for model: String) -> URL? {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard modelIDs.contains(trimmed) else {
            return nil
        }
        return endpointBaseURL.appendingPathComponent("models/\(trimmed):generateContent")
    }

    static func logTextCompletionResponse(
        model: String,
        statusCode: Int,
        requestByteCount: Int,
        elapsedMilliseconds: Int
    ) {
        logger.info(
            "Gemini text completion response: model=\(model, privacy: .public) status=\(statusCode, privacy: .public) requestBytes=\(requestByteCount, privacy: .public) elapsedMs=\(elapsedMilliseconds, privacy: .public)"
        )
    }

    static func logTextCompletionFailure(
        model: String,
        elapsedMilliseconds: Int
    ) {
        logger.error(
            "Gemini text completion request failed: model=\(model, privacy: .public) elapsedMs=\(elapsedMilliseconds, privacy: .public)"
        )
    }

    static func parseResponse(
        _ data: Data,
        fallbackLanguage: String? = nil
    ) throws -> TranscriptionResult {
        let response: GeminiGenerateContentResponse
        do {
            response = try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: data)
        } catch {
            throw GeminiTranscriptionError.invalidResponse
        }

        let text = response.candidates
            .flatMap { $0.content?.parts ?? [] }
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if response.candidates.contains(where: {
            $0.finishReason?.uppercased() == "MAX_TOKENS"
        }) {
            throw GeminiTranscriptionError.truncatedResponse
        }
        guard !text.isEmpty else {
            throw GeminiTranscriptionError.emptyResponse
        }

        return TranscriptionResult(text: text, detectedLanguage: fallbackLanguage)
    }

    static func transcriptionPrompt(
        settings: AppSettings,
        context: String,
        vocabulary: TranscriptionVocabularySnapshot
    ) -> String {
        var parts = [
            "Transcribe only the speech actually heard in this audio. Return only the complete transcript—no explanation, summary, labels, timestamps, Markdown, or translation. Preserve the spoken language mix, names, numbers, code, and natural punctuation. Do not copy or infer speech from the reference context or spelling hints. If there is no clear speech, return an empty response."
        ]

        if let language = settings.languageHint.openAILanguageCode {
            parts.append("The expected spoken language is \(language), but still transcribe only what is audible.")
        }

        let trimmedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedContext.isEmpty {
            parts.append("Reference context only (never copy it into the transcript):\n\(trimmedContext)")
        }
        if !vocabulary.prompt.isEmpty {
            parts.append("Spelling preferences only (never copy them unless spoken):\n\(vocabulary.prompt)")
        }

        return parts.joined(separator: "\n\n")
    }

    static func mimeType(for audioFileURL: URL) -> String {
        switch audioFileURL.pathExtension.lowercased() {
        case "wav":
            return "audio/wav"
        case "mp3", "mpeg", "mpga":
            return "audio/mpeg"
        case "m4a", "mp4":
            return "audio/mp4"
        case "aac":
            return "audio/aac"
        case "aif", "aiff", "aifc":
            return "audio/aiff"
        case "amr":
            return "audio/amr"
        case "caf":
            return "audio/x-caf"
        case "flac":
            return "audio/flac"
        case "ogg", "oga":
            return "audio/ogg"
        case "opus":
            return "audio/opus"
        case "webm":
            return "audio/webm"
        default:
            return "application/octet-stream"
        }
    }

    static func providerErrorMessage(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            return cleanedErrorMessage(message)
        }

        return cleanedErrorMessage(String(data: data, encoding: .utf8) ?? "")
    }

    private static func cleanedErrorMessage(_ message: String) -> String {
        let cleaned = message
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !cleaned.isEmpty else {
            return "Unknown error"
        }
        guard cleaned.count <= 1_000 else {
            return String(cleaned.prefix(1_000)) + "..."
        }
        return cleaned
    }
}

private struct GeminiTextGenerateContentRequest: Encodable {
    let systemInstruction: SystemInstruction
    let contents: [Content]
    let generationConfig: GeminiGenerationConfig

    enum CodingKeys: String, CodingKey {
        case systemInstruction
        case contents
        case generationConfig
    }

    struct SystemInstruction: Encodable {
        let parts: [Part]
    }

    struct Content: Encodable {
        let role: String
        let parts: [Part]
    }

    struct Part: Encodable {
        let text: String
    }

}

/// Shared Gemini completion path for optional transcript retouch, voice edit,
/// and AI emoji resolution. It deliberately uses the selected Gemini
/// transcription model and the same Gemini credential; it never reads
/// OpenAI-compatible connection settings or credentials.
struct GeminiTextCompletionService {
    typealias DataLoader = (URLRequest) async throws -> (Data, URLResponse)

    private let dataLoader: DataLoader

    init(session: URLSession = SensitiveRequestURLSession.shared) {
        dataLoader = { request in
            try await session.data(for: request)
        }
    }

    init(dataLoader: @escaping DataLoader) {
        self.dataLoader = dataLoader
    }

    func complete(
        systemInstruction: String,
        userContent: String,
        settings: AppSettings,
        apiKey: String?
    ) async throws -> String {
        let request = try makeURLRequest(
            systemInstruction: systemInstruction,
            userContent: userContent,
            settings: settings,
            apiKey: apiKey
        )
        let startedAt = Date()
        do {
            let (data, response) = try await dataLoader(request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let elapsedMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
            let requestByteCount = request.httpBody?.count ?? 0
            GeminiTranscriptionService.logTextCompletionResponse(
                model: settings.effectiveModel,
                statusCode: statusCode,
                requestByteCount: requestByteCount,
                elapsedMilliseconds: elapsedMilliseconds
            )

            guard (200 ..< 300).contains(statusCode) else {
                throw VoiceEditLLMError.requestFailed(
                    statusCode: statusCode,
                    message: GeminiTranscriptionService.providerErrorMessage(from: data)
                )
            }

            return try Self.parseResponse(data)
        } catch {
            GeminiTranscriptionService.logTextCompletionFailure(
                model: settings.effectiveModel,
                elapsedMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000)
            )
            throw error
        }
    }

    func makeURLRequest(
        systemInstruction: String,
        userContent: String,
        settings: AppSettings,
        apiKey: String?
    ) throws -> URLRequest {
        guard let apiKey = OpenAICompatibleRequestBuilder.normalizedAPIKey(apiKey) else {
            throw VoiceEditLLMError.missingAPIKey
        }
        guard let endpoint = GeminiTranscriptionService.endpoint(for: settings.effectiveModel) else {
            throw VoiceEditLLMError.requestFailed(
                statusCode: 0,
                message: "The selected Gemini model is not valid."
            )
        }

        let body = GeminiTextGenerateContentRequest(
            systemInstruction: .init(parts: [.init(text: systemInstruction)]),
            contents: [
                .init(role: "user", parts: [.init(text: userContent)])
            ],
            generationConfig: GeminiGenerationConfig()
        )

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue(GeminiAPIClient.headerValue, forHTTPHeaderField: "x-goog-api-client")
        urlRequest.setValue(UUID().uuidString, forHTTPHeaderField: "X-Client-Request-Id")
        urlRequest.httpBody = try JSONEncoder().encode(body)
        return urlRequest
    }

    static func parseResponse(_ data: Data) throws -> String {
        let response: GeminiGenerateContentResponse
        do {
            response = try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: data)
        } catch {
            throw VoiceEditLLMError.emptyResponse
        }

        if response.candidates.contains(where: {
            $0.finishReason?.uppercased() == "MAX_TOKENS"
        }) {
            throw VoiceEditLLMError.requestFailed(
                statusCode: 0,
                message: "Gemini stopped because its response reached the token limit."
            )
        }

        let text = response.candidates
            .flatMap { $0.content?.parts ?? [] }
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw VoiceEditLLMError.emptyResponse
        }
        return text
    }
}
