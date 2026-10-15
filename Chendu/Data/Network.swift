import Foundation
import Network

enum NetError: Error, LocalizedError {
    case http(Int)
    var errorDescription: String? {
        switch self { case .http(let code): "服务器返回 \(code)" }
    }
}

final class SiteClient: @unchecked Sendable {
    static let shared = SiteClient()

    static let baseURL: URL = {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["CHENDU_BASE_URL"], let url = URL(string: override) { return url }
        #endif
        return URL(string: "https://chendu-english.vercel.app/")!
    }()

    let session: URLSession
    /// Debug-only escape hatch so the simulator can reach the site through a local HTTP proxy (e.g. `CHENDU_PROXY=127.0.0.1:6789`).
    let usesProxy: Bool

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = false
        var proxied = false
        #if DEBUG
        if let spec = ProcessInfo.processInfo.environment["CHENDU_PROXY"], let colon = spec.lastIndex(of: ":"),
           let port = NWEndpoint.Port(String(spec[spec.index(after: colon)...])) {
            let host = NWEndpoint.Host(String(spec[..<colon]))
            config.proxyConfigurations = [ProxyConfiguration(httpCONNECTProxy: .hostPort(host: host, port: port))]
            proxied = true
        }
        #endif
        usesProxy = proxied
        session = URLSession(configuration: config)
    }

    func url(_ path: String) -> URL {
        path.isEmpty ? Self.baseURL : URL(string: path, relativeTo: Self.baseURL)!.absoluteURL
    }

    func data(_ path: String) async throws -> Data {
        var req = URLRequest(url: url(path))
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NetError.http(http.statusCode)
        }
        return data
    }

    func download(_ path: String, to destination: URL) async throws {
        let (tmp, resp) = try await session.download(from: url(path))
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NetError.http(http.statusCode)
        }
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: tmp, to: destination)
    }
}
