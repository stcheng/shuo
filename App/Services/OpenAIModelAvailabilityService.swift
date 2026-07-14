import CryptoKit
import Foundation

struct OpenAIModelAvailabilitySnapshot: Codable, Equatable {
    let scopeID: String
    let modelIDs: [String]
    let fetchedAt: Date

    var modelIDSet: Set<String> {
        Set(modelIDs)
    }

    func isFresh(at now: Date, ttl: TimeInterval) -> Bool {
        now.timeIntervalSince(fetchedAt) >= 0 && now.timeIntervalSince(fetchedAt) < ttl
    }
}

enum OpenAIModelAvailabilitySource: Equatable {
    case cache
    case network
}

struct OpenAIModelAvailabilityResult: Equatable {
    let snapshot: OpenAIModelAvailabilitySnapshot
    let source: OpenAIModelAvailabilitySource
}

enum OpenAIModelAvailabilityError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidBaseURL(String)
    case requestFailed(statusCode: Int, message: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add an OpenAI API key before refreshing models."
        case .invalidBaseURL(let baseURL):
            return OpenAICompatibleRequestBuilder.endpointValidationMessage(
                baseURLString: baseURL
            )
        case .requestFailed(let statusCode, let message):
            return "Could not refresh OpenAI models (\(statusCode)): \(message)"
        case .invalidResponse:
            return "The model list response was invalid."
        }
    }
}

protocol OpenAIModelAvailabilityStoring {
    func snapshot(for scopeID: String) -> OpenAIModelAvailabilitySnapshot?
    func save(_ snapshot: OpenAIModelAvailabilitySnapshot)
}

struct UserDefaultsOpenAIModelAvailabilityStore: OpenAIModelAvailabilityStoring {
    private let defaults: UserDefaults
    private let keyPrefix: String

    init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = "openAIModelAvailability"
    ) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    func snapshot(for scopeID: String) -> OpenAIModelAvailabilitySnapshot? {
        guard let data = defaults.data(forKey: cacheKey(scopeID)) else {
            return nil
        }
        return try? JSONDecoder().decode(OpenAIModelAvailabilitySnapshot.self, from: data)
    }

    func save(_ snapshot: OpenAIModelAvailabilitySnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        defaults.set(data, forKey: cacheKey(snapshot.scopeID))
    }

    private func cacheKey(_ scopeID: String) -> String {
        "\(keyPrefix).\(scopeID)"
    }
}

/// The service is immutable after initialization. URLSession and UserDefaults
/// are safe for the request/cache operations performed here; test-only custom
/// loaders are likewise called as a single request operation. Marking this
/// boundary sendable lets AppState await model refreshes without sharing its
/// main-actor state.
struct OpenAIModelAvailabilityService: @unchecked Sendable {
    static let cacheTTL: TimeInterval = 24 * 60 * 60

    typealias DataLoader = (URLRequest) async throws -> (Data, URLResponse)

    private let store: OpenAIModelAvailabilityStoring
    private let dataLoader: DataLoader

    init(
        store: OpenAIModelAvailabilityStoring = UserDefaultsOpenAIModelAvailabilityStore(),
        session: URLSession = SensitiveRequestURLSession.shared
    ) {
        self.store = store
        dataLoader = { request in
            try await session.data(for: request)
        }
    }

    init(
        store: OpenAIModelAvailabilityStoring,
        dataLoader: @escaping DataLoader
    ) {
        self.store = store
        self.dataLoader = dataLoader
    }

    func cachedSnapshot(settings: AppSettings, apiKey: String?) -> OpenAIModelAvailabilitySnapshot? {
        guard let apiKey = OpenAICompatibleRequestBuilder.normalizedAPIKey(apiKey) else {
            return nil
        }
        return store.snapshot(for: Self.scopeID(settings: settings, apiKey: apiKey))
    }

    func models(
        settings: AppSettings,
        apiKey: String?,
        forceRefresh: Bool = false,
        now: Date = Date()
    ) async throws -> OpenAIModelAvailabilityResult {
        guard let apiKey = OpenAICompatibleRequestBuilder.normalizedAPIKey(apiKey) else {
            throw OpenAIModelAvailabilityError.missingAPIKey
        }

        let scopeID = Self.scopeID(settings: settings, apiKey: apiKey)
        if !forceRefresh,
           let cached = store.snapshot(for: scopeID),
           cached.isFresh(at: now, ttl: Self.cacheTTL) {
            return OpenAIModelAvailabilityResult(snapshot: cached, source: .cache)
        }

        guard let endpoint = OpenAICompatibleRequestBuilder.endpoint(
            baseURLString: settings.openAIBaseURL,
            path: "models"
        ) else {
            throw OpenAIModelAvailabilityError.invalidBaseURL(settings.openAIBaseURL)
        }

        let request = OpenAICompatibleRequestBuilder.authenticatedGETRequest(
            endpoint: endpoint,
            apiKey: apiKey,
            settings: settings
        )
        let (data, response) = try await dataLoader(request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard (200 ..< 300).contains(statusCode) else {
            throw OpenAIModelAvailabilityError.requestFailed(
                statusCode: statusCode,
                message: OpenAICompatibleRequestBuilder.errorMessage(from: data)
            )
        }

        guard let decoded = try? JSONDecoder().decode(ModelListResponse.self, from: data) else {
            throw OpenAIModelAvailabilityError.invalidResponse
        }

        let snapshot = OpenAIModelAvailabilitySnapshot(
            scopeID: scopeID,
            modelIDs: Array(Set(decoded.data.map(\.id))).sorted(),
            fetchedAt: now
        )
        store.save(snapshot)
        return OpenAIModelAvailabilityResult(snapshot: snapshot, source: .network)
    }

    static func scopeID(settings: AppSettings, apiKey: String) -> String {
        let scope = [
            settings.openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            settings.openAIOrganizationID.trimmingCharacters(in: .whitespacesAndNewlines),
            settings.openAIProjectID.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        .joined(separator: "\u{1F}")

        let digest = SHA256.hash(data: Data(scope.utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

private struct ModelListResponse: Decodable {
    struct Model: Decodable {
        let id: String
    }

    let data: [Model]
}
