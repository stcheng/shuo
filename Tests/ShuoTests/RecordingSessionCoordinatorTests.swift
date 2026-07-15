import Foundation
import XCTest
@testable import Shuo

final class RecordingSessionCoordinatorTests: XCTestCase {
    @MainActor
    func testSerializesStartAndStopTransitions() async throws {
        let recorder = FakeAudioRecorder()
        let coordinator = RecordingSessionCoordinator(recorder: recorder)

        let firstStart = try await coordinator.start(inputDeviceID: "mic")
        let duplicateStart = try await coordinator.start(inputDeviceID: "mic")

        XCTAssertNotNil(firstStart)
        XCTAssertNil(duplicateStart)
        XCTAssertEqual(recorder.startCount, 1)
        XCTAssertEqual(coordinator.phase, .recording)

        let firstStop = await coordinator.stop()
        let duplicateStop = await coordinator.stop()
        XCTAssertEqual(firstStop, recorder.result.url)
        XCTAssertNil(duplicateStop)
        XCTAssertEqual(recorder.stopCount, 1)
        XCTAssertEqual(coordinator.phase, .idle)
    }

    @MainActor
    func testCanStartAgainAfterNormalStop() async throws {
        let recorder = FakeAudioRecorder()
        let coordinator = RecordingSessionCoordinator(recorder: recorder)

        let firstStart = try await coordinator.start(inputDeviceID: "mic")
        XCTAssertNotNil(firstStart)
        let stoppedURL = await coordinator.stop()
        XCTAssertEqual(stoppedURL, recorder.result.url)
        let secondStart = try await coordinator.start(inputDeviceID: "mic")
        XCTAssertNotNil(secondStart)

        XCTAssertEqual(recorder.startCount, 2)
        XCTAssertEqual(recorder.stopCount, 1)
        XCTAssertEqual(coordinator.phase, .recording)
    }

    @MainActor
    func testCanStartAgainAfterRecordingCancellation() async throws {
        let recorder = FakeAudioRecorder()
        let coordinator = RecordingSessionCoordinator(recorder: recorder)

        let firstStart = try await coordinator.start(inputDeviceID: "mic")
        XCTAssertNotNil(firstStart)
        XCTAssertEqual(coordinator.cancel(), recorder.result.url)
        let secondStart = try await coordinator.start(inputDeviceID: "mic")
        XCTAssertNotNil(secondStart)

        XCTAssertEqual(recorder.startCount, 2)
        XCTAssertEqual(recorder.cancelCount, 1)
        XCTAssertEqual(coordinator.phase, .recording)
    }

    @MainActor
    func testCancelDuringStartPreventsRecordingTransition() async throws {
        let recorder = FakeAudioRecorder(suspendsStart: true)
        let coordinator = RecordingSessionCoordinator(recorder: recorder)
        let startTask = Task {
            try await coordinator.start(inputDeviceID: "mic")
        }

        while recorder.startCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(coordinator.phase, .starting)
        _ = coordinator.cancel()

        let startResult = try await startTask.value
        XCTAssertNil(startResult)
        XCTAssertEqual(recorder.cancelCount, 1)
        XCTAssertEqual(coordinator.phase, .idle)
    }

    @MainActor
    func testWaitForPendingStartLetsTheNextPushToTalkStartProceed() async throws {
        let recorder = FakeAudioRecorder(suspendsStart: true)
        let coordinator = RecordingSessionCoordinator(recorder: recorder)
        let firstStart = Task {
            try await coordinator.start(inputDeviceID: "mic")
        }

        while recorder.startCount == 0 {
            await Task.yield()
        }
        _ = coordinator.cancel()

        let retry = Task { () throws -> AudioRecordingStartResult? in
            guard await coordinator.waitForPendingStartToFinish() else {
                return nil
            }
            return try await coordinator.start(inputDeviceID: "mic")
        }

        let firstResult = try await firstStart.value
        let retryResult = try await retry.value
        XCTAssertNil(firstResult)
        XCTAssertNotNil(retryResult)
        XCTAssertEqual(recorder.startCount, 2)
        XCTAssertEqual(coordinator.phase, .recording)
    }

    @MainActor
    func testForwardsMaximumDurationOnlyForActiveRecording() async throws {
        let recorder = FakeAudioRecorder()
        let coordinator = RecordingSessionCoordinator(recorder: recorder)
        var notificationCount = 0
        coordinator.onMaximumDurationReached = {
            notificationCount += 1
        }

        recorder.maximumDurationReachedHandler?()
        XCTAssertEqual(notificationCount, 0)

        _ = try await coordinator.start(inputDeviceID: "mic")
        recorder.maximumDurationReachedHandler?()
        XCTAssertEqual(notificationCount, 1)

        _ = await coordinator.stop()
        recorder.maximumDurationReachedHandler?()
        XCTAssertEqual(notificationCount, 1)
    }
}

@MainActor
private final class FakeAudioRecorder: AudioRecording {
    var maximumDurationReachedHandler: (@MainActor @Sendable () -> Void)?
    let result = AudioRecordingStartResult(
        url: URL(fileURLWithPath: "/tmp/fake-recording.wav"),
        route: AudioRoute(
            inputDevice: AudioInputDeviceOption(id: "mic", name: "Test Mic"),
            outputDevice: nil,
            resolvedAt: Date(timeIntervalSince1970: 0)
        )
    )
    var startCount = 0
    var stopCount = 0
    var cancelCount = 0
    private var remainingSuspendedStarts: Int
    private var startContinuation: CheckedContinuation<AudioRecordingStartResult, Error>?

    init(suspendsStart: Bool = false) {
        remainingSuspendedStarts = suspendsStart ? 1 : 0
    }

    func start(inputDeviceID: String) async throws -> AudioRecordingStartResult {
        try Task.checkCancellation()
        startCount += 1
        guard remainingSuspendedStarts > 0 else {
            return result
        }
        remainingSuspendedStarts -= 1

        return try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation
        }
    }

    func stop() async -> URL? {
        stopCount += 1
        return result.url
    }

    func cancel() -> URL? {
        cancelCount += 1
        startContinuation?.resume(throwing: CancellationError())
        startContinuation = nil
        return result.url
    }

}
