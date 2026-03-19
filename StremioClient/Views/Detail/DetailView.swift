import SwiftUI

struct DetailView: View {
    let item: MetaItem

    @Environment(AddonManager.self) private var addonManager
    @Environment(AppState.self) private var appState
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(WatchHistoryManager.self) private var watchHistory
    @State private var fullMeta: MetaItem?
    @State private var streams: [StreamItem] = []
    @State private var isLoadingStreams = false
    @State private var showStreamPicker = false
    @State private var showPlayer = false
    @State private var selectedStream: StreamItem?
    @State private var isLoadingMeta = true
    @State private var noStreamFound = false
    @State private var noStreamsAtAll = false
    @State private var selectedSeason: Int = 1
    @State private var loadingEpisode: MetaItem.Video?   // which episode row is spinning
    @State private var activeEpisode: MetaItem.Video?    // episode being played (for PlayerView)

    private var displayItem: MetaItem { fullMeta ?? item }

    // MARK: - Computed helpers for series

    private var availableSeasons: [Int] {
        let seasons = displayItem.videos?.compactMap(\.season) ?? []
        let unique = Array(Set(seasons))
        // Season 0 = specials/extras — sort real seasons first, then season 0 at end
        let real = unique.filter { $0 > 0 }.sorted()
        let specials = unique.filter { $0 == 0 }
        return real + specials
    }

    private var episodesInSelectedSeason: [MetaItem.Video] {
        (displayItem.videos ?? [])
            .filter { $0.season == selectedSeason }
            .sorted { ($0.episode ?? 0) < ($1.episode ?? 0) }
    }

