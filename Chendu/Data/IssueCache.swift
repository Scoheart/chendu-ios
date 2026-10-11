import Foundation

/// On-disk cache: `Application Support/Chendu/index.json` and `issues/<date>/{issue.json,audio*.mp3}`.
struct IssueCache {
    let root: URL

    init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.root = base.appendingPathComponent("Chendu", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    private var indexURL: URL { root.appendingPathComponent("index.json") }

    func issueDir(_ date: String) -> URL { root.appendingPathComponent("issues/\(date)", isDirectory: true) }

    func fileURL(_ date: String, _ file: String) -> URL { issueDir(date).appendingPathComponent(file) }

    func saveIndex(_ issues: [IssueSummary]) {
        guard let data = try? JSONEncoder().encode(FeedIndex(version: 1, issues: issues)) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    func loadIndex() -> [IssueSummary]? {
        guard let data = try? Data(contentsOf: indexURL) else { return nil }
        return try? JSONDecoder().decode(FeedIndex.self, from: data).issues
    }

    func save(_ issue: Issue) {
        let dir = issueDir(issue.date)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(issue) else { return }
        try? data.write(to: dir.appendingPathComponent("issue.json"), options: .atomic)
    }

    func loadIssue(_ date: String) -> Issue? {
        guard let data = try? Data(contentsOf: fileURL(date, "issue.json")) else { return nil }
        return try? JSONDecoder().decode(Issue.self, from: data)
    }

    func cachedIssueDates() -> [String] {
        let dir = root.appendingPathComponent("issues", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { FileManager.default.fileExists(atPath: fileURL($0, "issue.json").path) }.sorted(by: >)
    }

    func hasFile(_ date: String, _ file: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(date, file).path)
    }

    func totalBytes() -> Int64 {
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var sum: Int64 = 0
        for case let url as URL in e {
            sum += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return sum
    }

    func clear() {
        try? FileManager.default.removeItem(at: root.appendingPathComponent("issues", isDirectory: true))
    }
}
