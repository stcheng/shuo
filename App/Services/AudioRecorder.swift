@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import OSLog

enum AudioRecorderError: LocalizedError {
    case microphonePermissionDenied
    case failedToStart
    case selectedInputDeviceUnavailable
    case inputDidNotBecomeReady

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission was denied. Enable Shuo in System Settings > Privacy & Security > Microphone."
        case .failedToStart:
            return "Recording could not be started."
        case .selectedInputDeviceUnavailable:
            return "The selected microphone is unavailable. Reconnect it or choose System Default."
        case .inputDidNotBecomeReady:
            return "The selected microphone did not begin sending audio. Reconnect it or choose another input."
        }
    }
}

struct AudioInputDeviceOption: Identifiable, Equatable {
    let id: String
    let name: String
}

enum AudioInputSelectionDiagnostics: Equatable {
    case systemDefault
    case custom
}

struct AudioInputDeviceDiagnostics: Equatable {
    let transport: String
    let isConnected: Bool
}

/// A redacted, support-safe view of the current input route. Device names and
/// identifiers stay out of copied diagnostics because either can contain
/// personal information.
struct AudioInputDiagnostics: Equatable {
    let selection: AudioInputSelectionDiagnostics
    let resolvedDevice: AudioInputDeviceDiagnostics?
    let availableDeviceCount: Int
}

struct AudioRoute: Equatable {
    let inputDevice: AudioInputDeviceOption
    let outputDevice: AudioOutputDeviceOption?
    let resolvedAt: Date

    var outputDeviceID: String? {
        outputDevice?.id
    }
}

struct AudioRecordingStartResult: Equatable {
    let url: URL
    let route: AudioRoute
}

struct AudioCaptureGraphReusePolicy {
    static func shouldReuse(
        cachedDeviceID: String,
        cachedDeviceIsConnected: Bool,
        requestedDeviceID: String,
        requestedDeviceIsConnected: Bool,
        runtimeInvalidated: Bool
    ) -> Bool {
        cachedDeviceID == requestedDeviceID
            && cachedDeviceIsConnected
            && requestedDeviceIsConnected
            && !runtimeInvalidated
    }
}

struct AudioCaptureStartRetryPolicy {
    static func maximumAttemptCount(forTransportType transportType: Int32) -> Int {
        UInt32(bitPattern: transportType) == kAudioDeviceTransportTypeUSB ? 2 : 1
    }
}

struct AudioCaptureSegmentCallbackPolicy {
    static func shouldAccept(
        activeGeneration: UInt64?,
        callbackGeneration: UInt64,
        hasActiveSegment: Bool,
        isCurrentOutput: Bool
    ) -> Bool {
        activeGeneration == callbackGeneration
            && hasActiveSegment
            && isCurrentOutput
    }
}

enum AudioCaptureReadinessObservation: Equatable {
    case digitalSilence
    case candidate
    case ready
}

struct AudioCaptureReadinessPolicy: Equatable {
    static let outputSampleRate = 16_000
    static let bluetooth = AudioCaptureReadinessPolicy(
        requiredStableFrameCount: outputSampleRate / 10,
        minimumActiveFraction: 0.02,
        digitalSilenceFloor: 0.000_000_1,
        timeout: 8,
        maximumPreRollFrameCount: outputSampleRate / 2
    )
    static let usb = AudioCaptureReadinessPolicy(
        requiredStableFrameCount: outputSampleRate / 10,
        minimumActiveFraction: 0.02,
        digitalSilenceFloor: 0.000_000_1,
        timeout: 3,
        maximumPreRollFrameCount: outputSampleRate / 2
    )

    let requiredStableFrameCount: Int
    let minimumActiveFraction: Double
    let digitalSilenceFloor: Float
    let timeout: TimeInterval
    let maximumPreRollFrameCount: Int

    static func policy(forTransportType transportType: Int32) -> AudioCaptureReadinessPolicy? {
        switch UInt32(bitPattern: transportType) {
        case kAudioDeviceTransportTypeBluetooth,
             kAudioDeviceTransportTypeBluetoothLE:
            return .bluetooth
        case kAudioDeviceTransportTypeUSB:
            return .usb
        default:
            return nil
        }
    }
}

struct AudioCaptureReadinessGate {
    let policy: AudioCaptureReadinessPolicy

    private(set) var stableFrameCount = 0
    private(set) var isReady = false

    mutating func observe(_ samples: [Float]) -> AudioCaptureReadinessObservation {
        guard !samples.isEmpty else {
            reset()
            return .digitalSilence
        }

        let activeSampleCount = samples.reduce(into: 0) { count, sample in
            if sample.isFinite, abs(sample) > policy.digitalSilenceFloor {
                count += 1
            }
        }
        let activeFraction = Double(activeSampleCount) / Double(samples.count)
        guard activeFraction >= policy.minimumActiveFraction else {
            reset()
            return .digitalSilence
        }

        guard !isReady else {
            return .ready
        }

        stableFrameCount += samples.count
        guard stableFrameCount >= policy.requiredStableFrameCount else {
            return .candidate
        }

        isReady = true
        return .ready
    }

    mutating func reset() {
        stableFrameCount = 0
        isReady = false
    }
}

enum AudioCaptureReadinessPhase: Equatable {
    case warmingUp
    case readyToCommit
    case committed
    case rewarmingAfterFormatChange
}

/// Buffers microphone warm-up without making it part of the recording until
/// the start handshake commits on the capture queue. The same gate is reused
/// after a Bluetooth format renegotiation, but that internal re-warm does not
/// move the UI back to its preparing state.
struct AudioCaptureReadinessBuffer {
    let policy: AudioCaptureReadinessPolicy

    private(set) var phase: AudioCaptureReadinessPhase
    private(set) var pendingSamples: [Float] = []
    private(set) var discardedDigitalSilenceFrameCount = 0
    private(set) var discardedCandidateFrameCount = 0
    private var gate: AudioCaptureReadinessGate

    init(
        policy: AudioCaptureReadinessPolicy,
        initiallyCommitted: Bool = false
    ) {
        self.policy = policy
        phase = initiallyCommitted ? .committed : .warmingUp
        gate = AudioCaptureReadinessGate(policy: policy)
    }

    /// Returns only samples that are safe to append to the committed output.
    /// Initial warm-up never returns samples; it must first be atomically
    /// committed by `commitInitialReadinessIfReady()`.
    mutating func consume(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else {
            return []
        }

        switch phase {
        case .committed:
            return samples
        case .warmingUp, .readyToCommit, .rewarmingAfterFormatChange:
            let observation = gate.observe(samples)
            switch observation {
            case .digitalSilence:
                discardedDigitalSilenceFrameCount += samples.count
                discardPendingSamples()
                if phase == .readyToCommit {
                    phase = .warmingUp
                }
                return []
            case .candidate:
                appendPending(samples)
                return []
            case .ready:
                appendPending(samples)
                if phase == .rewarmingAfterFormatChange {
                    phase = .committed
                    return takePendingSamples()
                }
                phase = .readyToCommit
                return []
            }
        }
    }

