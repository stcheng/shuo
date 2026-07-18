import AVFoundation
import Foundation

struct TranscriptionRequest {
    let audioFileURL: URL
    let settings: AppSettings
    let context: String
    let vocabulary: TranscriptionVocabularySnapshot
    let apiKey: String?
}

struct TranscriptionResult {
    let text: String
    let detectedLanguage: String?
}

enum LocalWhisperTranscriptionError: LocalizedError {
    case missingExecutable
    case executableNotFound(String)
    case missingModel
    case modelNotFound(String)
    case unsupportedModel(String)
    case processFailed(statusCode: Int32, output: String)
    case processTimedOut(TimeInterval)

    var errorDescription: String? {
        switch self {
        case .missingExecutable:
            return "Local whisper executable is not configured."
        case .executableNotFound(let path):
            return "Local whisper executable was not found or is not executable: \(path)"
        case .missingModel:
            return "Local whisper model is not configured."
        case .modelNotFound(let path):
            return "Local whisper model was not found: \(path)"
        case .unsupportedModel(let path):
            return "The selected local model is not supported by Shuo: \(path)"
        case .processFailed(let statusCode, let output):
            return "Local whisper failed (\(statusCode)): \(output)"
        case .processTimedOut(let timeout):
            return "Local whisper did not finish within \(Int(timeout)) seconds and was stopped."
        }
    }
}

protocol TranscriptionService {
    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult
}

enum TranscriptionServiceFactory {
    static func makeService(for provider: TranscriptionProvider) -> TranscriptionService {
        switch provider {
        case .openAI:
            return OpenAITranscriptionService()
        case .elevenLabs:
            return ElevenLabsTranscriptionService()
        case .alibaba:
            return AlibabaTranscriptionService()
        case .gemini:
            return GeminiTranscriptionService()
        case .local:
            return LocalWhisperTranscriptionService()
        case .custom:
            return StubTranscriptionService()
        }
    }
}

struct LocalWhisperTranscriptionService: TranscriptionService {
    static let transcriptionTimeout: TimeInterval = 10 * 60

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        let modelURL = try resolveModelURL(from: request.settings.localWhisperModelPath)

        guard let engine = LocalTranscriptionEngine.infer(fromModelPath: modelURL.path) else {
            throw LocalWhisperTranscriptionError.unsupportedModel(modelURL.path)
        }

