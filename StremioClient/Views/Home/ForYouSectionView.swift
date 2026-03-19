import SwiftUI

struct ForYouSectionView: View {
    @Environment(AddonManager.self) private var addonManager
    @Environment(AppState.self) private var appState
    @Environment(WatchHistoryManager.self) private var history

    @State private var tastePicks: [MetaItem] = []
    @State private var isLoadingTaste = false

    @State private var becauseRows: [(title: String, items: [MetaItem])] = []
    @State private var isLoadingBecause = false

    @State private var claudeRecs: [ClaudeRecommendation] = []
    @State private var isLoadingClaude = false
    @State private var claudeError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {

            // ── Continue Watching ──────────────────────────────────────────
            let continueItems = history.continueWatching
            if !continueItems.isEmpty {
                continueWatchingRow(items: continueItems)
            }

            if history.events.isEmpty {
                teaserRow
            } else {
                // ── Your Taste ────────────────────────────────────────────
                if isLoadingTaste {
                    skeletonRow(title: "Your Taste")
                } else if !tastePicks.isEmpty {
                    metaItemRow(title: "Your Taste", items: tastePicks)
                }

                // ── Because You Watched X ──────────────────────────────
                if isLoadingBecause && becauseRows.isEmpty {
                    skeletonRow(title: "Because You Watched…")
                }
                ForEach(becauseRows, id: \.title) { row in
                    metaItemRow(title: "Because you watched \(row.title)", items: row.items)
                }

                // ── Claude "Curated For You" ───────────────────────────
                if !appState.claudeApiKey.isEmpty {
                    claudeSection
                }
            }
        }
        .task { await loadTaste() }
        .task(id: appState.tmdbApiKey) { await loadBecause() }
        .task(id: appState.claudeApiKey) { await loadClaude() }
    }

    // MARK: - Continue Watching

    private func continueWatchingRow(items: [PlaybackProgress]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Continue Watching")
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { progress in
                        continueCard(progress)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func continueCard(_ progress: PlaybackProgress) -> some View {
        let stub = MetaItem(
            id: progress.metaId,
            type: progress.type,
            name: progress.name,
            poster: progress.poster,
            background: nil, description: nil, releaseInfo: nil,
            imdbRating: nil, genre: nil, genres: nil, runtime: nil,
            cast: nil, director: nil, year: nil, videos: nil
        )
        return NavigationLink(value: stub) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottom) {
                    if let posterURL = stub.posterURL {
                        AsyncImage(url: posterURL) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFill()
                            case .failure:
                                posterPlaceholder
                            default:
                                posterPlaceholder.overlay(ProgressView().tint(Theme.accent))
                            }
                        }
                        .frame(width: Theme.cardWidth, height: Theme.cardHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(color: .black.opacity(0.5), radius: 6, y: 4)
                    } else {
                        posterPlaceholder
                            .frame(width: Theme.cardWidth, height: Theme.cardHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .shadow(color: .black.opacity(0.5), radius: 6, y: 4)
                    }

                    // Progress bar
                    VStack(spacing: 0) {
                        Spacer()
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white.opacity(0.3))
                                    .frame(height: 3)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Theme.accent)
                                    .frame(width: geo.size.width * progress.completionPercent, height: 3)
                            }
                        }
                        .frame(height: 3)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 6)
                    }
                }

                Text(progress.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .frame(width: Theme.cardWidth, alignment: .leading)

                if let label = progress.episodeLabel {
                    Text(label + (progress.episodeName.map { " · \($0)" } ?? ""))
                        .font(.caption2)
                        .foregroundStyle(Theme.accent)
                        .frame(width: Theme.cardWidth, alignment: .leading)
                        .lineLimit(1)
                } else {
                    Text("\(Int(progress.completionPercent * 100))% watched")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: Theme.cardWidth, alignment: .leading)
                }
            }
            .frame(width: Theme.cardWidth)
        }
        .buttonStyle(.plain)
    }

    private var posterPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Theme.surface)
            .overlay(Image(systemName: "film").foregroundStyle(Theme.textSecondary))
    }

    // MARK: - Claude shelf

    @ViewBuilder
    private var claudeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Curated For You")
                    .font(.title3.bold())
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if isLoadingClaude {
                    ProgressView().tint(Theme.accent)
                } else if !claudeRecs.isEmpty {
                    Button {
                        Task { await refreshClaude() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .padding(.horizontal)

            if let error = claudeError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            } else if isLoadingClaude && claudeRecs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(0..<6, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Theme.surface)
                                .frame(width: Theme.cardWidth, height: Theme.cardHeight)
                                .shimmering()
                        }
                    }
                    .padding(.horizontal)
                }
            } else if claudeRecs.isEmpty && !isLoadingClaude {
                Text("Play a few titles to unlock AI-curated recommendations.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(claudeRecs) { rec in
                            claudeCard(rec)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    @ViewBuilder
    private func claudeCard(_ rec: ClaudeRecommendation) -> some View {
        if let item = rec.resolvedItem {
            NavigationLink(value: item) {
                VStack(alignment: .leading, spacing: 6) {
                    MediaCardView(item: item)
                    reasonBadge(rec.reason)
                }
                .frame(width: Theme.cardWidth)
            }
            .buttonStyle(.plain)
        } else {
            // No TMDB resolution — show title card only
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.surface)
                    .frame(width: Theme.cardWidth, height: Theme.cardHeight)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.title2)
                                .foregroundStyle(Theme.accent)
                            Text(rec.title)
                                .font(.caption.bold())
                                .foregroundStyle(Theme.textPrimary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                            if let year = rec.year {
                                Text(year)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    )
                reasonBadge(rec.reason)
            }
            .frame(width: Theme.cardWidth)
        }
    }

    private func reasonBadge(_ reason: String) -> some View {
        Text(reason)
            .font(.system(size: 9))
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(3)
            .frame(width: Theme.cardWidth, alignment: .leading)
    }

    // MARK: - Generic shelf helpers

    private func metaItemRow(title: String, items: [MetaItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { item in
                        NavigationLink(value: item) {
                            MediaCardView(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func skeletonRow(title: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<6, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Theme.surface)
                            .frame(width: Theme.cardWidth, height: Theme.cardHeight)
                            .shimmering()
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Teaser

    private var teaserRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("For You")
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal)

            HStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(Theme.accent.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Personalised picks coming soon")
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.textPrimary)
                    Text("Play a title to unlock \"Your Taste\", \"Because You Watched\", and AI-curated shelves.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)
        }
    }

    // MARK: - Data loading

    private func loadTaste() async {
        guard !addonManager.addons.isEmpty else { return }
        isLoadingTaste = true

        var pool: [MetaItem] = []
        let addon = addonManager.addons[0]
        await withTaskGroup(of: [MetaItem].self) { group in
            for catalog in addon.manifest.catalogs.prefix(3) {
                group.addTask {
                    (try? await AddonClient.shared.fetchCatalog(
                        addon: addon, type: catalog.type, id: catalog.id
                    )) ?? []
                }
            }
            for await items in group { pool.append(contentsOf: items) }
        }

        var seen = Set<String>()
        pool = pool.filter { seen.insert($0.id).inserted }
        tastePicks = RecommendationEngine.topMatches(from: pool, history: history, limit: 20)
        isLoadingTaste = false
    }

    private func loadBecause() async {
        let apiKey = appState.tmdbApiKey
        guard !apiKey.isEmpty else { return }
        isLoadingBecause = true
        becauseRows = []

        for seed in history.recentTitles.prefix(3) {
            let recs = await TMDBService.shared.recommendations(
                forImdbId: seed.metaId, apiKey: apiKey
            )
            if !recs.isEmpty {
                becauseRows.append((title: seed.name, items: recs))
            }
        }
        isLoadingBecause = false
    }

    private func loadClaude() async {
        let claudeKey = appState.claudeApiKey
        guard !claudeKey.isEmpty, !history.events.isEmpty else { return }
        isLoadingClaude = true
        claudeError = nil
        claudeRecs = await ClaudeRecommendationService.shared.recommendations(
            history: history,
            claudeKey: claudeKey,
            tmdbKey: appState.tmdbApiKey
        )
        isLoadingClaude = false
    }

    private func refreshClaude() async {
        let claudeKey = appState.claudeApiKey
        guard !claudeKey.isEmpty else { return }
        isLoadingClaude = true
        claudeError = nil
        claudeRecs = await ClaudeRecommendationService.shared.refresh(
            history: history,
            claudeKey: claudeKey,
            tmdbKey: appState.tmdbApiKey
        )
        isLoadingClaude = false
    }
}
