import Foundation

enum ElevenLabsTranscriptionError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case requestFailed(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add an ElevenLabs API key in Settings before using ElevenLabs."
        case .invalidResponse:
            return "ElevenLabs returned a response that Shuo could not read."
        case .requestFailed(let statusCode, let message):
            return "ElevenLabs transcription failed (\(statusCode)): \(message)"
        }
    }
}

private struct ElevenLabsTranscriptionResponse: Decodable {
    let text: String
    let languageCode: String?

    enum CodingKeys: String, CodingKey {
        case text
        case languageCode = "language_code"
    }
}

struct ElevenLabsTranscriptionService: TranscriptionService {
    static let endpoint = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!
    static let modelID = "scribe_v2"
    static let maximumKeytermCount = 100

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        let boundary = "Boundary-\(UUID().uuidString)"
        let urlRequest = try makeURLRequest(request, boundary: boundary)
        let (data, response) = try await SensitiveRequestURLSession.shared.data(for: urlRequest)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let bodyText = String(data: data, encoding: .utf8) ?? ""

        guard (200..<300).contains(statusCode) else {
            throw ElevenLabsTranscriptionError.requestFailed(
                statusCode: statusCode,
                message: errorMessage(from: data, fallback: bodyText)
            )
        }

        guard let result = try? JSONDecoder().decode(
            ElevenLabsTranscriptionResponse.self,
            from: data
        ) else {
            throw ElevenLabsTranscriptionError.invalidResponse
        }

        return TranscriptionResult(
            text: result.text.trimmingCharacters(in: .whitespacesAndNewlines),
            detectedLanguage: result.languageCode
        )
    }

    func makeURLRequest(
        _ request: TranscriptionRequest,
        boundary: String
    ) throws -> URLRequest {
        guard let apiKey = normalizedAPIKey(request.apiKey) else {
            throw ElevenLabsTranscriptionError.missingAPIKey
        }

        var urlRequest = URLRequest(url: Self.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        urlRequest.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        urlRequest.httpBody = try makeMultipartBody(
            boundary: boundary,
            audioFileURL: request.audioFileURL,
            languageHint: request.settings.languageHint,
            vocabulary: request.vocabulary
        )
        return urlRequest
    }

    func makeMultipartBody(
        boundary: String,
        audioFileURL: URL,
        languageHint: LanguageHint,
        vocabulary: TranscriptionVocabularySnapshot
    ) throws -> Data {
        var body = Data()
        body.appendElevenLabsFormField(
            name: "model_id",
            value: Self.modelID,
            boundary: boundary
        )
        body.appendElevenLabsFormField(
            name: "tag_audio_events",
            value: "false",
            boundary: boundary
        )
        body.appendElevenLabsFormField(
            name: "no_verbatim",
            value: "false",
            boundary: boundary
        )

        if let languageCode = languageHint.elevenLabsLanguageCode {
            body.appendElevenLabsFormField(
                name: "language_code",
                value: languageCode,
                boundary: boundary
            )
        }

        for keyterm in Self.keyterms(from: vocabulary.terms) {
            body.appendElevenLabsFormField(
                name: "keyterms",
                value: keyterm,
                boundary: boundary
            )
        }

        body.appendElevenLabsFileField(
            name: "file",
            filename: audioFileURL.lastPathComponent,
            contentType: audioFileURL.elevenLabsMIMEType,
            data: try Data(contentsOf: audioFileURL),
            boundary: boundary
        )
        body.appendElevenLabsString("--\(boundary)--\r\n")
        return body
    }

    static func keyterms(from terms: [String]) -> [String] {
        let unsupportedCharacters = CharacterSet(charactersIn: "<>{}[]\\")
        var seen = Set<String>()
        var keyterms: [String] = []

        for term in terms {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = trimmed.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: nil
            ).lowercased()
            let wordCount = trimmed.split(whereSeparator: \Character.isWhitespace).count

            guard !trimmed.isEmpty,
                  trimmed.count < 50,
                  wordCount <= 5,
                  trimmed.rangeOfCharacter(from: unsupportedCharacters) == nil,
                  seen.insert(normalized).inserted else {
                continue
            }

            keyterms.append(trimmed)
            if keyterms.count == maximumKeytermCount {
                break
            }
        }
        return keyterms
    }

    private func normalizedAPIKey(_ apiKey: String?) -> String? {
        let trimmed = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func errorMessage(from data: Data, fallback: String) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let detail = object["detail"] as? [String: Any],
               let message = detail["message"] as? String {
                return message
            }
            if let detail = object["detail"] as? String {
                return detail
            }
            if let message = object["message"] as? String {
                return message
            }
        }
        return fallback.isEmpty ? "Unknown error" : fallback
    }
}

private extension URL {
    var elevenLabsMIMEType: String {
        switch pathExtension.lowercased() {
        case "m4a", "mp4":
            return "audio/mp4"
        case "mp3", "mpeg", "mpga":
            return "audio/mpeg"
        case "wav":
            return "audio/wav"
        case "webm":
            return "audio/webm"
        default:
            return "application/octet-stream"
        }
    }
}

private extension Data {
    mutating func appendElevenLabsFormField(
        name: String,
        value: String,
        boundary: String
    ) {
        appendElevenLabsString("--\(boundary)\r\n")
        appendElevenLabsString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        appendElevenLabsString("\(value)\r\n")
    }

    mutating func appendElevenLabsFileField(
        name: String,
        filename: String,
        contentType: String,
        data: Data,
        boundary: String
    ) {
        appendElevenLabsString("--\(boundary)\r\n")
        appendElevenLabsString(
            "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"
        )
        appendElevenLabsString("Content-Type: \(contentType)\r\n\r\n")
        append(data)
        appendElevenLabsString("\r\n")
    }

    mutating func appendElevenLabsString(_ string: String) {
        append(Data(string.utf8))
    }
}