        switch engine {
        case .senseVoice:
            return try await LocalSenseVoiceTranscriptionService().transcribe(
                audioFileURL: request.audioFileURL,
                modelURL: modelURL
            )
        case .whisper:
            return try await transcribeWithWhisper(
                request,
                modelURL: modelURL
            )
        }
    }

    private func transcribeWithWhisper(
        _ request: TranscriptionRequest,
        modelURL: URL
    ) async throws -> TranscriptionResult {
        let executableURL = try resolveExecutableURL(from: request.settings.localWhisperExecutablePath)
        let outputBaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("shuo-whisper-\(UUID().uuidString)")

        let output = try await runWhisper(
            executableURL: executableURL,
            modelURL: modelURL,
            audioFileURL: request.audioFileURL,
            outputBaseURL: outputBaseURL,
            languageHint: request.settings.languageHint,
            performanceMode: request.settings.localWhisperPerformanceMode,
            initialPrompt: LocalWhisperInitialPrompt.make(
                settings: request.settings,
                vocabularyPrompt: request.vocabulary.prompt
            )
        )
        let transcript = transcriptText(outputBaseURL: outputBaseURL, fallbackOutput: output)

        try? FileManager.default.removeItem(at: outputBaseURL.appendingPathExtension("txt"))

        return TranscriptionResult(
            text: transcript,
            detectedLanguage: request.settings.languageHint == .automatic
                || request.settings.languageHint == .mixed
                ? nil
                : request.settings.languageHint.localWhisperLanguageCode
        )
    }

    private func resolveExecutableURL(from configuredPath: String) throws -> URL {
        let trimmedPath = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)

        if let executableURL = LocalWhisperExecutableResolver.resolvedExecutableURL(configuredPath: trimmedPath) {
            return executableURL
        }

        if trimmedPath.isEmpty {
            throw LocalWhisperTranscriptionError.missingExecutable
        }

        throw LocalWhisperTranscriptionError.executableNotFound(trimmedPath)
    }

    private func resolveModelURL(from configuredPath: String) throws -> URL {
        let trimmedPath = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedPath.isEmpty else {
            throw LocalWhisperTranscriptionError.missingModel
        }

        guard FileManager.default.fileExists(atPath: trimmedPath) else {
            throw LocalWhisperTranscriptionError.modelNotFound(trimmedPath)
        }

        return URL(fileURLWithPath: trimmedPath)
    }

    private func runWhisper(
        executableURL: URL,
        modelURL: URL,
        audioFileURL: URL,
        outputBaseURL: URL,
        languageHint: LanguageHint,
        performanceMode: LocalWhisperPerformanceMode,
        initialPrompt: String
    ) async throws -> String {
        let arguments = LocalWhisperCommandArguments.make(
            modelURL: modelURL,
            audioFileURL: audioFileURL,
            outputBaseURL: outputBaseURL,
            languageHint: languageHint,
            performanceMode: performanceMode,
            initialPrompt: initialPrompt
        )

        let result: CancellableProcessResult
        do {
            result = try await CancellableProcessRunner.run(
                executableURL: executableURL,
                arguments: arguments,
                timeout: Self.transcriptionTimeout
            )
        } catch CancellableProcessRunnerError.timedOut(let timeout) {
            throw LocalWhisperTranscriptionError.processTimedOut(timeout)
        }

        guard result.terminationStatus == 0 else {
            throw LocalWhisperTranscriptionError.processFailed(
                statusCode: result.terminationStatus,
                output: cleanProcessOutput(result.output)
            )
        }

        return result.output
    }

    private func transcriptText(outputBaseURL: URL, fallbackOutput: String) -> String {
        let transcriptURL = outputBaseURL.appendingPathExtension("txt")

        if let data = try? Data(contentsOf: transcriptURL),
           let text = String(data: data, encoding: .utf8) {
            let cleanedText = cleanTranscriptOutput(text)
            if !cleanedText.isEmpty {
                return cleanedText
            }
        }

        return cleanTranscriptOutput(fallbackOutput)
    }

    private func cleanTranscriptOutput(_ output: String) -> String {
        output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !isWhisperLogLine($0) }
            .joined(separator: " ")
    }

    private func cleanProcessOutput(_ output: String) -> String {
        let cleaned = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > 1_000 else {
            return cleaned
        }

        return String(cleaned.prefix(1_000)) + "..."
    }

    private func isWhisperLogLine(_ line: String) -> Bool {
        let prefixes = [
            "whisper_",
            "ggml_",
            "main:",
            "system_info:",
            "sampling:",
            "processing:",
            "output_txt:"
        ]

        return prefixes.contains { line.hasPrefix($0) }
    }
}

enum LocalSenseVoiceTranscriptionError: LocalizedError {
    case missingExecutable
    case missingVADAsset(String)
    case processFailed(statusCode: Int32, output: String)
    case processTimedOut(TimeInterval)

    var errorDescription: String? {
        switch self {
        case .missingExecutable:
            return "The bundled SenseVoice runtime is unavailable. Reinstall Shuo to restore local transcription."
        case .missingVADAsset(let path):
            return "SenseVoice's local speech-segmentation asset is missing: \(path)"
        case .processFailed(let statusCode, let output):
            return "SenseVoice failed (\(statusCode)): \(output)"
        case .processTimedOut(let timeout):
            return "SenseVoice did not finish within \(Int(timeout)) seconds and was stopped."
        }
    }
}

/// SenseVoice is a separate local ASR engine with a GGUF model contract. It
/// receives the same 16 kHz mono WAV Shuo already records, but intentionally
/// does not receive Whisper's `--prompt`: this runtime has no prompt/hotword
/// interface, so pretending otherwise would make vocabulary behavior opaque.
struct LocalSenseVoiceTranscriptionService {
    static let transcriptionTimeout: TimeInterval = LocalWhisperTranscriptionService.transcriptionTimeout

