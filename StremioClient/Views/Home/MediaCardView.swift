import SwiftUI

struct MediaCardView: View {
    let item: MetaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
