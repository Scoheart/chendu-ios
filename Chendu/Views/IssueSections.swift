import SwiftUI

struct AudioSection: View {
    var issue: Issue
    @Environment(IssueStore.self) private var store
    private var player: AudioPlayer { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("听 · 朗读音频")
            Text("AI 合成朗读（TTS）。建议先不看原文盲听一遍，再对照原文跟读。")
                .font(.system(size: 14)).foregroundStyle(Color.muted)
            if issue.audio.isEmpty {
                Text("本期没有音频").font(.system(size: 14)).foregroundStyle(Color.muted)
            }
            ForEach(issue.audio) { track in
                let current = player.isCurrent(issue.date, track)
                Button {
                    player.toggle(issue: issue, track: track, store: store)
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(current ? Color.grammarRed : Color(Ink.leadBG))
                            if current && player.isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: current && player.isPlaying ? "pause.fill" : "play.fill")
                                    .foregroundStyle(current ? .white : Color.grammarRed)
                            }
                        }
                        .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.isSlow ? "🐢 \(track.label)" : "🎧 \(track.label)").font(.system(size: 16, weight: .medium))
                            Text(track.detail).font(.system(size: 12)).foregroundStyle(Color.muted)
                        }
                        Spacer()
                        if store.localAudio(issue.date, track) != nil {
                            Image(systemName: "arrow.down.circle.fill").foregroundStyle(Color(Ink.idiom)).font(.footnote)
                                .accessibilityLabel("已下载")
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.rule))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(track.isSlow ? "playSlow" : "playNormal")
                .accessibilityLabel("\(current && player.isPlaying ? "暂停" : "播放") \(track.label)")
            }
            if let err = player.error, player.nowPlaying?.date == issue.date {
                Text("音频播放失败：\(err)").font(.footnote).foregroundStyle(Color.grammarRed)
            }
        }
    }
}

struct WordsSection: View {
    var words: [ReviewWord]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("复习词")
            VStack(spacing: 0) {
                ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            SayButton(text: w.word)
                            Text(w.word).font(.serif(18, weight: .bold)).foregroundStyle(Color.ink)
                            Text(w.ipa).font(.system(size: 13)).foregroundStyle(Color.muted)
                            Spacer(minLength: 0)
                        }
                        Text(w.meaning).font(.system(size: 15)).foregroundStyle(Color.ink).padding(.leading, 30)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            SayButton(text: w.example)
                            Text(w.example).font(.serif(15).italic()).foregroundStyle(Color(red: 0.24, green: 0.23, blue: 0.2))
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if i < words.count - 1 { Divider().overlay(Color(red: 0.94, green: 0.92, blue: 0.87)) }
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.rule))
        }
    }
}

struct PatternsSection: View {
    var patterns: [SentencePattern]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("可以模仿的句型")
            ForEach(Array(patterns.enumerated()), id: \.offset) { i, p in
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(i + 1). \(p.pattern)").font(.serif(17, weight: .bold)).foregroundStyle(Color.ink)
                    if !p.patternZh.isEmpty { Text(p.patternZh).font(.system(size: 14)).foregroundStyle(Color.muted) }
                    if !p.source.isEmpty {
                        Text("原文：\(p.source)").font(.serif(14)).foregroundStyle(Color.muted)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        SayButton(text: p.model)
                        Text(p.model).font(.serif(17)).foregroundStyle(Color(Ink.vocab))
                    }
                    Text(p.modelZh).font(.system(size: 14)).foregroundStyle(Color(red: 0.29, green: 0.27, blue: 0.24))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.rule))
                .textSelection(.enabled)
            }
        }
    }
}

struct PodcastSection: View {
    var podcast: Podcast

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("延伸收听 · 播客")
            if let url = URL(string: podcast.url) {
                Link(destination: url) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(podcast.source).font(.system(size: 13)).opacity(0.7)
                        Text("\(podcast.title) ↗").font(.serif(20)).multilineTextAlignment(.leading)
                        Text(podcast.summary).font(.system(size: 14)).opacity(0.85).multilineTextAlignment(.leading)
                    }
                    .foregroundStyle(Color(red: 0.96, green: 0.94, blue: 1))
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(Ink.podcastBG)))
                }
                .accessibilityIdentifier("podcastLink")
            }
        }
    }
}

struct SayButton: View {
    var text: String
    var body: some View {
        Button { Speaker.shared.say(text) } label: {
            Image(systemName: "speaker.wave.2").font(.system(size: 13)).foregroundStyle(Color.muted)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("朗读 \(text)")
    }
}

/// Compact transport shown at the bottom while an issue's audio is loaded.
struct MiniPlayerBar: View {
    private var player: AudioPlayer { .shared }
    @State private var scrubbing: Double?

    var body: some View {
        if let np = player.nowPlaying {
            VStack(spacing: 6) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(np.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text("\(np.date) · \(np.track.label)").font(.system(size: 11)).foregroundStyle(Color.muted)
                    }
                    Spacer(minLength: 4)
                    Button { player.skip(-15) } label: { Image(systemName: "gobackward.15") }
                        .accessibilityLabel("后退 15 秒")
                    Button { player.togglePlayPause() } label: {
                        Group {
                            if player.isLoading { ProgressView() }
                            else { Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 30)) }
                        }
                        .frame(width: 32, height: 32)
                    }
                    .accessibilityIdentifier("miniPlayPause")
                    .accessibilityLabel(player.isPlaying ? "暂停" : "播放")
                    Button { player.skip(15) } label: { Image(systemName: "goforward.15") }
                        .accessibilityLabel("前进 15 秒")
                    Menu {
                        Picker("语速", selection: Binding(get: { player.rate }, set: { player.rate = $0 })) {
                            ForEach([Float(0.8), 1.0, 1.25, 1.5], id: \.self) { r in Text(String(format: "%.2g×", r)).tag(r) }
                        }
                        Button("关闭播放器", systemImage: "xmark") { player.stop() }
                    } label: {
                        Text(String(format: "%.2g×", player.rate)).font(.system(size: 12, weight: .semibold)).frame(minWidth: 30)
                    }
                }
                .tint(.grammarRed)
                HStack(spacing: 8) {
                    Text(clock(scrubbing ?? player.currentTime)).accessibilityIdentifier("elapsedTime")
                    Slider(value: Binding(
                        get: { scrubbing ?? player.currentTime },
                        set: { scrubbing = $0 }
                    ), in: 0...max(player.duration, 1)) { editing in
                        if !editing, let s = scrubbing { player.seek(to: s); scrubbing = nil }
                    }
                    .tint(.grammarRed)
                    Text(clock(player.duration))
                }
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Color.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) { Divider() }
        }
    }

    private func clock(_ t: Double) -> String {
        guard t.isFinite, t > 0 else { return "0:00" }
        let s = Int(t.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