    func transcribe(
        audioFileURL: URL,
        modelURL: URL
    ) async throws -> TranscriptionResult {
        guard let executableURL = LocalSenseVoiceExecutableResolver.resolvedExecutableURL() else {
            throw LocalSenseVoiceTranscriptionError.missingExecutable
        }
        let shouldUseVAD = LocalSenseVoiceSegmentationPolicy.shouldUseVAD(
            forDuration: Self.audioDuration(of: audioFileURL)
        )
        let vadURL = LocalWhisperModelCatalog.senseVoiceVADURL(
            in: modelURL.deletingLastPathComponent().path
        )
        if shouldUseVAD,
           !LocalWhisperModelCatalog.senseVoiceVADAsset.hasExpectedFileSize(at: vadURL) {
            throw LocalSenseVoiceTranscriptionError.missingVADAsset(vadURL.path)
        }

        let result: CancellableProcessResult
        do {
            result = try await CancellableProcessRunner.run(
                executableURL: executableURL,
                arguments: LocalSenseVoiceCommandArguments.make(
                    modelURL: modelURL,
                    audioFileURL: audioFileURL,
                    vadURL: shouldUseVAD ? vadURL : nil
                ),
                timeout: Self.transcriptionTimeout
            )
        } catch CancellableProcessRunnerError.timedOut(let timeout) {
            throw LocalSenseVoiceTranscriptionError.processTimedOut(timeout)
        }

        guard result.terminationStatus == 0 else {
            throw LocalSenseVoiceTranscriptionError.processFailed(
                statusCode: result.terminationStatus,
                output: cleanProcessOutput(
                    result.standardError.isEmpty ? result.output : result.standardError
                )
            )
        }

        return TranscriptionResult(
            text: Self.transcriptText(from: result.standardOutput),
            detectedLanguage: nil
        )
    }

    static func transcriptText(from output: String) -> String {
        let segments = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !isRuntimeLogLine($0) }

        return LocalSenseVoiceTranscriptJoiner.join(segments)
    }

    private func cleanProcessOutput(_ output: String) -> String {
        let cleaned = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > 1_000 else {
            return cleaned
        }
        return String(cleaned.prefix(1_000)) + "..."
    }

    private static func isRuntimeLogLine(_ line: String) -> Bool {
        ["[sensevoice]", "ggml_", "llama_", "system_info:"].contains {
            line.hasPrefix($0)
        }
    }

    private static func audioDuration(of audioFileURL: URL) -> TimeInterval? {
        guard let audioFile = try? AVAudioFile(forReading: audioFileURL) else {
            return nil
        }

        let sampleRate = audioFile.processingFormat.sampleRate
        guard sampleRate > 0 else {
            return nil
        }

        return Double(audioFile.length) / sampleRate
    }
}

/// SenseVoice's bundled VAD is useful for long recordings, where it keeps
/// individual inference windows bounded. For short push-to-talk utterances it
/// can discard quiet but intelligible speech entirely, so pass that audio to
/// the recognizer directly. If a duration cannot be read, retain VAD as the
/// conservative long-audio path.
enum LocalSenseVoiceSegmentationPolicy {
    static let directInferenceMaximumDuration: TimeInterval = 30

    static func shouldUseVAD(forDuration duration: TimeInterval?) -> Bool {
        guard let duration, duration.isFinite else {
            return true
        }

        return duration >= directInferenceMaximumDuration
    }
}

/// The SenseVoice runtime emits one line per VAD segment. Preserve Chinese,
/// Japanese, and Korean adjacency while restoring an English word boundary
/// when the runtime split ordinary Latin text into separate segments.
enum LocalSenseVoiceTranscriptJoiner {
    static func join(_ segments: [String]) -> String {
        segments.reduce("") { partial, segment in
            guard !partial.isEmpty else {
                return segment
            }
            return partial + (needsSpace(between: partial, and: segment) ? " " : "") + segment
        }
    }

    private static func needsSpace(between previous: String, and next: String) -> Bool {
        guard let previousCharacter = previous.last,
              let nextCharacter = next.first,
              !previousCharacter.isWhitespace,
              !nextCharacter.isWhitespace else {
            return false
        }

        if isCJK(previousCharacter) || isCJK(nextCharacter) {
            return false
        }

        if previousCharacter.isLetter || previousCharacter.isNumber {
            return nextCharacter.isLetter || nextCharacter.isNumber
        }

        return ".,!?;:)]}".contains(previousCharacter)
            && (nextCharacter.isLetter || nextCharacter.isNumber)
    }

    private static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x2E80 ... 0x2EFF, // CJK radicals
                 0x3000 ... 0x303F, // CJK punctuation
                 0x3040 ... 0x30FF, // Hiragana + Katakana
                 0x3400 ... 0x4DBF, // CJK Extension A
                 0x4E00 ... 0x9FFF, // CJK Unified Ideographs
                 0xAC00 ... 0xD7AF, // Hangul syllables
                 0xF900 ... 0xFAFF, // CJK compatibility ideographs
                 0xFF00 ... 0xFFEF: // full-width forms
                return true
            default:
                return false
            }
        }
    }
}

