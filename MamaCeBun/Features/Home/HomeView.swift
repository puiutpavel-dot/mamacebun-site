import SwiftUI
import CoreLocation

/// Un local deschis din „Acasă”, cu preparatul din care a fost ales (pentru `.sheet(item:)`).
struct HomeSelection: Identifiable, Hashable {
    let restaurant: Restaurant
    let dish: Dish?
    var id: String { "\(restaurant.id)#\(dish?.rawValue ?? "-")" }
}

/// Unde se poate ajunge din „Acasă” prin NavigationStack.
enum HomeRoute: Hashable {
    case top(Dish)
    case saved
}

/// Tab 1 — „Acasă”: unde găsești cei mai buni mici, papanași și cea mai bună ciorbă de burtă din țară,
/// plus rezumatul traseului tău.
struct HomeView: View {
    @Environment(RestaurantStore.self) private var store
    @Environment(CommunityStore.self) private var community
    @Environment(FavoritesStore.self) private var favorites
    @Environment(ReviewStore.self) private var reviews
    @Environment(BadgeCenter.self) private var badges
    @Environment(LocationManager.self) private var location

    @State private var path: [HomeRoute] = []
    @State private var selection: HomeSelection?
    @State private var showAbout = false
    @State private var showBadges = false
    @State private var showSuggest = false

    /// Ordinea secțiunilor de pe pagina de start.
    private let sections: [Dish] = [.mici, .ciorbaDeBurta, .papanasi]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if let pick = weeklyPick {
                        WeeklyPickCard(pick: pick, score: score(pick.restaurant, pick.dish)) {
                            selection = HomeSelection(restaurant: pick.restaurant, dish: pick.dish)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                    }
                    ForEach(sections) { dish in
                        dishSection(dish)
                    }
                    savedSection
                    suggestCard
                }
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(Text(verbatim: "Mamă, ce Bun!"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .overlay {
                if store.isLoading { ProgressView() }
            }
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .top(let dish):
                    DishTopView(dish: dish)
                case .saved:
                    FavoritesView(embedded: true)
                }
            }
            .sheet(item: $selection) { item in
                RestaurantDetailView(restaurant: item.restaurant, focusDish: item.dish, userLocation: location.lastLocation)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(24)
                    .presentationBackground(Color(.systemBackground))
            }
            .sheet(isPresented: $showAbout) { AboutView() }
            .sheet(isPresented: $showBadges) { BadgesView() }
            .sheet(isPresented: $showSuggest) { SuggestVenueView() }
            .onAppear {
                #if DEBUG
                if ScreenshotConfig.showBadges { showBadges = true }
                if ScreenshotConfig.showAbout { showAbout = true }
                #endif
            }
        }
    }

    // MARK: - Antet

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                CircleButton(systemImage: "info.circle", tint: .primary) { showAbout = true }
                    .accessibilityLabel(Text("Despre aplicație"))
                Spacer()
                CircleButton(systemImage: "plus", tint: .accentColor) { showSuggest = true }
                    .accessibilityLabel(Text("Propune un local"))
                CircleButton(systemImage: "medal.fill", tint: .orange) { showBadges = true }
                    .accessibilityLabel(Text("Insigne"))
                CircleButton(systemImage: "heart.fill", tint: .accentColor) { path.append(.saved) }
                    .accessibilityLabel(Text("Traseul meu"))
            }
            .padding(.bottom, 4)

            Text(greeting)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(verbatim: "Mamă, ce Bun!")
                .font(.largeTitle.weight(.bold))
            Text("Cei mai buni mici, papanași și cea mai bună ciorbă de burtă din toată țara.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var greeting: LocalizedStringKey {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<11: "Bună dimineața! Ce mâncăm azi?"
        case 11..<18: "Bună ziua! Ce mâncăm azi?"
        default: "Bună seara! Ce mâncăm azi?"
        }
    }

    // MARK: - Topuri pe preparat

    private func dishSection(_ dish: Dish) -> some View {
        let top = Array(HomeRanking.ranked(dish, store: store, community: community).prefix(10))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "\(dish.emoji) \(dish.homeTitle)")
                    .font(.title3.weight(.bold))
                Spacer()
                Button {
                    path.append(.top(dish))
                } label: {
                    HStack(spacing: 2) {
                        Text("Top 10")
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(dish.color)
                }
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(top.enumerated()), id: \.element.id) { index, restaurant in
                        Button {
                            selection = HomeSelection(restaurant: restaurant, dish: dish)
                        } label: {
                            TopCard(rank: index + 1, restaurant: restaurant, dish: dish, score: score(restaurant, dish))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }
        }
        .padding(.top, 24)
    }

    private func score(_ restaurant: Restaurant, _ dish: Dish) -> Double? {
        community.rating(for: restaurant, dish: dish)?.score
    }

    // MARK: - Recomandarea săptămânii

    /// Un local foarte bine notat, care are poză cu preparatul; se schimbă în fiecare săptămână.
    private var weeklyPick: WeeklyPick? {
        var candidates: [WeeklyPick] = []
        for dish in sections {
            for restaurant in HomeRanking.ranked(dish, store: store, community: community).prefix(10) {
                if let photo = restaurant.photos.first(where: { $0.dish == dish }) {
                    candidates.append(WeeklyPick(restaurant: restaurant, dish: dish, photo: photo))
                }
            }
        }
        guard !candidates.isEmpty else { return nil }
        let week = Calendar(identifier: .iso8601).component(.weekOfYear, from: .now)
        let year = Calendar(identifier: .iso8601).component(.yearForWeekOfYear, from: .now)
        return candidates[(week + year) % candidates.count]
    }

    // MARK: - Traseul meu

    private var savedSection: some View {
        let all = badges.statuses(reviews: reviews, favorites: favorites, restaurants: store)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "❤️ ") + Text("Traseul meu")
                Spacer()
                Button {
                    path.append(.saved)
                } label: {
                    HStack(spacing: 2) {
                        Text("Deschide")
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                    }
                    .font(.subheadline.weight(.medium))
                }
            }
            .font(.title3.weight(.bold))
            .padding(.horizontal, 16)

            HStack(spacing: 10) {
                StatTile(systemImage: "heart.fill", tint: .accentColor, value: "\(favorites.wantToGo.count)", title: "Vreau să merg") {
                    path.append(.saved)
                }
                StatTile(systemImage: "checkmark.seal.fill", tint: .green, value: "\(favorites.visited.count)", title: "Am fost") {
                    path.append(.saved)
                }
                StatTile(systemImage: "medal.fill", tint: .orange, value: "\(all.filter(\.isUnlocked).count)/\(all.count)", title: "Insigne") {
                    showBadges = true
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 28)
    }
}

