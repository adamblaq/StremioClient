import SwiftUI

struct DownloadsView: View {
    @Environment(DownloadManager.self) private var downloadManager
    @State private var selectedDownload: Download?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

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
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
}

struct DownloadRowView: View {
    let download: Download
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: download.posterURL.flatMap(URL.init)) { phase in
                if case .success(let img) = phase { img.resizable().scaledToFill() }
                else { Theme.background }
            }
            .frame(width: 50, height: 75)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 6) {
                Text(download.displayTitle)
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)

                statusView
            }

            Spacer()

            statusIcon
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusView: some View {
        switch download.status {
        case .downloading:
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: download.progress)
                    .tint(Theme.accent)
                HStack {
                    if download.totalMB > 0 {
                        Text(String(format: "%.0f / %.0f MB", download.downloadedMB, download.totalMB))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Text(String(format: "%.0f MB", download.downloadedMB))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    if download.speedMBps > 0.01 {
                        Text(String(format: "%.1f MB/s", download.speedMBps))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        case .completed:
            Text("Ready to watch")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed:
            HStack(spacing: 8) {
                Text("Download failed")
                    .font(.caption)
                    .foregroundStyle(.red)
                Button("Retry", action: onRetry)
                    .font(.caption.bold())
                    .foregroundStyle(Theme.accent)
            }
        case .queued:
            Text("Queued")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        case .paused:
            Text("Paused")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch download.status {
        case .completed:
            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(Theme.accent)
        case .downloading:
            ProgressView()
                .tint(Theme.accent)
        case .failed:
            Image(systemName: "exclamationmark.circle")
                .font(.title2)
                .foregroundStyle(.red)
        default:
            Image(systemName: "clock")
                .font(.title2)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
