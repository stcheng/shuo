import Foundation

enum OpenAITranscriptionError: LocalizedError {
    case missingAPIKey
    case invalidBaseURL(String)
    case requestFailed(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add an OpenAI API key in Settings before using the OpenAI provider."
        case .invalidBaseURL(let baseURL):
            return OpenAICompatibleRequestBuilder.endpointValidationMessage(
                baseURLString: baseURL
            )
        case .requestFailed(let statusCode, let message):
            return "OpenAI transcription failed (\(statusCode)): \(message)"
        }
    }
}

private struct OpenAITranscriptionResponse: Decodable {
    let text: String
}

struct OpenAITranscriptionService: TranscriptionService {
    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        guard let apiKey = OpenAICompatibleRequestBuilder.normalizedAPIKey(request.apiKey) else {
            throw OpenAITranscriptionError.missingAPIKey
        }

        guard let endpoint = OpenAICompatibleRequestBuilder.endpoint(
            baseURLString: request.settings.openAIBaseURL,
            path: "audio/transcriptions"
        ) else {
            throw OpenAITranscriptionError.invalidBaseURL(request.settings.openAIBaseURL)
        }
        let boundary = "Boundary-\(UUID().uuidString)"
        var urlRequest = OpenAICompatibleRequestBuilder.authenticatedPOSTRequest(
            endpoint: endpoint,
            apiKey: apiKey,
            settings: request.settings,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )

        urlRequest.httpBody = try makeMultipartBody(
            boundary: boundary,
            audioFileURL: request.audioFileURL,
            settings: request.settings,
            context: request.context,
            vocabulary: request.vocabulary
        )

        let (data, response) = try await SensitiveRequestURLSession.shared.data(for: urlRequest)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let bodyText = String(data: data, encoding: .utf8) ?? ""

        guard (200..<300).contains(statusCode) else {
            throw OpenAITranscriptionError.requestFailed(
                statusCode: statusCode,
                message: OpenAICompatibleRequestBuilder.errorMessage(from: data, fallback: bodyText)
            )
        }

        return TranscriptionResult(
            text: transcriptionText(from: data, fallback: bodyText),
            detectedLanguage: nil
        )
    }

    private func makeMultipartBody(
        boundary: String,
        audioFileURL: URL,
        settings: AppSettings,
        context: String,
        vocabulary: TranscriptionVocabularySnapshot
    ) throws -> Data {
        var body = Data()

        body.appendFormField(name: "model", value: settings.effectiveModel, boundary: boundary)
        body.appendFormField(name: "response_format", value: "json", boundary: boundary)

        if let language = settings.languageHint.openAILanguageCode {
            body.appendFormField(name: "language", value: language, boundary: boundary)
        }

        let prompt = buildPrompt(
            settings: settings,
            context: context,
            vocabulary: vocabulary
        )
        if !prompt.isEmpty, settings.effectiveModel != "gpt-4o-transcribe-diarize" {
            body.appendFormField(name: "prompt", value: prompt, boundary: boundary)
        }

        let audioData = try Data(contentsOf: audioFileURL)
        body.appendFileField(
            name: "file",
            filename: audioFileURL.lastPathComponent,
            contentType: audioFileURL.mimeType,
            data: audioData,
            boundary: boundary
        )

        body.appendString("--\(boundary)--\r\n")
        return body
    }

    func buildPrompt(
        settings: AppSettings,
        context: String,
        vocabulary: TranscriptionVocabularySnapshot = .empty
    ) -> String {
        var parts = [promptSafetyInstruction(for: settings.selectedTranscriptionLanguages)]

        parts.append(context.trimmingCharacters(in: .whitespacesAndNewlines))

        if !vocabulary.prompt.isEmpty {
            parts.append("Prefer these spellings for names and technical terms:\n\(vocabulary.prompt)")
        }

        if settings.appliesPunctuationPostProcessing {
            parts.append(
                "Use normal punctuation where it naturally belongs. Shuo applies deterministic local text cleanup after transcription."
            )
        }

        return parts
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private func promptSafetyInstruction(
        for languages: Set<TranscriptionLanguage>
    ) -> String {
        // The transcription prompt is a weak prior, not a system prompt. Keep
        // its language aligned with the user's likely speech instead of
        // front-loading every mixed-language request with English prose.
        if languages.contains(.chinese) {
            return "只转写音频中实际说出的内容，不翻译。下方上下文和拼写提示仅作参考，不得抄写，也不得据此改变输出语言。没有清晰人声、只有静音或背景噪音时，返回空文本。"
        }
        if languages.contains(.japanese) {
            return "音声で実際に話された内容だけを書き起こし、翻訳しないでください。以下の文脈と表記ヒントは参考用であり、転記したり出力言語を決める根拠にしたりしないでください。明瞭な発話がなく、無音または背景雑音だけの場合は空のテキストを返してください。"
        }
        if languages.contains(.spanish) {
            return "Transcribe solo lo que se dice en el audio; no lo traduzcas. El contexto y las pistas de ortografía siguientes son solo de referencia: no los copies ni elijas el idioma de salida a partir de ellos. Si no hay voz clara, solo silencio o ruido de fondo, devuelve texto vacío."
        }
        if languages.contains(.french) {
            return "Transcrivez uniquement ce qui est dit dans l’audio, sans traduire. Le contexte et les indices orthographiques ci-dessous ne sont que des références : ne les recopiez pas et ne choisissez pas la langue de sortie à partir d’eux. S’il n’y a pas de parole claire, seulement du silence ou du bruit, renvoyez un texte vide."
        }
        return "Transcribe only the spoken audio. Do not translate. Treat the context and spelling hints below as non-spoken reference only: never copy them into the transcript or choose an output language from them. If there is no clear speech, only silence, or only background noise, return an empty transcript."
    }

    private func transcriptionText(from data: Data, fallback: String) -> String {
        if let response = try? JSONDecoder().decode(OpenAITranscriptionResponse.self, from: data) {
            return response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    }

}

private extension URL {
    var mimeType: String {
        switch pathExtension.lowercased() {
        case "m4a", "mp4":
            return "audio/mp4"
        case "mp3":
            return "audio/mpeg"
        case "mpeg", "mpga":
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
    mutating func appendFormField(name: String, value: String, boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        appendString("\(value)\r\n")
    }

    mutating func appendFileField(name: String, filename: String, contentType: String, data: Data, boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        appendString("Content-Type: \(contentType)\r\n\r\n")
        append(data)
        appendString("\r\n")
    }

    mutating func appendString(_ string: String) {
        append(Data(string.utf8))
    }
}
