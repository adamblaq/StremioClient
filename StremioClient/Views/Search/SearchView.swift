import SwiftUI

struct SearchView: View {
    @Environment(AddonManager.self) private var addonManager

    @State private var query = ""
    @State private var results: [MetaItem] = []
    @State private var isSearching = false
    @State private var selectedType = "movie"
    @State private var searchTask: Task<Void, Never>?

    private let types = ["movie", "series"]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    Picker("Type", selection: $selectedType) {
                        Text("Movies").tag("movie")
                        Text("Series").tag("series")
                    }
                    .pickerStyle(.segmented)
                    .padding()
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
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: Theme.cardWidth), spacing: 16)], spacing: 20) {
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
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .searchable(text: $query, prompt: "Movies, shows…")
            .onChange(of: query) { _, _ in performSearch() }
            .navigationDestination(for: MetaItem.self) { item in
                DetailView(item: item)
            }
        }
    }

    private func performSearch() {
        searchTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000) // debounce
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
