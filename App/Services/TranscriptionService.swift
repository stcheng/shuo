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
        let executableURL = try resolveExecutableURL(from: request.settings.localWhisperExecutablePath)
        let modelURL = try resolveModelURL(from: request.settings.localWhisperModelPath)
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

/// whisper.cpp treats `--prompt` as prior transcript context, so short,
/// naturally punctuated examples are more dependable than an instruction such
/// as "add punctuation". Put preferred spellings before the style examples:
/// small multilingual models can repeat the decoded sentence when a short
/// vocabulary fragment is appended to the end of a long multilingual prompt.
enum LocalWhisperInitialPrompt {
    static func make(
        settings: AppSettings,
        vocabularyPrompt: String
    ) -> String {
        var parts: [String] = []
        let languages = settings.selectedTranscriptionLanguages
        let trimmedVocabulary = vocabularyPrompt
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedVocabulary.isEmpty {
            parts.append(trimmedVocabulary + ".")
        }

        if languages.contains(.chinese) {
            switch settings.resolvedChineseTextConversionMode {
            case .traditional:
                parts.append("今天我們來試一下。效果不錯，我們繼續。")
            case .keep, .simplified:
                parts.append("今天我们来试一下。效果不错，我们继续。")
            }
        }
        if languages.contains(.english) {
            parts.append("Let's try this. It sounds good, so we'll continue.")
        }
        if languages.contains(.spanish) {
            parts.append("Vamos a probarlo. Suena bien, así que continuaremos.")
        }
        if languages.contains(.french) {
            parts.append("Essayons. Le résultat est bon, alors continuons.")
        }
        if languages.contains(.japanese) {
            parts.append("今日は試してみます。うまくいきました。続けましょう。")
        }

        return String(parts.joined(separator: " ").prefix(2_000))
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
