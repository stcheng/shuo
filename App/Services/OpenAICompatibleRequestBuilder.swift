import Foundation

enum SensitiveRequestRedirectPolicy {
    static func allowsRedirect(from sourceURL: URL?, to destinationURL: URL?) -> Bool {
        guard let sourceOrigin = origin(for: sourceURL),
              let destinationOrigin = origin(for: destinationURL) else {
            return false
        }
        return sourceOrigin == destinationOrigin
    }

    private static func origin(for url: URL?) -> Origin? {
        guard let url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = components.host?.lowercased(),
              !host.isEmpty else {
            return nil
        }
        let port = components.port ?? (scheme == "https" ? 443 : 80)
        return Origin(scheme: scheme, host: host, port: port)
    }

    private struct Origin: Equatable {
        let scheme: String
        let host: String
        let port: Int
    }
}

private final class SensitiveRequestSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard SensitiveRequestRedirectPolicy.allowsRedirect(
            from: response.url,
            to: request.url
        ) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

enum SensitiveRequestURLSession {
    /// A cloud request should fail visibly instead of inheriting Foundation's
    /// multi-day resource timeout. The request timeout covers stalled network
    /// activity; the resource timeout still leaves room for a five-minute
    /// recording to upload and be transcribed.
    static let requestTimeout: TimeInterval = 90
    static let resourceTimeout: TimeInterval = 12 * 60

    static let shared: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        return URLSession(
            configuration: configuration,
            delegate: SensitiveRequestSessionDelegate(),
            delegateQueue: nil
        )
    }()
}

enum OpenAICompatibleEndpointValidationError: LocalizedError, Equatable {
    case invalidURL
    case insecureRemoteHTTP

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Enter a valid OpenAI-compatible HTTPS base URL. HTTP is allowed only for localhost, 127.0.0.1, or ::1."
        case .insecureRemoteHTTP:
            return "Remote OpenAI-compatible endpoints must use HTTPS to protect the API key and request data in transit. HTTP is allowed only for localhost, 127.0.0.1, or ::1."
        }
    }
}

struct OpenAICompatibleRequestBuilder {
    static func normalizedAPIKey(_ apiKey: String?) -> String? {
        guard let apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            return nil
        }
        return apiKey
    }

    static func endpoint(baseURLString: String, path: String) -> URL? {
        try? validatedEndpoint(baseURLString: baseURLString, path: path)
    }

    static func validatedEndpoint(baseURLString: String, path: String) throws -> URL {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              let baseURL = components.url else {
            throw OpenAICompatibleEndpointValidationError.invalidURL
        }

        if scheme == "http", !isLocalLoopbackHost(host) {
            throw OpenAICompatibleEndpointValidationError.insecureRemoteHTTP
        }

        return baseURL.appendingPathComponent(path)
    }

    static func usesThirdPartyRelay(baseURLString: String) -> Bool {
        connectionIdentity(baseURLString: baseURLString)
            != "https://api.openai.com/v1"
    }

    static func connectionIdentity(baseURLString: String) -> String {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            return trimmed
        }

        let defaultPort = scheme == "https" ? 443 : 80
        let port = components.port == defaultPort ? nil : components.port
        let normalizedPath = components.percentEncodedPath
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let authority = port.map { "\(host):\($0)" } ?? host
        return "\(scheme)://\(authority)/\(normalizedPath)"
    }

    static func endpointValidationMessage(baseURLString: String) -> String {
        do {
            _ = try validatedEndpoint(baseURLString: baseURLString, path: "")
            return OpenAICompatibleEndpointValidationError.invalidURL.localizedDescription
        } catch let error as OpenAICompatibleEndpointValidationError {
            return error.localizedDescription
        } catch {
            return OpenAICompatibleEndpointValidationError.invalidURL.localizedDescription
        }
    }

    static func authenticatedPOSTRequest(
        endpoint: URL,
        apiKey: String,
        settings: AppSettings,
        contentType: String,
        requestID: UUID = UUID()
    ) -> URLRequest {
        authenticatedRequest(
            endpoint: endpoint,
            method: "POST",
            apiKey: apiKey,
            settings: settings,
            contentType: contentType,
            requestID: requestID
        )
    }

    static func authenticatedGETRequest(
        endpoint: URL,
        apiKey: String,
        settings: AppSettings,
        requestID: UUID = UUID()
    ) -> URLRequest {
        authenticatedRequest(
            endpoint: endpoint,
            method: "GET",
            apiKey: apiKey,
            settings: settings,
            contentType: nil,
            requestID: requestID
        )
    }

    private static func authenticatedRequest(
        endpoint: URL,
        method: String,
        apiKey: String,
        settings: AppSettings,
        contentType: String?,
        requestID: UUID
    ) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        request.setValue(requestID.uuidString, forHTTPHeaderField: "X-Client-Request-Id")

        let organizationID = settings.openAIOrganizationID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !organizationID.isEmpty {
            request.setValue(organizationID, forHTTPHeaderField: "OpenAI-Organization")
        }

        let projectID = settings.openAIProjectID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !projectID.isEmpty {
            request.setValue(projectID, forHTTPHeaderField: "OpenAI-Project")
        }

        return request
    }

    static func errorMessage(from data: Data, fallback: String = "") -> String {
        if let response = try? JSONDecoder().decode(OpenAICompatibleErrorResponse.self, from: data) {
            return response.error.message.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let bodyText = String(data: data, encoding: .utf8) ?? fallback
        return bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func cleanedModelOutput(_ content: String) -> String {
        var output = content.trimmingCharacters(in: .whitespacesAndNewlines)

        if output.hasPrefix("```") {
            output = output.replacingOccurrences(
                of: #"^```[A-Za-z]*\s*"#,
                with: "",
                options: .regularExpression
            )
            output = output.replacingOccurrences(
                of: #"\s*```$"#,
                with: "",
                options: .regularExpression
            )
            output = output.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if output.count >= 2,
           let first = output.first,
           let last = output.last,
           (first == "\"" && last == "\"") || (first == "“" && last == "”") {
            output.removeFirst()
            output.removeLast()
            output = output.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return output
    }

    private static func isLocalLoopbackHost(_ host: String) -> Bool {
        let normalizedHost = host
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .lowercased()
        return normalizedHost == "localhost"
            || normalizedHost == "127.0.0.1"
            || normalizedHost == "::1"
    }
}

private struct OpenAICompatibleErrorResponse: Decodable {
    struct APIError: Decodable {
        let message: String
    }

    let error: APIError
}
