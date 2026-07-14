import Foundation

@MainActor
protocol AudioRecording: AnyObject {
    var maximumDurationReachedHandler: (@MainActor @Sendable () -> Void)? { get set }
    func start(inputDeviceID: String) async throws -> AudioRecordingStartResult
    func stop() async -> URL?
    func cancel() -> URL?
}

extension AudioRecorder: AudioRecording {}

@MainActor
final class RecordingSessionCoordinator {
    enum Phase: Equatable {
        case idle
        case starting
        case recording
        case stopping
    }

    private let recorder: AudioRecording
    private(set) var phase: Phase = .idle
    private(set) var currentRecordingURL: URL?
    private(set) var currentRoute: AudioRoute?
    private(set) var lastRoute: AudioRoute?
    private var cancelStartRequested = false
    private var startTask: Task<AudioRecordingStartResult, Error>?
    var onMaximumDurationReached: (() -> Void)?

    init(recorder: AudioRecording = AudioRecorder()) {
        self.recorder = recorder
        recorder.maximumDurationReachedHandler = { [weak self] in
            guard self?.phase == .recording else {
                return
            }
            self?.onMaximumDurationReached?()
        }
    }

    var isStarting: Bool { phase == .starting }
    var isRecording: Bool { phase == .recording }
    var isStopping: Bool { phase == .stopping }

    /// A push-to-talk release can cancel a Bluetooth microphone while its
    /// start task is still unwinding. A subsequent press should wait for that
    /// cancellation to settle rather than being silently dropped.
    func waitForPendingStartToFinish() async -> Bool {
        while phase == .starting {
            do {
                try await Task.sleep(nanoseconds: 20_000_000)
            } catch {
                return false
            }
        }
        return true
    }

    func start(inputDeviceID: String) async throws -> AudioRecordingStartResult? {
        guard phase == .idle else {
            return nil
        }

        phase = .starting
        cancelStartRequested = false

        do {
            let startTask = Task {
                try Task.checkCancellation()
                return try await recorder.start(inputDeviceID: inputDeviceID)
            }
            self.startTask = startTask
            let result = try await startTask.value
            if cancelStartRequested {
                resetCurrentSession()
                return nil
            }

            currentRecordingURL = result.url
            currentRoute = result.route
            lastRoute = result.route
            phase = .recording
            return result
        } catch {
            let cancellationWasRequested = cancelStartRequested || error is CancellationError
            resetCurrentSession()
            if cancellationWasRequested {
                return nil
            }
            throw error
        }
    }

    func stop() async -> URL? {
        guard phase == .recording else {
            return nil
        }

        phase = .stopping
        let url = await recorder.stop()
        resetCurrentSession()
        return url
    }

    @discardableResult
    func cancel() -> URL? {
        switch phase {
        case .starting:
            cancelStartRequested = true
            startTask?.cancel()
            return recorder.cancel()
        case .recording:
            let url = recorder.cancel() ?? currentRecordingURL
            resetCurrentSession()
            return url
        case .idle, .stopping:
            return nil
        }
    }

    private func resetCurrentSession() {
        phase = .idle
        currentRecordingURL = nil
        currentRoute = nil
        startTask = nil
        cancelStartRequested = false
    }
}
