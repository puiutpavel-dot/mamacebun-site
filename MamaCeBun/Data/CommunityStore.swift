import Foundation
import Observation

/// O notă dată de un utilizator oarecare (inclusiv de tine), așa cum vine de la server.
struct CommunityReview: Identifiable, Hashable {
    let id: String
    let restaurantID: String
    let dish: Dish
    let uid: String
    let score: Double
    let comment: String
    let updatedAt: Date
    let reportCount: Int

    /// Comentariile raportate de cel puțin atâția utilizatori nu mai apar nimănui.
    static let hideAfterReports = 3
    var isHidden: Bool { reportCount >= Self.hideAfterReports }

    /// Id-ul documentului: o singură notă per utilizator, local și preparat.
    static func documentID(restaurantID: String, dish: Dish, uid: String) -> String {
        "\(restaurantID)_\(dish.rawValue)_\(uid)"
    }
}

/// Media comunității pentru un preparat dintr-un local.
struct CommunityStats: Hashable {
    let average: Double
    let count: Int
}

/// Serverul de note. Azi: Firebase (dacă e configurat) sau nimic. Interfața nu depinde de Firebase.
protocol CommunityService: AnyObject {
    var isAvailable: Bool { get }
    var currentUserID: String? { get }
    func signIn() async throws
    func fetchAll() async throws -> [CommunityReview]
    func submit(_ review: UserReview) async throws
    func delete(restaurantID: String, dish: Dish) async throws
    func report(_ review: CommunityReview) async throws
    /// Salvează un local propus (doar scriere; numai dezvoltatorul îl vede, din consolă).
    func suggest(_ suggestion: VenueSuggestion) async throws
}

extension CommunityService {
    func suggest(_ suggestion: VenueSuggestion) async throws {}
}

/// Fără server: aplicația merge ca înainte, doar cu notele tale.
final class OfflineCommunityService: CommunityService {
    var isAvailable: Bool { false }
    var currentUserID: String? { nil }
    func signIn() async throws {}
    func fetchAll() async throws -> [CommunityReview] { [] }
    func submit(_ review: UserReview) async throws {}
    func delete(restaurantID: String, dish: Dish) async throws {}
    func report(_ review: CommunityReview) async throws {}
}

/// Notele tuturor utilizatorilor: medii pe local și preparat + comentarii.
@MainActor
@Observable
final class CommunityStore {
    private(set) var reviews: [CommunityReview] = []
    private(set) var stats: [String: CommunityStats] = [:]
    private(set) var isLoading = false
    var lastError: String?

    @ObservationIgnored private let service: CommunityService
    @ObservationIgnored private let defaults: UserDefaults
    private static let reportedKey = "community.reportedReviewIDs"
    /// Comentariile raportate de tine — ascunse imediat pe telefonul tău.
    private(set) var reportedByMe: Set<String>
    private static let blockedKey = "community.blockedUserIDs"
    /// Utilizatorii blocați de tine — nu le mai vezi niciun comentariu.
    private(set) var blockedUsers: Set<String>
    private static let termsKey = "community.termsAccepted"
    /// Ai acceptat regulile comunității (o singură dată, înainte de primul comentariu public).
    private(set) var hasAcceptedTerms: Bool

    init(service: CommunityService, defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
        reportedByMe = Set(defaults.stringArray(forKey: Self.reportedKey) ?? [])
        blockedUsers = Set(defaults.stringArray(forKey: Self.blockedKey) ?? [])
        hasAcceptedTerms = defaults.bool(forKey: Self.termsKey)
    }

    func acceptTerms() {
        hasAcceptedTerms = true
        defaults.set(true, forKey: Self.termsKey)
    }

    func block(userID: String) {
        blockedUsers.insert(userID)
        defaults.set(Array(blockedUsers), forKey: Self.blockedKey)
    }

    func unblockAll() {
        blockedUsers.removeAll()
        defaults.removeObject(forKey: Self.blockedKey)
    }

    var isAvailable: Bool { service.isAvailable }
    var currentUserID: String? { service.currentUserID }

    func stats(for restaurant: Restaurant, dish: Dish) -> CommunityStats? {
        stats[UserReview.key(restaurantID: restaurant.id, dish: dish)]
    }

    /// Câte note trebuie să aibă un local ca să intre în clasament.
    static let minimumForRanking = 3

    /// Media folosită la ordonare (doar dacă sunt destule note).
    func rankingScore(for restaurant: Restaurant, dish: Dish) -> Double? {
        guard let stats = stats(for: restaurant, dish: dish), stats.count >= Self.minimumForRanking else { return nil }
        return stats.average
    }

    /// Media comunității în formatul folosit de ecrane; altfel nota din baza de date (dacă există).
    func rating(for restaurant: Restaurant, dish: Dish) -> DishRating? {
        if let stats = stats(for: restaurant, dish: dish) {
            return DishRating(dish: dish, score: stats.average, reviewCount: stats.count)
        }
        return restaurant.rating(for: dish)
    }

