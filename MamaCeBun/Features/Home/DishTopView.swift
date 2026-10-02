import SwiftUI
import CoreLocation

/// „Top 10” pentru un preparat: în toată țara, lângă tine sau în județul tău.
struct DishTopView: View {
    let dish: Dish

    @Environment(RestaurantStore.self) private var store
    @Environment(CommunityStore.self) private var community
    @Environment(LocationManager.self) private var location

    enum Scope: Hashable, CaseIterable, Identifiable {
        case country, nearby, county
        var id: Self { self }
        var title: LocalizedStringKey {
            switch self {
            case .country: "Toată țara"
            case .nearby: "Lângă mine"
            case .county: "Județul meu"
            }
        }
    }

    /// Raza pentru „Lângă mine”.
    private static let nearbyRadius: CLLocationDistance = 50_000

    @State private var scope: Scope = .country
    @State private var selection: HomeSelection?

    private var myCounty: String? {
        guard let here = location.lastLocation else { return nil }
        return store.restaurants.min { here.distance(from: $0.location) < here.distance(from: $1.location) }?.county
    }

    private var top: [Restaurant] {
        let ranked = HomeRanking.ranked(dish, store: store, community: community)
        let filtered: [Restaurant]
        switch scope {
        case .country:
            filtered = ranked
        case .nearby:
            guard let here = location.lastLocation else { return [] }
            filtered = ranked.filter { here.distance(from: $0.location) <= Self.nearbyRadius }
        case .county:
            guard let county = myCounty else { return [] }
            filtered = ranked.filter { $0.county == county }
        }
        return Array(filtered.prefix(10))
    }

    var body: some View {
        List {
            Section {
                ForEach(Array(top.enumerated()), id: \.element.id) { index, restaurant in
                    Button {
                        selection = HomeSelection(restaurant: restaurant, dish: dish)
                    } label: {
                        TopRow(rank: index + 1, restaurant: restaurant, dish: dish,
                               score: community.rating(for: restaurant, dish: dish)?.score,
                               distance: location.lastLocation.map { $0.distance(from: restaurant.location) })
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Bazat pe gusturile și percepțiile consumatorilor")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Scope.allCases) { item in
                                ScopeChip(title: item.title, systemImage: item == .nearby ? "location.fill" : nil,
                                          tint: dish.color, isSelected: scope == item) {
                                    scope = item
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 6)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text(verbatim: "\(dish.emoji) \(dish.topTitle)"))
        .navigationBarTitleDisplayMode(.large)
        .overlay {
            if top.isEmpty {
                if scope != .country && location.lastLocation == nil {
                    ContentUnavailableView("Locația e oprită", systemImage: "location.slash",
                                           description: Text("Permite accesul la locație ca să vezi topul din zona ta."))
                } else {
                    ContentUnavailableView("Niciun local încă", systemImage: "fork.knife",
                                           description: Text("Încă nu avem un loc verificat aici."))
                }
            }
        }
        .animation(.snappy, value: scope)
        .sensoryFeedback(.selection, trigger: scope)
        .sheet(item: $selection) { item in
            RestaurantDetailView(restaurant: item.restaurant, focusDish: item.dish, userLocation: location.lastLocation)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
                .presentationBackground(Color(.systemBackground))
        }
    }
}

private struct TopRow: View {
    let rank: Int
    let restaurant: Restaurant
    let dish: Dish
    let score: Double?
    let distance: CLLocationDistance?

    private var rankColor: Color {
        switch rank {
        case 1: Color(red: 0.88, green: 0.63, blue: 0.0)
        case 2: Color(red: 0.62, green: 0.62, blue: 0.66)
        case 3: Color(red: 0.76, green: 0.49, blue: 0.23)
        default: Color(.tertiaryLabel)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: "\(rank)")
                .font(.headline.weight(.heavy))
                .foregroundStyle(rankColor)
                .frame(width: 24)
            VenueImage(url: restaurant.photos.first(where: { $0.dish == dish })?.url, dish: dish)
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(restaurant.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(restaurant.city)
                    if let distance {
                        Text(verbatim: "·")
                        Text(Measurement(value: distance, unit: UnitLength.meters),
                             format: .measurement(width: .abbreviated, usage: .road))
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let score {
                Text(verbatim: score.formatted(.number.precision(.fractionLength(1))))
                    .font(.title3.weight(.heavy))
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

private struct ScopeChip: View {
    let title: LocalizedStringKey
    let systemImage: String?
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage { Image(systemName: systemImage).font(.caption) }
                Text(title).fontWeight(.semibold)
            }
            .font(.subheadline)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule().fill(tint)
                } else {
                    Capsule().fill(Color(.secondarySystemGroupedBackground))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
