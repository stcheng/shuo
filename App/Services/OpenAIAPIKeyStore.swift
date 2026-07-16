import Foundation
import OSLog
import Security

private enum CredentialStorageLog {
    static let logger = Logger(
        subsystem: AppBuildIdentity.bundleIdentifier,
        category: "Credentials"
    )
}

enum AppCredentialServices {
    static var openAI: String {
        AppBuildIdentity.credentialService("openai-api-key")
    }

    static var elevenLabs: String {
        AppBuildIdentity.credentialService("elevenlabs-api-key")
    }

    static var alibaba: String {
        AppBuildIdentity.credentialService("alibaba-api-key")
    }

    static var gemini: String {
        AppBuildIdentity.credentialService("gemini-api-key")
    }

    static var all: [String] {
        [openAI, elevenLabs, alibaba, gemini]
    }
}

protocol SecureCredentialStoring {
    func data(service: String, account: String) throws -> Data?
    func set(_ data: Data, service: String, account: String) throws
    func remove(service: String, account: String) throws
    func stabilizeAccess(service: String, account: String) throws
}

extension SecureCredentialStoring {
    func stabilizeAccess(service _: String, account _: String) throws {}
}

struct DevelopmentFileCredentialStore: SecureCredentialStoring {
    private let baseDirectory: URL
    private let fileManager: FileManager

    init(
        baseDirectory: URL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent(AppBuildIdentity.storageDirectoryName, isDirectory: true)
        .appendingPathComponent("Development", isDirectory: true)
        .appendingPathComponent("Credentials", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.baseDirectory = baseDirectory
        self.fileManager = fileManager
    }

    static var activeForCurrentBuild: DevelopmentFileCredentialStore? {
        guard Bundle.main.object(forInfoDictionaryKey: "ShuoDevelopmentBuild") as? Bool == true else {
            return nil
        }
        return DevelopmentFileCredentialStore()
    }

    func data(service: String, account: String) throws -> Data? {
        let url = credentialURL(service: service, account: account)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        try enforcePrivatePermissions()
        return try Data(contentsOf: url)
    }

    func set(_ data: Data, service: String, account: String) throws {
        try ensurePrivateDirectory()
        let url = credentialURL(service: service, account: account)
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: url.path
        )
    }

    func remove(service: String, account: String) throws {
        let url = credentialURL(service: service, account: account)
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.removeItem(at: url)
    }

    func stabilizeAccess(service _: String, account _: String) throws {
        try enforcePrivatePermissions()
    }

    private func ensurePrivateDirectory() throws {
        try fileManager.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
        )
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: baseDirectory.path
        )
    }

    private func enforcePrivatePermissions() throws {
        try ensurePrivateDirectory()
        for service in AppCredentialServices.all {
            let url = credentialURL(service: service, account: "default")
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.setAttributes(
                    [.posixPermissions: NSNumber(value: Int16(0o600))],
                    ofItemAtPath: url.path
                )
            }
        }
    }

    private func credentialURL(service: String, account: String) -> URL {
        let fileName: String
        switch service {
        case AppCredentialServices.openAI:
            fileName = "openai-api-key"
        case AppCredentialServices.elevenLabs:
            fileName = "elevenlabs-api-key"
        case AppCredentialServices.alibaba:
            fileName = "alibaba-api-key"
        case AppCredentialServices.gemini:
            fileName = "gemini-api-key"
        default:
            let safeService = service.map { $0.isLetter || $0.isNumber ? $0 : "_" }
            let safeAccount = account.map { $0.isLetter || $0.isNumber ? $0 : "_" }
            fileName = "\(String(safeService))-\(String(safeAccount))"
        }
        return baseDirectory.appendingPathComponent(fileName, isDirectory: false)
    }
}

