import Foundation

#if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseFirestore)
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

/// Notele comunității în Cloud Firestore, cu autentificare anonimă (fără ecran de login).
///
/// Structura:
/// - `reviews/{restaurantID}_{dish}_{uid}`: restaurantID, dish, uid, score, comment, createdAt, updatedAt, reportCount
/// - `reports/{reviewID}_{uid}`: uid, reviewId, createdAt — un raport per utilizator per notă
/// - `suggestions/{auto}`: localuri propuse de utilizatori (status „pending”), văzute doar din consolă
/// Regulile de securitate sunt în `firestore.rules`, în rădăcina repo-ului.
final class FirebaseCommunityService: CommunityService {
    private var db: Firestore { Firestore.firestore() }

    var isAvailable: Bool { true }
    var currentUserID: String? { Auth.auth().currentUser?.uid }

    /// Configurează Firebase doar dacă există `GoogleService-Info.plist` în aplicație.
    static func configureIfPossible() -> Bool {
        if FirebaseApp.app() != nil { return true }
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return false }
        FirebaseApp.configure()
        return true
    }

    func signIn() async throws {
        try await SignInCoordinator.shared.signIn()
    }

    func fetchAll() async throws -> [CommunityReview] {
        let snapshot = try await db.collection("reviews").limit(to: 5000).getDocuments()
        return snapshot.documents.compactMap { Self.parse(id: $0.documentID, data: $0.data()) }
    }

    func submit(_ review: UserReview) async throws {
        try await signIn()
        guard let uid = currentUserID else { return }
        let ref = db.collection("reviews").document(
            CommunityReview.documentID(restaurantID: review.restaurantID, dish: review.dish, uid: uid)
        )
        let existing = try await ref.getDocument()
        if existing.exists {
            try await ref.updateData([
                "score": review.score,
                "comment": review.comment,
                "updatedAt": FieldValue.serverTimestamp()
            ])
        } else {
            try await ref.setData([
                "restaurantID": review.restaurantID,
                "dish": review.dish.rawValue,
                "uid": uid,
                "score": review.score,
                "comment": review.comment,
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp(),
                "reportCount": 0
            ])
        }
    }

    func delete(restaurantID: String, dish: Dish) async throws {
        try await signIn()
        guard let uid = currentUserID else { return }
        try await db.collection("reviews")
            .document(CommunityReview.documentID(restaurantID: restaurantID, dish: dish, uid: uid))
            .delete()
    }

    func report(_ review: CommunityReview) async throws {
        try await signIn()
        guard let uid = currentUserID, uid != review.uid else { return }
        let batch = db.batch()
        batch.setData(
            ["uid": uid, "reviewId": review.id, "createdAt": FieldValue.serverTimestamp()],
            forDocument: db.collection("reports").document("\(review.id)_\(uid)")
        )
        batch.updateData(
            ["reportCount": FieldValue.increment(Int64(1))],
            forDocument: db.collection("reviews").document(review.id)
        )
        try await batch.commit()
    }

    func suggest(_ suggestion: VenueSuggestion) async throws {
        try await signIn()
        guard let uid = currentUserID else { return }
        try await db.collection("suggestions").addDocument(data: [
            "name": suggestion.trimmedName,
            "city": suggestion.trimmedCity,
            "address": suggestion.address,
            "dishes": suggestion.orderedDishes.map(\.rawValue),
            "note": suggestion.note,
            "link": suggestion.link,
            "uid": uid,
            "status": "pending",
            "createdAt": FieldValue.serverTimestamp()
        ])
    }

    /// O singură autentificare anonimă odată: fără ea, două apeluri simultane (ex. reîncărcarea notelor
    /// și trimiterea unei note la prima pornire) creau doi utilizatori, iar scrierea pleca cu uid-ul unuia
    /// și token-ul celuilalt — refuzată de reguli.
    private actor SignInCoordinator {
        static let shared = SignInCoordinator()
        private var pending: Task<Void, Error>?

        func signIn() async throws {
            if Auth.auth().currentUser != nil { return }
            if let pending {
                try await pending.value
                return
            }
            let task = Task { _ = try await Auth.auth().signInAnonymously() }
            pending = task
            do {
                try await task.value
                pending = nil
            } catch {
                pending = nil
                throw error
            }
        }
    }

    private static func parse(id: String, data: [String: Any]) -> CommunityReview? {
        guard
            let restaurantID = data["restaurantID"] as? String,
            let dish = (data["dish"] as? String).flatMap(Dish.init(rawValue:)),
            let uid = data["uid"] as? String,
            let score = (data["score"] as? NSNumber)?.doubleValue
        else { return nil }
        return CommunityReview(
            id: id,
            restaurantID: restaurantID,
            dish: dish,
            uid: uid,
            score: score,
            comment: data["comment"] as? String ?? "",
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast,
            reportCount: (data["reportCount"] as? NSNumber)?.intValue ?? 0
        )
    }
}
#endif

enum CommunityServiceFactory {
    /// Firebase dacă e disponibil și configurat, altfel modul offline.
    static func make() -> CommunityService {
        #if DEBUG
        if ScreenshotConfig.isActive {
            // Capturi „curate” (fișe trimise localurilor): fără note de exemplu.
            return ScreenshotConfig.clean ? OfflineCommunityService() : ScreenshotCommunityService()
        }
        #if canImport(FirebaseFirestore)
        // Testul de fum din CI lucrează singur cu Firebase; restul aplicației rămâne offline.
        if FirebaseSmokeTest.isRequested { return OfflineCommunityService() }
        #endif
        #endif
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseFirestore)
        if FirebaseCommunityService.configureIfPossible() {
            return FirebaseCommunityService()
        }
        #endif
        return OfflineCommunityService()
    }
}
