import Foundation
import Observation

/// Where the currently shown data came from.
enum DataSource: String {
    case feed, html, cache, none

    var label: String {
        switch self {
        case .feed: "JSON 数据源"
        case .html: "网页解析（JSON 数据源未部署）"
        case .cache: "离线缓存"
        case .none: "—"
        }
    }
}

@MainActor
@Observable
final class IssueStore {
    static let shared = IssueStore()

    private(set) var summaries: [IssueSummary] = []
    private(set) var indexSource: DataSource = .none
    private(set) var isRefreshing = false
    private(set) var lastError: String?
    private(set) var lastRefresh: Date?
    /// Progress 0…1 for issues being saved for offline reading.
    private(set) var downloads: [String: Double] = [:]
    private(set) var cacheRevision = 0

    /// Set by a notification tap; the list opens the newest issue.
    var openLatestRequested = false

    let cache: IssueCache
    private let client: SiteClient
    private var memory: [String: Issue] = [:]
    private var feedAvailable: Bool?

    init(cache: IssueCache = IssueCache(), client: SiteClient = .shared) {
        self.cache = cache
        self.client = client
        if let cached = cache.loadIndex() {
            summaries = cached
            indexSource = .cache
        }
    }

    // MARK: index

    func refreshIndex() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let (issues, source) = try await fetchIndex()
            summaries = issues
            indexSource = source
            lastError = nil
            lastRefresh = .now
            cache.saveIndex(issues)
        } catch {
            lastError = Self.describe(error)
            if summaries.isEmpty {
                summaries = cache.loadIndex() ?? cache.cachedIssueDates().compactMap { cache.loadIssue($0)?.summary }
            }
            indexSource = summaries.isEmpty ? .none : .cache
        }
    }

    private func fetchIndex() async throws -> ([IssueSummary], DataSource) {
        if feedAvailable != false {
            do {
                let data = try await client.data("issues.json")
                let feed = try JSONDecoder().decode(FeedIndex.self, from: data)
                feedAvailable = true
                return (feed.issues.sorted { $0.date > $1.date }, .feed)
            } catch NetError.http {
                feedAvailable = false
            } catch is DecodingError {
                feedAvailable = false
            }
        }
        let html = String(decoding: try await client.data(""), as: UTF8.self)
        let issues = SiteParser.parseIndex(html)
        if issues.isEmpty { throw SiteParser.ParseError.missing("往期列表") }
        return (issues, .html)
    }

    // MARK: issues

    func cachedIssue(_ date: String) -> Issue? {
        memory[date] ?? cache.loadIssue(date)
    }

    /// Network first so corrections to an issue show up; the offline copy is used when the network fails.
    func issue(_ date: String) async throws -> (Issue, DataSource) {
        do {
            let (issue, source) = try await fetchIssue(date)
            memory[date] = issue
            cache.save(issue)
            cacheRevision += 1
            return (issue, source)
        } catch {
            if let cached = cachedIssue(date) {
                memory[date] = cached
                return (cached, .cache)
            }
            throw error
        }
    }

    private func fetchIssue(_ date: String) async throws -> (Issue, DataSource) {
        if feedAvailable != false {
            do {
                let data = try await client.data("issues/\(date)/issue.json")
                return (try JSONDecoder().decode(Issue.self, from: data), .feed)
            } catch NetError.http {
                // Missing per-issue JSON: fall through to the page.
            } catch is DecodingError {
                // Incompatible feed version: fall through to the page.
            }
        }
        let html = String(decoding: try await client.data("issues/\(date)/"), as: UTF8.self)
        return (try SiteParser.parseIssue(html, date: date), .html)
    }

    // MARK: audio & offline

    func remoteURL(_ date: String, _ file: String) -> URL { client.url("issues/\(date)/\(file)") }

    func localAudio(_ date: String, _ track: AudioTrack) -> URL? {
        cache.hasFile(date, track.file) ? cache.fileURL(date, track.file) : nil
    }

    func downloadAudio(_ date: String, _ track: AudioTrack) async throws -> URL {
        if let local = localAudio(date, track) { return local }
        let dest = cache.fileURL(date, track.file)
        try await client.download("issues/\(date)/\(track.file)", to: dest)
        cacheRevision += 1
        return dest
    }

    func isOffline(_ date: String) -> Bool {
        _ = cacheRevision
        guard let issue = cachedIssue(date) else { return false }
        return issue.audio.allSatisfy { cache.hasFile(date, $0.file) }
    }

    func isCached(_ date: String) -> Bool {
        _ = cacheRevision
        return memory[date] != nil || cache.hasFile(date, "issue.json")
    }

    /// Saves the issue text and both audio tracks.
    func saveOffline(_ date: String) async {
        guard downloads[date] == nil else { return }
        downloads[date] = 0.02
        defer { downloads[date] = nil; cacheRevision += 1 }
        do {
            let (issue, _) = try await issue(date)
            let total = Double(max(issue.audio.count, 1))
            for (i, track) in issue.audio.enumerated() {
                _ = try await downloadAudio(date, track)
                downloads[date] = Double(i + 1) / total
            }
        } catch {
            lastError = Self.describe(error)
        }
    }

    func saveRecentOffline(count: Int) async {
        for s in summaries.prefix(count) { await saveOffline(s.date) }
    }

    var cachedIssueCount: Int { _ = cacheRevision; return cache.cachedIssueDates().count }

    var cacheBytes: Int64 { _ = cacheRevision; return cache.totalBytes() }

    func clearCache() {
        cache.clear()
        memory.removeAll()
        cacheRevision += 1
    }

    static func describe(_ error: Error) -> String {
        if let e = error as? URLError {
            switch e.code {
            case .notConnectedToInternet, .networkConnectionLost: return "没有网络连接"
            case .timedOut: return "连接超时"
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed: return "无法连接到晨读网站"
            default: return "网络错误（\(e.code.rawValue)）"
            }
        }
        return error.localizedDescription
    }
}
