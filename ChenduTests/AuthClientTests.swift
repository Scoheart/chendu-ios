import XCTest
@testable import Chendu

private struct ScriptedTransport: HTTPTransport {
    var handler: (URLRequest) -> (Data, Int)

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, status) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}

final class AuthClientTests: XCTestCase {
    private let base = URL(string: "http://127.0.0.1:54321")!

    func testMagicLinkRequests() async throws {
        var seen: [URLRequest] = []
        let client = AuthClient(baseURL: base, anonKey: "anon-test", transport: ScriptedTransport { request in
            seen.append(request)
            if request.url?.path.hasSuffix("/verify") == true {
                let body = #"{"access_token":"access","refresh_token":"refresh","expires_in":3600,"user":{"id":"11111111-1111-4111-8111-111111111111"}}"#
                return (Data(body.utf8), 200)
            }
            return (Data("{}".utf8), 200)
        })
        try await client.sendMagicLink(email: "a@example.com")
        let session = try await client.verifyMagicLink(email: "a@example.com", token: "123456")
        XCTAssertEqual(session.userId, "11111111-1111-4111-8111-111111111111")
        XCTAssertEqual(seen[0].url?.path, "/auth/v1/otp")
        XCTAssertEqual(seen[0].value(forHTTPHeaderField: "apikey"), "anon-test")
        let otp = try JSONSerialization.jsonObject(with: seen[0].httpBody!) as! [String: Any]
        XCTAssertEqual(otp["email"] as? String, "a@example.com")
        XCTAssertEqual(seen[1].url?.path, "/auth/v1/verify")
    }

    func testAppleRequestShape() throws {
        let client = AuthClient(baseURL: base, anonKey: "anon-test", transport: URLSessionTransport())
        let request = client.appleRequest(idToken: "apple-token", nonce: "nonce-1")
        XCTAssertEqual(request.url?.path, "/auth/v1/token")
        XCTAssertTrue(request.url?.query?.contains("grant_type=id_token") == true)
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        XCTAssertEqual(body["provider"] as? String, "apple")
        XCTAssertEqual(body["id_token"] as? String, "apple-token")
        XCTAssertEqual(body["nonce"] as? String, "nonce-1")
        let role = ["service", "role"].joined(separator: "_")
        XCTAssertFalse(request.url!.absoluteString.contains(role))
    }

    @MainActor
    func testSessionRoundTripDoesNotTouchNotes() throws {
        let secrets = MemorySecrets()
        let store = SessionStore(secrets: secrets)
        let session = AuthSession(accessToken: "a", refreshToken: "r", userId: "user", expiresAt: Date(timeIntervalSince1970: 1_800_000_000))
        try store.save(session)
        XCTAssertEqual(store.session?.userId, "user")
        store.clear()
        XCTAssertNil(store.session)
        XCTAssertNil(secrets.read(account: "session"))
    }
}
