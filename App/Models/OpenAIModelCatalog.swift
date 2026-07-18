import Foundation

enum OpenAIModelSelectionError: LocalizedError, Equatable {
    case noCompatibleTranscriptionModel
    case noCompatibleTextModel

    var errorDescription: String? {
        switch self {
        case .noCompatibleTranscriptionModel:
            return "This API account returned no Shuo-compatible transcription model. Refresh models or choose a fixed model."
        case .noCompatibleTextModel:
            return "This API account returned no compatible model for optional cloud text features. Transcription can still use a separately selected model."
        }
    }
}

enum OpenAITranscriptionModelIDValidationError: LocalizedError, Equatable {
    case empty
    case tooLong
    case containsControlCharacter

    var errorDescription: String? {
        switch self {
        case .empty:
            return "Enter a transcription model ID."
        case .tooLong:
            return "The transcription model ID is too long."
        case .containsControlCharacter:
            return "The transcription model ID cannot contain line breaks or control characters."
        }
    }
}

enum OpenAIModelSelectionMode: String, CaseIterable, Codable, Identifiable {
    case automatic
    case fixed

    var id: String { rawValue }
}

/// Text processing can be disabled independently from transcription. Keep this
/// separate from `OpenAIModelSelectionMode`: transcription must always resolve
/// to either an automatic or explicitly selected model.
enum OpenAITextModelSelectionMode: String, CaseIterable, Codable, Identifiable {
    case automatic
    case fixed
    case disabled

    var id: String { rawValue }
}

enum OpenAIModelPurpose: String, Equatable {
    case accuracy
    case speedAndCost
    case compatibility
    case textPostProcessing
}

struct OpenAIModelDescriptor: Identifiable, Equatable {
    let id: String
    let displayName: String
    let purpose: OpenAIModelPurpose
}

struct OpenAIModelCatalog {
    static let maximumTranscriptionModelIDLength = 200

    static let transcriptionModels = [
        OpenAIModelDescriptor(
            id: "gpt-4o-transcribe",
            displayName: "GPT-4o Transcribe",
            purpose: .accuracy
        ),
        OpenAIModelDescriptor(
            id: "gpt-4o-mini-transcribe",
            displayName: "GPT-4o mini Transcribe",
            purpose: .speedAndCost
        ),
        OpenAIModelDescriptor(
            id: "whisper-1",
            displayName: "Whisper-1 · Cloud API",
            purpose: .compatibility
        ),
        OpenAIModelDescriptor(
            id: "whisper-large-v3-turbo",
            displayName: "Whisper Large V3 Turbo",
            purpose: .speedAndCost
        ),
        OpenAIModelDescriptor(
            id: "whisper-large-v3",
            displayName: "Whisper Large V3",
            purpose: .accuracy
        ),
        OpenAIModelDescriptor(
            id: "FunAudioLLM/SenseVoiceSmall",
            displayName: "SenseVoice Small",
            purpose: .accuracy
        ),
        OpenAIModelDescriptor(
            id: "TeleAI/TeleSpeechASR",
            displayName: "TeleSpeech ASR",
            purpose: .speedAndCost
        )
    ]

    static let textModels = [
        OpenAIModelDescriptor(
            id: "gpt-5.4-mini",
            displayName: "GPT-5.4 mini",
            purpose: .textPostProcessing
        ),
        OpenAIModelDescriptor(
            id: "gpt-4.1-mini",
            displayName: "GPT-4.1 mini",
            purpose: .textPostProcessing
        ),
        OpenAIModelDescriptor(
            id: "openai/gpt-oss-20b",
            displayName: "GPT-OSS 20B",
            purpose: .textPostProcessing
        ),
        OpenAIModelDescriptor(
            id: "openai/gpt-oss-120b",
            displayName: "GPT-OSS 120B",
            purpose: .textPostProcessing
        ),
        OpenAIModelDescriptor(
            id: "llama-3.1-8b-instant",
            displayName: "Llama 3.1 8B Instant",
            purpose: .textPostProcessing
        ),
        OpenAIModelDescriptor(
            id: "Qwen/Qwen-3-8B",
            displayName: "Qwen 3 8B",
            purpose: .textPostProcessing
        ),
        OpenAIModelDescriptor(
            id: "THUDM/GLM-4-9B-0414",
            displayName: "GLM-4 9B",
            purpose: .textPostProcessing
        )
    ]

