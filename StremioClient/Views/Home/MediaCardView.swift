import SwiftUI

struct MediaCardView: View {
    let item: MetaItem
    var showFeedback = false   // enable long-press context menu when inside recommendation rows

    @Environment(WatchHistoryManager.self) private var watchHistory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: item.posterURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        posterPlaceholder
                    default:
                        posterPlaceholder.overlay(ProgressView())
                    }
                }
                .frame(width: Theme.cardWidth, height: Theme.cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.5), radius: 6, y: 4)

                // Feedback badge
                if let fb = watchHistory.feedback[item.id] {
                    Image(systemName: fb == .liked ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(fb == .liked ? Color.green : Color.red)
                        .clipShape(Circle())
                        .padding(6)
                }
            }

            Text(item.name)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .frame(width: Theme.cardWidth, alignment: .leading)

            Text(item.displayYear)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: Theme.cardWidth, alignment: .leading)
        }
        .frame(width: Theme.cardWidth)
        .contextMenu {
            Section("Rate this") {
                Button {
                    let current = watchHistory.feedback[item.id]
                    if current == .liked {
                        watchHistory.clearFeedback(for: item.id)
                    } else {
                        watchHistory.setFeedback(.liked, for: item.id)
                    }
                } label: {
                    let isLiked = watchHistory.feedback[item.id] == .liked
                    Label(isLiked ? "Remove Like" : "Like", systemImage: isLiked ? "hand.thumbsup" : "hand.thumbsup.fill")
                }

                Button(role: .destructive) {
                    let current = watchHistory.feedback[item.id]
                    if current == .disliked {
                        watchHistory.clearFeedback(for: item.id)
                    } else {
                        watchHistory.setFeedback(.disliked, for: item.id)
                    }
                } label: {
                    let isDisliked = watchHistory.feedback[item.id] == .disliked
                    Label(isDisliked ? "Remove Dislike" : "Not for me", systemImage: "hand.thumbsdown.fill")
                }
            }
        }
    }

    private var posterPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Theme.surface)
            .frame(width: Theme.cardWidth, height: Theme.cardHeight)
            .overlay(
                Image(systemName: "film")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.textSecondary)
            )
    }
}
