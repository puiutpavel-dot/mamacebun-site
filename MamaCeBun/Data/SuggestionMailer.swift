import Foundation

/// Trimite localurile propuse pe e-mail la dezvoltator, printr-un formular Formspree
/// (fără server propriu). Dacă `endpoint` e gol, rămâne doar copia din Firestore.
enum SuggestionMailer {
    /// Ex. `https://formspree.io/f/abcdwxyz` — se completează după ce dezvoltatorul își face formularul.
    static let endpoint: URL? = URL(string: "https://formspree.io/f/xppwevrd")

    static func send(_ suggestion: VenueSuggestion) async -> Bool {
        guard let endpoint else { return false }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let payload: [String: Any] = [
            "_subject": "Local nou propus: \(suggestion.trimmedName) (\(suggestion.trimmedCity))",
            "nume": suggestion.trimmedName,
            "localitate": suggestion.trimmedCity,
            "adresa": suggestion.address,
            "preparate": suggestion.orderedDishes.map(\.rawValue).joined(separator: ", "),
            "de_ce_e_bun": suggestion.note,
            "link": suggestion.link,
            "message": suggestion.emailBody
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return false }
        request.httpBody = body
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
        } catch {
            return false
        }
    }
}
