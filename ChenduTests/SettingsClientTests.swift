import XCTest
@testable import Chendu

final class SettingsClientTests: XCTestCase {
    func testProfilePatchCarriesLearnerFieldsAndNoSecret() throws {
        var draft = ProfileDraft()
        draft.excerptWords = 220
        draft.learnerLevel = "C1"
        let body = SettingsRequests.profileBody(draft)
        XCTAssertEqual(body["excerpt_words"] as? Int, 220)
        XCTAssertEqual(body["learner_level"] as? String, "C1")
        let rendered = String(data: try JSONSerialization.data(withJSONObject: body), encoding: .utf8)!
        XCTAssertFalse(rendered.contains("sk-"))
        XCTAssertFalse(rendered.contains("secret"))
    }

    func testKeySaveUsesTheRpcAndThePublicRowHasNoSecret() throws {
        let body = SettingsRequests.saveKeyBody(provider: "openai", label: "default", secret: "sk-test-secret-ABCD")
        XCTAssertEqual(body["p_provider"] as? String, "openai")
        XCTAssertEqual(body["p_secret"] as? String, "sk-test-secret-ABCD")
        let row = try JSONDecoder().decode(PublicKeyRow.self, from: Data(#"{"id":"k","provider":"openai","label":"default","key_hint":"ABCD"}"#.utf8))
        XCTAssertEqual(row.keyHint, "ABCD")
        XCTAssertFalse(String(data: try JSONEncoder().encode(row), encoding: .utf8)!.contains("sk-"))
    }
}
