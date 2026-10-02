import Foundation
import CoreLocation
import Observation

/// Baza de date națională, comună tuturor tab-urilor.
@Observable
final class RestaurantStore {
    private(set) var restaurants: [Restaurant] = []
    private(set) var isLoading = false
    var errorMessage: String?

    @ObservationIgnored private let repository: RestaurantRepository

    @ObservationIgnored private let feed: RemoteRestaurantFeed?

    init(repository: RestaurantRepository = LocalJSONRestaurantRepository(),
         feed: RemoteRestaurantFeed? = RemoteRestaurantFeed()) {
        self.repository = repository
        #if DEBUG
        // Capturile pentru App Store folosesc mereu lista inclusă în aplicație.
        self.feed = ScreenshotConfig.isActive ? nil : feed
        #else
        self.feed = feed
        #endif
    }

    /// Județele (și Bucureștiul) care au cel puțin un local, în ordine alfabetică românească.
    func counties(for dish: Dish) -> [String] {
        let names = Set(restaurants.filter { $0.serves(dish) }.map(\.county))
        return names.sorted { $0.compare($1, locale: Locale(identifier: "ro_RO")) == .orderedAscending }
    }

    /// Tipurile de local prezente pentru preparat — cele „featured” primele.
    func kinds(for dish: Dish) -> [VenueKind] {
        let present = Set(restaurants.filter { $0.serves(dish) }.map(\.kind))
        let featured = dish.featuredKinds.filter { present.contains($0) }
        let others = VenueKind.allCases.filter { present.contains($0) && !featured.contains($0) }
        return featured + others
    }

    /// Localurile pentru un tab, ordonate: notă la preparat ↓, apoi lăudat înainte de „doar în meniu”,
    /// apoi cât de bine e susținută recomandarea, apoi distanța față de utilizator, apoi numele.
    func restaurants(
        for dish: Dish,
        county: String? = nil,
        kind: VenueKind? = nil,
        near location: CLLocation? = nil
    ) -> [Restaurant] {
        restaurants
            .filter { $0.serves(dish) }
            .filter { county == nil || $0.county == county }
            .filter { kind == nil || $0.kind == kind }
            .sorted { a, b in
                let scoreA = a.rating(for: dish)?.score ?? -1
                let scoreB = b.rating(for: dish)?.score ?? -1
                if scoreA != scoreB { return scoreA > scoreB }

                // Recomandările lăudate explicit înaintea celor „doar în meniu”.
                let weakA = a.isMenuOnly(dish)
                let weakB = b.isMenuOnly(dish)
                if weakA != weakB { return !weakA }

                let rankA = a.specialtyRank(for: dish)
                let rankB = b.specialtyRank(for: dish)
                if rankA != rankB { return rankA < rankB }

                if let location {
                    let distanceA = location.distance(from: a.location)
                    let distanceB = location.distance(from: b.location)
                    if distanceA != distanceB { return distanceA < distanceB }
                }
                return a.name.localizedCompare(b.name) == .orderedAscending
            }
    }

    func restaurants(withIDs ids: Set<String>) -> [Restaurant] {
        restaurants.filter { ids.contains($0.id) }
    }

    @MainActor
    func load() async {
        guard restaurants.isEmpty, !isLoading else { return }
        isLoading = true
        if let cached = feed?.cached() {
            restaurants = cached
        } else {
            do {
                restaurants = try await repository.fetchRestaurants()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
        await refreshFromFeed()
    }

    /// Aduce lista actualizată de pe site, fără să blocheze afișarea celei existente.
    @MainActor
    func refreshFromFeed() async {
        guard let feed, let fresh = await feed.fetch() else { return }
        restaurants = fresh
        errorMessage = nil
    }
}
