import AVFoundation
import Foundation

@MainActor
final class RecordingCuePlayer {
    private var players: [RecordingCueSound: AVAudioPlayer] = [:]

    init() {
        RecordingCueSound.allCases.forEach { sound in
            players[sound] = try? makePlayer(for: sound)
        }
    }

    func play(
        _ sound: RecordingCueSound,
        volumeScale: Float = 1,
        outputDeviceID: String? = nil
    ) throws {
        let player = try preparedPlayer(for: sound)
        player.stop()
        player.currentTime = 0
        player.volume = sound.volume * max(0, min(1, volumeScale))
        player.currentDevice = outputDeviceID
        player.prepareToPlay()

        if player.play() {
            return
        }

        guard outputDeviceID != nil else {
            throw RecordingCuePlayerError.failedToPlay
        }

        player.stop()
        player.currentTime = 0
        player.currentDevice = nil
        player.prepareToPlay()

        guard player.play() else {
            throw RecordingCuePlayerError.failedToPlay
        }
    }

    private func preparedPlayer(for sound: RecordingCueSound) throws -> AVAudioPlayer {
        if let player = players[sound] {
            return player
        }

        let player = try makePlayer(for: sound)
        players[sound] = player
        return player
    }

    private func makePlayer(for sound: RecordingCueSound) throws -> AVAudioPlayer {
        let player = try AVAudioPlayer(data: Self.makeCueWAVData(for: sound))
        player.volume = sound.volume
        player.prepareToPlay()
        return player
    }

    private static func makeCueWAVData(for sound: RecordingCueSound) -> Data {
        let sampleRate = 44_100
        let sampleCount = Int(Double(sampleRate) * sound.duration)
        let bytesPerSample = 2
        let channels = 1
        let bitsPerSample = 16
        let byteRate = sampleRate * channels * bytesPerSample
        let blockAlign = channels * bytesPerSample

        var samples = Data(capacity: sampleCount * bytesPerSample)

        for index in 0..<sampleCount {
            let time = Double(index) / Double(sampleRate)
            let mixedTone = sound.tones.reduce(0.0) { partialResult, tone in
                partialResult + tone.sample(at: time)
            }
            // A gentle soft clip keeps overlapping partials rounded instead of
            // producing the brittle edge of hard sample clipping.
            let normalized = tanh(mixedTone)
            var sample = Int16(normalized * Double(Int16.max)).littleEndian

            withUnsafeBytes(of: &sample) { buffer in
                samples.append(contentsOf: buffer)
            }
        }

        var data = Data()
        data.appendASCII("RIFF")
        data.appendLittleEndianUInt32(UInt32(36 + samples.count))
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendLittleEndianUInt32(16)
        data.appendLittleEndianUInt16(1)
        data.appendLittleEndianUInt16(UInt16(channels))
        data.appendLittleEndianUInt32(UInt32(sampleRate))
        data.appendLittleEndianUInt32(UInt32(byteRate))
        data.appendLittleEndianUInt16(UInt16(blockAlign))
        data.appendLittleEndianUInt16(UInt16(bitsPerSample))
        data.appendASCII("data")
        data.appendLittleEndianUInt32(UInt32(samples.count))
        data.append(samples)

        return data
    }
}

enum RecordingCuePlayerError: LocalizedError {
    case failedToPlay

    var errorDescription: String? {
        switch self {
        case .failedToPlay:
            return "Recording start cue could not be played."
        }
    }
}

private struct RecordingCueTone {
    let start: Double
    let duration: Double
    let partials: [RecordingCuePartial]
    let amplitude: Double
    let attack: Double
    let decayPower: Double

    func sample(at time: Double) -> Double {
        let elapsed = time - start
        guard elapsed >= 0, elapsed <= duration else {
            return 0
        }

        let progress = min(1, max(0, elapsed / duration))
        let attackProgress = min(1, elapsed / max(0.001, attack))
        let easedAttack = attackProgress * attackProgress * (3 - 2 * attackProgress)
        let naturalDecay = pow(max(0, 1 - progress), decayPower)
        let envelope = easedAttack * naturalDecay
        let partialWeightSum = max(1.0, partials.reduce(0.0) { $0 + $1.weight })
        let tone = partials.reduce(0.0) { partialResult, partial in
            partialResult + partial.sample(at: elapsed, duration: duration)
        } / partialWeightSum

        return tone * amplitude * envelope
    }
}

private struct RecordingCuePartial {
    let frequency: Double
    let weight: Double
    let phase: Double
    let endFrequencyMultiplier: Double

