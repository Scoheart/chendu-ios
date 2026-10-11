import Foundation

struct ProfileDraft: Equatable {
    var learnerLevel = "B1"
    var explanationLang = "zh-CN"
    var annotationDepth = "standard"
    var annotationKinds = ["vocab", "grammar", "idiom"]
    var excerptWords = 400
    var vocabCount = 12
    var includeIpa = true
    var patternCount = 4
    var provider = "openai"
    var model = "gpt-4.1-mini"
    var voice = "alloy"
    var rotationMode = "round_robin"
}

struct AppSettingsDraft: Equatable {
    var timezone = "Asia/Shanghai"
    var deliveryTime = "08:00"
    var pushEnabled = false
    var theme = "paper"
    var fontScale = 1.0
    var bodyFont = "serif"
    var handwritingHeadings = true
    var syncNotes = true
}

struct PublicKeyRow: Codable, Equatable {
    var id: String
    var provider: String
    var label: String
    var keyHint: String

    enum CodingKeys: String, CodingKey {
        case id, provider, label
        case keyHint = "key_hint"
    }
}

enum SettingsRequests {
    static func profileBody(_ draft: ProfileDraft) -> [String: Any] {
        [
            "learner_level": draft.learnerLevel,
            "explanation_lang": draft.explanationLang,
            "annotation_depth": draft.annotationDepth,
            "annotation_kinds": draft.annotationKinds,
            "excerpt_words": draft.excerptWords,
            "vocab_count": draft.vocabCount,
            "include_ipa": draft.includeIpa,
            "pattern_count": draft.patternCount,
            "rotation": ["mode": draft.rotationMode],
            "tasks": [
                "select": ["provider": draft.provider, "model": draft.model],
                "tts": ["provider": draft.provider, "model": "tts-1", "voice": draft.voice],
            ],
        ]
    }

    static func settingsBody(_ draft: AppSettingsDraft) -> [String: Any] {
        [
            "timezone": draft.timezone,
            "delivery_time": draft.deliveryTime,
            "push_enabled": draft.pushEnabled,
            "theme": draft.theme,
            "font_scale": draft.fontScale,
            "body_font": draft.bodyFont,
            "handwriting_headings": draft.handwritingHeadings,
            "sync_notes": draft.syncNotes,
        ]
    }

    static func saveKeyBody(provider: String, label: String, secret: String) -> [String: Any] {
        ["p_provider": provider, "p_label": label, "p_secret": secret]
    }
}

struct SettingsClient {
    var baseURL: URL
    var anonKey: String
    var accessToken: String
    var userId: String
    var transport: any HTTPTransport

    func saveProfile(_ draft: ProfileDraft) async throws {
        try await send(patch(table: "generation_profiles", filter: "user_id=eq.\(userId)", body: SettingsRequests.profileBody(draft)))
    }

    func saveSettings(_ draft: AppSettingsDraft) async throws {
        try await send(patch(table: "user_settings", filter: "user_id=eq.\(userId)", body: SettingsRequests.settingsBody(draft)))
    }

    func saveKey(provider: String, label: String, secret: String) async throws -> PublicKeyRow {
        var request = URLRequest(url: baseURL.appending(path: "rest/v1/rpc/save_provider_key"))
        request.httpMethod = "POST"
        authorize(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: SettingsRequests.saveKeyBody(provider: provider, label: label, secret: secret))
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else { throw AuthError.http(response.statusCode) }
        let rows = try JSONDecoder().decode([PublicKeyRow].self, from: data)
        guard let row = rows.first else { throw AuthError.malformed }
        return row
    }

    func restorePrompt(task: String) async throws {
        var parts = URLComponents(url: baseURL.appending(path: "rest/v1/prompt_templates"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [
            URLQueryItem(name: "owner_id", value: "eq.\(userId)"),
            URLQueryItem(name: "task", value: "eq.\(task)"),
        ]
        var request = URLRequest(url: parts.url!)
        request.httpMethod = "DELETE"
        authorize(&request)
        try await send(request)
    }

    func addRss(title: String, url: String, topic: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "rest/v1/sources"))
        request.httpMethod = "POST"
        authorize(&request)
        request.setValue("return=representation", forHTTPHeaderField: "prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "owner_id": userId,
            "kind": "rss",
            "title": title,
            "url": url,
            "topic": topic,
            "license": "all-rights-reserved",
        ])
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else { throw AuthError.http(response.statusCode) }
        guard
            let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
            let id = rows.first?["id"] as? String
        else { throw AuthError.malformed }
        var sub = URLRequest(url: baseURL.appending(path: "rest/v1/subscriptions"))
        sub.httpMethod = "POST"
        authorize(&sub)
        sub.setValue("return=minimal", forHTTPHeaderField: "prefer")
        sub.httpBody = try JSONSerialization.data(withJSONObject: ["user_id": userId, "source_id": id])
        try await send(sub)
    }

    func copyPrompt(task: String, body: String, basedOnId: String, basedOnVersion: Int) async throws {
        var request = URLRequest(url: baseURL.appending(path: "rest/v1/prompt_templates"))
        request.httpMethod = "POST"
        authorize(&request)
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "prefer")
        var payload: [String: Any] = [
            "owner_id": userId,
            "task": task,
            "version": 1,
            "body": body,
        ]
        if !basedOnId.isEmpty {
            payload["based_on_id"] = basedOnId
            payload["based_on_version"] = basedOnVersion
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        try await send(request)
    }

    private func patch(table: String, filter: String, body: [String: Any]) -> URLRequest {
        var parts = URLComponents(url: baseURL.appending(path: "rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        parts.percentEncodedQuery = filter
        var request = URLRequest(url: parts.url!)
        request.httpMethod = "PATCH"
        authorize(&request)
        request.setValue("return=minimal", forHTTPHeaderField: "prefer")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func authorize(_ request: inout URLRequest) {
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
    }

    private func send(_ request: URLRequest) async throws {
        let (_, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else { throw AuthError.http(response.statusCode) }
    }
}