    /// Must be called on the same serial queue that calls `consume`.
    /// Returning nil means the live-input requirement has not yet been met.
    mutating func commitInitialReadinessIfReady() -> [Float]? {
        guard phase == .readyToCommit else {
            return nil
        }

        phase = .committed
        return takePendingSamples()
    }

    /// Invalidates any uncommitted samples. Once recording has committed, a
    /// format change enters an internal warm-up so its digital-zero prefix is
    /// not appended to the active recording.
    mutating func sourceFormatDidChange() {
        gate.reset()
        discardPendingSamples()
        switch phase {
        case .committed, .rewarmingAfterFormatChange:
            phase = .rewarmingAfterFormatChange
        case .warmingUp, .readyToCommit:
            phase = .warmingUp
        }
    }

    /// A normal stop may arrive before a post-commit format re-warm reaches
    /// the full stability window. Candidate buffers have already passed the
    /// live-audio test, so retain them rather than truncating the sentence.
    mutating func finishCommittedRecording() -> [Float] {
        guard phase == .rewarmingAfterFormatChange else {
            return []
        }

        phase = .committed
        return takePendingSamples()
    }

    private mutating func appendPending(_ samples: [Float]) {
        pendingSamples.append(contentsOf: samples)
        let excessCount = pendingSamples.count - policy.maximumPreRollFrameCount
        if excessCount > 0 {
            discardedCandidateFrameCount += excessCount
            pendingSamples.removeFirst(excessCount)
        }
    }

    private mutating func discardPendingSamples() {
        discardedCandidateFrameCount += pendingSamples.count
        pendingSamples.removeAll(keepingCapacity: true)
    }

    private mutating func takePendingSamples() -> [Float] {
        let samples = pendingSamples
        pendingSamples.removeAll(keepingCapacity: true)
        return samples
    }
}

private enum AudioCaptureConversionError: Error {
    case invalidFormat
    case bufferAllocationFailed
    case bufferCopyFailed(OSStatus)
    case converterCreationFailed
    case conversionFailed(String)
}

struct AudioCaptureSourceFormat: Equatable {
    let sampleRate: Double
    let channelCount: AVAudioChannelCount

    init(_ format: AVAudioFormat) {
        sampleRate = format.sampleRate
        channelCount = format.channelCount
    }
}

struct AudioCaptureSourceFormatChange: Equatable {
    let old: AudioCaptureSourceFormat
    let new: AudioCaptureSourceFormat
}

struct ConvertedAudioSamples {
    /// Output that belongs to the old source format. It must be consumed before
    /// capture readiness is reset for `sourceFormatChange`.
    let previousFormatTailSamples: [Float]
    let samples: [Float]
    let sourceFormat: AudioCaptureSourceFormat
    let sourceFormatChange: AudioCaptureSourceFormatChange?

    var sourceFormatChanged: Bool {
        sourceFormatChange != nil
    }
}

private final class AudioConverterInputSupplyState: @unchecked Sendable {
    private let lock = NSLock()
    private var hasSuppliedInput = false

    /// AVAudioConverter calls its input block synchronously today, but lock
    /// this tiny state machine so the ownership remains correct if that
    /// implementation changes and to make the sendability contract explicit.
    func claimInput() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !hasSuppliedInput else {
            return false
        }
        hasSuppliedInput = true
        return true
    }
}

final class AudioCaptureBufferConverter {
    private static let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Double(AudioCaptureReadinessPolicy.outputSampleRate),
        channels: 1,
        interleaved: false
    )!

    private var inputFormat: AVAudioFormat?
    private var converter: AVAudioConverter?

    func reset() {
        inputFormat = nil
        converter = nil
    }

    func convert(_ sampleBuffer: CMSampleBuffer) throws -> ConvertedAudioSamples {
        try convert(Self.ownedPCMBuffer(from: sampleBuffer))
    }

    func convert(_ inputBuffer: AVAudioPCMBuffer) throws -> ConvertedAudioSamples {
        var previousFormatTailSamples: [Float] = []
        var sourceFormatChange: AudioCaptureSourceFormatChange?

        if let inputFormat,
           inputFormat.isEqual(inputBuffer.format),
           converter != nil {
        } else {
            if let inputFormat, converter != nil {
                previousFormatTailSamples = try drainCurrentConverter()
                sourceFormatChange = AudioCaptureSourceFormatChange(
                    old: AudioCaptureSourceFormat(inputFormat),
                    new: AudioCaptureSourceFormat(inputBuffer.format)
                )
            }
            try configureConverter(for: inputBuffer.format)
        }

        guard let converter else {
            throw AudioCaptureConversionError.converterCreationFailed
        }

        return ConvertedAudioSamples(
            previousFormatTailSamples: previousFormatTailSamples,
            samples: try convert(inputBuffer, using: converter),
            sourceFormat: AudioCaptureSourceFormat(inputBuffer.format),
            sourceFormatChange: sourceFormatChange
        )
    }

    /// Signals end-of-stream and returns every frame still buffered inside the
    /// sample-rate converter. The converter is reset whether draining succeeds
    /// or fails, so a later recording cannot inherit its state.
    func finish() throws -> [Float] {
        defer { reset() }
        return try drainCurrentConverter()
    }

    private func configureConverter(for format: AVAudioFormat) throws {
        guard let nextConverter = AVAudioConverter(
            from: format,
            to: Self.outputFormat
        ) else {
            throw AudioCaptureConversionError.converterCreationFailed
        }
        nextConverter.primeMethod = .normal
        nextConverter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        inputFormat = format
        converter = nextConverter
    }

    private func convert(
        _ inputBuffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter
    ) throws -> [Float] {
        let ratio = Self.outputFormat.sampleRate / inputBuffer.format.sampleRate
        let outputCapacity = max(
            1,
            Int(ceil(Double(inputBuffer.frameLength) * ratio)) + 64
        )
        let inputSupply = AudioConverterInputSupplyState()

        return try collectOutput(
            from: converter,
            outputCapacity: outputCapacity
        ) { _, inputStatus in
            guard inputSupply.claimInput() else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            inputStatus.pointee = .haveData
            return inputBuffer
        }
    }

    private func drainCurrentConverter() throws -> [Float] {
        guard let converter else {
            return []
        }

        return try collectOutput(
            from: converter,
            outputCapacity: 512
        ) { _, inputStatus in
            inputStatus.pointee = .endOfStream
            return nil
        }
    }

    private func collectOutput(
        from converter: AVAudioConverter,
        outputCapacity: Int,
        inputBlock: @escaping AVAudioConverterInputBlock
    ) throws -> [Float] {
        var samples: [Float] = []
        var shouldContinue = true
        var iterationCount = 0

        while shouldContinue {
            iterationCount += 1
            guard iterationCount <= 1_024 else {
                throw AudioCaptureConversionError.conversionFailed(
                    "Audio converter did not reach a terminal state"
                )
            }

            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: Self.outputFormat,
                frameCapacity: AVAudioFrameCount(outputCapacity)
            ) else {
                throw AudioCaptureConversionError.bufferAllocationFailed
            }

            var conversionError: NSError?
            let status = converter.convert(
                to: outputBuffer,
                error: &conversionError,
                withInputFrom: inputBlock
            )

            if status == .error || conversionError != nil {
                throw AudioCaptureConversionError.conversionFailed(
                    conversionError?.localizedDescription ?? "Unknown audio conversion error"
                )
            }

            if outputBuffer.frameLength > 0,
               let channelData = outputBuffer.floatChannelData?[0] {
                samples.append(
                    contentsOf: UnsafeBufferPointer(
                        start: channelData,
                        count: Int(outputBuffer.frameLength)
                    )
                )
            }

            switch status {
            case .haveData:
                shouldContinue = true
            case .inputRanDry, .endOfStream:
                shouldContinue = false
            case .error:
                shouldContinue = false
            @unknown default:
                shouldContinue = false
            }
        }

        return samples
    }

    private static func ownedPCMBuffer(from sampleBuffer: CMSampleBuffer) throws -> AVAudioPCMBuffer {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            throw AudioCaptureConversionError.invalidFormat
        }
        let format = AVAudioFormat(cmAudioFormatDescription: formatDescription)

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0,
              frameCount <= Int(Int32.max),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(frameCount)
              ) else {
            throw AudioCaptureConversionError.bufferAllocationFailed
        }

        // AVAudioPCMBuffer exposes zero-sized AudioBuffers until frameLength is
        // initialized. Core Media requires a pre-populated, correctly sized
        // AudioBufferList as the copy destination.
        buffer.frameLength = AVAudioFrameCount(frameCount)

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: buffer.mutableAudioBufferList
        )
        guard status == noErr else {
            throw AudioCaptureConversionError.bufferCopyFailed(status)
        }
        return buffer
    }
}

