import Foundation

extension AppSettings {
    static var defaultLocalWhisperModelDirectoryPath: String {
        AppStoragePaths.applicationSupportDirectory()
            .appendingPathComponent("Models", isDirectory: true)
            .path
    }
}
