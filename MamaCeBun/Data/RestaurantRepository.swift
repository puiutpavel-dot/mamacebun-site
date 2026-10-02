import Foundation

/// Sursa de date pentru localuri. UI-ul depinde doar de acest protocol,
/// așa că trecerea de la JSON local la Firebase înseamnă doar o nouă implementare.
protocol RestaurantRepository {
    func fetchRestaurants() async throws -> [Restaurant]
}

enum RepositoryError: LocalizedError {
    case fileNotFound(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let name): String(localized: "Nu am găsit fișierul de date „\(name).json”.")
        }
    }
}

/// MVP: citește localurile dintr-un JSON inclus în aplicație.
struct LocalJSONRestaurantRepository: RestaurantRepository {
    var fileName = "restaurants"
    var bundle: Bundle = .main

    func fetchRestaurants() async throws -> [Restaurant] {
        guard let url = bundle.url(forResource: fileName, withExtension: "json") else {
            throw RepositoryError.fileNotFound(fileName)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([Restaurant].self, from: data)
    }
}

/// Lista actualizată de localuri, publicată pe site. Așa pot apărea localuri noi
/// (de exemplu propunerile aprobate) fără o versiune nouă în App Store.
/// Dacă nu e internet, folosește ultima listă descărcată sau, la nevoie, pe cea din aplicație.
struct RemoteRestaurantFeed {
    static let url = URL(string: "https://puiutpavel-dot.github.io/mamacebun-site/data/restaurants.json")!
    /// O listă mai scurtă de atât e considerată greșită și ignorată.
    static let minimumCount = 30

    /// Cache-ul e legat de build: după o actualizare din App Store pornim de la lista inclusă.
    private var cacheURL: URL? {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("restaurants-\(build).json")
    }

    func cached() -> [Restaurant]? {
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL) else { return nil }
        return Self.validated(data)
    }

    func fetch() async -> [Restaurant]? {
        var request = URLRequest(url: Self.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let result = try? await URLSession.shared.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              let restaurants = Self.validated(result.0) else { return nil }
        if let cacheURL { try? result.0.write(to: cacheURL, options: .atomic) }
        return restaurants
    }

    private static func validated(_ data: Data) -> [Restaurant]? {
        guard let list = try? JSONDecoder().decode([Restaurant].self, from: data),
              list.count >= minimumCount,
              Set(list.map(\.id)).count == list.count else { return nil }
        return list
    }
}

// Pasul următor (Firebase):
//
// import FirebaseFirestore
//
// struct FirestoreRestaurantRepository: RestaurantRepository {
//     private let db = Firestore.firestore()
//
//     func fetchRestaurants() async throws -> [Restaurant] {
//         let snapshot = try await db.collection("restaurants").getDocuments()
//         return try snapshot.documents.map { try $0.data(as: Restaurant.self) }
//     }
// }
//
// Apoi, în MamaCeBunApp: RestaurantStore(repository: FirestoreRestaurantRepository())
