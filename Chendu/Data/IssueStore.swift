import Foundation
import Observation

/// Where the currently shown data came from.
enum DataSource: String {
    case remote, cache, none

    var label: String {
        switch self {
        case .remote: "Supabase"
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
    private var memory: [String: Issue] = [:]
    private var audioPaths: [String: [String: String]] = [:]
    private let remoteOverride: (any IssueRemote)?

    init(cache: IssueCache = IssueCache(), remote: (any IssueRemote)? = nil) {
        self.cache = cache
        self.remoteOverride = remote
        if let cached = cache.loadIndex() {
            summaries = cached
            indexSource = .cache
        }
    }

    private func remote() -> (any IssueRemote)? {
        if let remoteOverride { return remoteOverride }
        guard let session = SessionStore.live.session else { return nil }
        return SupabaseIssueRemote(
            baseURL: SupabaseConfig.url,
            anonKey: SupabaseConfig.anonKey,
            accessToken: session.accessToken,
            transport: URLSessionTransport()
        )
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
        guard let remote = remote() else { return (cache.loadIndex() ?? [], .cache) }
        let fetched = try await remote.fetchIssues()
        audioPaths = fetched.audioPaths
        for issue in fetched.issues {
            memory[issue.date] = issue
            cache.save(issue)
        }
        return (fetched.issues.map(\.summary), .remote)
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
        if let cached = cachedIssue(date) { return (cached, .cache) }
        throw OfflineOnly()
    }

    // MARK: audio & offline

    func remoteURL(_ date: String, _ file: String) -> URL { cache.fileURL(date, file) }

    func localAudio(_ date: String, _ track: AudioTrack) -> URL? {
        cache.hasFile(date, track.file) ? cache.fileURL(date, track.file) : nil
    }

    func downloadAudio(_ date: String, _ track: AudioTrack) async throws -> URL {
        if let local = localAudio(date, track) { return local }
        guard let remote = remote(), let path = audioPaths[date]?[track.id] else { throw OfflineOnly() }
        let data = try await remote.audioData(storagePath: path)
        let dest = cache.fileURL(date, track.file)
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: dest, options: .atomic)
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
        if error is OfflineOnly { return "这一期还没有缓存" }
        return error.localizedDescription
    }
}

private struct OfflineOnly: Error {}
