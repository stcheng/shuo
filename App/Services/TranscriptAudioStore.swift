import Foundation

struct UnreferencedTranscriptRecording: Equatable {
    let fileName: String
    let createdAt: Date
}

struct TranscriptAudioStore {
    private let fileManager: FileManager
    private let baseDirectory: URL?
    private let removeItem: (URL) throws -> Void

    init(
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil,
        removeItem: ((URL) throws -> Void)? = nil
    ) {
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory
        self.removeItem = removeItem ?? { url in
            try fileManager.removeItem(at: url)
        }
    }

    func storeRecording(at temporaryURL: URL, for transcriptID: UUID) throws -> String {
        let fileExtension = temporaryURL.pathExtension.isEmpty ? "wav" : temporaryURL.pathExtension
        let fileName = "\(transcriptID.uuidString).\(fileExtension)"
        let destinationURL = try audioDirectory()
            .appendingPathComponent(fileName, isDirectory: false)

        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        do {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        } catch {
            try fileManager.copyItem(at: temporaryURL, to: destinationURL)
            try? fileManager.removeItem(at: temporaryURL)
        }

        return fileName
    }

    func url(for item: TranscriptItem) -> URL? {
        guard let audioFileName = item.audioFileName else {
            return nil
        }

        return url(forFileName: audioFileName)
    }

    func url(forFileName audioFileName: String) -> URL? {
        guard isSafeAudioFileName(audioFileName),
              let directory = try? audioDirectory() else {
            return nil
        }

        return directory.appendingPathComponent(audioFileName, isDirectory: false)
    }

    func audioExists(for item: TranscriptItem) -> Bool {
        guard let url = url(for: item) else {
            return false
        }

        return fileManager.fileExists(atPath: url.path)
    }

    func deleteAudio(for item: TranscriptItem) throws {
        guard let audioFileName = item.audioFileName else {
            return
        }

        try deleteAudio(forFileName: audioFileName)
    }

    func deleteAudio(forFileName audioFileName: String) throws {
        guard let url = url(forFileName: audioFileName) else {
            throw TranscriptAudioStoreError.invalidAudioFileName(audioFileName)
        }

        do {
            try removeItem(url)
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain,
               nsError.code == NSFileNoSuchFileError {
                return
            }
            throw TranscriptAudioStoreError.deletionFailed(
                fileName: audioFileName,
                detail: error.localizedDescription
            )
        }

        guard !fileManager.fileExists(atPath: url.path) else {
            throw TranscriptAudioStoreError.deletionFailed(
                fileName: audioFileName,
                detail: "the file still exists after deletion"
            )
        }
    }

    func deleteAudio(for items: [TranscriptItem]) throws {
        for item in items {
            try deleteAudio(for: item)
        }
    }

    func unreferencedRecordings(
        referencedFileNames: Set<String>
    ) throws -> [UnreferencedTranscriptRecording] {
        let directory = try audioDirectory()
        guard fileManager.fileExists(atPath: directory.path) else {
            return []
        }

        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .creationDateKey,
            .contentModificationDateKey
        ]
        return try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )
        .compactMap { url -> UnreferencedTranscriptRecording? in
            let fileName = url.lastPathComponent
            guard isSafeAudioFileName(fileName),
                  !referencedFileNames.contains(fileName),
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true else {
                return nil
            }
            return UnreferencedTranscriptRecording(
                fileName: fileName,
                createdAt: values.creationDate
                    ?? values.contentModificationDate
                    ?? Date()
            )
        }
        .sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.fileName < rhs.fileName
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func audioDirectory() throws -> URL {
        if let baseDirectory {
            return baseDirectory
                .appendingPathComponent("Recordings", isDirectory: true)
        }

        return AppStoragePaths.applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("Recordings", isDirectory: true)
    }

    private func isSafeAudioFileName(_ fileName: String) -> Bool {
        !fileName.isEmpty
            && fileName == URL(fileURLWithPath: fileName).lastPathComponent
    }
}

enum TranscriptAudioStoreError: LocalizedError {
    case missingApplicationSupportDirectory
    case invalidAudioFileName(String)
    case deletionFailed(fileName: String, detail: String)

    var errorDescription: String? {
        switch self {
        case .missingApplicationSupportDirectory:
            return "Application Support directory is unavailable."
        case .invalidAudioFileName(let fileName):
            return "The recording filename is unsafe and was not deleted: \(fileName)"
        case .deletionFailed(let fileName, let detail):
            return "The recording could not be deleted (\(fileName)): \(detail)"
        }
    }
}
