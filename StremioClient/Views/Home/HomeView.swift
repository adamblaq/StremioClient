import SwiftUI

struct HomeView: View {
    @Environment(AddonManager.self) private var addonManager
    @Environment(WatchHistoryManager.self) private var watchHistory

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                if addonManager.addons.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 28) {
                            // Personalised shelves — hidden until user has watch history
                            ForYouSectionView(history: watchHistory)

                            ForEach(addonManager.addons) { addon in
                                ForEach(addon.manifest.catalogs.prefix(3), id: \.self) { catalog in
                                    CatalogRowView(
                                        title: "\(catalog.name)",
                                        type: catalog.type,
                                        addon: addon,
                                        catalogId: catalog.id
                                    )
                                }
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(for: MetaItem.self) { item in
                DetailView(item: item)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Addons Installed", systemImage: "puzzlepiece.extension")
        } description: {
            Text("Go to Addons tab to install content sources.")
        }
        .foregroundStyle(Theme.textPrimary)
    }
}