enum AudioInputDeviceCatalog {
    static let automaticDeviceID = "__automatic__"
    static let systemDefaultDeviceID = "__system_default__"

    static func devices() -> [AudioInputDeviceOption] {
        captureDevices()
            .sorted { $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending }
            .map {
                AudioInputDeviceOption(
                    id: $0.uniqueID,
                    name: $0.localizedName
                )
            }
    }

    static func diagnostics(for uniqueID: String) -> AudioInputDiagnostics {
        let availableDevices = captureDevices()
        let normalizedID = normalizedSelectionID(uniqueID)
        let selection: AudioInputSelectionDiagnostics = normalizedID == systemDefaultDeviceID
            ? .systemDefault
            : .custom
        let resolvedDevice: AVCaptureDevice?
        if selection == .systemDefault {
            resolvedDevice = AVCaptureDevice.default(for: .audio)
        } else {
            resolvedDevice = availableDevices.first { $0.uniqueID == normalizedID }
        }

        return AudioInputDiagnostics(
            selection: selection,
            resolvedDevice: resolvedDevice.map {
                AudioInputDeviceDiagnostics(
                    transport: transportDescription(for: $0.transportType),
                    isConnected: $0.isConnected
                )
            },
            availableDeviceCount: availableDevices.count
        )
    }

    static func transportDescription(for transportType: Int32) -> String {
        switch UInt32(bitPattern: transportType) {
        case kAudioDeviceTransportTypeBluetooth:
            return "Bluetooth"
        case kAudioDeviceTransportTypeBluetoothLE:
            return "Bluetooth LE"
        case kAudioDeviceTransportTypeBuiltIn:
            return "Built-in"
        case kAudioDeviceTransportTypeUSB:
            return "USB"
        case kAudioDeviceTransportTypeAggregate,
             kAudioDeviceTransportTypeAutoAggregate:
            return "Aggregate"
        case kAudioDeviceTransportTypeVirtual:
            return "Virtual"
        case kAudioDeviceTransportTypeThunderbolt:
            return "Thunderbolt"
        default:
            return String(format: "0x%08X", UInt32(bitPattern: transportType))
        }
    }

    static func audioObjectID(for uniqueID: String) -> AudioObjectID? {
        allAudioDeviceIDs().first { deviceID in
            coreAudioStringProperty(
                deviceID,
                selector: kAudioDevicePropertyDeviceUID
            ) == uniqueID
        }
    }

    static func device(for uniqueID: String) -> AVCaptureDevice? {
        let trimmedID = uniqueID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedID = normalizedSelectionID(trimmedID)
        if normalizedID == systemDefaultDeviceID {
            return AVCaptureDevice.default(for: .audio)
        }

        // An explicitly selected device is an instruction, not a preference.
        // Falling back here can silently record from a built-in microphone
        // while Settings still says AirPods (or another device) is selected.
        return captureDevices().first { $0.uniqueID == trimmedID }
    }

    static func isSpecialDeviceID(_ id: String) -> Bool {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedID.isEmpty
            || trimmedID == automaticDeviceID
            || trimmedID == systemDefaultDeviceID
    }

    /// Older releases exposed an Automatic choice that guessed a preferred
    /// headset or external microphone by name. That guess can select a device
    /// with no active audio route, so migrate it to macOS's actual default.
    static func normalizedSelectionID(_ id: String) -> String {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty,
              trimmedID != automaticDeviceID else {
            return systemDefaultDeviceID
        }

        return trimmedID
    }

    private static func captureDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        .devices
    }

    private static func allAudioDeviceIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr else {
            return []
        }

        var deviceIDs = [AudioObjectID](
            repeating: 0,
            count: Int(dataSize) / MemoryLayout<AudioObjectID>.size
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ) == noErr else {
            return []
        }
        return deviceIDs
    }

    private static func coreAudioStringProperty(
        _ deviceID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &value
        ) == noErr else {
            return nil
        }
        return value?.takeUnretainedValue() as String?
    }

}

/// UI-facing lifecycle calls are made on MainActor through `AudioRecording`;
/// every capture callback and teardown mutation is serialized on captureQueue.
/// The unchecked conformance documents that two-queue ownership contract for
/// the async Dispatch continuations used by start and stop.
final class AudioRecorder: NSObject, @unchecked Sendable {
    private final class SegmentSampleBufferDelegate: NSObject,
        AVCaptureAudioDataOutputSampleBufferDelegate {
        weak var recorder: AudioRecorder?
        let generation: UInt64

        init(recorder: AudioRecorder, generation: UInt64) {
            self.recorder = recorder
            self.generation = generation
        }

        func captureOutput(
            _ output: AVCaptureOutput,
            didOutput sampleBuffer: CMSampleBuffer,
            from connection: AVCaptureConnection
        ) {
            recorder?.consumeSampleBuffer(
                sampleBuffer,
                from: output,
                generation: generation
            )
        }
    }

