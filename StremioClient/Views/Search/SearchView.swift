import SwiftUI

// MARK: - Search mode

private enum SearchMode: String, CaseIterable {
    case keyword = "Search"
    case ask     = "Ask Claude"
}

// MARK: - Chat message model

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: String                           // "user" | "assistant"
    let text: String
    var suggestions: [ClaudeRecommendation]    // populated after TMDB resolution
}

// MARK: - Root view

struct SearchView: View {
    @Environment(AddonManager.self) private var addonManager
    @Environment(AppState.self)     private var appState

    @State private var mode: SearchMode = .keyword

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Mode picker — only shown when a Claude key is configured
                    if !appState.claudeApiKey.isEmpty {
                        Picker("Mode", selection: $mode) {
                            ForEach(SearchMode.allCases, id: \.self) { m in
                                Text(m.rawValue).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding()
                    }

                    switch mode {
                    case .keyword:
                        KeywordSearchView(addonManager: addonManager)
                    case .ask:
                        ClaudeSearchChatView()
                    }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(for: MetaItem.self) { item in
                DetailView(item: item)
            }
        }
    }
}

// MARK: - Keyword search (existing behaviour)

private struct KeywordSearchView: View {
    let addonManager: AddonManager

    @State private var query        = ""
    @State private var results: [MetaItem] = []
    @State private var isSearching  = false
    @State private var selectedType = "movie"
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Type", selection: $selectedType) {
                Text("Movies").tag("movie")
                Text("Series").tag("series")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .onChange(of: selectedType) { _, _ in performSearch() }

            if isSearching {
                ProgressView()
                    .tint(Theme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty && !query.isEmpty {
                ContentUnavailableView.search(text: query)
                    .foregroundStyle(Theme.textPrimary)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: Theme.cardWidth), spacing: 16)],
                        spacing: 20
                    ) {
                        ForEach(results) { item in
                            NavigationLink(value: item) {
                                MediaCardView(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .searchable(text: $query, prompt: "Movies, shows…")
        .onChange(of: query) { _, _ in performSearch() }
    }

    private func performSearch() {
        searchTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []; return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            isSearching = true
            results = (try? await AddonClient.shared.search(
                addons: addonManager.addons,
                type: selectedType,
                query: query
            )) ?? []
            isSearching = false
        }
    }
}

// MARK: - Claude chat search

private struct ClaudeSearchChatView: View {
    @Environment(AppState.self) private var appState

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var sendTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            if messages.isEmpty {
                emptyState
            } else {
                chatList
            }

            Divider().background(Theme.surface)
            inputBar
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 52))
                .foregroundStyle(Theme.accent)
            Text("Describe what you're in the mood for")
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 10) {
                suggestionChip("Something like Interstellar but more recent")
                suggestionChip("A feel-good comedy for Friday night")
                suggestionChip("A dark thriller series under 10 episodes")
                suggestionChip("Classic 90s action movies I might have missed")
            }
            Spacer()
        }
        .padding()
    }

    private func suggestionChip(_ text: String) -> some View {
        Button {
            inputText = text
            send()
        } label: {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Theme.surface)
                .clipShape(Capsule())
        }
    }

    // MARK: - Chat list

    private var chatList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(messages) { msg in
                        chatBubble(msg)
                            .id(msg.id)
                    }

                    if isLoading {
                        typingIndicator
                            .id("typing")
                    }

                    if let err = errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                            .id("error")
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
            }
            .onChange(of: isLoading) { _, loading in
                if loading { withAnimation { proxy.scrollTo("typing", anchor: .bottom) } }
            }
        }
    }

    // MARK: - Chat bubble

    @ViewBuilder
    private func chatBubble(_ msg: ChatMessage) -> some View {
        if msg.role == "user" {
            HStack {
                Spacer(minLength: 60)
                Text(msg.text)
                    .font(.body)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                        .padding(6)
                        .background(Theme.accent.opacity(0.15))
                        .clipShape(Circle())

                    Text(msg.text)
                        .font(.body)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .padding(.trailing, 40)
                }

                if !msg.suggestions.isEmpty {
                    suggestionsRow(msg.suggestions)
                }
            }
        }
    }

    // MARK: - Suggestions row

    private func suggestionsRow(_ suggestions: [ClaudeRecommendation]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(suggestions) { rec in
                    if let item = rec.resolvedItem {
                        NavigationLink(value: item) {
                            VStack(alignment: .leading, spacing: 4) {
                                MediaCardView(item: item)
                                Text(rec.reason)
                                    .font(.system(size: 9))
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(3)
                                    .frame(width: Theme.cardWidth, alignment: .leading)
                            }
                            .frame(width: Theme.cardWidth)
                        }
                        .buttonStyle(.plain)
                    } else {
                        // No TMDB poster — show title card
                        unresolvedCard(rec)
                    }
                }
            }
            .padding(.leading, 34)   // align under the bubble (past the sparkle icon)
            .padding(.trailing)
        }
    }

    private func unresolvedCard(_ rec: ClaudeRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.surface)
                .frame(width: Theme.cardWidth, height: Theme.cardHeight)
                .overlay(
                    VStack(spacing: 6) {
                        Image(systemName: rec.type == "series" ? "tv" : "film")
                            .font(.title2)
                            .foregroundStyle(Theme.accent)
                        Text(rec.title)
                            .font(.caption.bold())
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 6)
                        if let year = rec.year {
                            Text(year)
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                )
            Text(rec.reason)
                .font(.system(size: 9))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(3)
                .frame(width: Theme.cardWidth, alignment: .leading)
        }
        .frame(width: Theme.cardWidth)
    }

    // MARK: - Typing indicator

    private var typingIndicator: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(Theme.accent)
                .padding(6)
                .background(Theme.accent.opacity(0.15))
                .clipShape(Circle())

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Theme.textSecondary)
                        .frame(width: 7, height: 7)
                        .scaleEffect(isLoading ? 1.0 : 0.5)
                        .animation(
                            .easeInOut(duration: 0.5)
                            .repeatForever()
                            .delay(Double(i) * 0.15),
                            value: isLoading
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            if !messages.isEmpty {
                Button {
                    messages = []
                    errorMessage = nil
                    sendTask?.cancel()
                } label: {
                    Image(systemName: "trash")
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.leading, 4)
            }

            TextField("What do you want to watch?", text: $inputText, axis: .vertical)
                .lineLimit(1...4)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .onSubmit { send() }

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading
                                     ? Theme.textSecondary : Theme.accent)
            }
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.background)
    }

    // MARK: - Send

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isLoading else { return }

        inputText = ""
        errorMessage = nil

        let userMsg = ChatMessage(role: "user", text: text, suggestions: [])
        messages.append(userMsg)

        sendTask?.cancel()
        sendTask = Task { await fetchResponse(userText: text) }
    }

    private func fetchResponse(userText: String) async {
        isLoading = true

        // Build history for the API (all messages so far, including the one just added)
        let history = messages.map { (role: $0.role, text: $0.text) }

        do {
            let response = try await ClaudeSearchService.shared.respond(
                to: history,
                claudeKey: appState.claudeApiKey
            )

            // Resolve TMDB posters in parallel
            let resolved = await ClaudeSearchService.shared.resolve(
                suggestions: response.suggestions,
                tmdbKey: appState.tmdbApiKey
            )

            guard !Task.isCancelled else { return }

            let assistantMsg = ChatMessage(
                role: "assistant",
                text: response.text,
                suggestions: resolved
            )
            messages.append(assistantMsg)

        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