    /// The first real episode of the series (S1E1), skipping season 0 specials.
    private var firstEpisode: MetaItem.Video? {
        (displayItem.videos ?? [])
            .filter { ($0.season ?? 0) > 0 && $0.episode != nil }
            .sorted { a, b in
                if a.season! != b.season! { return a.season! < b.season! }
                return a.episode! < b.episode!
            }
            .first
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heroSection
                    infoSection
                    if displayItem.type == "series", let videos = displayItem.videos, !videos.isEmpty {
                        episodesSection(videos: videos)
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await loadMeta() }
        .sheet(isPresented: $showStreamPicker) {
            StreamPickerView(streams: streams, meta: displayItem) { stream in
                selectedStream = stream
                showPlayer = true
            }
        }
        .fullScreenCover(isPresented: $showPlayer) {
            if let stream = selectedStream {
                PlayerView(stream: stream, title: displayItem.name, meta: displayItem, episode: activeEpisode)
            }
        }
        .alert("No Suitable Stream Found", isPresented: $noStreamFound) {
            Button("Browse All Streams") { showStreamPicker = true }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Streams were found but none are cached on Real-Debrid. Browse manually to pick one.")
        }
        .alert("No Streams Found", isPresented: $noStreamsAtAll) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("No streams are available for this title from your installed addons. Try adding more addons in the Addons tab.")
        }
        .onChange(of: availableSeasons) { _, seasons in
            // Only update if current selection isn't in the list yet (initial load)
            if !seasons.contains(selectedSeason), let first = seasons.first {
                selectedSeason = first
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        // Content VStack sits in the normal flow; the image is a .background so it
        // never participates in the parent layout and cannot distort the content width.
        VStack(alignment: .leading, spacing: 12) {
            Text(displayItem.name)
                .font(.title.bold())
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)

            HStack(spacing: 8) {
                if let rating = displayItem.imdbRating {
                    Label(rating, systemImage: "star.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.yellow)
                }
                Text(displayItem.displayYear).font(.caption).foregroundStyle(Theme.textSecondary)
                if let runtime = displayItem.runtime {
                    Text(runtime).font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }

            HStack(spacing: 10) {
                // Smart Play — for series defaults to S1E1; for movies picks best stream.
                Button {
                    Task { await smartPlay(episode: displayItem.type == "series" ? firstEpisode : nil) }
                } label: {
                    Group {
                        if isLoadingStreams && loadingEpisode == nil {
                            HStack(spacing: 8) {
                                ProgressView().tint(.white)
                                Text("Finding best stream…").font(.headline)
                            }
                        } else {
                            Label(smartPlayLabel, systemImage: appState.isRealDebridConnected ? "wand.and.stars" : "play.fill")
                                .font(.headline)
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(isLoadingStreams)

                // Heart / Watchlist
                let inList = watchHistory.isInWatchlist(displayItem.id)
                Button {
                    if inList { watchHistory.removeFromWatchlist(displayItem.id) }
                    else { watchHistory.saveToWatchlist(displayItem) }
                } label: {
                    Image(systemName: inList ? "heart.fill" : "heart")
                        .font(.headline)
                        .foregroundStyle(inList ? .pink : Theme.textPrimary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // Manual stream picker
                Button {
                    Task {
                        let ep = displayItem.type == "series" ? firstEpisode : nil
                        await loadStreams(for: ep)
                        showStreamPicker = true
                    }
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(isLoadingStreams)

                // Download button — for movies; for series, use per-episode buttons below
                if displayItem.type == "movie" {
                    let dl = downloadManager.existingDownload(metaId: item.id)
                    downloadButton(existing: dl) {
                        Task { await startDownload(episode: nil) }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 340, alignment: .bottomLeading)
        .background {
            AsyncImage(url: displayItem.backgroundURL ?? displayItem.posterURL) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: Theme.surface
                }
            }
            .clipped()
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: Theme.background.opacity(0.7), location: 0.6),
                        .init(color: Theme.background, location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
    }

    private var smartPlayLabel: String {
        let verb = appState.isRealDebridConnected ? "Smart Play" : "Play"
        if displayItem.type == "series", let ep = firstEpisode,
           let s = ep.season, let e = ep.episode {
            return "\(verb) S\(s)E\(e)"
        }
        return verb
    }

    // MARK: - Info

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let desc = displayItem.description {
                Text(desc)
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(6)
            }

            if let genres = displayItem.allGenres, !genres.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(genres, id: \.self) { genre in
                            Text(genre)
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Theme.surface)
                                .clipShape(Capsule())
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                }
            }

            if let director = displayItem.director, !director.isEmpty {
                creditRow(label: "Director", names: director)
            }
            if let cast = displayItem.cast, !cast.isEmpty {
                creditRow(label: "Cast", names: Array(cast.prefix(5)))
            }
        }
        .padding()
    }

    private func creditRow(label: String, names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.bold()).foregroundStyle(Theme.textSecondary)
            Text(names.joined(separator: ", ")).font(.caption).foregroundStyle(Theme.textPrimary)
        }
    }

    // MARK: - Episodes

    private func episodesSection(videos: [MetaItem.Video]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Episodes")
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal)

            // Season picker — only shown when there are multiple seasons
            if availableSeasons.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availableSeasons, id: \.self) { season in
                            Button {
                                selectedSeason = season
                            } label: {
                                Text(season == 0 ? "Specials" : "Season \(season)")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedSeason == season ? Theme.accent : Theme.surface)
                                    .clipShape(Capsule())
                                    .foregroundStyle(selectedSeason == season ? .white : Theme.textPrimary)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }

            ForEach(episodesInSelectedSeason) { video in
                Button {
                    Task {
                        streams = []
                        loadingEpisode = video
                        await smartPlay(episode: video)
                        loadingEpisode = nil
                    }
                } label: {
                    episodeRow(video)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom)
    }

    private func episodeRow(_ video: MetaItem.Video) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: video.thumbnail.flatMap(URL.init)) { phase in
                if case .success(let img) = phase { img.resizable().scaledToFill() }
                else { Theme.surface }
            }
            .frame(width: 100, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .center) {
                if loadingEpisode == video {
                    ZStack {
                        Color.black.opacity(0.5)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        ProgressView().tint(.white)
                    }
                } else {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(radius: 4)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                if let s = video.season, let e = video.episode {
                    Text("S\(s)E\(e)").font(.caption.bold()).foregroundStyle(Theme.accent)
                }
                Text(video.displayName).font(.subheadline).foregroundStyle(Theme.textPrimary).lineLimit(1)
                if let overview = video.overview {
                    Text(overview).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(2)
                }
            }
            Spacer()

            // Per-episode download button
            let dl = downloadManager.existingDownload(
                metaId: item.id, season: video.season, episode: video.episode
            )
            downloadButton(existing: dl) {
                Task { await startDownload(episode: video) }
            }
            .padding(.trailing, 4)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// Compact download icon button — shows state (idle / downloading / done).
    @ViewBuilder
    private func downloadButton(existing: Download?, action: @escaping () -> Void) -> some View {
        switch existing?.status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
        case .downloading:
            ZStack {
                CircularProgressView(progress: existing?.progress ?? 0)
                    .frame(width: 28, height: 28)
                Image(systemName: "stop.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Theme.textSecondary)
            }
        case .failed:
            Button(action: action) {
                Image(systemName: "arrow.clockwise.circle")
                    .font(.title3)
                    .foregroundStyle(.red)
            }
        default:
            Button(action: action) {
                Image(systemName: "arrow.down.circle")
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - Stream loading

    /// Loads streams for a movie, or for a specific TV episode using `{imdbId}:{season}:{episode}`.
    private func loadStreams(for episode: MetaItem.Video? = nil) async {
        guard streams.isEmpty else { return }
        isLoadingStreams = true
        guard let type = item.type else { isLoadingStreams = false; return }

        // Cinemeta video IDs are already in {imdbId}:{season}:{episode} format (e.g. tt0386676:1:1).
        // Use video.id directly; fall back to constructing from season/episode numbers.
        let streamId: String
        if let ep = episode {
            if ep.id.contains(":") {
                streamId = ep.id
            } else if let season = ep.season, let epNum = ep.episode {
                streamId = "\(item.id):\(season):\(epNum)"
            } else {
                streamId = item.id
            }
        } else {
            streamId = item.id
        }

        print("[Streams] Fetching id=\(streamId)")
        streams = (try? await AddonClient.shared.fetchStreams(
            from: addonManager.addons, type: type, id: streamId
        )) ?? []
        isLoadingStreams = false
    }

    private func loadMeta() async {
        isLoadingMeta = true
        guard let type = item.type else { isLoadingMeta = false; return }
        let metaAddon = addonManager.addons.first {
            $0.manifest.supportsMeta && $0.manifest.types.contains(type)
        }
        if let addon = metaAddon {
            fullMeta = try? await AddonClient.shared.fetchMeta(addon: addon, type: type, id: item.id)
        }
        if let first = availableSeasons.first { selectedSeason = first }
        isLoadingMeta = false
    }

    /// Fetches streams and auto-selects the best one based on quality/size/RD cache.
    private func smartPlay(episode: MetaItem.Video? = nil) async {
        await loadStreams(for: episode)

        print("[SmartPlay] Total streams: \(streams.count)")
        for s in streams {
            let parsed = StreamSelector.parse(s)
            print("[SmartPlay] \(s.name ?? "?") | \(s.title ?? "?") | url=\(s.url ?? "nil") | q=\(parsed?.qualityP ?? 0)p | size=\(parsed?.sizeGB.map { "\($0)GB" } ?? "?") | RD=\(parsed?.isRDCached ?? false)")
        }

        if streams.isEmpty {
            print("[SmartPlay] No streams returned by any addon")
            noStreamsAtAll = true
            return
        }

        if appState.isRealDebridConnected {
            if let best = StreamSelector.selectBest(from: streams) {
                print("[SmartPlay] Selected: \(best.name ?? "?") | \(best.url ?? "nil")")
                // Record watch event before launching player
                watchHistory.record(displayItem, season: episode?.season, episode: episode?.episode)
                selectedStream = best
                activeEpisode = episode
                showPlayer = true
            } else {
                print("[SmartPlay] Streams found but none meet criteria — offering manual browse")
                noStreamFound = true
            }
        } else {
            // Record event when user is about to pick a stream manually
            watchHistory.record(displayItem, season: episode?.season, episode: episode?.episode)
            activeEpisode = episode
            showStreamPicker = true
        }
    }

    /// Fetches streams, picks the best one, resolves the redirect, and starts a background download.
    private func startDownload(episode: MetaItem.Video? = nil) async {
        streams = []
        await loadStreams(for: episode)
        guard let best = StreamSelector.selectBest(from: streams) else {
            print("[Download] No suitable stream found")
            return
        }
        await downloadManager.startDownload(meta: displayItem, stream: best, episode: episode)
    }
}

// MARK: - Circular progress indicator for download rows

private struct CircularProgressView: View {
    let progress: Double
    var body: some View {
        Circle()
            .stroke(Color.gray.opacity(0.3), lineWidth: 3)
            .overlay(
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.2), value: progress)
            )
    }
}
