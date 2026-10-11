import SwiftData
import SwiftUI

struct ReaderRoute: Hashable {
    var date: String
    var focusNote: UUID?
}

struct ReaderView: View {
    let date: String
    var focusNote: UUID?

    @Environment(IssueStore.self) private var store
    @Environment(\.modelContext) private var context
    @Query private var notes: [UserNote]

    @State private var issue: Issue?
    @State private var source: DataSource = .none
    @State private var loadError: String?
    @State private var activeKey: String?
    @State private var draft: NoteDraft?
    @AppStorage("readerFontSize") private var fontSize: Double = 19

    init(date: String, focusNote: UUID? = nil) {
        self.date = date
        self.focusNote = focusNote
        _notes = Query(filter: #Predicate<UserNote> { $0.issueDate == date }, sort: \UserNote.createdAt)
        if let cached = IssueCacheLookup.cached(date) {
            _issue = State(initialValue: cached)
            _source = State(initialValue: .cache)
        }
    }

    var body: some View {
        Group {
            if let issue {
                content(issue)
            } else if let loadError {
                ContentUnavailableView {
                    Label("读取失败", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("重试") { Task { await load() } }.buttonStyle(.borderedProminent).tint(.grammarRed)
                }
            } else {
                ProgressView("正在取今天的晨读…").tint(.grammarRed)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PaperBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .task { await load() }
        .sheet(item: $draft) { d in
            NoteEditor(draft: d, onSave: save, onDelete: d.existing.map { n in { delete(n) } })
        }
        .safeAreaInset(edge: .bottom) { MiniPlayerBar() }
    }

    private func load() async {
        loadError = nil
        do {
            let (fresh, src) = try await store.issue(date)
            if fresh != issue { issue = fresh }
            source = src
        } catch {
            if issue == nil { loadError = IssueStore.describe(error) }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text("晨读 · \(DateText.short(date))").font(.handZh(20)).foregroundStyle(Color.grammarRed)
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                Button("放大字号", systemImage: "textformat.size.larger") { fontSize = min(fontSize + 1, 26) }
                Button("缩小字号", systemImage: "textformat.size.smaller") { fontSize = max(fontSize - 1, 15) }
                Divider()
                ShareLink(item: SiteClient.shared.url("issues/\(date)/")) { Label("分享网页版", systemImage: "square.and.arrow.up") }
            } label: {
                Image(systemName: "textformat.size")
            }
            OfflineButton(date: date)
        }
    }

    // MARK: content

    private func content(_ issue: Issue) -> some View {
        let paragraphs = issue.paragraphs
        let noteParagraph = issue.paragraphForNote
        let notesByN = Dictionary(uniqueKeysWithValues: issue.notes.map { ($0.n, $0) })
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(issue)
                    legend
                    ForEach(paragraphs) { p in
                        if p.gapBefore {
                            Text("[ … ]")
                                .font(.serif(16))
                                .kerning(4)
                                .foregroundStyle(Color.muted)
                                .frame(maxWidth: .infinity)
                                .padding(.bottom, 16)
                                .accessibilityLabel("中间段落省略")
                        }
                        paragraphView(p, issue: issue, notesByN: notesByN, noteParagraph: noteParagraph)
                            .id("p\(p.index)")
                    }
                    if let credit = issue.credit { creditView(credit) }
                    AudioSection(issue: issue)
                    if !issue.words.isEmpty { WordsSection(words: issue.words) }
                    if !issue.patterns.isEmpty { PatternsSection(patterns: issue.patterns) }
                    if let podcast = issue.podcast { PodcastSection(podcast: podcast) }
                    myNotesSection(issue: issue, proxy: proxy)
                    if source == .cache {
                        Label("离线副本", systemImage: "arrow.down.circle")
                            .font(.footnote).foregroundStyle(Color.muted)
                            .padding(.top, 24)
                    }
                    Text("晨读 · 中文讲解为原创学习笔记；英文原文版权归原作者及媒体所有")
                        .font(.caption2).foregroundStyle(Color.muted)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 28)
                }
                .padding(.horizontal, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: activeKey) { _, key in
                guard key != nil else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("activeCard") }
                }
            }
            .onAppear {
                guard let focusNote, let n = notes.first(where: { $0.id == focusNote }) else { return }
                activeKey = n.key
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation { proxy.scrollTo("p\(n.paragraphIndex)", anchor: .center) }
                }
            }
        }
    }

    private func header(_ issue: Issue) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TopicChip(key: issue.topic, label: issue.topicLabel)
                Text(issue.dateLabel.isEmpty ? "今日精读" : issue.dateLabel)
                    .font(.handZh(17)).foregroundStyle(Color.muted)
            }
            .padding(.top, 16)
            Text(issue.title)
                .font(.serif(28, weight: .semibold))
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("issueTitle")
            if !issue.zhTitle.isEmpty {
                Text(issue.zhTitle).font(.system(size: 16)).foregroundStyle(Color(red: 0.29, green: 0.27, blue: 0.24))
            }
            if !issue.byline.isEmpty {
                Text(issue.byline).font(.system(size: 13)).foregroundStyle(Color.muted)
            }
            if !issue.lead.isEmpty {
                Text(issue.lead)
                    .font(.handZh(19))
                    .lineSpacing(4)
                    .foregroundStyle(Color(Ink.leadInk))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color(Ink.leadBG)).shadow(color: .black.opacity(0.06), radius: 0, y: 1))
                    .rotationEffect(.degrees(-0.3))
                    .padding(.top, 6)
            }
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                legendItem("词汇", Ink.vocab, style: .dotted)
                legendItem("语法", Ink.grammar, style: .solid)
                legendItem("地道表达", Ink.idiom, style: .fill(Ink.idiomBG))
                legendItem("我的笔记", Ink.user, style: .fill(Ink.userHL))
            }
            .font(.system(size: 13))
            Text("👆 点彩色划线看笔记 · ✏️ 长按选中原文可「加笔记」")
                .font(.handZh(15)).foregroundStyle(Color.grammarRed)
        }
        .padding(.vertical, 16)
    }

    private enum LegendStyle { case dotted, solid, fill(UIColor) }

    private func legendItem(_ label: String, _ color: UIColor, style: LegendStyle) -> some View {
        Text(label)
            .foregroundStyle(Color.muted)
            .padding(.horizontal, 3)
            .background {
                if case .fill(let bg) = style { RoundedRectangle(cornerRadius: 2).fill(Color(bg)) }
            }
            .overlay(alignment: .bottom) {
                switch style {
                case .dotted:
                    Line().stroke(Color(color), style: StrokeStyle(lineWidth: 2, dash: [2, 3])).frame(height: 2).offset(y: 2)
                case .solid:
                    Rectangle().fill(Color(color)).frame(height: 2).offset(y: 2)
                case .fill:
                    EmptyView()
                }
            }
    }

    @ViewBuilder
    private func paragraphView(_ p: Paragraph, issue: Issue, notesByN: [Int: Annotation], noteParagraph: [Int: Int]) -> some View {
        let plain = p.text
        let paraNotes = notes.filter { $0.paragraphIndex == p.index }
        let marks = paraNotes.compactMap { n in n.resolvedRange(in: plain).map { UserMark(id: n.id, range: $0) } }
        let rendering = ParagraphRendering.make(segments: p.segments, notes: notesByN, marks: marks, activeKey: activeKey, fontSize: fontSize)
        VStack(alignment: .leading, spacing: 10) {
            ParagraphText(
                index: p.index,
                rendering: rendering,
                onTapTag: { tag in
                    withAnimation(.easeOut(duration: 0.2)) { activeKey = activeKey == tag ? nil : tag }
                },
                onAddNote: { range, quote in
                    draft = NoteDraft(paragraphIndex: p.index, range: range, quote: quote, text: "")
                }
            )
            if let key = activeKey {
                if key.hasPrefix("n:"), let n = Int(key.dropFirst(2)), noteParagraph[n] == p.index, let note = notesByN[n] {
                    AnnotationCard(note: note) { withAnimation { activeKey = nil } }
                        .id("activeCard")
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else if let user = paraNotes.first(where: { $0.key == key }) {
                    UserNoteCard(
                        note: user,
                        onEdit: { draft = NoteDraft(existing: user, paragraphIndex: user.paragraphIndex, range: NSRange(location: user.start, length: user.length), quote: user.quote, text: user.text) },
                        onDelete: { delete(user) },
                        onClose: { withAnimation { activeKey = nil } }
                    )
                    .id("activeCard")
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(.bottom, 20)
    }

    private func creditView(_ credit: Credit) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().overlay(Color.rule)
            Text(credit.text).font(.system(size: 13)).foregroundStyle(Color.muted)
            ForEach(credit.links, id: \.url) { link in
                if let url = URL(string: link.url) {
                    Link(destination: url) {
                        Label(link.title, systemImage: "arrow.up.right.square").font(.system(size: 13))
                    }
                    .tint(Color.muted)
                }
            }
        }
    }

    @ViewBuilder
    private func myNotesSection(issue: Issue, proxy: ScrollViewProxy) -> some View {
        if !notes.isEmpty {
            SectionHeader("我的笔记")
            Text("只保存在这台手机上（可在「我的笔记」里导出）。").font(.system(size: 13)).foregroundStyle(Color.muted)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(notes) { note in
                    Button {
                        activeKey = note.key
                        withAnimation { proxy.scrollTo("p\(note.paragraphIndex)", anchor: .center) }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("“\(note.quote)”").font(.serif(15).italic()).foregroundStyle(Color(red: 0.42, green: 0.29, blue: 0.11)).lineLimit(2)
                            Text(note.text).font(.handZh(19)).foregroundStyle(Color.ink).multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.white))
                        .overlay(alignment: .leading) { Rectangle().fill(Color(Ink.userHLOn)).frame(width: 3) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("issueUserNote")
                }
            }
            .padding(.top, 6)
        }
    }

    // MARK: notes

    private func save(_ d: NoteDraft) {
        let text = d.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = d.existing {
            existing.text = text
            existing.updatedAt = .now
            activeKey = existing.key
        } else {
            let note = UserNote(issueDate: date, issueTitle: issue?.title ?? "", paragraphIndex: d.paragraphIndex,
                                start: d.range.location, length: d.range.length, quote: d.quote, text: text)
            context.insert(note)
            activeKey = note.key
        }
        try? context.save()
    }

    private func delete(_ note: UserNote) {
        if activeKey == note.key { activeKey = nil }
        context.delete(note)
        try? context.save()
    }
}

/// Synchronous cache read so a cached issue renders on the first frame.
enum IssueCacheLookup {
    static func cached(_ date: String) -> Issue? { IssueCache().loadIssue(date) }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

struct SectionHeader: View {
    var title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(.handZh(30))
            .foregroundStyle(Color.grammarRed)
            .padding(.top, 36)
            .padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

struct OfflineButton: View {
    var date: String
    @Environment(IssueStore.self) private var store

    var body: some View {
        if let progress = store.downloads[date] {
            ProgressView(value: progress)
                .progressViewStyle(.circular)
                .tint(.grammarRed)
                .accessibilityLabel("正在下载")
        } else if store.isOffline(date) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color(Ink.idiom))
                .accessibilityLabel("已离线保存")
        } else {
            Button {
                Task { await store.saveOffline(date) }
            } label: {
                Image(systemName: "arrow.down.circle")
            }
            .accessibilityLabel("离线保存（含音频）")
        }
    }
}
