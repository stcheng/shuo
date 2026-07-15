import Foundation

enum AlibabaTranscriptionError: LocalizedError {
    case missingAPIKey
    case audioFileUnavailable(String)
    case audioFileTooLarge(encodedByteCount: Int64, maximumByteCount: Int)
    case invalidResponse
    case emptyResponse
    case requestFailed(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add an Alibaba Cloud Model Studio API key in Settings before using Qwen ASR."
        case .audioFileUnavailable(let message):
            return "Shuo could not read the audio file: \(message)"
        case .audioFileTooLarge(_, let maximumByteCount):
            return "The Base64-encoded audio exceeds Alibaba Cloud's \(maximumByteCount / 1_048_576) MB input limit."
        case .invalidResponse:
            return "Alibaba Cloud returned a response that Shuo could not read."
        case .emptyResponse:
            return "Alibaba Cloud returned an empty transcription."
        case .requestFailed(let statusCode, let message):
            return "Alibaba Cloud transcription failed (\(statusCode)): \(message)"
        }
    }
}

private struct AlibabaTranscriptionRequestBody: Encodable {
    let model: String
    let messages: [Message]
    let stream: Bool
    let asrOptions: ASROptions

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case asrOptions = "asr_options"
    }

    struct Message: Encodable {
        let role: String
        let content: [Content]
    }

    struct Content: Encodable {
        let type: String
        let inputAudio: InputAudio

        enum CodingKeys: String, CodingKey {
            case type
            case inputAudio = "input_audio"
        }
    }

    struct InputAudio: Encodable {
        let data: String
    }

    struct ASROptions: Encodable {
        let language: String?
        let enableITN: Bool

        enum CodingKeys: String, CodingKey {
            case language
            case enableITN = "enable_itn"
        }
    }
}

private struct AlibabaTranscriptionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String
        let annotations: [Annotation]?
    }

    struct Annotation: Decodable {
        let language: String?
    }
}

struct AlibabaTranscriptionService: TranscriptionService {
    typealias DataLoader = (URLRequest) async throws -> (Data, URLResponse)

    static let endpoint = URL(
        string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
    )!
    static let modelID = "qwen3-asr-flash"

    /// Model Studio applies this limit to the Base64 value, after encoding.
    static let maximumEncodedAudioByteCount = 10 * 1_024 * 1_024

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
        let (data, response) = try await dataLoader(urlRequest)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard (200 ..< 300).contains(statusCode) else {
            throw AlibabaTranscriptionError.requestFailed(
                statusCode: statusCode,
                message: Self.providerErrorMessage(from: data)
            )
        }

