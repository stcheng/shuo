import Foundation
import XCTest
@testable import Shuo

final class AlibabaTranscriptionServiceTests: XCTestCase {
    func testBuildsOfficialQwenASRRequestWithoutLocalContext() throws {
        let audioURL = try makeTemporaryAudioFile(
            extension: "wav",
            data: Data([0x00, 0x01, 0x02, 0x03])
        )
        defer { try? FileManager.default.removeItem(at: audioURL) }

        var settings = AppSettings()
        settings.selectedTranscriptionLanguages = [.chinese]
        let transcriptionRequest = TranscriptionRequest(
            audioFileURL: audioURL,
            settings: settings,
            context: "PRIVATE HISTORY MUST NOT LEAVE THE MAC",
            vocabulary: TranscriptionVocabularySnapshot(
                terms: ["PrivateTerm", "/Users/example/private-project"]
            ),
            apiKey: "  dashscope-secret  "
        )

        let request = try AlibabaTranscriptionService().makeURLRequest(transcriptionRequest)
        let bodyData = try XCTUnwrap(request.httpBody)
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        )

        XCTAssertEqual(request.url, AlibabaTranscriptionService.endpoint)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer dashscope-secret")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(Set(body.keys), ["model", "messages", "stream", "asr_options"])
        XCTAssertEqual(body["model"] as? String, "qwen3-asr-flash")
        XCTAssertEqual(body["stream"] as? Bool, false)

        let options = try XCTUnwrap(body["asr_options"] as? [String: Any])
        XCTAssertEqual(Set(options.keys), ["language", "enable_itn"])
        XCTAssertEqual(options["language"] as? String, "zh")
        XCTAssertEqual(options["enable_itn"] as? Bool, true)

        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(Set(messages[0].keys), ["role", "content"])
        XCTAssertEqual(messages[0]["role"] as? String, "user")

