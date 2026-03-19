import SwiftUI
import UIKit
import AVKit
import AVFoundation
import Combine

// MARK: - Video surface (bare AVPlayerLayer, no built-in controls)

private class _PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}

private struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> _PlayerUIView {
        let v = _PlayerUIView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspect
        v.backgroundColor = .black
        return v
    }
    func updateUIView(_ uiView: _PlayerUIView, context: Context) {
        uiView.playerLayer.player = player
    }
}

// MARK: - AirPlay picker button

private struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = .white
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

// MARK: - PlayerView

struct PlayerView: View {
    let stream: StreamItem
    let title: String
    var meta: MetaItem? = nil
    var episode: MetaItem.Video? = nil
    /// All episodes in the series sorted by season/episode — drives auto-play next.
    var allEpisodes: [MetaItem.Video] = []

    @Environment(\.dismiss) private var dismiss
    @Environment(WatchHistoryManager.self) private var watchHistory
    @Environment(AddonManager.self) private var addonManager
    @Environment(AppState.self) private var appState

    // Core playback
    @State private var player: AVPlayer?
    @State private var currentEpisode: MetaItem.Video?
    @State private var errorMessage: String?
    @State private var setupTask: Task<Void, Never>?
    @State private var timeObserver: Any?

    // Playback state (fed by time observer)
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isPlaying = false

    // Scrubber
    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0

    // Controls visibility
    @State private var showControls = true
    @State private var hideTask: Task<Void, Never>?

    // Speed
    @State private var playbackRate: Float = 1.0
    @State private var showSpeedMenu = false

    // Audio / Subtitle tracks
    @State private var subtitleOptions: [AVMediaSelectionOption] = []
    @State private var audioOptions: [AVMediaSelectionOption] = []
    @State private var selectedSubtitle: AVMediaSelectionOption?
    @State private var selectedAudio: AVMediaSelectionOption?
    @State private var showTrackPicker = false

    // Auto-play next episode
    @State private var showNextUp = false
    @State private var nextUpCountdown = 5
    @State private var countdownTask: Task<Void, Never>?
    @State private var endObserver: NSObjectProtocol?

    // "Are you still watching?" (90 min idle)
    @State private var lastInteraction = Date()
    @State private var stillWatchingTask: Task<Void, Never>?
    @State private var showStillWatching = false

    // MARK: - Computed

    private var nextEpisode: MetaItem.Video? {
        guard let ep = currentEpisode ?? episode,
              let s = ep.season, let e = ep.episode else { return nil }
        // Try same season next episode, then first episode of next season
        return allEpisodes.first { $0.season == s && $0.episode == e + 1 }
            ?? allEpisodes.first { $0.season == s + 1 && $0.episode == 1 }
    }

    private var speedLabel: String {
        switch playbackRate {
        case 0.5:  return "0.5×"
        case 0.75: return "0.75×"
        case 1.25: return "1.25×"
        case 1.5:  return "1.5×"
        case 2.0:  return "2×"
        default:   return "1×"
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoSurface(player: player)
                    .ignoresSafeArea()
            }

            if player == nil && errorMessage == nil {
                ProgressView("Loading stream…")
                    .foregroundStyle(.white)
            }

            if let error = errorMessage {
                errorView(error)
            }

            if errorMessage == nil {
                controlsOverlay
            }

            if showNextUp, let next = nextEpisode {
                nextUpCard(next)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if showStillWatching {
                stillWatchingOverlay
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.3), value: showNextUp)
        .animation(.easeInOut(duration: 0.2), value: showStillWatching)
        .onAppear {
            currentEpisode = episode
            setupTask = Task { await setupPlayer(for: stream) }
            scheduleHide()
            startStillWatchingMonitor()
        }
        .onDisappear { cleanup() }
        .onReceive(Timer.publish(every: 10, on: .main, in: .common).autoconnect()) { _ in
            saveProgress()
        }
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
        .statusBarHidden()
    }

    // MARK: - Controls overlay

