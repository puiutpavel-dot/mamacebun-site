import SwiftUI

/// „Traseul meu”: localuri salvate, grupate pe județ. Se deschide din „Acasă”.
struct FavoritesView: View {
    /// `true` când e împins în NavigationStack-ul din „Acasă” (fără stivă proprie și fără butoanele de sus).
    var embedded = false

    @Environment(RestaurantStore.self) private var store
    @Environment(FavoritesStore.self) private var favorites
    @Environment(LocationManager.self) private var location
    @Environment(ReviewStore.self) private var reviews
    @Environment(BadgeCenter.self) private var badges

    enum SavedList: String, CaseIterable, Identifiable {
        case wantToGo
        case visited
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .wantToGo: "Vreau să merg"
            case .visited: "Am fost"
            }
        }
    }

    @State private var section: SavedList = .wantToGo
    @State private var selectedRestaurant: Restaurant?
    @State private var showBadges = false
    @State private var showAbout = false

    private var saved: [Restaurant] {
        store.restaurants(withIDs: section == .wantToGo ? favorites.wantToGo : favorites.visited)
    }

    private var groupedByCounty: [(county: String, restaurants: [Restaurant])] {
        Dictionary(grouping: saved, by: \.county)
            .map { (county: $0.key, restaurants: $0.value.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }) }
            .sorted { $0.county.compare($1.county, locale: Locale(identifier: "ro_RO")) == .orderedAscending }
    }

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack { content }
        }
    }

    private var content: some View {
            List {
                ForEach(groupedByCounty, id: \.county) { group in
                    Section {
                        ForEach(group.restaurants) { restaurant in
                            Button {
                                selectedRestaurant = restaurant
                            } label: {
                                FavoriteRow(restaurant: restaurant)
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                if section == .wantToGo {
                                    Button("Am fost", systemImage: "checkmark.seal") {
                                        favorites.toggleVisited(restaurant)
                                    }
                                    .tint(.green)
                                    Button("Șterge", systemImage: "trash", role: .destructive) {
                                        favorites.toggleWant(restaurant)
                                    }
                                } else {
                                    Button("Șterge", systemImage: "trash", role: .destructive) {
                                        favorites.toggleVisited(restaurant)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text(verbatim: "\(group.county) · \(group.restaurants.count)")
                    }
                }
            }
            .overlay {
                if saved.isEmpty {
                    ContentUnavailableView(
                        section == .wantToGo ? LocalizedStringKey("Niciun local salvat") : LocalizedStringKey("Niciun local bifat"),
                        systemImage: section == .wantToGo ? "heart" : "checkmark.seal",
                        description: Text(section == .wantToGo
                            ? LocalizedStringKey("Apasă „Vreau să merg” în fișa unui local ca să-ți faci traseul de weekend.")
                            : LocalizedStringKey("Bifează „Am fost” după ce ai gustat."))
                    )
                }
            }
            .navigationTitle("Traseul meu")
            // Selectorul stă sub titlul mare, pe toată lățimea (în toolbar ieșea deasupra titlului
            // și textele lungi, ex. „Szeretnék menni”, erau tăiate).
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Listă", selection: $section) {
                    ForEach(SavedList.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .toolbar {
                if !embedded {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showAbout = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel(Text("Despre aplicație"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showBadges = true
                    } label: {
                        // HStack, nu Label: pe iOS 26 bara de sus arată doar iconița unui Label.
                        let all = badges.statuses(reviews: reviews, favorites: favorites, restaurants: store)
                        HStack(spacing: 4) {
                            Image(systemName: "medal.fill")
                            Text(verbatim: "\(all.filter(\.isUnlocked).count)/\(all.count)")
                                .monospacedDigit()
                        }
                        .font(.subheadline.weight(.semibold))
                        .fixedSize()
                    }
                    .accessibilityLabel(Text("Insigne"))
                }
                }
            }
            .sheet(isPresented: $showAbout) {
                AboutView()
            }
            .sheet(isPresented: $showBadges) {
                BadgesView()
            }
            .onAppear {
                #if DEBUG
                guard !embedded else { return }
                if ScreenshotConfig.showBadges { showBadges = true }
                if ScreenshotConfig.showAbout { showAbout = true }
                #endif
            }
            .sheet(item: $selectedRestaurant) { restaurant in
                RestaurantDetailView(restaurant: restaurant, focusDish: nil, userLocation: location.lastLocation)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(24)
                    .presentationBackground(Color(.systemBackground))
            }
    }
}

private struct FavoriteRow: View {
    let restaurant: Restaurant

    @Environment(ReviewStore.self) private var reviews

    var body: some View {
        HStack(spacing: 12) {
            Text(restaurant.specialties.map(\.emoji).joined())
                .font(.title3)
                .frame(minWidth: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(restaurant.name).font(.headline)
                Text(verbatim: "\(restaurant.kind.displayName) · \(restaurant.city)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                let myReviews = reviews.reviews(for: restaurant)
                if !myReviews.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(myReviews) { review in
                            Text(verbatim: "\(review.dish.emoji) \(UserReview.format(review.score))")
                                .fontWeight(.semibold)
                                .foregroundStyle(review.dish.color)
                        }
                    }
                    .font(.caption)
                    .monospacedDigit()
                }
            }
        }
        .contentShape(Rectangle())
    }
}