    /// Capture graph mutation is owned by `captureQueue`. Notification
    /// callbacks only enqueue invalidation work on that queue, so graph
    /// references may safely cross the callback boundary without concurrent
    /// access to their mutable fields.
    private final class CaptureGraph: @unchecked Sendable {
        let session: AVCaptureSession
        let input: AVCaptureDeviceInput
        let output: AVCaptureAudioDataOutput
        var runtimeInvalidated = false
        var runtimeErrorObserver: NSObjectProtocol?
        var deviceDisconnectObserver: NSObjectProtocol?

        init(
            session: AVCaptureSession,
            input: AVCaptureDeviceInput,
            output: AVCaptureAudioDataOutput
        ) {
            self.session = session
            self.input = input
            self.output = output
        }

        deinit {
            if let runtimeErrorObserver {
                NotificationCenter.default.removeObserver(runtimeErrorObserver)
            }
            if let deviceDisconnectObserver {
                NotificationCenter.default.removeObserver(deviceDisconnectObserver)
            }
        }
    }

    private struct SegmentSnapshot {
        let url: URL
        let samples: [Float]
        let sourceFormatChangeCount: Int
        let latestSourceFormat: AudioCaptureSourceFormat?
        let conversionFailureCount: Int
        let timestampGapCount: Int
        let maximumTimestampGap: TimeInterval
        let discardedZeroFrameCount: Int
    }

    static let maximumRecordingDuration: TimeInterval = 5 * 60

    private static let logger = Logger(
        subsystem: AppBuildIdentity.bundleIdentifier,
        category: "AudioCapture"
    )
    private static let outputSampleRate = AudioCaptureReadinessPolicy.outputSampleRate

    private let captureQueue = DispatchQueue(
        label: "\(AppBuildIdentity.bundleIdentifier).audio-capture"
    )
    private let maximumRecordingDuration: TimeInterval
    private let bufferConverter = AudioCaptureBufferConverter()
    private var captureGraph: CaptureGraph?
    private var usbCaptureEngine: AVAudioEngine?
    private var segmentSampleBufferDelegate: SegmentSampleBufferDelegate?
    private var nextSegmentGeneration: UInt64 = 0
    private var activeSegmentGeneration: UInt64?
    private var recordingURL: URL?
    private var outputSamples: [Float] = []
    private var readinessBuffer: AudioCaptureReadinessBuffer?
    private var readinessWarmupStartedAt: Date?
    private var readinessZeroFrameBaseline = 0
    private var didNotifyMaximumDuration = false
    private var sourceFormatChangeCount = 0
    private var latestSourceFormat: AudioCaptureSourceFormat?
    private var conversionFailureCount = 0
    private var timestampGapCount = 0
    private var maximumTimestampGap: TimeInterval = 0
    private var expectedNextPresentationTime: CMTime?

    var maximumDurationReachedHandler: (@MainActor @Sendable () -> Void)?

    init(maximumRecordingDuration: TimeInterval = AudioRecorder.maximumRecordingDuration) {
        self.maximumRecordingDuration = max(1, maximumRecordingDuration)
        super.init()
    }

    var isRecording: Bool {
        captureQueue.sync {
            recordingURL != nil
                && (captureGraph?.session.isRunning == true || usbCaptureEngine?.isRunning == true)
        }
    }