extension HomeView {
    /// Invitația de a propune un local nou.
    fileprivate var suggestCard: some View {
        Button {
            showSuggest = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Știi un loc bun?")
                        .font(.headline)
                    Text("Propune un local unde se mănâncă bine mici, papanași sau ciorbă de burtă.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 24)
    }
}

// MARK: - Clasament

enum HomeRanking {
    /// Localurile cu notă pentru preparat, de la cea mai mare notă în jos
    /// (la egalitate: mai multe note înainte, apoi numele).
    @MainActor
    static func ranked(_ dish: Dish, store: RestaurantStore, community: CommunityStore) -> [Restaurant] {
        store.restaurants
            .filter { $0.serves(dish) }
            .compactMap { restaurant -> (Restaurant, DishRating)? in
                guard let rating = community.rating(for: restaurant, dish: dish) else { return nil }
                return (restaurant, rating)
            }
            .sorted { a, b in
                if a.1.score != b.1.score { return a.1.score > b.1.score }
                if a.1.reviewCount != b.1.reviewCount { return a.1.reviewCount > b.1.reviewCount }
                return a.0.name.localizedCompare(b.0.name) == .orderedAscending
            }
            .map(\.0)
    }
}

extension Dish {
    /// Titlul secțiunii de pe pagina de start.
    var homeTitle: String {
        switch self {
        case .mici: String(localized: "Cei mai buni mici")
        case .papanasi: String(localized: "Cei mai buni papanași")
        case .ciorbaDeBurta: String(localized: "Cea mai bună ciorbă")
        }
    }

    /// Titlul ecranului „Top 10”.
    var topTitle: String {
        switch self {
        case .mici: String(localized: "Topul micilor")
        case .papanasi: String(localized: "Topul papanașilor")
        case .ciorbaDeBurta: String(localized: "Topul ciorbelor de burtă")
        }
    }
}

// MARK: - Componente

struct WeeklyPick {
    let restaurant: Restaurant
    let dish: Dish
    let photo: VenuePhoto
}

private struct CircleButton: View {
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(Color(.secondarySystemGroupedBackground), in: Circle())
                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
    }
}

private struct WeeklyPickCard: View {
    let pick: WeeklyPick
    let score: Double?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                VenueImage(url: pick.photo.url, dish: pick.dish)
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Text(verbatim: pick.dish.emoji)
                        Text("Recomandarea săptămânii").textCase(.uppercase)
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(pick.dish.color, in: Capsule())

                    Text(pick.restaurant.name)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.circle.fill")
                        Text(pick.restaurant.city)
                        if let score {
                            Text(verbatim: "·")
                            Image(systemName: "star.fill").foregroundStyle(.yellow)
                            Text(verbatim: score.formatted(.number.precision(.fractionLength(1))))
                                .fontWeight(.semibold)
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.92))
                }
                .padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
    }
}

private struct TopCard: View {
    let rank: Int
    let restaurant: Restaurant
    let dish: Dish
    let score: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                VenueImage(url: restaurant.photos.first(where: { $0.dish == dish })?.url, dish: dish)
                    .frame(width: 168, height: 114)
                    .clipped()
                Text(verbatim: "\(rank)")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(dish.color)
                    .frame(minWidth: 28, minHeight: 28)
                    .background(Color.white.opacity(0.95), in: Circle())
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .padding(8)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(restaurant.name)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Text(restaurant.city)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let score {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill").foregroundStyle(.orange)
                        Text(verbatim: score.formatted(.number.precision(.fractionLength(1))))
                            .fontWeight(.bold)
                    }
                    .font(.subheadline)
                    .padding(.top, 5)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
        }
        .frame(width: 168, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
}

/// Poza unui preparat; fără poză → iconița preparatului pe fundal colorat.
struct VenueImage: View {
    let url: URL?
    let dish: Dish

    var body: some View {
        ZStack {
            LinearGradient(colors: [dish.color.opacity(0.14), dish.color.opacity(0.28)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Text(verbatim: dish.emoji).font(.system(size: 40))
                    }
                }
            } else {
                Text(verbatim: dish.emoji).font(.system(size: 40))
            }
        }
    }
}

private struct StatTile: View {
    let systemImage: String
    let tint: Color
    let value: String
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(tint)
                Text(verbatim: value)
                    .font(.title2.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