        return try Self.parseResponse(
            data,
            fallbackLanguage: Self.languageCode(for: request.settings)
        )
    }

    func makeURLRequest(_ request: TranscriptionRequest) throws -> URLRequest {
        guard let apiKey = Self.normalizedAPIKey(request.apiKey) else {
            throw AlibabaTranscriptionError.missingAPIKey
        }

        let audioData = try Self.readAudioData(at: request.audioFileURL)
        let encodedAudio = audioData.base64EncodedString()
        guard encodedAudio.utf8.count <= Self.maximumEncodedAudioByteCount else {
            throw AlibabaTranscriptionError.audioFileTooLarge(
                encodedByteCount: Int64(encodedAudio.utf8.count),
                maximumByteCount: Self.maximumEncodedAudioByteCount
            )
        }

        let dataURL = "data:\(Self.mimeType(for: request.audioFileURL));base64,\(encodedAudio)"
        let body = AlibabaTranscriptionRequestBody(
            model: Self.modelID,
            messages: [
                .init(
                    role: "user",
                    content: [
                        .init(
                            type: "input_audio",
                            inputAudio: .init(data: dataURL)
                        )
                    ]
                )
            ],
            stream: false,
            asrOptions: .init(
                language: Self.languageCode(for: request.settings),
                enableITN: true
            )
        )

        var urlRequest = URLRequest(url: Self.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try JSONEncoder().encode(body)
        return urlRequest
    }

    static func parseResponse(
        _ data: Data,
        fallbackLanguage: String? = nil
    ) throws -> TranscriptionResult {
        let response: AlibabaTranscriptionResponse
        do {
            response = try JSONDecoder().decode(AlibabaTranscriptionResponse.self, from: data)
        } catch {
            throw AlibabaTranscriptionError.invalidResponse
        }

        guard let message = response.choices.first?.message else {
            throw AlibabaTranscriptionError.invalidResponse
        }

        let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw AlibabaTranscriptionError.emptyResponse
        }

        let detectedLanguage = message.annotations?
            .compactMap(\.language)
            .first ?? fallbackLanguage
        return TranscriptionResult(text: text, detectedLanguage: detectedLanguage)
    }

    static func languageCode(for settings: AppSettings) -> String? {
        guard settings.selectedTranscriptionLanguages.count == 1,
              let language = settings.selectedTranscriptionLanguages.first else {
            return nil
        }

        switch language.rawValue {
        case "chinese":
            return "zh"
        case "english":
            return "en"
        case "japanese":
            return "ja"
        case "french":
            return "fr"
        case "spanish":
            return "es"
        default:
            return nil
        }
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
        case "wma":
            return "audio/x-ms-wma"
        case "avi":
            return "video/x-msvideo"
        case "flv":
            return "video/x-flv"
        case "mkv":
            return "video/x-matroska"
        case "wmv":
            return "video/x-ms-wmv"
        default:
            return "application/octet-stream"
        }
    }

    static func providerErrorMessage(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any] {
                let message = error["message"] as? String
                let code = error["code"] as? String
                if let combined = combinedErrorMessage(code: code, message: message) {
                    return combined
                }
            }

            let message = object["message"] as? String
            let code = object["code"] as? String
            if let combined = combinedErrorMessage(code: code, message: message) {
                return combined
            }
        }

        return cleanedErrorMessage(String(data: data, encoding: .utf8) ?? "")
    }

    private static func normalizedAPIKey(_ apiKey: String?) -> String? {
        let trimmed = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func readAudioData(at audioFileURL: URL) throws -> Data {
        do {
            if let fileSize = try audioFileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                let predictedEncodedByteCount = Int64(4) * ((Int64(fileSize) + 2) / 3)
                guard predictedEncodedByteCount <= Int64(maximumEncodedAudioByteCount) else {
                    throw AlibabaTranscriptionError.audioFileTooLarge(
                        encodedByteCount: predictedEncodedByteCount,
                        maximumByteCount: maximumEncodedAudioByteCount
                    )
                }
            }

            return try Data(contentsOf: audioFileURL, options: .mappedIfSafe)
        } catch let error as AlibabaTranscriptionError {
            throw error
        } catch {
            throw AlibabaTranscriptionError.audioFileUnavailable(error.localizedDescription)
        }
    }

    private static func combinedErrorMessage(code: String?, message: String?) -> String? {
        let cleanedCode = cleanedErrorMessage(code ?? "", fallback: "")
        let cleanedMessage = cleanedErrorMessage(message ?? "", fallback: "")

        if !cleanedCode.isEmpty, !cleanedMessage.isEmpty, cleanedCode != cleanedMessage {
            return "\(cleanedCode): \(cleanedMessage)"
        }
        if !cleanedMessage.isEmpty {
            return cleanedMessage
        }
        if !cleanedCode.isEmpty {
            return cleanedCode
        }
        return nil
    }

    private static func cleanedErrorMessage(
        _ message: String,
        fallback: String = "Unknown error"
    ) -> String {
        let cleaned = message
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !cleaned.isEmpty else {
            return fallback
        }
        guard cleaned.count > 1_000 else {
            return cleaned
        }
        return String(cleaned.prefix(1_000)) + "..."
    }
}