    init(
        _ frequency: Double,
        weight: Double,
        phase: Double = 0,
        endFrequencyMultiplier: Double = 1
    ) {
        self.frequency = frequency
        self.weight = weight
        self.phase = phase
        self.endFrequencyMultiplier = endFrequencyMultiplier
    }

    func sample(at elapsed: Double, duration: Double) -> Double {
        let frequencyDelta = frequency * (endFrequencyMultiplier - 1)
        // Integrating the linear frequency sweep keeps the waveform continuous.
        let cycles = frequency * elapsed
            + 0.5 * frequencyDelta * elapsed * elapsed / max(0.001, duration)
        return sin(2 * Double.pi * cycles + phase) * weight
    }
}

enum RecordingCuePlaybackLevel {
    static func scale(whisperModeEnabled: Bool) -> Float {
        // Whisper Mode may be used in very quiet rooms and its input
        // normalization can also pick up a cue played through speakers.
        whisperModeEnabled ? 0.18 : 1
    }
}

private extension RecordingCueSound {
    var duration: Double {
        switch self {
        case .softPing:
            return 0.21
        case .doubleTap:
            return 0.27
        case .brightChime:
            return 0.29
        case .lowPop:
            return 0.18
        case .deepDrop:
            return 0.22
        case .woodKnock:
            return 0.17
        case .softPulse:
            return 0.26
        case .lowOrbit:
            return 0.24
        case .subBeacon:
            return 0.25
        case .darkPulse:
            return 0.20
        }
    }

    var volume: Float {
        switch self {
        case .softPing:
            return 0.48
        case .doubleTap:
            return 0.50
        case .brightChime:
            return 0.46
        case .lowPop:
            return 0.52
        case .deepDrop:
            return 0.54
        case .woodKnock:
            return 0.55
        case .softPulse:
            return 0.50
        case .lowOrbit:
            return 0.50
        case .subBeacon:
            return 0.49
        case .darkPulse:
            return 0.52
        }
    }

