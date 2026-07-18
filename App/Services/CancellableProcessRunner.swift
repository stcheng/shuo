import Darwin
import Foundation

enum CancellableProcessRunnerError: Error, Equatable {
    case timedOut(TimeInterval)
}

struct CancellableProcessResult: Equatable {
    let terminationStatus: Int32
    let standardOutput: String
    let standardError: String

    /// Preserve the historical combined output for existing diagnostics while
    /// allowing transcription engines to treat stdout as the sole text
    /// protocol. Interleaving stderr with recognized text is not safe.
    var output: String {
        switch (standardOutput.isEmpty, standardError.isEmpty) {
        case (true, true):
            return ""
        case (false, true):
            return standardOutput
        case (true, false):
            return standardError
        case (false, false):
            return standardOutput + "\n" + standardError
        }
    }
}

enum CancellableProcessRunner {
    static func run(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> CancellableProcessResult {
        let controller = ProcessExecutionController()

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let process = Process()
                    let standardOutputPipe = Pipe()
                    let standardErrorPipe = Pipe()
                    let outputCapture = ProcessOutputCapture()
                    let outputReadGroup = DispatchGroup()
                    process.executableURL = executableURL
                    process.arguments = arguments
                    process.standardOutput = standardOutputPipe
                    process.standardError = standardErrorPipe
                    controller.register(process)

                    do {
                        try process.run()
                        controller.processDidStart()

                        outputReadGroup.enter()
                        DispatchQueue.global(qos: .utility).async {
                            outputCapture.captureStandardOutput(
                                standardOutputPipe.fileHandleForReading.readDataToEndOfFile()
                            )
                            outputReadGroup.leave()
                        }
                        outputReadGroup.enter()
                        DispatchQueue.global(qos: .utility).async {
                            outputCapture.captureStandardError(
                                standardErrorPipe.fileHandleForReading.readDataToEndOfFile()
                            )
                            outputReadGroup.leave()
                        }

                        if timeout > 0 {
                            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                                controller.stop(reason: .timedOut(timeout))
                            }
                        }

                        process.waitUntilExit()
                        outputReadGroup.wait()
                        let stopReason = controller.complete()

                        switch stopReason {
                        case .cancelled:
                            continuation.resume(throwing: CancellationError())
                        case .timedOut(let timeout):
                            continuation.resume(
                                throwing: CancellableProcessRunnerError.timedOut(timeout)
                            )
                        case nil:
                            continuation.resume(returning: CancellableProcessResult(
                                terminationStatus: process.terminationStatus,
                                standardOutput: outputCapture.standardOutput,
                                standardError: outputCapture.standardError
                            ))
                        }
                    } catch {
                        _ = controller.complete()
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            controller.stop(reason: .cancelled)
        }
    }
}

private final class ProcessOutputCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var capturedStandardOutput = ""
    private var capturedStandardError = ""

    var standardOutput: String {
        lock.lock()
        defer { lock.unlock() }
        return capturedStandardOutput
    }

    var standardError: String {
        lock.lock()
        defer { lock.unlock() }
        return capturedStandardError
    }

    func captureStandardOutput(_ data: Data) {
        lock.lock()
        capturedStandardOutput = String(data: data, encoding: .utf8) ?? ""
        lock.unlock()
    }

    func captureStandardError(_ data: Data) {
        lock.lock()
        capturedStandardError = String(data: data, encoding: .utf8) ?? ""
        lock.unlock()
    }
}

private final class ProcessExecutionController: @unchecked Sendable {
    enum StopReason {
        case cancelled
        case timedOut(TimeInterval)
    }

    private let lock = NSLock()
    private var process: Process?
    private var stopReason: StopReason?
    private var completed = false

    func register(_ process: Process) {
        lock.lock()
        self.process = process
        lock.unlock()
    }

    func processDidStart() {
        lock.lock()
        let shouldStop = stopReason != nil && !completed
        let process = self.process
        lock.unlock()

        if shouldStop {
            terminate(process)
        }
    }

    func stop(reason: StopReason) {
        lock.lock()
        guard !completed, stopReason == nil else {
            lock.unlock()
            return
        }
        stopReason = reason
        let process = self.process
        lock.unlock()

        terminate(process)
    }

    func complete() -> StopReason? {
        lock.lock()
        defer { lock.unlock() }
        completed = true
        process = nil
        return stopReason
    }

    private func terminate(_ process: Process?) {
        guard let process, process.isRunning else {
            return
        }

        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            guard process.isRunning else {
                return
            }
            kill(process.processIdentifier, SIGKILL)
        }
    }
}
