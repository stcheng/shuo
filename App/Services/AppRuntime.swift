import AppKit
import Foundation

struct AppBuildIdentityMetadata: Equatable {
    let bundleIdentifier: String
    let displayName: String
    let storageDirectoryName: String
    let credentialServicePrefix: String
    let distributionChannel: String

    var isCommunityBuild: Bool {
        distributionChannel == "community"
    }

    func credentialService(_ suffix: String) -> String {
        "\(credentialServicePrefix).\(suffix)"
    }
}

enum AppBuildIdentity {
    static let officialBundleIdentifier = "dev.shuotian.Shuo"
    static let communityBundleIdentifier = "org.shuo.community"
    static let communityStorageDirectoryName = "Shuo Community"

    static var current: AppBuildIdentityMetadata {
        resolve(
            bundleIdentifier: Bundle.main.bundleIdentifier,
            infoDictionary: Bundle.main.infoDictionary ?? [:]
        )
    }

    static var bundleIdentifier: String { current.bundleIdentifier }
    static var displayName: String { current.displayName }
    static var storageDirectoryName: String { current.storageDirectoryName }
    static var isCommunityBuild: Bool { current.isCommunityBuild }

    static func credentialService(_ suffix: String) -> String {
        current.credentialService(suffix)
    }

    static func resolve(
        bundleIdentifier: String?,
        infoDictionary: [String: Any]
    ) -> AppBuildIdentityMetadata {
        let resolvedBundleIdentifier = normalized(bundleIdentifier)
            ?? officialBundleIdentifier
        let distributionChannel = normalized(
            infoDictionary["ShuoDistributionChannel"] as? String
        ) ?? (resolvedBundleIdentifier == communityBundleIdentifier ? "community" : "official")
        let isCommunityBuild = distributionChannel == "community"

        return AppBuildIdentityMetadata(
            bundleIdentifier: resolvedBundleIdentifier,
            displayName: normalized(infoDictionary["CFBundleName"] as? String)
                ?? (isCommunityBuild ? "Shuo Community" : "Shuo"),
            storageDirectoryName: normalized(
                infoDictionary["ShuoStorageDirectoryName"] as? String
            ) ?? (isCommunityBuild ? communityStorageDirectoryName : "Shuo"),
            credentialServicePrefix: normalized(
                infoDictionary["ShuoCredentialServicePrefix"] as? String
            ) ?? resolvedBundleIdentifier,
            distributionChannel: distributionChannel
        )
    }

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

enum AppRuntime {
    static var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    static var isCommunityBuild: Bool {
        AppBuildIdentity.isCommunityBuild
    }
}

@MainActor
enum AppDockIconController {
    static func apply(showDockIcon: Bool) {
        guard !AppRuntime.isRunningUnderXCTest else {
            return
        }
        guard let app = NSApp else {
            return
        }

        let desiredPolicy: NSApplication.ActivationPolicy = showDockIcon
            ? .regular
            : .accessory
        guard app.activationPolicy() != desiredPolicy else {
            return
        }

        app.setActivationPolicy(desiredPolicy)
    }
}

enum AppStoragePaths {
    static func applicationSupportDirectory(fileManager: FileManager = .default) -> URL {
        if let directory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            return directory.appendingPathComponent(
                AppBuildIdentity.storageDirectoryName,
                isDirectory: true
            )
        }

        // Durable user data must never silently fall back to a temporary
        // directory. This path is equivalent to the normal macOS result and
        // remains stable if the directory lookup is temporarily unavailable.
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(AppBuildIdentity.storageDirectoryName, isDirectory: true)
    }
}

extension FileManager {
    func shuoUpdateBackup(from primaryURL: URL, to backupURL: URL) throws {
        let stagedURL = backupURL.deletingLastPathComponent().appendingPathComponent(
            ".\(backupURL.lastPathComponent).staged-\(UUID().uuidString)"
        )
        try copyItem(at: primaryURL, to: stagedURL)
        defer { try? removeItem(at: stagedURL) }

        if fileExists(atPath: backupURL.path) {
            _ = try replaceItemAt(backupURL, withItemAt: stagedURL)
        } else {
            try moveItem(at: stagedURL, to: backupURL)
        }
    }
}
