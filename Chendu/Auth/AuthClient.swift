import Foundation

protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.http(0) }
        return (data, http)
    }
}

enum AuthError: Error, Equatable {
    case http(Int)
    case malformed
}

struct AuthSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var userId: String
    var expiresAt: Date
}

struct AuthClient: Sendable {
    var baseURL: URL
    var anonKey: String
    var transport: any HTTPTransport

    func sendMagicLink(email: String) async throws {
        let (_, response) = try await transport.send(otpRequest(email: email))
        guard (200..<300).contains(response.statusCode) else { throw AuthError.http(response.statusCode) }
    }

    func verifyMagicLink(email: String, token: String) async throws -> AuthSession {
        let (data, response) = try await transport.send(verifyRequest(email: email, token: token))
        guard (200..<300).contains(response.statusCode) else { throw AuthError.http(response.statusCode) }
        return try Self.session(from: data)
    }

    func signInWithApple(idToken: String, nonce: String) async throws -> AuthSession {
        let (data, response) = try await transport.send(appleRequest(idToken: idToken, nonce: nonce))
        guard (200..<300).contains(response.statusCode) else { throw AuthError.http(response.statusCode) }
        return try Self.session(from: data)
    }

    func otpRequest(email: String) -> URLRequest {
        jsonRequest(url: baseURL.appending(path: "auth/v1/otp"), body: [
            "email": email,
            "create_user": true,
        ])
    }

    func verifyRequest(email: String, token: String) -> URLRequest {
        let numeric = token.count <= 8 && token.allSatisfy(\.isNumber)
        let body: [String: Any] = numeric
            ? ["type": "email", "email": email, "token": token]
            : ["type": "magiclink", "token_hash": token]
        return jsonRequest(url: baseURL.appending(path: "auth/v1/verify"), body: body)
    }

    func appleRequest(idToken: String, nonce: String) -> URLRequest {
        var parts = URLComponents(url: baseURL.appending(path: "auth/v1/token"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "grant_type", value: "id_token")]
        return jsonRequest(url: parts.url!, body: [
            "provider": "apple",
            "id_token": idToken,
            "nonce": nonce,
        ])
    }

    static func session(from data: Data) throws -> AuthSession {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let access = json["access_token"] as? String,
            let refresh = json["refresh_token"] as? String,
            let user = json["user"] as? [String: Any],
            let userId = user["id"] as? String
        else { throw AuthError.malformed }
        let expiresIn = json["expires_in"] as? Double ?? 3600
        return AuthSession(
            accessToken: access,
            refreshToken: refresh,
            userId: userId,
            expiresAt: Date().addingTimeInterval(expiresIn)
        )
    }

    private func jsonRequest(url: URL, body: [String: Any]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }
}

enum SupabaseConfig {
    static var url: URL {
        if let raw = ProcessInfo.processInfo.environment["SUPABASE_URL"], let url = URL(string: raw) {
            return url
        }
        return URL(string: "http://127.0.0.1:54321")!
    }

    static var anonKey: String {
        ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"] ?? ""
    }
}
