import SwiftUI

struct CatalogRowView: View {
    let title: String
    let type: String
    let addon: Addon
    let catalogId: String

    @State private var items: [MetaItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal)

            if isLoading {
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
            } else if let error = errorMessage {
                Text("Error: \(error)")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            } else if items.isEmpty {
                Text("No content available")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal)
            } else {
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
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await AddonClient.shared.fetchCatalog(addon: addon, type: type, id: catalogId)
            print("[CatalogRow] \(title): fetched \(fetched.count) items from \(addon.transportUrl)/catalog/\(type)/\(catalogId).json")
            // Deduplicate within this row (same IMDB ID can appear twice in a catalog)
            var seen = Set<String>()
            items = fetched.filter { seen.insert($0.id).inserted }
        } catch {
            print("[CatalogRow] \(title): ERROR - \(error)")
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// Simple shimmer effect for loading skeletons
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: phase - 0.3),
                        .init(color: .white.opacity(0.08), location: phase),
                        .init(color: .clear, location: phase + 0.3)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1.3
                }
            }
    }
}

extension View {
    func shimmering() -> some View { modifier(ShimmerModifier()) }
}
