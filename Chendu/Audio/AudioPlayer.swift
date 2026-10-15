import AVFoundation
import MediaPlayer
import Observation
import UIKit

@MainActor
@Observable
final class AudioPlayer {
    struct NowPlaying: Equatable {
        var date: String
        var title: String
        var track: AudioTrack
    }

    static let shared = AudioPlayer()

    private(set) var nowPlaying: NowPlaying?
    private(set) var isPlaying = false
    private(set) var isLoading = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var error: String?
    var rate: Float = 1.0 {
        didSet { if isPlaying { player?.rate = rate }; updateNowPlayingInfo() }
    }

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    @ObservationIgnored private var remoteConfigured = false
    @ObservationIgnored private var loadToken = UUID()

    private init() {}

    func isCurrent(_ date: String, _ track: AudioTrack) -> Bool {
        nowPlaying?.date == date && nowPlaying?.track.id == track.id
    }

    func toggle(issue: Issue, track: AudioTrack, store: IssueStore) {
        if isCurrent(issue.date, track) {
            togglePlayPause()
        } else {
            Task { await play(issue: issue, track: track, store: store) }
        }
    }

    func play(issue: Issue, track: AudioTrack, store: IssueStore) async {
        let token = UUID()
        loadToken = token
        stopPlayer()
        nowPlaying = NowPlaying(date: issue.date, title: issue.title, track: track)
        error = nil
        isLoading = true
        currentTime = 0
        duration = 0

        let url: URL
        if let local = store.localAudio(issue.date, track) {
            url = local
        } else if SiteClient.shared.usesProxy {
            // AVPlayer ignores URLSession proxies, so fetch through the session first.
            do {
                url = try await store.downloadAudio(issue.date, track)
            } catch {
                guard loadToken == token else { return }
                self.error = IssueStore.describe(error)
                isLoading = false
                return
            }
        } else {
            url = store.remoteURL(issue.date, track.file)
            Task { _ = try? await store.downloadAudio(issue.date, track) }
        }
        guard loadToken == token else { return }

        activateSession()
        configureRemoteCommands()
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true
        self.player = player
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time) }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isPlaying = false
                self?.player?.seek(to: .zero)
                self?.currentTime = 0
                self?.updateNowPlayingInfo()
            }
        }
        player.playImmediately(atRate: rate)
        isPlaying = true
        updateNowPlayingInfo()

        if let d = try? await item.asset.load(.duration), d.isNumeric, loadToken == token {
            duration = d.seconds
            updateNowPlayingInfo()
        }
    }

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            activateSession()
            player.playImmediately(atRate: rate)
            isPlaying = true
        }
        updateNowPlayingInfo()
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        let t = max(0, min(seconds, duration > 0 ? duration : seconds))
        currentTime = t
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        updateNowPlayingInfo()
    }

    func skip(_ delta: Double) { seek(to: currentTime + delta) }

    func stop() {
        loadToken = UUID()
        stopPlayer()
        nowPlaying = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func stopPlayer() {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        player?.pause()
        player = nil
        isPlaying = false
        isLoading = false
    }

    private func tick(_ time: CMTime) {
        guard let player else { return }
        currentTime = time.seconds.isFinite ? time.seconds : 0
        if let item = player.currentItem, item.duration.isNumeric { duration = item.duration.seconds }
        let loading = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        if loading != isLoading { isLoading = loading }
        if let failure = player.currentItem?.error {
            error = IssueStore.describe(failure)
            isPlaying = false
        }
    }

    // MARK: system integration

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
        try? session.setActive(true)
        if interruptionObserver == nil {
            interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
                let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
                MainActor.assumeIsolated {
                    if type == .began { self?.isPlaying = false; self?.updateNowPlayingInfo() }
                }
            }
        }
    }

    private func configureRemoteCommands() {
        guard !remoteConfigured else { return }
        remoteConfigured = true
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { if self?.isPlaying == false { self?.togglePlayPause() } }
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { if self?.isPlaying == true { self?.togglePlayPause() } }
            return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.togglePlayPause() }
            return .success
        }
        c.skipForwardCommand.preferredIntervals = [15]
        c.skipForwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.skip(15) }
            return .success
        }
        c.skipBackwardCommand.preferredIntervals = [15]
        c.skipBackwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.skip(-15) }
            return .success
        }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            MainActor.assumeIsolated { self?.seek(to: e.positionTime) }
            return .success
        }
        c.nextTrackCommand.isEnabled = false
        c.previousTrackCommand.isEnabled = false
    }

    private func updateNowPlayingInfo() {
        guard let np = nowPlaying else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: np.title,
            MPMediaItemPropertyArtist: "晨读 · \(np.track.label)",
            MPMediaItemPropertyAlbumTitle: "晨读 \(np.date)",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let art = UIImage(named: "Artwork") {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: art.size) { _ in art }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

/// Speaks single words and example sentences (the site's 🔊 buttons).
@MainActor
final class Speaker {
    static let shared = Speaker()
    private let synth = AVSpeechSynthesizer()

    func say(_ text: String) {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "en-US")
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        synth.speak(u)
    }
}
