import Foundation

enum OpenAIModelSelectionError: LocalizedError, Equatable {
    case noCompatibleTranscriptionModel
    case noCompatibleTextModel

    var errorDescription: String? {
        switch self {
        case .noCompatibleTranscriptionModel:
            return "This API account returned no Shuo-compatible transcription model. Refresh models or choose a fixed model."
        case .noCompatibleTextModel:
            return "This API account returned no Shuo-compatible text model. Refresh models or choose a fixed text model."
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
        )
    ]

    static let defaultTranscriptionModelID = transcriptionModels[0].id
    static let defaultTextModelID = textModels[0].id

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

        return transcriptionModels
            .map(\.id)
            .first(where: availableModelIDs.contains)
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