    func start(inputDeviceID: String = AudioInputDeviceCatalog.systemDefaultDeviceID) async throws -> AudioRecordingStartResult {
        try Task.checkCancellation()
        let hasMicrophoneAccess = await AudioRecorder.requestMicrophoneAccess()
        try Task.checkCancellation()
        guard hasMicrophoneAccess else {
            throw AudioRecorderError.microphonePermissionDenied
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shuo-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        let inputDiagnostics = AudioInputDeviceCatalog.diagnostics(for: inputDeviceID)
        let selectionDescription = inputDiagnostics.selection == .systemDefault
            ? "system-default"
            : "custom"
        let resolvedTransport = inputDiagnostics.resolvedDevice?.transport ?? "unavailable"
        let resolvedIsConnected = inputDiagnostics.resolvedDevice?.isConnected ?? false
        Self.logger.info(
            "Audio input requested: selection=\(selectionDescription, privacy: .public), resolved=\(inputDiagnostics.resolvedDevice != nil, privacy: .public), transport=\(resolvedTransport, privacy: .public), connected=\(resolvedIsConnected, privacy: .public), availableInputs=\(inputDiagnostics.availableDeviceCount, privacy: .public)"
        )

        guard let device = AudioInputDeviceCatalog.device(for: inputDeviceID) else {
            Self.logger.error("Requested audio input is unavailable")
            throw AudioRecorderError.selectedInputDeviceUnavailable
        }

        Self.logger.info(
            "Audio input resolved: name=\(device.localizedName, privacy: .private), identifier=\(device.uniqueID, privacy: .private), transport=\(AudioInputDeviceCatalog.transportDescription(for: device.transportType), privacy: .public), connected=\(device.isConnected, privacy: .public)"
        )

        let inputDevice = AudioInputDeviceOption(
            id: device.uniqueID,
            name: device.localizedName
        )
        let route = AudioRoute(
            inputDevice: inputDevice,
            outputDevice: AudioOutputDeviceCatalog.preferredOutputDevice(matchingInputDevice: inputDevice),
            resolvedAt: Date()
        )

        do {
            let policy = AudioCaptureReadinessPolicy.policy(
                forTransportType: device.transportType
            )
            let transport = AudioInputDeviceCatalog.transportDescription(for: device.transportType)

            let maximumAttemptCount = AudioCaptureStartRetryPolicy.maximumAttemptCount(
                forTransportType: device.transportType
            )
            for attempt in 1...maximumAttemptCount {
                do {
                    try Task.checkCancellation()
                    try await prepareSegmentAndStartCapture(
                        device: device,
                        url: url,
                        readinessPolicy: policy,
                        transportDescription: transport
                    )
                    try Task.checkCancellation()
                    if let policy {
                        try await waitForInputReadiness(timeout: policy.timeout)
                    }
                    try Task.checkCancellation()
                    return AudioRecordingStartResult(url: url, route: route)
                } catch AudioRecorderError.inputDidNotBecomeReady
                    where attempt < maximumAttemptCount {
                    Self.logger.notice(
                        "USB input produced no live audio; rebuilding capture graph before retry: attempt=\(attempt, privacy: .public), maximumAttempts=\(maximumAttemptCount, privacy: .public)"
                    )
                    await abortActiveSegment(invalidateGraph: true)
                }
            }
            throw AudioRecorderError.inputDidNotBecomeReady
        } catch {
            if error is CancellationError {
                Self.logger.info("Audio capture start cancelled")
            } else {
                Self.logger.error(
                    "Audio capture start failed: \(String(describing: error), privacy: .public)"
                )
            }
            await abortActiveSegment(invalidateGraph: !(error is CancellationError))
            try? FileManager.default.removeItem(at: url)
            if error is AudioRecorderError || error is CancellationError {
                throw error
            }
            throw AudioRecorderError.failedToStart
        }
    }

    func stop() async -> URL? {
        guard let snapshot = await stopAndSnapshotActiveSegment() else {
            return nil
        }

        guard !snapshot.samples.isEmpty else {
            Self.logger.error(
                "Audio capture stopped without samples: finalRate=\(snapshot.latestSourceFormat?.sampleRate ?? 0, privacy: .public), finalChannels=\(snapshot.latestSourceFormat?.channelCount ?? 0, privacy: .public), formatChanges=\(snapshot.sourceFormatChangeCount, privacy: .public), conversionFailures=\(snapshot.conversionFailureCount, privacy: .public), discardedZeroFrames=\(snapshot.discardedZeroFrameCount, privacy: .public)"
            )
            try? FileManager.default.removeItem(at: snapshot.url)
            return nil
        }

        do {
            try await Task.detached(priority: .userInitiated) {
                try Self.writeWAV(
                    samples: snapshot.samples,
                    sampleRate: Self.outputSampleRate,
                    to: snapshot.url
                )
            }.value
        } catch {
            Self.logger.error(
                "Failed to write captured audio: \(String(describing: error), privacy: .public)"
            )
            try? FileManager.default.removeItem(at: snapshot.url)
            return nil
        }

        guard Self.isReadableAudioFile(snapshot.url) else {
            Self.logger.error("Captured audio file failed readability validation")
            try? FileManager.default.removeItem(at: snapshot.url)
            return nil
        }

        Self.logger.info(
            "Audio capture finished: frames=\(snapshot.samples.count, privacy: .public), finalRate=\(snapshot.latestSourceFormat?.sampleRate ?? 0, privacy: .public), finalChannels=\(snapshot.latestSourceFormat?.channelCount ?? 0, privacy: .public), formatChanges=\(snapshot.sourceFormatChangeCount, privacy: .public), conversionFailures=\(snapshot.conversionFailureCount, privacy: .public), timestampGaps=\(snapshot.timestampGapCount, privacy: .public), maximumGap=\(snapshot.maximumTimestampGap, privacy: .public), discardedZeroFrames=\(snapshot.discardedZeroFrameCount, privacy: .public), discardedZeroDuration=\(Double(snapshot.discardedZeroFrameCount) / Double(Self.outputSampleRate), privacy: .public)"
        )

        return snapshot.url
    }

    func cancel() -> URL? {
        let url = captureQueue.sync {
            let url = recordingURL
            quiesceCaptureGraphOnCaptureQueue(drainConverter: false)
            resetSegmentStateOnCaptureQueue()
            return url
        }

        if let url {
            try? FileManager.default.removeItem(at: url)
        }

        return url
    }

    private func consumeSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        from output: AVCaptureOutput,
        generation: UInt64
    ) {
        guard AudioCaptureSegmentCallbackPolicy.shouldAccept(
            activeGeneration: activeSegmentGeneration,
            callbackGeneration: generation,
            hasActiveSegment: recordingURL != nil,
            isCurrentOutput: captureGraph?.output === output
        ) else {
            Self.logger.debug(
                "Discarded stale audio callback: generation=\(generation, privacy: .public)"
            )
            return
        }

        trackPresentationTimestamp(of: sampleBuffer)

        let convertedAudio: ConvertedAudioSamples
        do {
            convertedAudio = try bufferConverter.convert(sampleBuffer)
        } catch {
            conversionFailureCount += 1
            Self.logger.error(
                "Audio buffer conversion failed: \(String(describing: error), privacy: .public)"
            )
            return
        }

        consumeConvertedAudio(convertedAudio)
    }

