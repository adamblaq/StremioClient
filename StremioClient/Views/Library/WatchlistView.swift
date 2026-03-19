import SwiftUI

struct WatchlistView: View {
    let history: WatchHistoryManager

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        let items = history.watchlistItems
        if items.isEmpty {
            ContentUnavailableView {
                Label("Nothing Saved Yet", systemImage: "heart")
            } description: {
                Text("Tap the heart on any title to save it here.")
            }
            .foregroundStyle(Theme.textPrimary)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(items) { item in
                        NavigationLink(value: item.metaItem) {
                            VStack(alignment: .leading, spacing: 6) {
                                AsyncImage(url: item.posterURL) { phase in
                                    switch phase {
                                    case .success(let img): img.resizable().scaledToFill()
                                    default:
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Theme.surface)
                                            .overlay(Image(systemName: "film")
                                                .foregroundStyle(Theme.textSecondary))
                                    }
                                }
                                .aspectRatio(2/3, contentMode: .fill)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .shadow(color: .black.opacity(0.4), radius: 4, y: 3)
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        history.removeFromWatchlist(item.id)
                                    } label: {
                                        Image(systemName: "heart.fill")
                                            .font(.caption.bold())
                                            .foregroundStyle(.pink)
                                            .padding(5)
                                            .background(.black.opacity(0.45))
                                            .clipShape(Circle())
                                    }
                                    .padding(6)
                                }

                                Text(item.name)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)

                                if let year = item.year {
                                    Text(year)
                                        .font(.caption2)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
    }
}
