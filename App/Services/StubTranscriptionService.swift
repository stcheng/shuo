import Foundation

struct StubTranscriptionService: TranscriptionService {
    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        try await Task.sleep(nanoseconds: 250_000_000)
        let localizer = AppLocalizer(language: request.settings.appLanguage)

        return TranscriptionResult(
            text: localizer.localizedStubTranscript(),
            detectedLanguage: nil
        )
    }
}
