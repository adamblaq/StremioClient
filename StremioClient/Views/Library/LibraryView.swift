import SwiftUI

struct LibraryView: View {
    @Environment(WatchHistoryManager.self) private var watchHistory
    @Environment(DownloadManager.self) private var downloadManager
    @State private var selectedTab = 0
    @State private var selectedDownload: Download?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Segment picker
                    Picker("", selection: $selectedTab) {
                        Text("Saved").tag(0)
                        Text("Downloads").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    if selectedTab == 0 {
                        WatchlistView(history: watchHistory)
                    } else {
                        downloadsContent
                    }
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(for: MetaItem.self) { item in
                DetailView(item: item)
            }
            .fullScreenCover(item: $selectedDownload) { download in
                if let url = download.localFileURL {
                    PlayerView(
                        stream: StreamItem(name: download.displayTitle, title: nil,
                                          url: url.absoluteString, infoHash: nil, behaviorHints: nil),
                        title: download.displayTitle
                    )
                }
            }
        }
    }

    private var downloadsContent: some View {
        Group {
            if downloadManager.downloads.isEmpty {
                ContentUnavailableView {
                    Label("No Downloads", systemImage: "arrow.down.circle")
                } description: {
                    Text("Download movies and shows to watch offline.")
                }
                .foregroundStyle(Theme.textPrimary)
            } else {
                List {
                    ForEach(downloadManager.downloads) { download in
                        DownloadRowView(download: download) {
                            downloadManager.retryDownload(download)
                        }
                        .listRowBackground(Theme.surface)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                downloadManager.deleteDownload(download)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .onTapGesture {
                            if download.isPlayable { selectedDownload = download }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
            }
        }
    }
}