    private func consumeUSBInputBuffer(
        _ inputBuffer: AVAudioPCMBuffer,
        generation: UInt64
    ) {
        guard activeSegmentGeneration == generation,
              recordingURL != nil,
              usbCaptureEngine != nil else {
            Self.logger.debug(
                "Discarded stale USB audio callback: generation=\(generation, privacy: .public)"
            )
            return
        }

        do {
            consumeConvertedAudio(try bufferConverter.convert(inputBuffer))
        } catch {
            conversionFailureCount += 1
            Self.logger.error(
                "USB audio buffer conversion failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func consumeConvertedAudio(_ convertedAudio: ConvertedAudioSamples) {
        if latestSourceFormat == nil {
            Self.logger.info(
                "Audio input format: rate=\(convertedAudio.sourceFormat.sampleRate, privacy: .public), channels=\(convertedAudio.sourceFormat.channelCount, privacy: .public)"
            )
        }
        latestSourceFormat = convertedAudio.sourceFormat

        // A format change drains the old converter first. Its tail belongs to
        // the old readiness phase and must be consumed before the new source
        // format invalidates pending warm-up samples.
        consumeConvertedSamples(convertedAudio.previousFormatTailSamples)

        if let change = convertedAudio.sourceFormatChange {
            sourceFormatChangeCount += 1
            Self.logger.info(
                "Audio input format changed: oldRate=\(change.old.sampleRate, privacy: .public), oldChannels=\(change.old.channelCount, privacy: .public), newRate=\(change.new.sampleRate, privacy: .public), newChannels=\(change.new.channelCount, privacy: .public)"
            )
            if var readinessBuffer {
                readinessBuffer.sourceFormatDidChange()
                self.readinessBuffer = readinessBuffer
                readinessWarmupStartedAt = Date()
                readinessZeroFrameBaseline = readinessBuffer.discardedDigitalSilenceFrameCount
            }
        }

        consumeConvertedSamples(convertedAudio.samples)
    }

    private func consumeConvertedSamples(_ samples: [Float]) {
        guard !samples.isEmpty else {
            return
        }

        guard var readinessBuffer else {
            appendOutputSamples(samples)
            return
        }

        let previousPhase = readinessBuffer.phase
        let committedSamples = readinessBuffer.consume(samples)
        self.readinessBuffer = readinessBuffer
        appendOutputSamples(committedSamples)

        if previousPhase == .rewarmingAfterFormatChange,
           readinessBuffer.phase == .committed {
            logReadinessCompletion(
                kind: "format-change",
                readinessBuffer: readinessBuffer
            )
        }
    }

    private func appendOutputSamples(_ samples: [Float]) {
        let sampleLimit = max(1, Int(Double(Self.outputSampleRate) * maximumRecordingDuration))
        let remainingCapacity = sampleLimit - outputSamples.count
        if remainingCapacity > 0 {
            outputSamples.append(contentsOf: samples.prefix(remainingCapacity))
        }

        if outputSamples.count >= sampleLimit, !didNotifyMaximumDuration {
            didNotifyMaximumDuration = true
            Task { @MainActor [weak self] in
                self?.maximumDurationReachedHandler?()
            }
        }
    }

    private func resetSegmentStateOnCaptureQueue() {
        activeSegmentGeneration = nil
        segmentSampleBufferDelegate = nil
        recordingURL = nil
        outputSamples.removeAll(keepingCapacity: true)
        readinessBuffer = nil
        readinessWarmupStartedAt = nil
        readinessZeroFrameBaseline = 0
        didNotifyMaximumDuration = false
        sourceFormatChangeCount = 0
        latestSourceFormat = nil
        conversionFailureCount = 0
        timestampGapCount = 0
        maximumTimestampGap = 0
        expectedNextPresentationTime = nil
        bufferConverter.reset()
    }

    private func prepareSegmentAndStartCapture(
        device: AVCaptureDevice,
        url: URL,
        readinessPolicy: AudioCaptureReadinessPolicy?,
        transportDescription: String
    ) async throws {
        if UInt32(bitPattern: device.transportType) == kAudioDeviceTransportTypeUSB {
            try await prepareUSBEngineAndStartCapture(
                device: device,
                url: url,
                readinessPolicy: readinessPolicy ?? .usb,
                transportDescription: transportDescription
            )
            return
        }

        try await withCheckedThrowingContinuation { continuation in
            captureQueue.async {
                do {
                    guard self.recordingURL == nil else {
                        throw AudioRecorderError.failedToStart
                    }

                    let graphSetupStartedAt = CFAbsoluteTimeGetCurrent()
                    let (graph, graphReused) = try self.captureGraphOnCaptureQueue(
                        for: device
                    )
                    let graphSetupDuration = CFAbsoluteTimeGetCurrent() - graphSetupStartedAt

                    guard !graph.session.isRunning else {
                        graph.runtimeInvalidated = true
                        self.discardCaptureGraphOnCaptureQueue(graph)
                        throw AudioRecorderError.failedToStart
                    }

                    self.resetSegmentStateOnCaptureQueue()
                    self.recordingURL = url
                    self.readinessBuffer = AudioCaptureReadinessBuffer(
                        policy: readinessPolicy ?? .bluetooth,
                        initiallyCommitted: readinessPolicy == nil
                    )
                    self.readinessWarmupStartedAt = readinessPolicy == nil ? nil : Date()
                    self.nextSegmentGeneration &+= 1
                    let segmentDelegate = SegmentSampleBufferDelegate(
                        recorder: self,
                        generation: self.nextSegmentGeneration
                    )
                    self.segmentSampleBufferDelegate = segmentDelegate
                    self.activeSegmentGeneration = segmentDelegate.generation
                    graph.output.setSampleBufferDelegate(
                        segmentDelegate,
                        queue: self.captureQueue
                    )

                    let sessionStartStartedAt = CFAbsoluteTimeGetCurrent()
                    graph.session.startRunning()
                    let sessionStartDuration = CFAbsoluteTimeGetCurrent() - sessionStartStartedAt

                    guard graph.session.isRunning else {
                        graph.output.setSampleBufferDelegate(nil, queue: nil)
                        graph.runtimeInvalidated = true
                        self.resetSegmentStateOnCaptureQueue()
                        self.discardCaptureGraphOnCaptureQueue(graph)
                        throw AudioRecorderError.failedToStart
                    }

                    Self.logger.info(
                        "Audio capture starting: transport=\(transportDescription, privacy: .public), readinessHandshake=\(readinessPolicy != nil, privacy: .public), graphReused=\(graphReused, privacy: .public), graphSetupDuration=\(graphSetupDuration, privacy: .public), sessionStartDuration=\(sessionStartDuration, privacy: .public), deviceName=\(device.localizedName, privacy: .private), deviceIdentifier=\(device.uniqueID, privacy: .private)"
                    )
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func prepareUSBEngineAndStartCapture(
        device: AVCaptureDevice,
        url: URL,
        readinessPolicy: AudioCaptureReadinessPolicy,
        transportDescription: String
    ) async throws {
        guard let audioObjectID = AudioInputDeviceCatalog.audioObjectID(
            for: device.uniqueID
        ) else {
            throw AudioRecorderError.selectedInputDeviceUnavailable
        }

        try await withCheckedThrowingContinuation { continuation in
            captureQueue.async {
                let setupStartedAt = CFAbsoluteTimeGetCurrent()
                let engine = AVAudioEngine()
                let inputNode = engine.inputNode
                var tapInstalled = false

                do {
                    guard self.recordingURL == nil else {
                        throw AudioRecorderError.failedToStart
                    }

                    // AVCaptureSession can deliver digital zeros from a live
                    // USB microphone on macOS. Bind AVAudioEngine's input unit
                    // directly to the Core Audio device, as Yuwp does.
                    if let captureGraph = self.captureGraph {
                        self.discardCaptureGraphOnCaptureQueue(captureGraph)
                    }
                    guard let audioUnit = inputNode.audioUnit else {
                        throw AudioRecorderError.failedToStart
                    }
                    var selectedDeviceID = audioObjectID
                    let selectionStatus = AudioUnitSetProperty(
                        audioUnit,
                        kAudioOutputUnitProperty_CurrentDevice,
                        kAudioUnitScope_Global,
                        0,
                        &selectedDeviceID,
                        UInt32(MemoryLayout<AudioObjectID>.size)
                    )
                    guard selectionStatus == noErr else {
                        Self.logger.error(
                            "Failed to bind USB input audio unit: status=\(selectionStatus, privacy: .public)"
                        )
                        throw AudioRecorderError.failedToStart
                    }

                    let sourceFormat = inputNode.inputFormat(forBus: 0)
                    guard sourceFormat.sampleRate > 0,
                          sourceFormat.channelCount > 0 else {
                        Self.logger.error(
                            "USB input exposed an invalid format: rate=\(sourceFormat.sampleRate, privacy: .public), channels=\(sourceFormat.channelCount, privacy: .public)"
                        )
                        throw AudioRecorderError.failedToStart
                    }

                    self.resetSegmentStateOnCaptureQueue()
                    self.recordingURL = url
                    self.readinessBuffer = AudioCaptureReadinessBuffer(
                        policy: readinessPolicy
                    )
                    self.readinessWarmupStartedAt = Date()
                    self.nextSegmentGeneration &+= 1
                    let generation = self.nextSegmentGeneration
                    self.activeSegmentGeneration = generation
                    self.usbCaptureEngine = engine

                    let bufferSize = AVAudioFrameCount(sourceFormat.sampleRate * 0.1)
                    inputNode.installTap(
                        onBus: 0,
                        bufferSize: bufferSize,
                        format: sourceFormat
                    ) { [weak self] buffer, _ in
                        guard let self,
                              let copiedBuffer = Self.copyPCMBuffer(buffer) else {
                            return
                        }
                        self.captureQueue.async {
                            self.consumeUSBInputBuffer(
                                copiedBuffer,
                                generation: generation
                            )
                        }
                    }
                    tapInstalled = true

                    engine.prepare()
                    try engine.start()
                    guard engine.isRunning else {
                        throw AudioRecorderError.failedToStart
                    }

                    let setupDuration = CFAbsoluteTimeGetCurrent() - setupStartedAt
                    Self.logger.info(
                        "Audio capture starting: backend=AVAudioEngine, transport=\(transportDescription, privacy: .public), readinessHandshake=true, graphReused=false, setupDuration=\(setupDuration, privacy: .public), sourceRate=\(sourceFormat.sampleRate, privacy: .public), sourceChannels=\(sourceFormat.channelCount, privacy: .public), deviceName=\(device.localizedName, privacy: .private), deviceIdentifier=\(device.uniqueID, privacy: .private)"
                    )
                    continuation.resume()
                } catch {
                    if tapInstalled {
                        inputNode.removeTap(onBus: 0)
                    }
                    engine.stop()
                    engine.reset()
                    self.usbCaptureEngine = nil
                    self.resetSegmentStateOnCaptureQueue()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func copyPCMBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(
            pcmFormat: buffer.format,
            frameCapacity: buffer.frameLength
        ) else {
            return nil
        }
        copy.frameLength = buffer.frameLength

        let sourceBuffers = UnsafeMutableAudioBufferListPointer(
            buffer.mutableAudioBufferList
        )
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(
            copy.mutableAudioBufferList
        )
        guard sourceBuffers.count == destinationBuffers.count else {
            return nil
        }

        for index in sourceBuffers.indices {
            guard let source = sourceBuffers[index].mData,
                  let destination = destinationBuffers[index].mData else {
                return nil
            }
            let byteCount = min(
                Int(sourceBuffers[index].mDataByteSize),
                Int(destinationBuffers[index].mDataByteSize)
            )
            memcpy(destination, source, byteCount)
            destinationBuffers[index].mDataByteSize = UInt32(byteCount)
        }
        return copy
    }

    private func abortActiveSegment(invalidateGraph: Bool) async {
        await withCheckedContinuation { continuation in
            captureQueue.async {
                let hadActiveSegment = self.recordingURL != nil
                self.quiesceCaptureGraphOnCaptureQueue(drainConverter: false)
                if invalidateGraph,
                   hadActiveSegment,
                   let graph = self.captureGraph {
                    graph.runtimeInvalidated = true
                    self.discardCaptureGraphOnCaptureQueue(graph)
                }
                self.resetSegmentStateOnCaptureQueue()
                continuation.resume()
            }
        }
    }

    private func stopAndSnapshotActiveSegment() async -> SegmentSnapshot? {
        await withCheckedContinuation { continuation in
            captureQueue.async {
                guard let url = self.recordingURL else {
                    continuation.resume(returning: nil)
                    return
                }

                self.quiesceCaptureGraphOnCaptureQueue(drainConverter: true)
                let snapshot = SegmentSnapshot(
                    url: url,
                    samples: self.outputSamples,
                    sourceFormatChangeCount: self.sourceFormatChangeCount,
                    latestSourceFormat: self.latestSourceFormat,
                    conversionFailureCount: self.conversionFailureCount,
                    timestampGapCount: self.timestampGapCount,
                    maximumTimestampGap: self.maximumTimestampGap,
                    discardedZeroFrameCount: self.readinessBuffer?.discardedDigitalSilenceFrameCount ?? 0
                )
                self.resetSegmentStateOnCaptureQueue()
                continuation.resume(returning: snapshot)
            }
        }
    }

    /// All capture teardown is serialized with capture callbacks. Callers must
    /// already be running on captureQueue.
    private func quiesceCaptureGraphOnCaptureQueue(drainConverter: Bool) {
        if let engine = usbCaptureEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            engine.reset()
            usbCaptureEngine = nil
        }

        captureGraph?.output.setSampleBufferDelegate(nil, queue: nil)
        if captureGraph?.session.isRunning == true {
            captureGraph?.session.stopRunning()
        }

        if drainConverter {
            do {
                consumeConvertedSamples(try bufferConverter.finish())
            } catch {
                conversionFailureCount += 1
                Self.logger.error(
                    "Audio converter drain failed: \(String(describing: error), privacy: .public)"
                )
            }

            if var readinessBuffer {
                let finalCandidateSamples = readinessBuffer.finishCommittedRecording()
                self.readinessBuffer = readinessBuffer
                appendOutputSamples(finalCandidateSamples)
            }
        } else {
            bufferConverter.reset()
        }
    }

    private func captureGraphOnCaptureQueue(
        for device: AVCaptureDevice
    ) throws -> (CaptureGraph, Bool) {
        if let captureGraph,
           AudioCaptureGraphReusePolicy.shouldReuse(
               cachedDeviceID: captureGraph.input.device.uniqueID,
               cachedDeviceIsConnected: captureGraph.input.device.isConnected,
               requestedDeviceID: device.uniqueID,
               requestedDeviceIsConnected: device.isConnected,
               runtimeInvalidated: captureGraph.runtimeInvalidated
           ) {
            return (captureGraph, true)
        }

        let replacement = try makeCaptureGraphOnCaptureQueue(for: device)
        if let captureGraph {
            discardCaptureGraphOnCaptureQueue(captureGraph)
        }
        captureGraph = replacement
        return (replacement, false)
    }

    private func makeCaptureGraphOnCaptureQueue(
        for device: AVCaptureDevice
    ) throws -> CaptureGraph {
        let session = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureAudioDataOutput()

        guard session.canAddInput(input),
              session.canAddOutput(output) else {
            throw AudioRecorderError.failedToStart
        }

        session.beginConfiguration()
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()

        let graph = CaptureGraph(session: session, input: input, output: output)
        graph.runtimeErrorObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session,
            queue: nil
        ) { [weak self, weak graph] notification in
            guard let self, let graph else {
                return
            }
            let runtimeError = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
            let errorDomain = runtimeError?.domain ?? "unknown"
            let errorCode = runtimeError?.code ?? 0
            let errorDescription = runtimeError?.localizedDescription ?? "unavailable"
            self.captureQueue.async {
                graph.runtimeInvalidated = true
                Self.logger.error(
                    "Audio capture runtime error; graph will be rebuilt: domain=\(errorDomain, privacy: .public), code=\(errorCode, privacy: .public), description=\(errorDescription, privacy: .private)"
                )
            }
        }
        graph.deviceDisconnectObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification,
            object: nil,
            queue: nil
        ) { [weak self, weak graph] notification in
            guard let self,
                  let graph,
                  let disconnectedDevice = notification.object as? AVCaptureDevice,
                  disconnectedDevice.uniqueID == graph.input.device.uniqueID else {
                return
            }
            let deviceName = disconnectedDevice.localizedName
            let deviceID = disconnectedDevice.uniqueID
            self.captureQueue.async {
                graph.runtimeInvalidated = true
                Self.logger.info(
                    "Audio input disconnected; cached capture graph invalidated: name=\(deviceName, privacy: .private), identifier=\(deviceID, privacy: .private)"
                )
            }
        }
        return graph
    }

    private func discardCaptureGraphOnCaptureQueue(_ graph: CaptureGraph) {
        graph.output.setSampleBufferDelegate(nil, queue: nil)
        if graph.session.isRunning {
            graph.session.stopRunning()
        }
        if let observer = graph.runtimeErrorObserver {
            NotificationCenter.default.removeObserver(observer)
            graph.runtimeErrorObserver = nil
        }
        if let observer = graph.deviceDisconnectObserver {
            NotificationCenter.default.removeObserver(observer)
            graph.deviceDisconnectObserver = nil
        }
        if captureGraph === graph {
            captureGraph = nil
        }
    }

    private func waitForInputReadiness(timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            try Task.checkCancellation()
            let didCommit = captureQueue.sync {
                guard var readinessBuffer,
                      let committedSamples = readinessBuffer.commitInitialReadinessIfReady() else {
                    return false
                }
                self.readinessBuffer = readinessBuffer
                appendOutputSamples(committedSamples)
                logReadinessCompletion(
                    kind: "initial",
                    readinessBuffer: readinessBuffer
                )
                return true
            }
            if didCommit {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        let summary = captureQueue.sync {
            guard let readinessBuffer else {
                return ("unavailable", 0, 0, 0)
            }
            return (
                String(describing: readinessBuffer.phase),
                readinessBuffer.pendingSamples.count,
                readinessBuffer.discardedDigitalSilenceFrameCount,
                readinessBuffer.discardedCandidateFrameCount
            )
        }
        let zeroDuration = Double(summary.2) / Double(Self.outputSampleRate)
        Self.logger.error(
            "Audio readiness timed out: phase=\(summary.0, privacy: .public), pendingFrames=\(summary.1, privacy: .public), discardedZeroFrames=\(summary.2, privacy: .public), discardedZeroDuration=\(zeroDuration, privacy: .public), discardedCandidateFrames=\(summary.3, privacy: .public)"
        )
        throw AudioRecorderError.inputDidNotBecomeReady
    }

    private func logReadinessCompletion(
        kind: String,
        readinessBuffer: AudioCaptureReadinessBuffer
    ) {
        let latency = readinessWarmupStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        let discardedZeroFrames = max(
            0,
            readinessBuffer.discardedDigitalSilenceFrameCount - readinessZeroFrameBaseline
        )
        let discardedZeroDuration = Double(discardedZeroFrames) / Double(Self.outputSampleRate)
        Self.logger.info(
            "Audio readiness committed: kind=\(kind, privacy: .public), latency=\(latency, privacy: .public), discardedZeroFrames=\(discardedZeroFrames, privacy: .public), discardedZeroDuration=\(discardedZeroDuration, privacy: .public)"
        )
        readinessWarmupStartedAt = nil
        readinessZeroFrameBaseline = readinessBuffer.discardedDigitalSilenceFrameCount
    }

    private func trackPresentationTimestamp(of sampleBuffer: CMSampleBuffer) {
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard presentationTime.isValid,
              presentationTime.isNumeric else {
            return
        }

        if let expectedNextPresentationTime,
           expectedNextPresentationTime.isValid,
           expectedNextPresentationTime.isNumeric {
            let gap = CMTimeGetSeconds(presentationTime - expectedNextPresentationTime)
            if gap.isFinite, abs(gap) > 0.05 {
                timestampGapCount += 1
                maximumTimestampGap = max(maximumTimestampGap, abs(gap))
                Self.logger.info(
                    "Audio timestamp discontinuity: \(gap, privacy: .public) seconds"
                )
            }
        }

        let duration = CMSampleBufferGetDuration(sampleBuffer)
        if duration.isValid, duration.isNumeric {
            expectedNextPresentationTime = presentationTime + duration
        } else if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
                  let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription),
                  streamDescription.pointee.mSampleRate > 0 {
            let frameDuration = Double(CMSampleBufferGetNumSamples(sampleBuffer))
                / streamDescription.pointee.mSampleRate
            expectedNextPresentationTime = presentationTime + CMTime(
                seconds: frameDuration,
                preferredTimescale: 1_000_000_000
            )
        }
    }

    static func writeWAV(samples: [Float], sampleRate: Int, to url: URL) throws {
        guard !samples.isEmpty else {
            throw AudioRecorderError.failedToStart
        }

        let bytesPerSample = 2
        let channels = 1
        let bitsPerSample = 16
        let byteRate = sampleRate * channels * bytesPerSample
        let blockAlign = channels * bytesPerSample

        var pcmData = Data(capacity: samples.count * bytesPerSample)
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            var value = Int16(clamped * Float(Int16.max)).littleEndian
            withUnsafeBytes(of: &value) { buffer in
                pcmData.append(contentsOf: buffer)
            }
        }

        var wavData = Data()
        wavData.appendASCII("RIFF")
        wavData.appendLittleEndianUInt32(UInt32(36 + pcmData.count))
        wavData.appendASCII("WAVE")
        wavData.appendASCII("fmt ")
        wavData.appendLittleEndianUInt32(16)
        wavData.appendLittleEndianUInt16(1)
        wavData.appendLittleEndianUInt16(UInt16(channels))
        wavData.appendLittleEndianUInt32(UInt32(sampleRate))
        wavData.appendLittleEndianUInt32(UInt32(byteRate))
        wavData.appendLittleEndianUInt16(UInt16(blockAlign))
        wavData.appendLittleEndianUInt16(UInt16(bitsPerSample))
        wavData.appendASCII("data")
        wavData.appendLittleEndianUInt32(UInt32(pcmData.count))
        wavData.append(pcmData)

        try wavData.write(to: url, options: .atomic)
    }

    private static func isReadableAudioFile(_ url: URL) -> Bool {
        guard let fileSize = try? FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? NSNumber,
              fileSize.intValue > 44 else {
            return false
        }

        return (try? AVAudioFile(forReading: url)) != nil
    }

    static func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            break
        @unknown default:
            return false
        }

        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(string.data(using: .ascii) ?? Data())
    }

    mutating func appendLittleEndianUInt16(_ value: UInt16) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { buffer in
            append(contentsOf: buffer)
        }
    }

    mutating func appendLittleEndianUInt32(_ value: UInt32) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { buffer in
            append(contentsOf: buffer)
        }
    }
}
