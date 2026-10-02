import Foundation

/// Un local propus de un utilizator. Ajunge la dezvoltator (Firestore `suggestions` + e-mail),
/// care îl verifică și, dacă îl aprobă, îl adaugă în baza de date la următorul update.
struct VenueSuggestion: Hashable {
    var name: String
    var city: String
    var address: String
    var dishes: Set<Dish>
    var note: String
    var link: String

    static let maxNote = 280

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedCity: String { city.trimmingCharacters(in: .whitespacesAndNewlines) }

    var isComplete: Bool {
        trimmedName.count >= 2 && trimmedCity.count >= 2 && !dishes.isEmpty && note.count <= Self.maxNote
    }

    /// Fără cuvinte nepotrivite în niciun câmp.
    var isClean: Bool {
        [name, city, address, note].allSatisfy(ContentFilter.isAllowed)
    }

    /// Preparatele în ordinea fixă din aplicație.
    var orderedDishes: [Dish] { Dish.allCases.filter(dishes.contains) }

    /// Textul e-mailului primit de dezvoltator.
    var emailBody: String {
        var lines = [
            "Local propus în aplicația Mamă, ce Bun!",
            "",
            "Nume: \(trimmedName)",
            "Localitate: \(trimmedCity)",
            "Adresă: \(address.isEmpty ? "-" : address)",
            "Preparate: \(orderedDishes.map(\.rawValue).joined(separator: ", "))",
            "De ce e bun: \(note.isEmpty ? "-" : note)",
            "Link: \(link.isEmpty ? "-" : link)"
        ]
        lines.append("")
        lines.append("Răspunde lui Claude cu „aprob” sau „resping” ca să intre (sau nu) în următorul update.")
        return lines.joined(separator: "\n")
    }
}
