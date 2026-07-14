import Foundation

struct TranscriptProcessingResult {
    let rawText: String
    let locallyProcessedText: String
    let text: String
}

struct PreparedTranscript {
    let transcript: String
    let rawText: String
    let locallyProcessedText: String
}

@MainActor
final class TranscriptProcessingWorkflow {
    private let postProcessor: TranscriptPostProcessor
    private let transcriptRetouchLLMService: TranscriptRetouchLLMService
    private let emojiAIResolverService: EmojiAIResolverService
    private var emojiAIResolutionCache: [String: String] = [:]
    private var emojiAINoMatchCache = Set<String>()
    private(set) var lastWarning: String?

    init(
        postProcessor: TranscriptPostProcessor = TranscriptPostProcessor(),
        transcriptRetouchLLMService: TranscriptRetouchLLMService = TranscriptRetouchLLMService(),
        emojiAIResolverService: EmojiAIResolverService = EmojiAIResolverService()
    ) {
        self.postProcessor = postProcessor
        self.transcriptRetouchLLMService = transcriptRetouchLLMService
        self.emojiAIResolverService = emojiAIResolverService
    }

    func process(
        _ transcript: String,
        settings: AppSettings,
        apiKey: String?,
        correctionLearningSnapshot: CorrectionLearningSnapshot = .empty
    ) async -> TranscriptProcessingResult {
        let prepared = prepare(
            transcript,
            settings: settings,
            correctionLearningSnapshot: correctionLearningSnapshot
        )
        let text = await finalize(
            prepared,
            settings: settings,
            apiKey: apiKey,
            correctionLearningSnapshot: correctionLearningSnapshot
        )

        return TranscriptProcessingResult(
            rawText: prepared.rawText,
            locallyProcessedText: prepared.locallyProcessedText,
            text: text
        )
    }

    func prepare(
        _ transcript: String,
        settings: AppSettings,
        correctionLearningSnapshot: CorrectionLearningSnapshot = .empty
    ) -> PreparedTranscript {
        let settings = CloudTextAICapabilityPolicy.applying(to: settings)
        let rawText = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let locallyProcessedText = postProcessor.process(
            transcript,
            settings: settings,
            correctionLearningSnapshot: correctionLearningSnapshot
        )

        return PreparedTranscript(
            transcript: transcript,
            rawText: rawText,
            locallyProcessedText: locallyProcessedText
        )
    }

    func finalize(
        _ prepared: PreparedTranscript,
        settings: AppSettings,
        apiKey: String?,
        correctionLearningSnapshot: CorrectionLearningSnapshot = .empty
    ) async -> String {
        let settings = CloudTextAICapabilityPolicy.applying(to: settings)
        lastWarning = nil
        let retouchedText = await processedTranscriptAfterOptionalRetouch(
            rawText: prepared.transcript,
            fallbackText: prepared.locallyProcessedText,
            settings: settings,
            apiKey: apiKey,
            correctionLearningSnapshot: correctionLearningSnapshot
        )
        return await applyAIEmojiResolutionIfNeeded(
            to: retouchedText,
            settings: settings,
            apiKey: apiKey
        )
    }

    private func processedTranscriptAfterOptionalRetouch(
        rawText: String,
        fallbackText: String,
        settings: AppSettings,
        apiKey: String?,
        correctionLearningSnapshot: CorrectionLearningSnapshot
    ) async -> String {
        guard settings.transcriptRetouchEnabled,
              !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallbackText
        }
        guard let apiKey,
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            recordWarning(VoiceEditLLMError.missingAPIKey.localizedDescription)
            return fallbackText
        }

        do {
            let retouchedText = try await transcriptRetouchLLMService.retouch(
                TranscriptRetouchLLMRequest(
                    text: rawText,
                    settings: settings,
                    apiKey: apiKey
                )
            )
            return postProcessor.process(
                retouchedText,
                settings: settings,
                correctionLearningSnapshot: correctionLearningSnapshot
            )
        } catch {
            recordWarning(error.localizedDescription)
            return fallbackText
        }
    }

    private func applyAIEmojiResolutionIfNeeded(
        to text: String,
        settings: AppSettings,
        apiKey: String?
    ) async -> String {
        guard settings.emojiPostProcessingEnabled,
              settings.aiEmojiResolverEnabled else {
            return text
        }
        guard let apiKey,
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            recordWarning(VoiceEditLLMError.missingAPIKey.localizedDescription)
            return text
        }

        let matches = EmojiResolverService.shared.unresolvedPhraseMatches(in: text)
        guard !matches.isEmpty else {
            return text
        }

        var replacements: [(EmojiPhraseMatch, String)] = []

        for match in matches {
            let cacheKey = Self.normalizedEmojiResolutionCacheKey(match.phrase)
            if let cached = emojiAIResolutionCache[cacheKey] {
                replacements.append((match, cached))
                continue
            }

            if emojiAINoMatchCache.contains(cacheKey) {
                continue
            }

            do {
                if let emoji = try await emojiAIResolverService.resolve(
                    phrase: match.phrase,
                    settings: settings,
                    apiKey: apiKey
                ) {
                    emojiAIResolutionCache[cacheKey] = emoji
                    replacements.append((match, emoji))
                } else {
                    emojiAINoMatchCache.insert(cacheKey)
                }
            } catch {
                recordWarning(error.localizedDescription)
            }
        }

        guard !replacements.isEmpty else {
            return text
        }

        return EmojiResolverService.shared.applying(replacements, to: text)
    }

    private static func normalizedEmojiResolutionCacheKey(_ phrase: String) -> String {
        phrase
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
    }

    private func recordWarning(_ warning: String) {
        guard lastWarning == nil else {
            return
        }
        lastWarning = warning
    }
}
