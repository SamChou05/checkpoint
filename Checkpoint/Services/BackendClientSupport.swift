import Foundation

enum BackendRequestFactory {
    static func post(
        to url: URL,
        authorizationToken: String?,
        timeout: TimeInterval
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            BackendClientIdentity.installID,
            forHTTPHeaderField: "X-Checkpoint-Install-ID"
        )
        if let token = authorizationToken?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = timeout
        return request
    }
}

struct BackendErrorResponse: Decodable {
    var code: String?
}

enum BackendClientIdentity {
    static let installIDKey = "checkpoint.backend.install.id.v1"

    static var installID: String {
        installID(defaults: .standard)
    }

    static func installID(defaults: UserDefaults) -> String {
        if let existingID = defaults.string(forKey: installIDKey),
           UUID(uuidString: existingID) != nil {
            return existingID
        }

        let newID = UUID().uuidString
        defaults.set(newID, forKey: installIDKey)
        return newID
    }

    static func clearInstallID(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: installIDKey)
    }
}
