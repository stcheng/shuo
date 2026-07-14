import Darwin
import Foundation

enum CancellableProcessRunnerError: Error, Equatable {
    case timedOut(TimeInterval)
}

struct CancellableProcessResult: Equatable {
    let terminationStatus: Int32
    let output: String
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
                    let outputPipe = Pipe()
                    process.executableURL = executableURL
                    process.arguments = arguments
                    process.standardOutput = outputPipe
                    process.standardError = outputPipe
                    controller.register(process)

                    do {
                        try process.run()
                        controller.processDidStart()
                        if timeout > 0 {
                            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                                controller.stop(reason: .timedOut(timeout))
                            }
                        }

                        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                        process.waitUntilExit()
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
                                output: String(data: outputData, encoding: .utf8) ?? ""
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
