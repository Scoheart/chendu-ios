import Foundation

protocol IssueRemote: Sendable {
    func fetchIssues() async throws -> (issues: [Issue], audioPaths: [String: [String: String]])
    func audioData(storagePath: String) async throws -> Data
}

struct SupabaseIssueRemote: IssueRemote {
    var baseURL: URL
    var anonKey: String
    var accessToken: String
    var transport: any HTTPTransport

    func fetchIssues() async throws -> (issues: [Issue], audioPaths: [String: [String: String]]) {
        let select = "id,issue_date,topic,topic_label,title,zh_title,byline,lead,blocks,credit,podcast,annotations(n,kind,tag,head,body),vocab(position,word,ipa,meaning,example),patterns(position,pattern,pattern_zh,source_sentence,model_sentence,model_zh),audio_assets(kind,storage_path)"
        var parts = URLComponents(url: baseURL.appending(path: "rest/v1/issues"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [
            URLQueryItem(name: "select", value: select),
            URLQueryItem(name: "order", value: "issue_date.desc"),
        ]
        let (data, response) = try await transport.send(authorized(parts.url!))
        guard (200..<300).contains(response.statusCode) else { throw AuthError.http(response.statusCode) }
        return (try IssueMapper.issues(from: data), try IssueMapper.storagePaths(from: data))
    }

    func audioData(storagePath: String) async throws -> Data {
        let object = storagePath.hasPrefix("audio/") ? String(storagePath.dropFirst("audio/".count)) : storagePath
        var sign = URLRequest(url: baseURL.appending(path: "storage/v1/object/sign/audio/\(object)"))
        sign.httpMethod = "POST"
        sign.setValue(anonKey, forHTTPHeaderField: "apikey")
        sign.setValue("Bearer \(accessToken)", forHTTPHeaderField: "authorization")
        sign.setValue("application/json", forHTTPHeaderField: "content-type")
        sign.httpBody = Data("{\"expiresIn\":3600}".utf8)
        let (data, response) = try await transport.send(sign)
        guard (200..<300).contains(response.statusCode) else { throw AuthError.http(response.statusCode) }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let signed = (json["signedURL"] as? String) ?? (json["signedUrl"] as? String)
        else { throw AuthError.malformed }
        let absolute = signed.hasPrefix("http") ? signed : baseURL.absoluteString + "/storage/v1" + signed
        guard let url = URL(string: absolute) else { throw AuthError.malformed }
        let (bytes, download) = try await transport.send(authorized(url))
        guard (200..<300).contains(download.statusCode) else { throw AuthError.http(download.statusCode) }
        return bytes
    }

    private func authorized(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "authorization")
        return request
    }
}