    @ViewBuilder
    private var controlsOverlay: some View {
        ZStack {
            if showControls {
                VStack {
                    LinearGradient(colors: [.black.opacity(0.65), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 130)
                    Spacer()
                    LinearGradient(colors: [.clear, .black.opacity(0.75)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 150)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                topBar
                    .opacity(showControls ? 1 : 0)

                Spacer()

                centerControls
                    .opacity(showControls ? 1 : 0)

                Spacer()

                bottomBar
                    .opacity(showControls ? 1 : 0)
            }
            .animation(.easeInOut(duration: 0.25), value: showControls)
        }
        .contentShape(Rectangle())
        .onTapGesture { bumpControls() }
        .sheet(isPresented: $showTrackPicker) { trackPickerSheet }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                saveProgress(); setupTask?.cancel(); player?.pause(); dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.4))
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let ep = currentEpisode ?? episode, let s = ep.season, let e = ep.episode {
                    Text("S\(s)E\(e) · \(ep.displayName)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }

            Spacer()

            AirPlayButton()
                .frame(width: 36, height: 36)

            if !subtitleOptions.isEmpty || audioOptions.count > 1 {
                Button { showTrackPicker.toggle(); bumpControls() } label: {
                    Image(systemName: "text.bubble")
                        .font(.body)
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.black.opacity(0.4))
                        .clipShape(Circle())
                }
            }

            Button { showSpeedMenu.toggle(); bumpControls() } label: {
                Text(speedLabel)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.4))
                    .clipShape(Capsule())
            }
            .confirmationDialog("Playback Speed", isPresented: $showSpeedMenu, titleVisibility: .visible) {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0] as [Double], id: \.self) { rate in
                    Button(rate == 1.0 ? "Normal (1×)" : "\(rate)×") {
                        playbackRate = Float(rate)
                        if isPlaying { player?.rate = playbackRate }
                        bumpControls()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 52)
    }

    private var centerControls: some View {
        HStack(spacing: 52) {
            Button { skip(-10) } label: {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.white)
            }

            Button { togglePlayPause() } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 50, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
            }