        let content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 1)
        XCTAssertEqual(Set(content[0].keys), ["type", "input_audio"])
        XCTAssertEqual(content[0]["type"] as? String, "input_audio")

        let inputAudio = try XCTUnwrap(content[0]["input_audio"] as? [String: Any])
        XCTAssertEqual(Set(inputAudio.keys), ["data"])
        XCTAssertEqual(inputAudio["data"] as? String, "data:audio/wav;base64,AAECAw==")

        let bodyText = try XCTUnwrap(String(data: bodyData, encoding: .utf8))
        XCTAssertFalse(bodyText.contains("PRIVATE HISTORY"))
        XCTAssertFalse(bodyText.contains("PrivateTerm"))
        XCTAssertFalse(bodyText.contains("private-project"))
    }

    func testOmitsLanguageForMultilingualSelection() throws {
        let audioURL = try makeTemporaryAudioFile(extension: "mp3", data: Data([0x01]))
        defer { try? FileManager.default.removeItem(at: audioURL) }

        var settings = AppSettings()
        settings.selectedTranscriptionLanguages = [.chinese, .english]
        let request = try AlibabaTranscriptionService().makeURLRequest(
            makeRequest(audioURL: audioURL, settings: settings)
        )
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any]
        )
        let options = try XCTUnwrap(body["asr_options"] as? [String: Any])

        XCTAssertNil(options["language"])
        XCTAssertEqual(options["enable_itn"] as? Bool, true)
    }

    func testMapsSupportedSingleLanguages() {
        let examples: [(TranscriptionLanguage, String)] = [
            (.chinese, "zh"),
            (.english, "en"),
            (.japanese, "ja"),
            (.french, "fr"),
            (.spanish, "es")
        ]

        for (language, expectedCode) in examples {
            var settings = AppSettings()
            settings.selectedTranscriptionLanguages = [language]
            XCTAssertEqual(
                AlibabaTranscriptionService.languageCode(for: settings),
                expectedCode
            )
        }
    }

    func testUsesCorrectMIMETypesForCommonAudioFiles() {
        let examples = [
            ("recording.wav", "audio/wav"),
            ("recording.mp3", "audio/mpeg"),
            ("recording.m4a", "audio/mp4"),
            ("recording.aac", "audio/aac"),
            ("recording.flac", "audio/flac"),
            ("recording.ogg", "audio/ogg"),
            ("recording.webm", "audio/webm")
        ]

        for (filename, expectedMIMEType) in examples {
            XCTAssertEqual(
                AlibabaTranscriptionService.mimeType(
                    for: URL(fileURLWithPath: "/tmp/\(filename)")
                ),
                expectedMIMEType
            )
        }
    }

    func testRejectsMissingAPIKeyBeforeReadingAudio() {
        let request = TranscriptionRequest(
            audioFileURL: URL(fileURLWithPath: "/does/not/exist.wav"),
            settings: AppSettings(),
            context: "",
            vocabulary: .empty,
            apiKey: "   "
        )

        XCTAssertThrowsError(try AlibabaTranscriptionService().makeURLRequest(request)) { error in
            guard case AlibabaTranscriptionError.missingAPIKey = error else {
                return XCTFail("Expected missingAPIKey, got \(error)")
            }
        }
    }

    func testRejectsAudioWhoseBase64ValueWouldExceedTenMegabytes() throws {
        let maximumSourceByteCount = AlibabaTranscriptionService.maximumEncodedAudioByteCount / 4 * 3
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        XCTAssertTrue(FileManager.default.createFile(atPath: audioURL.path, contents: nil))
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let handle = try FileHandle(forWritingTo: audioURL)
        try handle.truncate(atOffset: UInt64(maximumSourceByteCount + 1))
        try handle.close()

        XCTAssertThrowsError(
            try AlibabaTranscriptionService().makeURLRequest(makeRequest(audioURL: audioURL))
        ) { error in
            guard case AlibabaTranscriptionError.audioFileTooLarge(
                let encodedByteCount,
                let maximumByteCount
            ) = error else {
                return XCTFail("Expected audioFileTooLarge, got \(error)")
            }
            XCTAssertGreaterThan(encodedByteCount, Int64(maximumByteCount))
            XCTAssertEqual(
                maximumByteCount,
                AlibabaTranscriptionService.maximumEncodedAudioByteCount
            )
        }
    }

    func testParsesContentAndDetectedLanguage() throws {
        let response = Data(
            #"{"choices":[{"message":{"content":"  你好，Shuo。\n","annotations":[{"language":"zh"}]}}]}"#.utf8
        )

        let result = try AlibabaTranscriptionService.parseResponse(response)

        XCTAssertEqual(result.text, "你好，Shuo。")
        XCTAssertEqual(result.detectedLanguage, "zh")
    }

    func testRejectsMalformedAndEmptyResponses() {
        XCTAssertThrowsError(
            try AlibabaTranscriptionService.parseResponse(Data(#"{"choices":[]}"#.utf8))
        ) { error in
            guard case AlibabaTranscriptionError.invalidResponse = error else {
                return XCTFail("Expected invalidResponse, got \(error)")
            }
        }

        let emptyResponse = Data(
            #"{"choices":[{"message":{"content":"  \n "}}]}"#.utf8
        )
        XCTAssertThrowsError(
            try AlibabaTranscriptionService.parseResponse(emptyResponse)
        ) { error in
            guard case AlibabaTranscriptionError.emptyResponse = error else {
                return XCTFail("Expected emptyResponse, got \(error)")
            }
        }
    }

    func testSurfacesProviderHTTPErrorMessage() async throws {
        let audioURL = try makeTemporaryAudioFile(extension: "wav", data: Data([0x01]))
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: AlibabaTranscriptionService.endpoint,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )
        )
        let service = AlibabaTranscriptionService { _ in
            (
                Data(#"{"error":{"code":"InvalidApiKey","message":"API key is invalid"}}"#.utf8),
                response
            )
        }

        do {
            _ = try await service.transcribe(makeRequest(audioURL: audioURL))
            XCTFail("Expected the provider error to be thrown")
        } catch let error as AlibabaTranscriptionError {
            guard case .requestFailed(let statusCode, let message) = error else {
                return XCTFail("Expected requestFailed, got \(error)")
            }
            XCTAssertEqual(statusCode, 401)
            XCTAssertEqual(message, "InvalidApiKey: API key is invalid")
        }
    }

    private func makeRequest(
        audioURL: URL,
        settings: AppSettings = AppSettings(),
        apiKey: String = "dashscope-secret"
    ) -> TranscriptionRequest {
        TranscriptionRequest(
            audioFileURL: audioURL,
            settings: settings,
            context: "",
            vocabulary: .empty,
            apiKey: apiKey
        )
    }

    private func makeTemporaryAudioFile(
        extension fileExtension: String,
        data: Data
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        try data.write(to: url, options: .atomic)
        return url
    }
}
