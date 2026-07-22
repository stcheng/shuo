import Foundation

enum OpenAITranscriptionError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidBaseURL(String)
    case invalidModelID(OpenAITranscriptionModelIDValidationError)
    case customEndpointVerificationRequired
    case requestFailed(statusCode: Int, message: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add an OpenAI API key in Settings before using the OpenAI provider."
        case .invalidBaseURL(let baseURL):
            return OpenAICompatibleRequestBuilder.endpointValidationMessage(
                baseURLString: baseURL
            )
        case .invalidModelID(let error):
            return error.localizedDescription
        case .customEndpointVerificationRequired:
            return "Test the selected model for this custom service before sending a recording."
        case .requestFailed(let statusCode, let message):
            return "OpenAI transcription failed (\(statusCode)): \(message)"
        case .invalidResponse:
            return "The transcription endpoint returned an invalid response."
        }
    }
}

private struct OpenAITranscriptionResponse: Decodable {
    let text: String
}

struct OpenAITranscriptionService: TranscriptionService {
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

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        guard let apiKey = OpenAICompatibleRequestBuilder.normalizedAPIKey(request.apiKey) else {
            throw OpenAITranscriptionError.missingAPIKey
        }
        guard !request.settings.requiresCustomOpenAITranscriptionVerification else {
            throw OpenAITranscriptionError.customEndpointVerificationRequired
        }

        let modelID: String
        do {
            modelID = try OpenAIModelCatalog.validatedFixedTranscriptionModelID(
                request.settings.effectiveModel
            )
        } catch let error as OpenAITranscriptionModelIDValidationError {
            throw OpenAITranscriptionError.invalidModelID(error)
        }

        let audioData = try Data(contentsOf: request.audioFileURL)
        let profile: OpenAITranscriptionRequestProfile =
            OpenAICompatibleRequestBuilder.usesOpenAICompatibleMinimalRequestProfile(
                baseURLString: request.settings.openAIBaseURL
            ) ? .compatibleMinimal : .openAIStandard
        return try await transcribe(
            audioData: audioData,
            filename: request.audioFileURL.lastPathComponent,
            mimeType: request.audioFileURL.mimeType,
            modelID: modelID,
            settings: request.settings,
            apiKey: apiKey,
            context: request.context,
            vocabulary: request.vocabulary,
            profile: profile
        )
    }

    /// Tests only the OpenAI-style audio-transcriptions contract with a short,
    /// generated silent WAV. It never reuses a user's recording or context.
    func verifySelectedModel(settings: AppSettings, apiKey: String?) async throws {
        guard let apiKey = OpenAICompatibleRequestBuilder.normalizedAPIKey(apiKey) else {
            throw OpenAITranscriptionError.missingAPIKey
        }

        let modelID: String
        do {
            modelID = try OpenAIModelCatalog.validatedFixedTranscriptionModelID(
                settings.effectiveModel
            )
        } catch let error as OpenAITranscriptionModelIDValidationError {
            throw OpenAITranscriptionError.invalidModelID(error)
        }

        _ = try await transcribe(
            audioData: OpenAIProtocolTestAudio.wavData,
            filename: OpenAIProtocolTestAudio.filename,
            mimeType: OpenAIProtocolTestAudio.mimeType,
            modelID: modelID,
            settings: settings,
            apiKey: apiKey,
            context: "",
            vocabulary: .empty,
            profile: .compatibleMinimal
        )
    }

    private func transcribe(
        audioData: Data,
        filename: String,
        mimeType: String,
        modelID: String,
        settings: AppSettings,
        apiKey: String,
        context: String,
        vocabulary: TranscriptionVocabularySnapshot,
        profile: OpenAITranscriptionRequestProfile
    ) async throws -> TranscriptionResult {

        guard let endpoint = OpenAICompatibleRequestBuilder.endpoint(
            baseURLString: settings.openAIBaseURL,
            path: "audio/transcriptions"
        ) else {
            throw OpenAITranscriptionError.invalidBaseURL(settings.openAIBaseURL)
        }
        let boundary = "Boundary-\(UUID().uuidString)"
        var urlRequest = OpenAICompatibleRequestBuilder.authenticatedPOSTRequest(
            endpoint: endpoint,
            apiKey: apiKey,
            settings: settings,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )

        urlRequest.httpBody = try makeMultipartBody(
            boundary: boundary,
            audioData: audioData,
            filename: filename,
            mimeType: mimeType,
            modelID: modelID,
            settings: settings,
            context: context,
            vocabulary: vocabulary,
            profile: profile
        )

        let (data, response) = try await dataLoader(urlRequest)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let bodyText = String(data: data, encoding: .utf8) ?? ""

        guard (200..<300).contains(statusCode) else {
            throw OpenAITranscriptionError.requestFailed(
                statusCode: statusCode,
                message: OpenAICompatibleRequestBuilder.errorMessage(from: data, fallback: bodyText)
            )
        }

        guard let decoded = try? JSONDecoder().decode(OpenAITranscriptionResponse.self, from: data) else {
            throw OpenAITranscriptionError.invalidResponse
        }
        return TranscriptionResult(
            text: decoded.text.trimmingCharacters(in: .whitespacesAndNewlines),
            detectedLanguage: nil
        )
    }

    private func makeMultipartBody(
        boundary: String,
        audioData: Data,
        filename: String,
        mimeType: String,
        modelID: String,
        settings: AppSettings,
        context: String,
        vocabulary: TranscriptionVocabularySnapshot,
        profile: OpenAITranscriptionRequestProfile
    ) throws -> Data {
        var body = Data()

        body.appendFormField(name: "model", value: modelID, boundary: boundary)

        if profile == .openAIStandard {
            body.appendFormField(name: "response_format", value: "json", boundary: boundary)

            if let language = settings.languageHint.openAILanguageCode {
                body.appendFormField(name: "language", value: language, boundary: boundary)
            }

            let prompt = buildPrompt(
                settings: settings,
                context: context,
                vocabulary: vocabulary
            )
            if !prompt.isEmpty, modelID != "gpt-4o-transcribe-diarize" {
                body.appendFormField(name: "prompt", value: prompt, boundary: boundary)
            }
        }

        body.appendFileField(
            name: "file",
            filename: filename,
            contentType: mimeType,
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

}

private enum OpenAITranscriptionRequestProfile {
    case openAIStandard
    case compatibleMinimal
}

private enum OpenAIProtocolTestAudio {
    static let filename = "shuo-protocol-test.wav"
    static let mimeType = "audio/wav"
    static let wavData: Data = {
        let sampleRate: UInt32 = 8_000
        let sampleCount: UInt32 = 4_000
        let dataSize = sampleCount * 2
        var data = Data()
        data.append(Data("RIFF".utf8))
        data.appendLittleEndian(36 + dataSize)
        data.append(Data("WAVEfmt ".utf8))
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(sampleRate)
        data.appendLittleEndian(sampleRate * 2)
        data.appendLittleEndian(UInt16(2))
        data.appendLittleEndian(UInt16(16))
        data.append(Data("data".utf8))
        data.appendLittleEndian(dataSize)
        data.append(Data(repeating: 0, count: Int(dataSize)))
        return data
    }()
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
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

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