enum LocalSenseVoiceCommandArguments {
    static func make(modelURL: URL, audioFileURL: URL, vadURL: URL?) -> [String] {
        var arguments = [
            "-m", modelURL.path,
            "-a", audioFileURL.path
        ]

        if let vadURL {
            arguments += ["--vad", vadURL.path, "--vad-maxseg", "30000"]
        }

        return arguments
    }
}

/// whisper.cpp treats `--prompt` as prior transcript context, so short,
/// naturally punctuated examples are more dependable than an instruction such
/// as "add punctuation". For a single selected language, a short native
/// example can establish punctuation style. For a mixed selection, never add
/// generated sentences: with automatic language detection, a free-standing
/// English or Chinese sentence becomes an artificial language prior for a
/// short utterance. In that path the user's glossary is the only optional
/// hint, and an empty glossary means no `--prompt` at all.
enum LocalWhisperInitialPrompt {
    static func make(
        settings: AppSettings,
        vocabularyPrompt: String
    ) -> String {
        var parts: [String] = []
        let languages = settings.selectedTranscriptionLanguages
        let trimmedVocabulary = vocabularyPrompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let meaningfulVocabulary = vocabularyPromptWithoutBuiltInMarker(
            trimmedVocabulary
        )

        let usesAutomaticMixedLanguageDetection = languages.count > 1

        if !usesAutomaticMixedLanguageDetection, languages.contains(.chinese) {
            switch settings.resolvedChineseTextConversionMode {
            case .traditional:
                parts.append("今天我們來試一下。效果不錯，我們繼續。")
            case .keep, .simplified:
                parts.append("今天我们来试一下。效果不错，我们继续。")
            }
        }

        if !meaningfulVocabulary.isEmpty {
            parts.append(meaningfulVocabulary + ".")
        }

        // `--prompt` is prior transcript, not a language allow-list. The
        // common Chinese + English path therefore has no generic English or
        // Chinese sentence; doing so otherwise biases automatic detection.
        if !usesAutomaticMixedLanguageDetection, languages.contains(.english) {
            parts.append("Let's try this. It sounds good, so we'll continue.")
        }
        if !usesAutomaticMixedLanguageDetection, languages.contains(.spanish) {
            parts.append("Vamos a probarlo. Suena bien, así que continuaremos.")
        }
        if !usesAutomaticMixedLanguageDetection, languages.contains(.french) {
            parts.append("Essayons. Le résultat est bon, alors continuons.")
        }
        if !usesAutomaticMixedLanguageDetection, languages.contains(.japanese) {
            parts.append("今日は試してみます。うまくいきました。続けましょう。")
        }

        return String(parts.joined(separator: " ").prefix(2_000))
    }

    private static func vocabularyPromptWithoutBuiltInMarker(_ prompt: String) -> String {
        let terms = prompt
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Shuo is inserted by the composer as an inert product-name fallback.
        // It must not become the only English prior for automatic mixed input.
        guard !terms.isEmpty,
              !terms.allSatisfy({ $0.caseInsensitiveCompare("Shuo") == .orderedSame }) else {
            return ""
        }
        return prompt
    }
}

enum LocalWhisperCommandArguments {
    static func make(
        modelURL: URL,
        audioFileURL: URL,
        outputBaseURL: URL,
        languageHint: LanguageHint,
        performanceMode: LocalWhisperPerformanceMode,
        activeProcessorCount: Int = ProcessInfo.processInfo.activeProcessorCount,
        initialPrompt: String = ""
    ) -> [String] {
        var arguments = [
            "-m", modelURL.path,
            "-f", audioFileURL.path,
            "-otxt",
            "-of", outputBaseURL.path,
            "-nt"
        ]

        switch performanceMode {
        case .balanced:
            break
        case .fast:
            arguments.append(contentsOf: [
                "-t", "\(fastThreadCount(activeProcessorCount: activeProcessorCount))",
                "-bo", "1",
                "-bs", "1",
                "-nf",
                "-np"
            ])
        }

        if let languageCode = languageHint.localWhisperLanguageCode {
            arguments.append(contentsOf: ["-l", languageCode])
        }

        let trimmedPrompt = initialPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrompt.isEmpty {
            arguments.append(contentsOf: ["--prompt", trimmedPrompt])
        }

        return arguments
    }

    static func preferredTermsPrompt(from glossary: String) -> String {
        let terms = glossary
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(100)
        return String(terms.joined(separator: ", ").prefix(2_000))
    }

    static func fastThreadCount(activeProcessorCount: Int) -> Int {
        max(1, min(activeProcessorCount, 8))
    }
}
