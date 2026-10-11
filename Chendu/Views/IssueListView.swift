import SwiftUI

struct IssueListView: View {
    @Environment(IssueStore.self) private var store
    @State private var path: [ReaderRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    masthead
                    statusBanner
                    if let latest = store.summaries.first {
                        NavigationLink(value: ReaderRoute(date: latest.date)) { HeroCard(issue: latest) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("issue-\(latest.date)")
                    } else if store.isRefreshing {
                        ProgressView("正在取往期…").frame(maxWidth: .infinity).padding(.top, 60).tint(.grammarRed)
                    } else {
                        ContentUnavailableView("还没有期刊", systemImage: "book.closed", description: Text("下拉刷新试试。"))
                            .padding(.top, 40)
                    }
                    if store.summaries.count > 1 {
                        Text("往期")
                            .font(.handZh(30))
                            .foregroundStyle(Color.grammarRed)
                            .padding(.top, 36)
                            .padding(.bottom, 4)
                        ForEach(store.summaries.dropFirst()) { s in
                            NavigationLink(value: ReaderRoute(date: s.date)) { ArchiveRow(issue: s) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("issue-\(s.date)")
                        }
                    }
                    Text("晨读 · 英文原文版权归原作者及媒体所有，仅节选用于个人学习")
                        .font(.caption2).foregroundStyle(Color.muted)
                        .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                        .padding(.vertical, 28)
                }
                .padding(.horizontal, 20)
            }
            .refreshable { await store.refreshIndex() }
            .background(PaperBackground())
            .navigationDestination(for: ReaderRoute.self) { r in ReaderView(date: r.date, focusNote: r.focusNote) }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) { MiniPlayerBar() }
        }
        .task { await store.refreshIndex() }
        .onChange(of: store.openLatestRequested) { _, requested in
            guard requested else { return }
            store.openLatestRequested = false
            Task {
                await store.refreshIndex()
                if let latest = store.summaries.first { path = [ReaderRoute(date: latest.date)] }
            }
        }
    }

    private var masthead: some View {
        VStack(spacing: 6) {
            Text("晨读").font(.handZh(56)).foregroundStyle(Color.grammarRed)
            Text("每天一篇真实英文 · 美股 × AI 轮换 · 手写批注精读")
                .font(.handZh(16)).foregroundStyle(Color.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var statusBanner: some View {
        if let err = store.lastError {
            Label(store.summaries.isEmpty ? err : "\(err)，显示的是离线缓存", systemImage: "icloud.slash")
                .font(.footnote)
                .foregroundStyle(Color.muted)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(Ink.leadBG)))
                .padding(.top, 8)
        }
    }
}

private struct HeroCard: View {
    var issue: IssueSummary
    @Environment(IssueStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TopicChip(key: issue.topic, label: issue.topicLabel)
                Text("最新一期 · \(DateText.short(issue.date))").font(.handZh(17)).foregroundStyle(Color.muted)
                Spacer()
                OfflineBadge(date: issue.date)
            }
            Text(issue.title)
                .font(.serif(24, weight: .semibold))
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.leading)
            Text(issue.zhTitle).font(.system(size: 15)).foregroundStyle(Color(red: 0.29, green: 0.27, blue: 0.24))
            if let lead = issue.lead, !lead.isEmpty {
                Text(lead).font(.handZh(18)).foregroundStyle(Color(Ink.leadInk)).lineLimit(5).lineSpacing(3)
            }
            HStack {
                Spacer()
                Text("开始读 →").font(.handZh(22)).foregroundStyle(Color.grammarRed)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white).shadow(color: Color(red: 0.24, green: 0.16, blue: 0.04).opacity(0.18), radius: 14, y: 8))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.rule))
        .padding(.top, 16)
    }
}

private struct ArchiveRow: View {
    var issue: IssueSummary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(issue.date.dropFirst(5))).font(.handEn(22)).foregroundStyle(Color.muted)
                TopicChip(key: issue.topic, label: issue.topicLabel)
            }
            .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(issue.title).font(.serif(17)).foregroundStyle(Color.ink).multilineTextAlignment(.leading)
                Text(issue.zhTitle).font(.system(size: 13)).foregroundStyle(Color.muted).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            OfflineBadge(date: issue.date)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle().stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundStyle(Color.rule).frame(height: 1)
        }
    }
}

private struct OfflineBadge: View {
    var date: String
    @Environment(IssueStore.self) private var store

    var body: some View {
        if store.isOffline(date) {
            Image(systemName: "arrow.down.circle.fill").font(.footnote).foregroundStyle(Color(Ink.idiom))
                .accessibilityLabel("已离线保存")
        } else if store.downloads[date] != nil {
            ProgressView().controlSize(.mini)
        }
    }
}