    var tones: [RecordingCueTone] {
        switch self {
        case .softPing:
            return [
                RecordingCueTone(
                    start: 0.008,
                    duration: 0.18,
                    partials: [
                        RecordingCuePartial(
                            523.25,
                            weight: 0.68,
                            endFrequencyMultiplier: 0.985
                        ),
                        RecordingCuePartial(
                            1_049,
                            weight: 0.18,
                            phase: 0.32,
                            endFrequencyMultiplier: 0.992
                        ),
                        RecordingCuePartial(1_572, weight: 0.09, phase: 0.75),
                        RecordingCuePartial(2_115, weight: 0.05, phase: 1.1)
                    ],
                    amplitude: 0.25,
                    attack: 0.008,
                    decayPower: 1.65
                ),
                RecordingCueTone(
                    start: 0.052,
                    duration: 0.11,
                    partials: [
                        RecordingCuePartial(783.99, weight: 0.80, phase: 0.15),
                        RecordingCuePartial(1_569, weight: 0.20, phase: 0.65)
                    ],
                    amplitude: 0.045,
                    attack: 0.012,
                    decayPower: 1.9
                )
            ]
        case .doubleTap:
            return [
                RecordingCueTone(
                    start: 0.008,
                    duration: 0.09,
                    partials: [
                        RecordingCuePartial(
                            415.30,
                            weight: 0.70,
                            endFrequencyMultiplier: 0.975
                        ),
                        RecordingCuePartial(833, weight: 0.19, phase: 0.42),
                        RecordingCuePartial(1_240, weight: 0.08, phase: 0.82),
                        RecordingCuePartial(1_669, weight: 0.03, phase: 1.15)
                    ],
                    amplitude: 0.27,
                    attack: 0.004,
                    decayPower: 2.4
                ),
                RecordingCueTone(
                    start: 0.125,
                    duration: 0.11,
                    partials: [
                        RecordingCuePartial(
                            523.25,
                            weight: 0.68,
                            endFrequencyMultiplier: 0.985
                        ),
                        RecordingCuePartial(1_049, weight: 0.20, phase: 0.38),
                        RecordingCuePartial(1_572, weight: 0.09, phase: 0.78),
                        RecordingCuePartial(2_104, weight: 0.03, phase: 1.2)
                    ],
                    amplitude: 0.25,
                    attack: 0.004,
                    decayPower: 2.15
                )
            ]
        case .brightChime:
            return [
                RecordingCueTone(
                    start: 0.008,
                    duration: 0.25,
                    partials: [
                        RecordingCuePartial(523.25, weight: 0.50),
                        RecordingCuePartial(783.99, weight: 0.22, phase: 0.18),
                        RecordingCuePartial(1_049, weight: 0.16, phase: 0.42),
                        RecordingCuePartial(1_578, weight: 0.08, phase: 0.8),
                        RecordingCuePartial(2_110, weight: 0.04, phase: 1.2)
                    ],
                    amplitude: 0.22,
                    attack: 0.012,
                    decayPower: 1.45
                ),
                RecordingCueTone(
                    start: 0.065,
                    duration: 0.16,
                    partials: [
                        RecordingCuePartial(659.25, weight: 0.74, phase: 0.2),
                        RecordingCuePartial(1_326, weight: 0.19, phase: 0.62),
                        RecordingCuePartial(1_982, weight: 0.07, phase: 1.05)
                    ],
                    amplitude: 0.055,
                    attack: 0.014,
                    decayPower: 1.7
                )
            ]
        case .lowPop:
            return [
                RecordingCueTone(
                    start: 0.006,
                    duration: 0.14,
                    partials: [
                        RecordingCuePartial(
                            329.63,
                            weight: 0.74,
                            endFrequencyMultiplier: 0.70
                        ),
                        RecordingCuePartial(
                            659.26,
                            weight: 0.17,
                            phase: 0.34,
                            endFrequencyMultiplier: 0.72
                        ),
                        RecordingCuePartial(
                            995,
                            weight: 0.07,
                            phase: 0.76,
                            endFrequencyMultiplier: 0.75
                        ),
                        RecordingCuePartial(1_320, weight: 0.02, phase: 1.1)
                    ],
                    amplitude: 0.29,
                    attack: 0.003,
                    decayPower: 2.8
                ),
                RecordingCueTone(
                    start: 0.07,
                    duration: 0.075,
                    partials: [
                        RecordingCuePartial(493.88, weight: 0.78, phase: 0.12),
                        RecordingCuePartial(991, weight: 0.22, phase: 0.55)
                    ],
                    amplitude: 0.06,
                    attack: 0.006,
                    decayPower: 2.2
                )
            ]
        case .deepDrop:
            return [
                RecordingCueTone(
                    start: 0.006,
                    duration: 0.19,
                    partials: [
                        RecordingCuePartial(
                            246.94,
                            weight: 0.67,
                            endFrequencyMultiplier: 0.71
                        ),
                        RecordingCuePartial(
                            494.5,
                            weight: 0.20,
                            phase: 0.28,
                            endFrequencyMultiplier: 0.73
                        ),
                        RecordingCuePartial(
                            742,
                            weight: 0.09,
                            phase: 0.68,
                            endFrequencyMultiplier: 0.76
                        ),
                        RecordingCuePartial(996, weight: 0.04, phase: 1.05)
                    ],
                    amplitude: 0.32,
                    attack: 0.005,
                    decayPower: 2.15
                )
            ]
        case .woodKnock:
            return [
                RecordingCueTone(
                    start: 0.006,
                    duration: 0.11,
                    partials: [
                        RecordingCuePartial(
                            196,
                            weight: 0.56,
                            endFrequencyMultiplier: 0.92
                        ),
                        RecordingCuePartial(397, weight: 0.24, phase: 0.3),
                        RecordingCuePartial(604, weight: 0.13, phase: 0.72),
                        RecordingCuePartial(826, weight: 0.07, phase: 1.1)
                    ],
                    amplitude: 0.36,
                    attack: 0.002,
                    decayPower: 3.6
                ),
                RecordingCueTone(
                    start: 0.026,
                    duration: 0.105,
                    partials: [
                        RecordingCuePartial(293.66, weight: 0.72, phase: 0.2),
                        RecordingCuePartial(591, weight: 0.20, phase: 0.6),
                        RecordingCuePartial(887, weight: 0.08, phase: 1.0)
                    ],
                    amplitude: 0.075,
                    attack: 0.004,
                    decayPower: 2.7
                )
            ]
        case .softPulse:
            return [
                RecordingCueTone(
                    start: 0.006,
                    duration: 0.105,
                    partials: [
                        RecordingCuePartial(
                            261.63,
                            weight: 0.69,
                            endFrequencyMultiplier: 0.84
                        ),
                        RecordingCuePartial(525, weight: 0.20, phase: 0.34),
                        RecordingCuePartial(790, weight: 0.08, phase: 0.75),
                        RecordingCuePartial(1_052, weight: 0.03, phase: 1.1)
                    ],
                    amplitude: 0.29,
                    attack: 0.004,
                    decayPower: 2.7
                ),
                RecordingCueTone(
                    start: 0.115,
                    duration: 0.105,
                    partials: [
                        RecordingCuePartial(
                            329.63,
                            weight: 0.68,
                            endFrequencyMultiplier: 0.96
                        ),
                        RecordingCuePartial(661, weight: 0.20, phase: 0.3),
                        RecordingCuePartial(990, weight: 0.09, phase: 0.72),
                        RecordingCuePartial(1_326, weight: 0.03, phase: 1.08)
                    ],
                    amplitude: 0.245,
                    attack: 0.005,
                    decayPower: 2.45
                )
            ]
        case .lowOrbit:
            return [
                RecordingCueTone(
                    start: 0.006,
                    duration: 0.205,
                    partials: [
                        RecordingCuePartial(
                            220,
                            weight: 0.58,
                            endFrequencyMultiplier: 1.12
                        ),
                        RecordingCuePartial(
                            440,
                            weight: 0.21,
                            phase: 0.26,
                            endFrequencyMultiplier: 1.10
                        ),
                        RecordingCuePartial(662, weight: 0.12, phase: 0.62),
                        RecordingCuePartial(893, weight: 0.06, phase: 0.98),
                        RecordingCuePartial(1_108, weight: 0.03, phase: 1.25)
                    ],
                    amplitude: 0.28,
                    attack: 0.006,
                    decayPower: 1.8
                ),
                RecordingCueTone(
                    start: 0.07,
                    duration: 0.12,
                    partials: [
                        RecordingCuePartial(329.63, weight: 0.70, phase: 0.15),
                        RecordingCuePartial(664, weight: 0.21, phase: 0.52),
                        RecordingCuePartial(1_002, weight: 0.09, phase: 0.9)
                    ],
                    amplitude: 0.045,
                    attack: 0.012,
                    decayPower: 1.75
                )
            ]
        case .subBeacon:
            return [
                RecordingCueTone(
                    start: 0.006,
                    duration: 0.085,
                    partials: [
                        RecordingCuePartial(
                            329.63,
                            weight: 0.64,
                            endFrequencyMultiplier: 0.96
                        ),
                        RecordingCuePartial(662, weight: 0.22, phase: 0.3),
                        RecordingCuePartial(998, weight: 0.10, phase: 0.7),
                        RecordingCuePartial(1_341, weight: 0.04, phase: 1.08)
                    ],
                    amplitude: 0.25,
                    attack: 0.004,
                    decayPower: 2.4
                ),
                RecordingCueTone(
                    start: 0.105,
                    duration: 0.11,
                    partials: [
                        RecordingCuePartial(
                            220,
                            weight: 0.62,
                            endFrequencyMultiplier: 0.90
                        ),
                        RecordingCuePartial(
                            443,
                            weight: 0.23,
                            phase: 0.28,
                            endFrequencyMultiplier: 0.92
                        ),
                        RecordingCuePartial(671, weight: 0.10, phase: 0.68),
                        RecordingCuePartial(903, weight: 0.05, phase: 1.02)
                    ],
                    amplitude: 0.28,
                    attack: 0.004,
                    decayPower: 2.35
                )
            ]
        case .darkPulse:
            return [
                RecordingCueTone(
                    start: 0.006,
                    duration: 0.165,
                    partials: [
                        RecordingCuePartial(
                            185,
                            weight: 0.55,
                            endFrequencyMultiplier: 0.78
                        ),
                        RecordingCuePartial(
                            370,
                            weight: 0.23,
                            phase: 0.25,
                            endFrequencyMultiplier: 0.80
                        ),
                        RecordingCuePartial(559, weight: 0.13, phase: 0.62),
                        RecordingCuePartial(752, weight: 0.06, phase: 0.98),
                        RecordingCuePartial(935, weight: 0.03, phase: 1.24)
                    ],
                    amplitude: 0.35,
                    attack: 0.003,
                    decayPower: 2.5
                ),
                RecordingCueTone(
                    start: 0.004,
                    duration: 0.055,
                    partials: [
                        RecordingCuePartial(
                            740,
                            weight: 0.70,
                            phase: 0.2,
                            endFrequencyMultiplier: 0.82
                        ),
                        RecordingCuePartial(
                            1_110,
                            weight: 0.30,
                            phase: 0.75,
                            endFrequencyMultiplier: 0.86
                        )
                    ],
                    amplitude: 0.06,
                    attack: 0.002,
                    decayPower: 3.2
                )
            ]
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