struct KeychainCredentialStore: SecureCredentialStoring {
    func data(service: String, account: String) throws -> Data? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainCredentialStoreError(status: status)
        }
    }

    func set(_ data: Data, service: String, account: String) throws {
        let query = baseQuery(service: service, account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw KeychainCredentialStoreError(status: updateStatus)
        }

        var newItem = query
        attributes.forEach { newItem[$0.key] = $0.value }
        newItem[kSecAttrAccess as String] = try callingApplicationAccess(service: service)
        let addStatus = SecItemAdd(newItem as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainCredentialStoreError(status: addStatus)
        }
    }

    func remove(service: String, account: String) throws {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainCredentialStoreError(status: status)
        }
    }

    func stabilizeAccess(service: String, account: String) throws {
        let attributes: [String: Any] = [
            kSecAttrAccess as String: try callingApplicationAccess(service: service)
        ]
        let status = SecItemUpdate(
            baseQuery(service: service, account: account) as CFDictionary,
            attributes as CFDictionary
        )
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainCredentialStoreError(status: status)
        }
    }

    private func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func callingApplicationAccess(service: String) throws -> SecAccess {
        // SecAccess is the legacy macOS Keychain ACL API. We intentionally
        // retain it for existing file-based Keychain items so a release update
        // preserves their established app access instead of reintroducing a
        // Keychain prompt. A future move to the data-protection Keychain needs
        // an explicit, user-safe migration rather than a warning-only swap.
        var access: SecAccess?
        let descriptor: String
        switch service {
        case AppCredentialServices.openAI:
            descriptor = "Shuo OpenAI API Key"
        case AppCredentialServices.elevenLabs:
            descriptor = "Shuo ElevenLabs API Key"
        case AppCredentialServices.alibaba:
            descriptor = "Shuo Alibaba Model Studio API Key"
        case AppCredentialServices.gemini:
            descriptor = "Shuo Gemini API Key"
        default:
            descriptor = "Shuo Secure Credential"
        }
        let status = SecAccessCreate(descriptor as CFString, nil, &access)
        guard status == errSecSuccess, let access else {
            throw KeychainCredentialStoreError(status: status)
        }
        return access
    }
}

struct KeychainCredentialStoreError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        return "The API key could not be saved securely: \(detail)"
    }
}

enum OpenAIAPIKeyStore {
    private static let defaultsKey = "openAIAPIKey"
    private static var service: String { AppCredentialServices.openAI }
    private static let account = "default"
    private static var accessMigrationKey: String {
        scopedAccessMigrationKey("credentialAccess.openAI.version")
    }

    static func load(
        userDefaults: UserDefaults = .standard,
        credentialStore: SecureCredentialStoring = KeychainCredentialStore(),
        developmentCredentialStore: SecureCredentialStoring? = DevelopmentFileCredentialStore
            .activeForCurrentBuild
    ) throws -> String {
        if let developmentCredentialStore {
            if let data = try developmentCredentialStore.data(service: service, account: account),
               let storedKey = String(data: data, encoding: .utf8) {
                CredentialStorageLog.logger.info(
                    "Loaded OpenAI credential from development storage"
                )
                userDefaults.removeObject(forKey: defaultsKey)
                return storedKey
            }

            if let data = try credentialStore.data(service: service, account: account),
               let storedKey = String(data: data, encoding: .utf8) {
                try developmentCredentialStore.set(data, service: service, account: account)
                CredentialStorageLog.logger.notice(
                    "Migrated OpenAI credential from Keychain to development storage"
                )
                userDefaults.removeObject(forKey: defaultsKey)
                return storedKey
            }

            let legacyKey = normalized(userDefaults.string(forKey: defaultsKey) ?? "")
            guard !legacyKey.isEmpty else {
                return ""
            }
            try developmentCredentialStore.set(
                Data(legacyKey.utf8),
                service: service,
                account: account
            )
            CredentialStorageLog.logger.notice(
                "Migrated OpenAI credential from legacy defaults to development storage"
            )
            userDefaults.removeObject(forKey: defaultsKey)
            return legacyKey
        }

        if let data = try credentialStore.data(service: service, account: account),
           let storedKey = String(data: data, encoding: .utf8) {
            CredentialAccessMigration.runIfNeeded(
                service: service,
                account: account,
                defaultsKey: accessMigrationKey,
                userDefaults: userDefaults,
                credentialStore: credentialStore
            )
            userDefaults.removeObject(forKey: defaultsKey)
            return storedKey
        }

        let legacyKey = normalized(userDefaults.string(forKey: defaultsKey) ?? "")
        guard !legacyKey.isEmpty else {
            return ""
        }

        try credentialStore.set(Data(legacyKey.utf8), service: service, account: account)
        CredentialAccessMigration.markComplete(
            defaultsKey: accessMigrationKey,
            userDefaults: userDefaults
        )
        userDefaults.removeObject(forKey: defaultsKey)
        return legacyKey
    }

