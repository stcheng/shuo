import Foundation

struct LocalWhisperSetupService {
    func applyManagedModelBackupPolicy(directoryPath: String) throws {
        try LocalWhisperBackupPolicy.applyToInstalledManagedModels(in: directoryPath)
    }

    func detectEngine() -> URL? {
        LocalWhisperExecutableResolver.resolvedExecutableURL(configuredPath: "")
    }

    func installEngine() async throws -> URL {
        try await LocalWhisperAssetInstaller.installEngineWithHomebrew()
    }

    func isModelInstalled(_ model: LocalWhisperManagedModel, directoryPath: String) -> Bool {
        LocalWhisperModelCatalog.isInstalled(model, in: directoryPath)
    }

    func settingsSelectingInstalledModel(
        _ model: LocalWhisperManagedModel,
        currentSettings: AppSettings
    ) -> AppSettings? {
        let modelURL = model.destinationURL(in: currentSettings.localWhisperModelDirectoryPath)
        guard model.hasExpectedFileSize(at: modelURL) else {
            return nil
        }

        return settingsSelectingModel(at: modelURL, currentSettings: currentSettings)
    }

    func downloadModel(
        _ model: LocalWhisperManagedModel,
        directoryPath: String,
        progress: @escaping @Sendable (LocalWhisperDownloadProgress) -> Void = { _ in }
    ) async throws -> URL {
        let modelURL = try await LocalWhisperAssetInstaller.downloadModel(
            model,
            to: directoryPath,
            progress: progress
        )
        LocalWhisperModelCatalog.invalidateCache(for: modelURL.deletingLastPathComponent().path)
        return modelURL
    }

    func settingsSelectingModel(at modelURL: URL, currentSettings: AppSettings) -> AppSettings {
        var updatedSettings = currentSettings
        let standardizedModelURL = modelURL.standardizedFileURL
        updatedSettings.provider = .local
        updatedSettings.localWhisperModelDirectoryPath = standardizedModelURL.deletingLastPathComponent().path
        updatedSettings.localWhisperModelPath = standardizedModelURL.path
        updatedSettings.normalizeSelections()
        return updatedSettings
    }

    func deleteModel(
        _ model: LocalWhisperManagedModel,
        currentSettings: AppSettings
    ) throws -> AppSettings {
        let modelURL = model.destinationURL(in: currentSettings.localWhisperModelDirectoryPath)
        try LocalWhisperAssetInstaller.deleteModel(at: modelURL)
        LocalWhisperModelCatalog.invalidateCache(for: modelURL.deletingLastPathComponent().path)

        var updatedSettings = currentSettings
        let selectedModelPath = updatedSettings.localWhisperModelPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !selectedModelPath.isEmpty,
           URL(fileURLWithPath: selectedModelPath).standardizedFileURL == modelURL.standardizedFileURL {
            let fallbackModels = LocalWhisperModelCatalog.featuredModels
                + LocalWhisperModelCatalog.additionalModels
            if let fallbackModel = fallbackModels.first(where: { candidate in
                candidate.id != model.id
                    && isModelInstalled(
                        candidate,
                        directoryPath: updatedSettings.localWhisperModelDirectoryPath
                    )
            }) {
                updatedSettings = settingsSelectingModel(
                    at: fallbackModel.destinationURL(
                        in: updatedSettings.localWhisperModelDirectoryPath
                    ),
                    currentSettings: updatedSettings
                )
            } else {
                updatedSettings.localWhisperModelPath = ""
            }
        }
        updatedSettings.normalizeSelections()
        return updatedSettings
    }
}
