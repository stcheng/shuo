import AVFoundation
import CoreAudio
import Foundation

struct AudioOutputDeviceOption: Equatable {
    let id: String
    let name: String
    let audioObjectID: AudioDeviceID
}

enum AudioOutputDeviceCatalog {
    static func preferredOutputDeviceUID(matchingInputDeviceID inputDeviceID: String) -> String? {
        preferredOutputDevice(matchingInputDeviceID: inputDeviceID)?.id
    }

    static func preferredOutputDevice(matchingInputDeviceID inputDeviceID: String) -> AudioOutputDeviceOption? {
        guard let inputDevice = AudioInputDeviceCatalog.device(for: inputDeviceID) else {
            return nil
        }

        return preferredOutputDevice(matchingInputDevice: AudioInputDeviceOption(
            id: inputDevice.uniqueID,
            name: inputDevice.localizedName
        ))
    }

    static func preferredOutputDevice(matchingInputDevice inputDevice: AudioInputDeviceOption) -> AudioOutputDeviceOption? {
        let inputName = inputDevice.name
        guard automaticDeviceScore(inputName) > 0 else {
            return nil
        }

        let normalizedInputName = normalizedDeviceName(inputName)
        guard !normalizedInputName.isEmpty else {
            return nil
        }

        let outputDevices = devices()
            .filter { !isVirtualDeviceName($0.name) }

        return outputDevices
            .sorted { lhs, rhs in
                let lhsScore = outputMatchScore(outputName: lhs.name, normalizedInputName: normalizedInputName)
                let rhsScore = outputMatchScore(outputName: rhs.name, normalizedInputName: normalizedInputName)
                if lhsScore == rhsScore {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhsScore > rhsScore
            }
            .first { outputMatchScore(outputName: $0.name, normalizedInputName: normalizedInputName) > 0 }
    }

    static func devices() -> [AudioOutputDeviceOption] {
        allAudioDeviceIDs()
            .filter(hasOutputChannels)
            .compactMap { audioObjectID in
                guard let name = stringProperty(kAudioObjectPropertyName, for: audioObjectID),
                      let uid = stringProperty(kAudioDevicePropertyDeviceUID, for: audioObjectID) else {
                    return nil
                }

                return AudioOutputDeviceOption(
                    id: uid,
                    name: name,
                    audioObjectID: audioObjectID
                )
            }
    }

    private static func outputMatchScore(outputName: String, normalizedInputName: String) -> Int {
        let normalizedOutputName = normalizedDeviceName(outputName)
        guard !normalizedOutputName.isEmpty,
              automaticDeviceScore(outputName) > 0 else {
            return 0
        }

        if normalizedOutputName == normalizedInputName {
            return 300
        }

        if normalizedOutputName.contains(normalizedInputName)
            || normalizedInputName.contains(normalizedOutputName) {
            return 220
        }

        let inputTokens = tokenSet(from: normalizedInputName)
        let outputTokens = tokenSet(from: normalizedOutputName)
        let sharedTokenCount = inputTokens.intersection(outputTokens).count
        if sharedTokenCount >= 2 {
            return 160 + sharedTokenCount
        }

        return 0
    }

    private static func allAudioDeviceIDs() -> [AudioDeviceID] {
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

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard deviceCount > 0 else {
            return []
        }

        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )

        guard status == noErr else {
            return []
        }

        return deviceIDs
    }

    private static func hasOutputChannels(_ audioObjectID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            audioObjectID,
            &address,
            0,
            nil,
            &dataSize
        ) == noErr, dataSize > 0 else {
            return false
        }

        let bufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer {
            bufferListPointer.deallocate()
        }

        let status = AudioObjectGetPropertyData(
            audioObjectID,
            &address,
            0,
            nil,
            &dataSize,
            bufferListPointer
        )
        guard status == noErr else {
            return false
        }

        let audioBufferList = bufferListPointer.assumingMemoryBound(to: AudioBufferList.self)
        return UnsafeMutableAudioBufferListPointer(audioBufferList).contains { buffer in
            buffer.mNumberChannels > 0
        }
    }

    private static func stringProperty(
        _ selector: AudioObjectPropertySelector,
        for audioObjectID: AudioDeviceID
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>?

        let status = AudioObjectGetPropertyData(
            audioObjectID,
            &address,
            0,
            nil,
            &dataSize,
            &value
        )

        guard status == noErr else {
            return nil
        }

        return value?.takeUnretainedValue() as String?
    }

    private static func tokenSet(from normalizedName: String) -> Set<String> {
        Set(normalizedName.split(separator: " ").map(String.init))
    }

    private static func normalizedDeviceName(_ name: String) -> String {
        var normalizedName = name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()

        [
            "microphone",
            "mic",
            "speakers",
            "speaker",
            "headphones",
            "headphone",
            "input",
            "output",
            "audio",
            "hands-free",
            "handsfree"
        ].forEach {
            normalizedName = normalizedName.replacingOccurrences(of: $0, with: " ")
        }

        let allowedScalars = normalizedName.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }

        return String(allowedScalars)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func automaticDeviceScore(_ name: String) -> Int {
        let normalizedName = name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()

        if isVirtualDeviceName(normalizedName) {
            return -100
        }

        if [
            "airpods",
            "beats",
            "headset",
            "headphone",
            "earbud",
            "earbuds",
            "bose",
            "sony",
            "jabra",
            "plantronics",
            "poly",
            "logitech",
            "anker",
            "soundcore",
            "shokz",
            "aftershokz",
            "wh-",
            "wf-"
        ].contains(where: normalizedName.contains) {
            return 100
        }

        if [
            "usb",
            "rode",
            "shure",
            "blue",
            "yeti",
            "scarlett",
            "focusrite",
            "elgato",
            "apogee",
            "samson"
        ].contains(where: normalizedName.contains) {
            return 80
        }

        return 0
    }

    private static func isVirtualDeviceName(_ name: String) -> Bool {
        let normalizedName = name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()

        return [
            "zoom",
            "blackhole",
            "loopback",
            "soundflower",
            "obs",
            "teams",
            "webex",
            "aggregate",
            "multi-output",
            "virtual"
        ].contains(where: normalizedName.contains)
    }
}
