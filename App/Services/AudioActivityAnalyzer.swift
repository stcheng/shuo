import AVFoundation
import Foundation
import OSLog

struct AudioActivityAnalysis {
    let duration: TimeInterval
    let activeDuration: TimeInterval
    let rmsDBFS: Double
    let peakDBFS: Double
    let noiseFloorDBFS: Double
    let speechLevelDBFS: Double
    let speechThresholdDBFS: Double

    func containsSpeech(settings: AppSettings) -> Bool {
        guard duration >= settings.minimumRecordingDuration else {
            return false
        }

        // Use an adaptive activity window so quiet speech is not compared to
        // the same absolute level as ordinary speech. It still needs to be
        // meaningfully above the recording's low-level noise: a quiet but
        // otherwise steady microphone floor can make every adaptive chunk
        // appear active.
        let quietSpeechFloorDBFS = min(
            -45,
            max(-60, settings.silenceThresholdDBFS - 8)
        )
        guard speechLevelDBFS >= quietSpeechFloorDBFS else {
            return false
        }

        // A single click, keyboard tap, or microphone transient can have a
        // high peak without containing speech. Require sustained activity so
        // those sounds cannot trigger a transcription request.
        return activeDuration >= settings.minimumSpeechDuration
    }
}

struct AudioActivityAnalyzer {
    private static let logger = Logger(
        subsystem: AppBuildIdentity.bundleIdentifier,
        category: "AudioCapture"
    )

    func analyze(
        _ url: URL,
        silenceThresholdDBFS: Double,
        adaptsToNoiseFloor: Bool = false
    ) throws -> AudioActivityAnalysis {
        let audioFile = try AVAudioFile(
            forReading: url,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let format = audioFile.processingFormat
        let sampleRate = format.sampleRate
        let channelCount = max(1, Int(format.channelCount))
        let chunkFrames = AVAudioFrameCount(max(256, Int(sampleRate * 0.02)))

        var totalFrames: Int64 = 0
        var totalSquaredAmplitude = 0.0
        var peakAmplitude = 0.0
        var chunks = [(levelDBFS: Double, frameCount: Int64)]()

        while audioFile.framePosition < audioFile.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
                break
            }

            try audioFile.read(into: buffer, frameCount: chunkFrames)
            let frameLength = Int(buffer.frameLength)

            guard frameLength > 0,
                  let channelData = buffer.floatChannelData else {
                break
            }

            var chunkSquaredAmplitude = 0.0

            for frame in 0..<frameLength {
                var sampleAmplitude = 0.0

                for channel in 0..<channelCount {
                    let channelAmplitude = Double(abs(channelData[channel][frame]))
                    sampleAmplitude = max(sampleAmplitude, channelAmplitude)
                }

                let squaredAmplitude = sampleAmplitude * sampleAmplitude
                totalSquaredAmplitude += squaredAmplitude
                chunkSquaredAmplitude += squaredAmplitude
                peakAmplitude = max(peakAmplitude, sampleAmplitude)
            }

            let chunkRMS = sqrt(chunkSquaredAmplitude / Double(frameLength))
            chunks.append((
                levelDBFS: Self.dbFS(fromAmplitude: chunkRMS),
                frameCount: Int64(frameLength)
            ))
            totalFrames += Int64(frameLength)
        }

        guard totalFrames > 0 else {
            Self.logger.error("Audio activity analysis found no frames")
            return AudioActivityAnalysis(
                duration: 0,
                activeDuration: 0,
                rmsDBFS: -.infinity,
                peakDBFS: -.infinity,
                noiseFloorDBFS: -.infinity,
                speechLevelDBFS: -.infinity,
                speechThresholdDBFS: silenceThresholdDBFS
            )
        }

        let levels = chunks.map(\.levelDBFS).sorted()
        let noiseFloorDBFS = Self.percentile(levels, fraction: 0.2)
        let speechLevelDBFS = Self.percentile(levels, fraction: 0.85)
        let speechThresholdDBFS = adaptsToNoiseFloor
            ? Self.adaptiveSpeechThresholdDBFS(
                noiseFloorDBFS: noiseFloorDBFS,
                speechLevelDBFS: speechLevelDBFS
            )
            : silenceThresholdDBFS
        let activeFrames = chunks.reduce(into: Int64(0)) { result, chunk in
            if chunk.levelDBFS >= speechThresholdDBFS {
                result += chunk.frameCount
            }
        }
        let rms = sqrt(totalSquaredAmplitude / Double(totalFrames))