    /// Comentariile altora (fără ale tale, fără cele ascunse), cele mai noi primele.
    func comments(for restaurant: Restaurant, dish: Dish, limit: Int = 3) -> [CommunityReview] {
        reviews
            .filter {
                $0.restaurantID == restaurant.id && $0.dish == dish && !$0.comment.isEmpty
                    && !$0.isHidden && !reportedByMe.contains($0.id) && !blockedUsers.contains($0.uid)
                    && $0.uid != currentUserID
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map { $0 }
    }

    /// Se conectează, trimite notele tale care nu au ajuns încă pe server și descarcă tot.
    func refresh(syncing local: [UserReview]) async {
        guard service.isAvailable, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await service.signIn()
            var fetched = try await service.fetchAll()
            if let uid = service.currentUserID {
                let mine = Dictionary(
                    fetched.filter { $0.uid == uid }.map { (UserReview.key(restaurantID: $0.restaurantID, dish: $0.dish), $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                let pending = local.filter { review in
                    guard let remote = mine[review.id] else { return true }
                    return remote.score != review.score || remote.comment != review.comment
                }
                for review in pending {
                    try await service.submit(review)
                }
                if !pending.isEmpty {
                    fetched = try await service.fetchAll()
                }
            }
            apply(fetched)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func submit(_ review: UserReview) async {
        guard service.isAvailable else { return }
        do {
            try await service.submit(review)
            if let uid = service.currentUserID {
                var updated = reviews.filter {
                    !($0.uid == uid && $0.restaurantID == review.restaurantID && $0.dish == review.dish)
                }
                updated.append(CommunityReview(
                    id: CommunityReview.documentID(restaurantID: review.restaurantID, dish: review.dish, uid: uid),
                    restaurantID: review.restaurantID, dish: review.dish, uid: uid,
                    score: review.score, comment: review.comment, updatedAt: review.date, reportCount: 0
                ))
                apply(updated)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func delete(restaurant: Restaurant, dish: Dish) async {
        guard service.isAvailable else { return }
        do {
            try await service.delete(restaurantID: restaurant.id, dish: dish)
            if let uid = service.currentUserID {
                apply(reviews.filter { !($0.uid == uid && $0.restaurantID == restaurant.id && $0.dish == dish) })
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Șterge de pe server toate notele tale (inclusiv comentariile). Întoarce `false` dacă ceva n-a mers.
    func deleteAllMine() async -> Bool {
        guard service.isAvailable else { return true }
        do {
            try await service.signIn()
            guard let uid = service.currentUserID else { return true }
            let mine = try await service.fetchAll().filter { $0.uid == uid }
            for review in mine {
                try await service.delete(restaurantID: review.restaurantID, dish: review.dish)
            }
            apply(reviews.filter { $0.uid != uid })
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func report(_ review: CommunityReview) async {
        reportedByMe.insert(review.id)
        defaults.set(Array(reportedByMe), forKey: Self.reportedKey)
        guard service.isAvailable else { return }
        do {
            try await service.report(review)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Trimite un local propus: în Firestore și, dacă e configurat, pe e-mail la dezvoltator.
    /// Întoarce `true` dacă a ajuns măcar pe una dintre căi.
    func suggest(_ suggestion: VenueSuggestion) async -> Bool {
        var delivered = false
        if service.isAvailable {
            do {
                try await service.suggest(suggestion)
                delivered = true
            } catch {
                lastError = error.localizedDescription
            }
        }
        if await SuggestionMailer.send(suggestion) { delivered = true }
        return delivered
    }

    private func apply(_ all: [CommunityReview]) {
        reviews = all
        var sums: [String: (total: Double, count: Int)] = [:]
        for review in all where !review.isHidden {
            let key = UserReview.key(restaurantID: review.restaurantID, dish: review.dish)
            sums[key, default: (0, 0)].total += review.score
            sums[key, default: (0, 0)].count += 1
        }
        stats = sums.mapValues { CommunityStats(average: $0.total / Double($0.count), count: $0.count) }
    }
}

#if DEBUG
/// Date de comunitate inventate, doar pentru capturile din CI și Xcode Previews.
final class ScreenshotCommunityService: CommunityService {
    var isAvailable: Bool { true }
    var currentUserID: String? { "me" }
    func signIn() async throws {}
    func submit(_ review: UserReview) async throws {}
    func delete(restaurantID: String, dish: Dish) async throws {}
    func report(_ review: CommunityReview) async throws {}

    func fetchAll() async throws -> [CommunityReview] {
        var result: [CommunityReview] = []
        func add(_ restaurantID: String, _ dish: Dish, _ scores: [Double], comments: [String] = []) {
            for (index, score) in scores.enumerated() {
                result.append(CommunityReview(
                    id: "\(restaurantID)_\(dish.rawValue)_seed\(index)",
                    restaurantID: restaurantID, dish: dish, uid: "seed\(index)", score: score,
                    comment: index < comments.count ? comments[index] : "",
                    updatedAt: Date(timeIntervalSinceNow: Double(-3600 * (index + 1))), reportCount: 0
                ))
            }
        }
        add("hanu-lui-manuc", .ciorbaDeBurta,
            [9, 8.5, 9, 8, 9.5, 8.5, 9, 8, 8.5, 9, 9, 8.5, 7.5, 9, 9.5, 8.5, 9, 8, 9, 8.5, 9, 8.5],
            comments: [
                String(localized: "Porție mare, smântână din belșug și ardei iute la cerere."),
                String(localized: "Merită drumul prin Centrul Vechi.")
            ])
        add("caru-cu-bere", .papanasi, [9, 9.5, 9, 8.5, 9.5, 9, 9, 9.5, 8.5, 9, 9.5, 9])
        add("caru-cu-bere", .mici, [8, 8.5, 7.5, 8, 8.5, 8])
        add("vatra", .papanasi, [8.5, 9, 8, 8.5, 9])
        return result
    }
}
#endif