    static func save(
        _ apiKey: String,
        userDefaults: UserDefaults = .standard,
        credentialStore: SecureCredentialStoring = KeychainCredentialStore(),
        developmentCredentialStore: SecureCredentialStoring? = DevelopmentFileCredentialStore
            .activeForCurrentBuild
    ) throws {
        let trimmed = normalized(apiKey)

        if let developmentCredentialStore {
            if trimmed.isEmpty {
                try developmentCredentialStore.remove(service: service, account: account)
            } else {
                try developmentCredentialStore.set(
                    Data(trimmed.utf8),
                    service: service,
                    account: account
                )
            }
            CredentialStorageLog.logger.info(
                "Updated OpenAI credential in development storage; removed=\(trimmed.isEmpty, privacy: .public)"
            )
            userDefaults.removeObject(forKey: defaultsKey)
            return
        }

        if trimmed.isEmpty {
            try credentialStore.remove(service: service, account: account)
            userDefaults.removeObject(forKey: accessMigrationKey)
        } else {
            try credentialStore.set(Data(trimmed.utf8), service: service, account: account)
        }

        userDefaults.removeObject(forKey: defaultsKey)
    }

    private static func normalized(_ apiKey: String) -> String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ElevenLabsAPIKeyStore {
    private static var service: String { AppCredentialServices.elevenLabs }
    private static let account = "default"
    private static var accessMigrationKey: String {
        scopedAccessMigrationKey("credentialAccess.elevenLabs.version")
    }

    static func load(
        userDefaults: UserDefaults = .standard,
        credentialStore: SecureCredentialStoring = KeychainCredentialStore(),
        developmentCredentialStore: SecureCredentialStoring? = DevelopmentFileCredentialStore
            .activeForCurrentBuild
    ) throws -> String {
        if let developmentCredentialStore {
            if let data = try developmentCredentialStore.data(service: service, account: account),
               let storedKey = String(data: data, encoding: .utf8) {
                CredentialStorageLog.logger.info(
                    "Loaded ElevenLabs credential from development storage"
                )
                return normalized(storedKey)
            }
            guard let data = try credentialStore.data(service: service, account: account),
                  let storedKey = String(data: data, encoding: .utf8) else {
                return ""
            }
            try developmentCredentialStore.set(data, service: service, account: account)
            CredentialStorageLog.logger.notice(
                "Migrated ElevenLabs credential from Keychain to development storage"
            )
            return normalized(storedKey)
        }

        guard let data = try credentialStore.data(service: service, account: account),
              let storedKey = String(data: data, encoding: .utf8) else {
            return ""
        }
        CredentialAccessMigration.runIfNeeded(
            service: service,
            account: account,
            defaultsKey: accessMigrationKey,
            userDefaults: userDefaults,
            credentialStore: credentialStore
        )
        return normalized(storedKey)
    }

    static func save(
        _ apiKey: String,
        userDefaults: UserDefaults = .standard,
        credentialStore: SecureCredentialStoring = KeychainCredentialStore(),
        developmentCredentialStore: SecureCredentialStoring? = DevelopmentFileCredentialStore
            .activeForCurrentBuild
    ) throws {
        let trimmed = normalized(apiKey)
        if let developmentCredentialStore {
            if trimmed.isEmpty {
                try developmentCredentialStore.remove(service: service, account: account)
            } else {
                try developmentCredentialStore.set(
                    Data(trimmed.utf8),
                    service: service,
                    account: account
                )
            }
            CredentialStorageLog.logger.info(
                "Updated ElevenLabs credential in development storage; removed=\(trimmed.isEmpty, privacy: .public)"
            )
            return
        }

        if trimmed.isEmpty {
            try credentialStore.remove(service: service, account: account)
            userDefaults.removeObject(forKey: accessMigrationKey)
        } else {
            try credentialStore.set(Data(trimmed.utf8), service: service, account: account)
        }
    }

    private static func normalized(_ apiKey: String) -> String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum AlibabaAPIKeyStore {
    private static var service: String { AppCredentialServices.alibaba }
    private static let account = "default"
    private static var accessMigrationKey: String {
        scopedAccessMigrationKey("credentialAccess.alibaba.version")
    }

    static func load(
        userDefaults: UserDefaults = .standard,
        credentialStore: SecureCredentialStoring = KeychainCredentialStore(),
        developmentCredentialStore: SecureCredentialStoring? = DevelopmentFileCredentialStore
            .activeForCurrentBuild
    ) throws -> String {
        if let developmentCredentialStore {
            if let data = try developmentCredentialStore.data(service: service, account: account),
               let storedKey = String(data: data, encoding: .utf8) {
                CredentialStorageLog.logger.info(
                    "Loaded Alibaba credential from development storage"
                )
                return normalized(storedKey)
            }
            guard let data = try credentialStore.data(service: service, account: account),
                  let storedKey = String(data: data, encoding: .utf8) else {
                return ""
            }
            try developmentCredentialStore.set(data, service: service, account: account)
            CredentialStorageLog.logger.notice(
                "Migrated Alibaba credential from Keychain to development storage"
            )
            return normalized(storedKey)
        }

        guard let data = try credentialStore.data(service: service, account: account),
              let storedKey = String(data: data, encoding: .utf8) else {
            return ""
        }
        CredentialAccessMigration.runIfNeeded(
            service: service,
            account: account,
            defaultsKey: accessMigrationKey,
            userDefaults: userDefaults,
            credentialStore: credentialStore
        )
        return normalized(storedKey)
    }

    static func save(
        _ apiKey: String,
        userDefaults: UserDefaults = .standard,
        credentialStore: SecureCredentialStoring = KeychainCredentialStore(),
        developmentCredentialStore: SecureCredentialStoring? = DevelopmentFileCredentialStore
            .activeForCurrentBuild
    ) throws {
        let trimmed = normalized(apiKey)
        if let developmentCredentialStore {
            if trimmed.isEmpty {
                try developmentCredentialStore.remove(service: service, account: account)
            } else {
                try developmentCredentialStore.set(
                    Data(trimmed.utf8),
                    service: service,
                    account: account
                )
            }
            CredentialStorageLog.logger.info(
                "Updated Alibaba credential in development storage; removed=\(trimmed.isEmpty, privacy: .public)"
            )
            return
        }

        if trimmed.isEmpty {
            try credentialStore.remove(service: service, account: account)
            userDefaults.removeObject(forKey: accessMigrationKey)
        } else {
            try credentialStore.set(Data(trimmed.utf8), service: service, account: account)
        }
    }

    private static func normalized(_ apiKey: String) -> String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum GeminiAPIKeyStore {
    private static var service: String { AppCredentialServices.gemini }
    private static let account = "default"
    private static var accessMigrationKey: String {
        scopedAccessMigrationKey("credentialAccess.gemini.version")
    }

    static func load(
        userDefaults: UserDefaults = .standard,
        credentialStore: SecureCredentialStoring = KeychainCredentialStore(),
        developmentCredentialStore: SecureCredentialStoring? = DevelopmentFileCredentialStore
            .activeForCurrentBuild
    ) throws -> String {
        try ProviderAPIKeyStore.load(
            service: service,
            account: account,
            accessMigrationKey: accessMigrationKey,
            providerName: "Gemini",
            userDefaults: userDefaults,
            credentialStore: credentialStore,
            developmentCredentialStore: developmentCredentialStore
        )
    }

    static func save(
        _ apiKey: String,
        userDefaults: UserDefaults = .standard,
        credentialStore: SecureCredentialStoring = KeychainCredentialStore(),
        developmentCredentialStore: SecureCredentialStoring? = DevelopmentFileCredentialStore
            .activeForCurrentBuild
    ) throws {
        try ProviderAPIKeyStore.save(
            apiKey,
            service: service,
            account: account,
            accessMigrationKey: accessMigrationKey,
            providerName: "Gemini",
            userDefaults: userDefaults,
            credentialStore: credentialStore,
            developmentCredentialStore: developmentCredentialStore
        )
    }
}

private enum ProviderAPIKeyStore {
    static func load(
        service: String,
        account: String,
        accessMigrationKey: String,
        providerName: String,
        userDefaults: UserDefaults,
        credentialStore: SecureCredentialStoring,
        developmentCredentialStore: SecureCredentialStoring?
    ) throws -> String {
        if let developmentCredentialStore {
            if let data = try developmentCredentialStore.data(service: service, account: account),
               let storedKey = String(data: data, encoding: .utf8) {
                CredentialStorageLog.logger.info(
                    "Loaded \(providerName, privacy: .public) credential from development storage"
                )
                return normalized(storedKey)
            }
            guard let data = try credentialStore.data(service: service, account: account),
                  let storedKey = String(data: data, encoding: .utf8) else {
                return ""
            }
            try developmentCredentialStore.set(data, service: service, account: account)
            CredentialStorageLog.logger.notice(
                "Migrated \(providerName, privacy: .public) credential from Keychain to development storage"
            )
            return normalized(storedKey)
        }

        guard let data = try credentialStore.data(service: service, account: account),
              let storedKey = String(data: data, encoding: .utf8) else {
            return ""
        }
        CredentialAccessMigration.runIfNeeded(
            service: service,
            account: account,
            defaultsKey: accessMigrationKey,
            userDefaults: userDefaults,
            credentialStore: credentialStore
        )
        return normalized(storedKey)
    }

    static func save(
        _ apiKey: String,
        service: String,
        account: String,
        accessMigrationKey: String,
        providerName: String,
        userDefaults: UserDefaults,
        credentialStore: SecureCredentialStoring,
        developmentCredentialStore: SecureCredentialStoring?
    ) throws {
        let trimmed = normalized(apiKey)
        if let developmentCredentialStore {
            if trimmed.isEmpty {
                try developmentCredentialStore.remove(service: service, account: account)
            } else {
                try developmentCredentialStore.set(
                    Data(trimmed.utf8),
                    service: service,
                    account: account
                )
            }
            CredentialStorageLog.logger.info(
                "Updated \(providerName, privacy: .public) credential in development storage; removed=\(trimmed.isEmpty, privacy: .public)"
            )
            return
        }

        if trimmed.isEmpty {
            try credentialStore.remove(service: service, account: account)
            userDefaults.removeObject(forKey: accessMigrationKey)
        } else {
            try credentialStore.set(Data(trimmed.utf8), service: service, account: account)
        }
    }

    private static func normalized(_ apiKey: String) -> String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private func scopedAccessMigrationKey(_ baseKey: String) -> String {
    // A legacy file-based Keychain ACL identifies the trusted application at
    // its current location. Keep Xcode/DerivedData and the installed app from
    // incorrectly sharing a completed migration marker.
    let applicationPath = Bundle.main.bundleURL.standardizedFileURL.path
    return "\(baseKey).\(applicationPath)"
}

private enum CredentialAccessMigration {
    private static let currentVersion = 1

    static func runIfNeeded(
        service: String,
        account: String,
        defaultsKey: String,
        userDefaults: UserDefaults,
        credentialStore: SecureCredentialStoring
    ) {
        guard userDefaults.integer(forKey: defaultsKey) < currentVersion else {
            return
        }

        do {
            try credentialStore.stabilizeAccess(service: service, account: account)
            markComplete(defaultsKey: defaultsKey, userDefaults: userDefaults)
        } catch {
            NSLog("Shuo could not update Keychain access for %@: %@", service, error.localizedDescription)
        }
    }

    static func markComplete(defaultsKey: String, userDefaults: UserDefaults) {
        userDefaults.set(currentVersion, forKey: defaultsKey)
    }
}