        let analysis = AudioActivityAnalysis(
            duration: Double(totalFrames) / sampleRate,
            activeDuration: Double(activeFrames) / sampleRate,
            rmsDBFS: Self.dbFS(fromAmplitude: rms),
            peakDBFS: Self.dbFS(fromAmplitude: peakAmplitude),
            noiseFloorDBFS: noiseFloorDBFS,
            speechLevelDBFS: speechLevelDBFS,
            speechThresholdDBFS: speechThresholdDBFS
        )
        Self.logger.info(
            "Audio activity analyzed: duration=\(analysis.duration, privacy: .public), activeDuration=\(analysis.activeDuration, privacy: .public), rmsDBFS=\(analysis.rmsDBFS, privacy: .public), peakDBFS=\(analysis.peakDBFS, privacy: .public), noiseFloorDBFS=\(analysis.noiseFloorDBFS, privacy: .public), speechLevelDBFS=\(analysis.speechLevelDBFS, privacy: .public), speechThresholdDBFS=\(analysis.speechThresholdDBFS, privacy: .public)"
        )
        return analysis
    }

    static func adaptiveSpeechThresholdDBFS(
        noiseFloorDBFS: Double,
        speechLevelDBFS: Double
    ) -> Double {
        guard noiseFloorDBFS.isFinite, speechLevelDBFS.isFinite else {
            return -60
        }

        let dynamicRange = max(0, speechLevelDBFS - noiseFloorDBFS)
        let noiseMargin = min(9, max(3, dynamicRange * 0.45))
        let threshold = min(noiseFloorDBFS + noiseMargin, speechLevelDBFS - 3)
        return min(-30, max(-65, threshold))
    }

    private static func percentile(_ sortedValues: [Double], fraction: Double) -> Double {
        guard !sortedValues.isEmpty else {
            return -.infinity
        }

        let boundedFraction = min(1, max(0, fraction))
        let position = Double(sortedValues.count - 1) * boundedFraction
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = Int(position.rounded(.up))
        guard lowerIndex != upperIndex else {
            return sortedValues[lowerIndex]
        }

        let upperWeight = position - Double(lowerIndex)
        return sortedValues[lowerIndex] * (1 - upperWeight)
            + sortedValues[upperIndex] * upperWeight
    }

    private static func dbFS(fromAmplitude amplitude: Double) -> Double {
        guard amplitude > 0 else {
            return -120
        }
        return max(-120, 20 * log10(amplitude))
    }
}

struct WhisperAudioNormalizer {
    private static let targetSpeechLevelDBFS = -22.0
    private static let peakCeilingDBFS = -1.0
    private static let maximumGainDB = 18.0
    private static let minimumUsefulGainDB = 1.0

    func normalizedCopy(
        of sourceURL: URL,
        analysis: AudioActivityAnalysis
    ) throws -> URL? {
        let gainDB = Self.recommendedGainDB(
            speechLevelDBFS: analysis.speechLevelDBFS,
            peakDBFS: analysis.peakDBFS
        )
        guard gainDB >= Self.minimumUsefulGainDB else {
            return nil
        }

        let audioFile = try AVAudioFile(
            forReading: sourceURL,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let format = audioFile.processingFormat
        let channelCount = max(1, Int(format.channelCount))
        let chunkFrames: AVAudioFrameCount = 16_384
        let gain = Float(pow(10, gainDB / 20))
        var samples = [Float]()

        while audioFile.framePosition < audioFile.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
                break
            }
            try audioFile.read(into: buffer, frameCount: chunkFrames)

            guard buffer.frameLength > 0,
                  let channelData = buffer.floatChannelData else {
                break
            }

            for frame in 0..<Int(buffer.frameLength) {
                var strongestSample: Float = 0
                for channel in 0..<channelCount {
                    let sample = channelData[channel][frame]
                    if abs(sample) > abs(strongestSample) {
                        strongestSample = sample
                    }
                }
                samples.append(strongestSample * gain)
            }
        }

        guard !samples.isEmpty else {
            return nil
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("shuo-whisper-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        do {
            try AudioRecorder.writeWAV(
                samples: samples,
                sampleRate: max(1, Int(format.sampleRate.rounded())),
                to: outputURL
            )
            return outputURL
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    static func recommendedGainDB(
        speechLevelDBFS: Double,
        peakDBFS: Double
    ) -> Double {
        guard speechLevelDBFS.isFinite, peakDBFS.isFinite else {
            return 0
        }

        let gainForSpeech = targetSpeechLevelDBFS - speechLevelDBFS
        let peakHeadroom = peakCeilingDBFS - peakDBFS
        return max(0, min(maximumGainDB, gainForSpeech, peakHeadroom))
    }
}
