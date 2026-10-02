import SwiftUI

/// „Propune un local”: un loc unde se mănâncă bine mici, papanași sau ciorbă de burtă.
/// Propunerea ajunge la dezvoltator, care o verifică înainte să apară în aplicație.
struct SuggestVenueView: View {
    @Environment(CommunityStore.self) private var community
    @Environment(\.dismiss) private var dismiss

    @State private var suggestion = VenueSuggestion(name: "", city: "", address: "", dishes: [], note: "", link: "")
    @State private var isSending = false
    @State private var showBlocked = false
    @State private var showFailed = false
    @State private var sent = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Numele localului", text: $suggestion.name)
                        .textContentType(.organizationName)
                    TextField("Localitatea", text: $suggestion.city)
                        .textContentType(.addressCity)
                    TextField("Adresa (opțional)", text: $suggestion.address)
                        .textContentType(.fullStreetAddress)
                } header: {
                    Text("Localul")
                }

                Section {
                    ForEach(Dish.allCases) { dish in
                        Toggle(isOn: Binding(
                            get: { suggestion.dishes.contains(dish) },
                            set: { isOn in
                                if isOn { suggestion.dishes.insert(dish) } else { suggestion.dishes.remove(dish) }
                            }
                        )) {
                            Text(verbatim: "\(dish.emoji) \(dish.displayName)")
                        }
                        .tint(dish.color)
                    }
                } header: {
                    Text("Ce se mănâncă bine aici?")
                }

                Section {
                    TextField("De ce merită? (opțional)", text: $suggestion.note, axis: .vertical)
                        .lineLimit(3...6)
                    TextField("Link: site, Facebook sau Google Maps (opțional)", text: $suggestion.link)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Verificăm fiecare propunere înainte să apară în aplicație.")
                }
            }
            .navigationTitle("Propune un local")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anulează") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("Trimite") { send() }
                            .fontWeight(.semibold)
                            .disabled(!suggestion.isComplete)
                    }
                }
            }
            .alert("Text nepotrivit", isPresented: $showBlocked) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Te rugăm să reformulezi fără cuvinte nepotrivite.")
            }
            .alert("Nu s-a putut trimite", isPresented: $showFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Verifică legătura la internet și încearcă din nou.")
            }
            .alert("Mulțumim!", isPresented: $sent) {
                Button("OK") { dismiss() }
            } message: {
                Text("Am primit propunerea. După ce o verificăm, localul apare în aplicație.")
            }
        }
    }

    private func send() {
        guard suggestion.isClean else {
            showBlocked = true
            return
        }
        isSending = true
        Task {
            let ok = await community.suggest(suggestion)
            isSending = false
            if ok { sent = true } else { showFailed = true }
        }
    }
}