            Button { skip(10) } label: {
                Image(systemName: "goforward.10")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
            HStack {
                Text(formatTime(isScrubbing ? scrubValue : currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)
                Spacer()
                if duration > 0 {
                    Text(formatTime(duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            scrubber
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 44)
    }

    // MARK: - Scrubber

    private var scrubber: some View {
        GeometryReader { geo in
            let progress = duration > 0
                ? CGFloat((isScrubbing ? scrubValue : currentTime) / duration)
                : 0
            let trackH: CGFloat = isScrubbing ? 5 : 3

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.3))
                    .frame(height: trackH)

                Capsule()
                    .fill(Color.white)
                    .frame(width: max(0, geo.size.width * progress), height: trackH)

                if isScrubbing {
                    Circle()
                        .fill(.white)
                        .frame(width: 18, height: 18)
                        .offset(x: max(0, geo.size.width * progress - 9))
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        if !isScrubbing { isScrubbing = true; hideTask?.cancel() }
                        let ratio = max(0, min(1, val.location.x / geo.size.width))
                        scrubValue = ratio * duration
                    }
                    .onEnded { val in
                        let ratio = max(0, min(1, val.location.x / geo.size.width))
                        player?.seek(
                            to: CMTime(seconds: ratio * duration, preferredTimescale: 600),
                            toleranceBefore: .zero, toleranceAfter: .zero
                        )
                        isScrubbing = false
                        scheduleHide()
                    }
            )
        }
        .frame(height: 28)
        .animation(.easeInOut(duration: 0.12), value: isScrubbing)
    }

    // MARK: - Track picker sheet

    private var trackPickerSheet: some View {
        NavigationStack {
            List {
                if !subtitleOptions.isEmpty {
                    Section("Subtitles") {
                        Button {
                            disableSubtitles()
                            showTrackPicker = false
                        } label: {
                            HStack {
                                Text("Off")
                                Spacer()
                                if selectedSubtitle == nil {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                }
                            }
                        }
                        .foregroundStyle(Theme.textPrimary)

                        ForEach(subtitleOptions, id: \.self) { opt in
                            Button {
                                selectSubtitle(opt)
                                showTrackPicker = false
                            } label: {
                                HStack {
                                    Text(opt.displayName(with: .current))
                                    Spacer()
                                    if selectedSubtitle == opt {
                                        Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                    }
                                }
                            }
                            .foregroundStyle(Theme.textPrimary)
                        }
                    }
                }

                if audioOptions.count > 1 {
                    Section("Audio") {
                        ForEach(audioOptions, id: \.self) { opt in
                            Button {
                                selectAudio(opt)
                                showTrackPicker = false
                            } label: {
                                HStack {
                                    Text(opt.displayName(with: .current))
                                    Spacer()
                                    if selectedAudio == opt {
                                        Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                    }
                                }
                            }
                            .foregroundStyle(Theme.textPrimary)
                        }
                    }
                }
            }
            .navigationTitle("Audio & Subtitles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showTrackPicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Next Up card

    private func nextUpCard(_ next: MetaItem.Video) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 10) {
                    Text("Next up in \(nextUpCountdown)s")
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.7))

                    if let s = next.season, let e = next.episode {
                        Text("S\(s)E\(e) · \(next.displayName)")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack(spacing: 10) {
                        Button("Cancel") {
                            countdownTask?.cancel()
                            showNextUp = false
                        }
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))

                        Button {
                            countdownTask?.cancel()
                            showNextUp = false
                            Task { await playNext(next) }
                        } label: {
                            Label("Play Next", systemImage: "play.fill")
                                .font(.subheadline.bold())
                                .foregroundStyle(.black)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(.white)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(18)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.trailing, 20)
                .padding(.bottom, 60)
            }
        }
    }

    // MARK: - Still watching overlay

    private var stillWatchingOverlay: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.7))
                Text("Still watching?")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Button("Continue Watching") { resumeFromStillWatching() }
                    .font(.headline)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(.white)
                    .clipShape(Capsule())
            }
        }
        .onTapGesture { resumeFromStillWatching() }
    }

    private func resumeFromStillWatching() {
        showStillWatching = false
        player?.rate = playbackRate
        isPlaying = true
        lastInteraction = Date()
        startStillWatchingMonitor()
        bumpControls()
    }

    // MARK: - Error view

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)
            Text("Playback Failed")
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text(error)
                .font(.caption)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Close") { setupTask?.cancel(); dismiss() }
                .foregroundStyle(.white)
                .padding(.top, 8)
        }
    }

    // MARK: - Control actions

    private func bumpControls() {
        showControls = true
        lastInteraction = Date()
        scheduleHide()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            showControls = false
        }
    }

    private func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.rate = playbackRate
            isPlaying = true
        }
        bumpControls()
    }

    private func skip(_ seconds: Double) {
        guard let player else { return }
        let target = max(0, min(duration, currentTime + seconds))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        bumpControls()
    }

    // MARK: - Track selection

    private func selectSubtitle(_ opt: AVMediaSelectionOption) {
        guard let item = player?.currentItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible)
        else { return }
        item.select(opt, in: group)
        selectedSubtitle = opt
    }

    private func disableSubtitles() {
        guard let item = player?.currentItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible)
        else { return }
        item.select(nil, in: group)
        selectedSubtitle = nil
    }

    private func selectAudio(_ opt: AVMediaSelectionOption) {
        guard let item = player?.currentItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible)
        else { return }
        item.select(opt, in: group)
        selectedAudio = opt
    }

    // MARK: - Still watching monitor

    private func startStillWatchingMonitor() {
        stillWatchingTask?.cancel()
        stillWatchingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                guard isPlaying else { continue }
                if Date().timeIntervalSince(lastInteraction) > 5400 {   // 90 min
                    player?.pause()
                    isPlaying = false
                    showStillWatching = true
                    return
                }
            }
        }
    }

    // MARK: - Auto-play next episode

    private func setupEndObserver(for item: AVPlayerItem) {
        if let old = endObserver { NotificationCenter.default.removeObserver(old) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in handlePlaybackEnded() }
    }

    private func handlePlaybackEnded() {
        guard let next = nextEpisode else {
            saveProgress()
            dismiss()
            return
        }
        showNextUp = true
        nextUpCountdown = 5
        countdownTask?.cancel()
        countdownTask = Task {
            for remaining in stride(from: 4, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                nextUpCountdown = remaining
            }
            guard !Task.isCancelled else { return }
            showNextUp = false
            await playNext(next)
        }
    }

    private func playNext(_ next: MetaItem.Video) async {
        guard let meta else { return }
        saveProgress()
        currentEpisode = next

        guard let type = meta.type else { return }
        let streamId: String
        if next.id.contains(":") {
            streamId = next.id
        } else if let s = next.season, let e = next.episode {
            streamId = "\(meta.id):\(s):\(e)"
        } else {
            streamId = meta.id
        }

        let streams = (try? await AddonClient.shared.fetchStreams(
            from: addonManager.addons, type: type, id: streamId
        )) ?? []

        guard !streams.isEmpty else { return }
        let best = appState.isRealDebridConnected
            ? StreamSelector.selectBest(from: streams)
            : streams.first(where: { $0.isDirectPlay })
        guard let best else { return }

        watchHistory.record(meta, season: next.season, episode: next.episode)
        tearDownPlayer()
        await setupPlayer(for: best)
    }

    // MARK: - Progress

    private func saveProgress() {
        guard let meta, let player else { return }
        let seconds = player.currentTime().seconds
        guard seconds.isFinite, seconds > 5 else { return }
        var dur = player.currentItem?.duration.seconds ?? 0
        if !dur.isFinite || dur < 10 {
            dur = (meta.type ?? "movie") == "movie" ? 7200 : 2700
        }
        let ep = currentEpisode ?? episode
        watchHistory.updateProgress(
            for: meta, season: ep?.season, episode: ep?.episode,
            episodeName: ep?.displayName, seconds: seconds, duration: dur
        )
    }

    // MARK: - Lifecycle helpers

    private func tearDownPlayer() {
        if let token = timeObserver, let p = player { p.removeTimeObserver(token); timeObserver = nil }
        if let obs = endObserver { NotificationCenter.default.removeObserver(obs); endObserver = nil }
        player?.pause()
        player = nil
        currentTime = 0
        duration = 0
        isPlaying = false
        subtitleOptions = []
        audioOptions = []
        selectedSubtitle = nil
        selectedAudio = nil
        errorMessage = nil
    }

    private func cleanup() {
        saveProgress()
        setupTask?.cancel()
        hideTask?.cancel()
        countdownTask?.cancel()
        stillWatchingTask?.cancel()
        tearDownPlayer()
    }

    // MARK: - Player setup

    private func setupPlayer(for stream: StreamItem) async {
        guard let url = stream.streamURL else {
            errorMessage = "Invalid stream URL"
            return
        }

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        let playbackURL: URL
        if url.isFileURL {
            guard FileManager.default.fileExists(atPath: url.path) else {
                errorMessage = "Downloaded file not found. Please delete it and re-download."
                return
            }
            playbackURL = url
        } else {
            let resolved = await RedirectResolver.resolve(url)
            guard !Task.isCancelled else { return }
            guard resolved != url else {
                errorMessage = "Could not resolve stream URL. Try a different stream."
                return
            }
            playbackURL = resolved
        }

        let asset = AVURLAsset(url: playbackURL, options: [
            "AVURLAssetHTTPHeaderFieldsKey": [
                "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
            ]
        ])
        let item = AVPlayerItem(asset: asset)

        // Seek to resume position
        let ep = currentEpisode ?? episode
        if let meta, let secs = resumeSeconds(for: meta, episode: ep), secs > 5 {
            await item.seek(to: CMTime(seconds: secs, preferredTimescale: 600),
                           toleranceBefore: .zero, toleranceAfter: .zero)
        }

        let avPlayer = AVPlayer(playerItem: item)
        player = avPlayer

        // Periodic time observer — runs on main queue, safe to update @State
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak avPlayer] time in
            guard let avPlayer else { return }
            if !self.isScrubbing { self.currentTime = time.seconds }
            let d = avPlayer.currentItem?.duration.seconds ?? 0
            if d.isFinite && d > 0 { self.duration = d }
            self.isPlaying = avPlayer.timeControlStatus == .playing
        }

        setupEndObserver(for: item)
        loadTracks(from: item)

        // Wait for readyToPlay / failed
        for await (status, error) in playerStatusStream(item: item) {
            switch status {
            case .readyToPlay:
                avPlayer.rate = playbackRate
                isPlaying = true
            case .failed:
                errorMessage = error?.localizedDescription ?? "Unknown playback error"
            default: break
            }
        }
    }

    private func playerStatusStream(item: AVPlayerItem) -> AsyncStream<(AVPlayerItem.Status, (any Error)?)> {
        AsyncStream { cont in
            let obs = item.observe(\.status, options: [.initial, .new]) { observed, _ in
                switch observed.status {
                case .readyToPlay: cont.yield((.readyToPlay, nil)); cont.finish()
                case .failed:      cont.yield((.failed, observed.error)); cont.finish()
                default: break
                }
            }
            cont.onTermination = { _ in obs.invalidate() }
        }
    }

    private func loadTracks(from item: AVPlayerItem) {
        let asset = item.asset
        if let g = asset.mediaSelectionGroup(forMediaCharacteristic: .legible) {
            subtitleOptions = g.options
        }
        if let g = asset.mediaSelectionGroup(forMediaCharacteristic: .audible) {
            audioOptions = g.options
            selectedAudio = item.currentMediaSelection.selectedMediaOption(in: g)
        }
    }

    private func resumeSeconds(for meta: MetaItem, episode: MetaItem.Video?) -> Double? {
        let pct = watchHistory.completionPercent(metaId: meta.id, season: episode?.season, episode: episode?.episode)
        guard pct > 0.03 && pct < 0.92 else { return nil }
        let pid = PlaybackProgress.id(metaId: meta.id, season: episode?.season, episode: episode?.episode)
        return watchHistory.progressMap[pid]?.resumeSeconds
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let t = Int(seconds)
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
