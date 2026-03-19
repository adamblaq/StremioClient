import SwiftUI

struct StreamPickerView: View {
    let streams: [StreamItem]
    let meta: MetaItem
    let onPlay: (StreamItem) -> Void

    @Environment(DownloadManager.self) private var downloadManager
    @Environment(\.dismiss) private var dismiss

    private var directStreams: [StreamItem] { streams.filter(\.isDirectPlay) }
    private var torrentStreams: [StreamItem] { streams.filter(\.isTorrent) }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                if streams.isEmpty {
                    ContentUnavailableView("No Streams Found", systemImage: "antenna.radiowaves.left.and.right.slash")
                        .foregroundStyle(Theme.textPrimary)
                } else {
                    List {
                        if !directStreams.isEmpty {
                            Section {
                                ForEach(directStreams) { stream in
                                    StreamRowView(stream: stream, meta: meta) {
                                        onPlay(stream)
                                        dismiss()
                                    }
                                }
                            } header: {
                                Text("Direct Streams")
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }

                        if !torrentStreams.isEmpty {
                            Section {
                                ForEach(torrentStreams) { stream in
                                    StreamRowView(stream: stream, meta: meta, onPlay: nil)
                                }
                            } header: {
                                Text("Torrent Streams (not supported yet)")
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Choose Stream")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

struct StreamRowView: View {
    let stream: StreamItem
    let meta: MetaItem
    let onPlay: (() -> Void)?

    @Environment(DownloadManager.self) private var downloadManager

    private var alreadyDownloaded: Bool {
        downloadManager.downloads.contains { $0.metaId == meta.id && $0.status == .completed }
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(stream.displayName)
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.textPrimary)
                if !stream.displayTitle.isEmpty {
                    Text(stream.displayTitle)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
                if let quality = stream.quality {
                    Text(quality)
                        .font(.caption.bold())
                        .foregroundStyle(Theme.accent)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if let onPlay {
                    Button(action: onPlay) {
                        Image(systemName: "play.fill")
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(Theme.accent)
                            .clipShape(Circle())
                    }
                }

                if stream.isDirectPlay && !alreadyDownloaded {
                    Button {
                        Task { await downloadManager.startDownload(meta: meta, stream: stream) }
                    } label: {
                        Image(systemName: "arrow.down.circle")
                            .foregroundStyle(Theme.accent)
                            .font(.title2)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(Theme.surface)
    }
}
