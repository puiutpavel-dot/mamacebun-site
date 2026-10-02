import SwiftUI
import MapKit
import CoreLocation

/// Bottom sheet-ul (stil Apple Maps) deschis la tap pe un pin sau pe un rând din listă.
struct RestaurantDetailView: View {
    let restaurant: Restaurant
    /// Preparatul tab-ului din care s-a deschis fișa (apare primul). `nil` = din „Traseul meu”.
    let focusDish: Dish?
    let userLocation: CLLocation?

    @Environment(\.openURL) private var openURL
    @Environment(FavoritesStore.self) private var favorites
    @Environment(ReviewStore.self) private var reviews
    @Environment(CommunityStore.self) private var community

    /// Preparatul pentru care e deschis editorul de notă.
    @State private var ratingDish: Dish?
    /// Poza deschisă pe tot ecranul.
    @State private var openedPhoto: VenuePhoto?

    private var tint: Color { (focusDish ?? restaurant.signatureDish).color }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                actions
                dishesSection
                if let summary = restaurant.localizedSummary {
                    Text(summary)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                photosSection
                infoSection
                sourcesSection
            }
            .padding(20)
            .padding(.top, 8)
        }
        .tint(tint)
        .sheet(item: $ratingDish) { dish in
            ReviewEditorView(restaurant: restaurant, dish: dish)
                .presentationDetents([.large])
        }
        .task {
            #if DEBUG
            // Capturi CI: deschide editorul de notă peste fișă.
            if let dish = ScreenshotConfig.reviewDish, ScreenshotConfig.detailID == restaurant.id {
                try? await Task.sleep(for: .seconds(1.5))
                ratingDish = dish
            }
            #endif
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(restaurant.name)
                .font(.title2.weight(.bold))

            HStack(spacing: 6) {
                Text(restaurant.kind.displayName)
                Text("·")
                Text(restaurant.county)
                if let distance {
                    Text("·")
                    Text(distance)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Label("\(restaurant.address), \(restaurant.city)" as String, systemImage: "mappin.and.ellipse")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if restaurant.coordinatesApproximate {
                Label("Poziția pe hartă e aproximativă", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var distance: String? {
        guard let userLocation else { return nil }
        return MKDistanceFormatter().string(fromDistance: userLocation.distance(from: restaurant.location))
    }

    // MARK: - Acțiuni

    private var actions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Menu {
                    Button("Apple Maps", systemImage: "map") { openURL(appleMapsURL) }
                    Button("Waze", systemImage: "car") { openURL(wazeURL) }
                } label: {
                    Label("Navighează", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                if let phoneURL {
                    Button {
                        openURL(phoneURL)
                    } label: {
                        Label("Sună", systemImage: "phone.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }

            HStack(spacing: 10) {
                Button {
                    favorites.toggleWant(restaurant)
                } label: {
                    Label("Vreau să merg", systemImage: favorites.isWanted(restaurant) ? "heart.fill" : "heart")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    favorites.toggleVisited(restaurant)
                } label: {
                    Label("Am fost", systemImage: favorites.isVisited(restaurant) ? "checkmark.seal.fill" : "checkmark.seal")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .sensoryFeedback(.success, trigger: favorites.isWanted(restaurant) || favorites.isVisited(restaurant))
        }
        .controlSize(.large)
    }

    private var appleMapsURL: URL {
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [
            URLQueryItem(name: "daddr", value: "\(restaurant.latitude),\(restaurant.longitude)"),
            URLQueryItem(name: "q", value: restaurant.name),
            URLQueryItem(name: "dirflg", value: "d")
        ]
        return components.url!
    }

    private var wazeURL: URL {
        // Universal link: deschide aplicația Waze dacă e instalată, altfel site-ul.
        URL(string: "https://waze.com/ul?ll=\(restaurant.latitude),\(restaurant.longitude)&navigate=yes")!
    }

    private var phoneURL: URL? {
        guard let phone = restaurant.phone else { return nil }
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        return URL(string: "tel:\(digits)")
    }

    // MARK: - Preparate

    private var dishesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(hasRatings ? LocalizedStringKey("Note pe preparate") : LocalizedStringKey("Recomandat pentru"))
                .font(.headline)
            ForEach(restaurant.displayedDishes(focus: focusDish)) { dish in
                DishRow(
                    dish: dish,
                    rating: community.rating(for: restaurant, dish: dish),
                    detail: restaurant.detail(for: dish),
                    isMenuOnly: restaurant.isMenuOnly(dish),
                    isFocused: dish == focusDish,
                    userReview: reviews.review(for: restaurant, dish: dish),
                    onRate: { ratingDish = dish },
                    comments: community.comments(for: restaurant, dish: dish),
                    onReport: { review in
                        Task { await community.report(review) }
                    },
                    onBlock: { review in
                        community.block(userID: review.uid)
                    }
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var hasRatings: Bool {
        Dish.allCases.contains { community.rating(for: restaurant, dish: $0) != nil }
    }

    // MARK: - Poze

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Poze")
                .font(.headline)

            if restaurant.photos.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "camera")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Încă nu există poze. Fii primul care adaugă una!")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(orderedPhotos) { photo in
                            Button {
                                openedPhoto = photo
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    AsyncImage(url: photo.url) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        Color(.tertiarySystemFill)
                                            .overlay { ProgressView() }
                                    }
                                    .frame(width: 220, height: 147)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))

                                    if let caption = photo.caption {
                                        HStack(spacing: 4) {
                                            if let dish = photo.dish {
                                                Text(dish.emoji)
                                            }
                                            Text(caption)
                                                .lineLimit(1)
                                        }
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(.primary)
                                    }
                                }
                                .frame(width: 220, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(photo.caption ?? restaurant.name)
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
        .fullScreenCover(item: $openedPhoto) { photo in
            PhotoViewer(photos: orderedPhotos, selection: photo)
        }
    }

    /// Pozele preparatului din tab-ul curent vin primele.
    private var orderedPhotos: [VenuePhoto] {
        guard let focus = focusDish else { return restaurant.photos }
        let first = restaurant.photos.filter { $0.dish == focus }
        return first + restaurant.photos.filter { $0.dish != focus }
    }

    // MARK: - Program & contact

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let hours = restaurant.openingHours {
                Label(hours, systemImage: "clock")
            }
            if let phone = restaurant.phone {
                Label(phone, systemImage: "phone")
            }
            if let website = restaurant.website {
                Link(destination: website) {
                    Label(website.host() ?? website.absoluteString, systemImage: "safari")
                }
            }
        }
        .font(.subheadline)
    }

    // MARK: - Surse

    @ViewBuilder
    private var sourcesSection: some View {
        if !restaurant.sources.isEmpty {
            DisclosureGroup("De ce e pe hartă (\(restaurant.sources.count) surse)") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(restaurant.sources, id: \.self) { url in
                        Link(destination: url) {
                            Text(url.host() ?? url.absoluteString)
                                .font(.footnote)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
            }
            .font(.subheadline)
        }
    }
}

private struct DishRow: View {
    let dish: Dish
    let rating: DishRating?
    let detail: DishDetail?
    let isMenuOnly: Bool
    let isFocused: Bool
    let userReview: UserReview?
    let onRate: () -> Void
    let comments: [CommunityReview]
    let onReport: (CommunityReview) -> Void
    let onBlock: (CommunityReview) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(dish.emoji)
                .font(isFocused ? .title2 : .title3)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(dish.displayName)
                        .fontWeight(isFocused ? .bold : .semibold)
                    Spacer()
                    if let rating {
                        Text(verbatim: "\(rating.score.formatted(.number.precision(.fractionLength(1))))/10")
                            .fontWeight(.bold)
                            .foregroundStyle(dish.color)
                    }
                }
                .font(isFocused ? .body : .subheadline)

                if let rating {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(.tertiarySystemFill))
                            Capsule()
                                .fill(dish.color)
                                .frame(width: proxy.size.width * min(max(rating.score / 10, 0), 1))
                        }
                    }
                    .frame(height: 6)

                } else {
                    if userReview == nil {
                        Text("Încă fără note — fii primul care dă o notă!")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                userReviewRow

                ForEach(comments) { comment in
                    CommentRow(review: comment, tint: dish.color, onReport: { onReport(comment) }, onBlock: { onBlock(comment) })
                }

                if isMenuOnly {
                    Label("Doar în meniu, încă neconfirmat de recenzii", systemImage: "questionmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if let detail {
                    if let note = detail.localizedNote {
                        Text(note)
                            .font(.caption)
                    }
                    if !detail.localizedTags.isEmpty {
                        TagsView(tags: detail.localizedTags, tint: dish.color)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Nota utilizatorului (sau butonul „Dă o notă”).
    @ViewBuilder
    private var userReviewRow: some View {
        if let userReview {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                    Text("Nota ta")
                    Text(verbatim: "\(UserReview.format(userReview.score))/10")
                        .fontWeight(.bold)
                        .monospacedDigit()
                    Text(verbatim: "·")
                    Text(UserReview.verdict(for: userReview.score))
                    Spacer(minLength: 8)
                    Button("Modifică", action: onRate)
                        .buttonStyle(.borderless)
                        .font(.caption.weight(.semibold))
                }
                .font(.caption)
                .foregroundStyle(dish.color)

                if !userReview.comment.isEmpty {
                    Text(verbatim: "„\(userReview.comment)”")
                        .font(.caption)
                        .italic()
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            .padding(.top, 2)
        } else {
            Button(action: onRate) {
                Label("Dă o notă", systemImage: "star")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(dish.color)
            .padding(.top, 2)
        }
    }
}

/// Comentariul altui utilizator, cu opțiunile de a-l raporta sau de a bloca autorul.
private struct CommentRow: View {
    let review: CommunityReview
    let tint: Color
    let onReport: () -> Void
    let onBlock: () -> Void

    @State private var confirmBlock = false

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "person.crop.circle.fill")
                .foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "„\(review.comment)”")
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                Text(verbatim: "\(UserReview.format(review.score))/10")
                    .fontWeight(.semibold)
                    .foregroundStyle(tint)
            }
            Spacer(minLength: 4)
            Menu {
                Button("Raportează", systemImage: "flag", role: .destructive, action: onReport)
                Button("Blochează utilizatorul", systemImage: "hand.raised", role: .destructive) {
                    confirmBlock = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 20)
                    .contentShape(Rectangle())
            }
            .confirmationDialog("Blochezi acest utilizator?", isPresented: $confirmBlock, titleVisibility: .visible) {
                Button("Blochează", role: .destructive, action: onBlock)
            } message: {
                Text("Nu vei mai vedea niciun comentariu de la el. Poți anula din „Despre aplicație”.")
            }
        }
        .font(.caption)
        .padding(.top, 2)
    }
}

#if DEBUG
#Preview {
    RestaurantDetailView(restaurant: .preview, focusDish: .papanasi, userLocation: nil)
        .environment(FavoritesStore())
        .environment(ReviewStore(persistence: InMemoryReviewPersistence()))
        .environment(CommunityStore(service: OfflineCommunityService()))
}
#endif

/// Pozele pe tot ecranul, cu swipe între ele.
private struct PhotoViewer: View {
    let photos: [VenuePhoto]
    @State var selection: VenuePhoto
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $selection) {
                ForEach(photos) { photo in
                    VStack(spacing: 16) {
                        Spacer()
                        AsyncImage(url: photo.url) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            ProgressView().tint(.white)
                        }
                        if let caption = photo.caption {
                            Text(caption)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        Spacer()
                    }
                    .tag(photo)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .white.opacity(0.25))
            }
            .padding()
            .accessibilityLabel(Text("Închide"))
        }
    }
}