    static let defaultTranscriptionModelID = transcriptionModels[0].id
    static let defaultTextModelID = textModels[0].id

    /// Automatic transcription favors the most accurate compatible model before
    /// considering lower-latency or broad-compatibility alternatives.
    private static let transcriptionRecommendationOrder = [
        "gpt-4o-transcribe",
        "whisper-large-v3",
        "gpt-4o-mini-transcribe",
        "whisper-large-v3-turbo",
        "whisper-1",
        "FunAudioLLM/SenseVoiceSmall",
        "TeleAI/TeleSpeechASR"
    ]

    static var transcriptionModelIDs: [String] {
        transcriptionModels.map(\.id)
    }

    static var textModelIDs: [String] {
        textModels.map(\.id)
    }

    static func recommendedTranscriptionModelID(
        availableModelIDs: Set<String>?
    ) -> String? {
        guard let availableModelIDs else {
            return defaultTranscriptionModelID
        }

        return transcriptionRecommendationOrder.first(where: availableModelIDs.contains)
    }

    static func normalizedAutomaticTranscriptionModelID(_ modelID: String) -> String {
        transcriptionModels.contains(where: { $0.id == modelID })
            ? modelID
            : defaultTranscriptionModelID
    }

    static func recommendedTextModelID(availableModelIDs: Set<String>?) -> String? {
        guard let availableModelIDs else {
            return defaultTextModelID
        }

        return textModels
            .map(\.id)
            .first(where: availableModelIDs.contains)
    }

    static func normalizedAutomaticTextModelID(_ modelID: String) -> String {
        textModels.contains(where: { $0.id == modelID })
            ? modelID
            : defaultTextModelID
    }

    static func normalizedTextModelID(_ modelID: String) -> String {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.caseInsensitiveCompare("chat-latest") == .orderedSame {
            return defaultTextModelID
        }
        return trimmed
    }

    /// `/models` returns one mixed catalog for many OpenAI-compatible
    /// providers. Shuo's two menus call different API contracts, so keep
    /// obvious non-matching capabilities out of each menu while retaining
    /// newly introduced provider models that use conventional IDs.
    static func supportsTranscription(_ modelID: String) -> Bool {
        let normalized = modelID.lowercased()
        return transcriptionModels.contains {
            $0.id.caseInsensitiveCompare(modelID) == .orderedSame
        }
            || normalized.contains("asr")
            || normalized.contains("transcribe")
            || normalized.contains("whisper")
            || normalized.contains("sensevoice")
            || normalized.contains("speech-to-text")
    }

    static func supportsTextGeneration(_ modelID: String) -> Bool {
        let normalized = modelID.lowercased()
        guard !supportsTranscription(modelID) else {
            return false
        }

        let nonTextCapabilities = [
            "embedding", "embed", "rerank", "bge-", "gte-",
            "stable-diffusion", "text-to-image", "image-to-image",
            "text-to-video", "image-to-video", "video", "kolors",
            "flux", "wan-", "tts", "text-to-speech", "cosyvoice"
        ]
        return !nonTextCapabilities.contains { normalized.contains($0) }
    }

    static func validatedFixedTranscriptionModelID(_ modelID: String) throws -> String {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw OpenAITranscriptionModelIDValidationError.empty
        }
        guard trimmed.count <= maximumTranscriptionModelIDLength else {
            throw OpenAITranscriptionModelIDValidationError.tooLong
        }
        guard !trimmed.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0)
        }) else {
            throw OpenAITranscriptionModelIDValidationError.containsControlCharacter
        }
        return trimmed
    }

    static func errorIndicatesUnavailableModel(statusCode: Int, message: String) -> Bool {
        guard [400, 403, 404].contains(statusCode) else {
            return false
        }

        let normalized = message.lowercased()
        guard normalized.contains("model") else {
            return false
        }

        return normalized.contains("not found")
            || normalized.contains("does not exist")
            || normalized.contains("do not have access")
            || normalized.contains("not have access")
            || normalized.contains("permission")
            || normalized.contains("unsupported")
    }
}
