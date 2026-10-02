import SwiftUI

@main
struct MamaCeBunApp: App {
    @State private var store = RestaurantStore()
    @State private var favorites = FavoritesStore()
    @State private var location = LocationManager()
    @State private var reviews: ReviewStore = {
        #if DEBUG
        if ScreenshotConfig.isActive {
            return ScreenshotConfig.clean ? ReviewStore(persistence: InMemoryReviewPersistence()) : .screenshotSeed()
        }
        #endif
        return ReviewStore()
    }()
    @State private var community = CommunityStore(service: CommunityServiceFactory.make())
    @State private var badges = BadgeCenter()

    init() {
        #if DEBUG && canImport(FirebaseFirestore)
        if FirebaseSmokeTest.isRequested {
            Task { await FirebaseSmokeTest.run() }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(store)
                .environment(favorites)
                .environment(location)
                .environment(reviews)
                .environment(community)
                .environment(badges)
        }
    }
}

enum AppTab: Hashable {
    case home
    case dish(Dish)
}

struct RootTabView: View {
    @Environment(RestaurantStore.self) private var store
    @Environment(LocationManager.self) private var location
    @Environment(ReviewStore.self) private var reviews
    @Environment(CommunityStore.self) private var community
    @Environment(FavoritesStore.self) private var favorites
    @Environment(BadgeCenter.self) private var badges
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: AppTab = .home
    @State private var celebration: BadgeCelebration?

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("Acasă", systemImage: "house.fill") }
                .tag(AppTab.home)

            ForEach(Dish.allCases) { dish in
                DishTabView(dish: dish)
                    .tabItem { Label(dish.shortName, systemImage: dish.tabSymbol) }
                    .tag(AppTab.dish(dish))
            }
        }
        .tint(tint)
        .onAppear {
            #if DEBUG
            if let tab = ScreenshotConfig.tab {
                if tab == "favorites" || tab == "home" {
                    selection = .home
                } else if let dish = Dish(rawValue: tab) {
                    selection = .dish(dish)
                }
            }
            #endif
        }
        .task {
            location.requestPermission()
            await store.load()
            // Media comunității + trimiterea notelor tale care n-au ajuns încă pe server.
            await community.refresh(syncing: Array(reviews.reviews.values))
            checkBadges()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { checkBadges() }
        }
        .sheet(item: $celebration) { item in
            BadgeCelebrationView(badges: item.badges) { celebration = nil }
                .presentationDetents([.medium, .large])
                // Marcate ca văzute abia când apar efectiv (o foaie peste altă foaie poate să nu apară).
                .onAppear { badges.markSeen(item.badges) }
        }
        .alert(
            "Ceva n-a mers",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            ),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(store.errorMessage ?? "") }
        )
    }

    /// Insigne câștigate în afara editorului de notă (ex. „Vreau să merg”, județe bifate).
    private func checkBadges() {
        #if DEBUG
        if ScreenshotConfig.isActive { return }
        #endif
        guard !store.restaurants.isEmpty else { return }
        let unlocked = badges.newlyUnlocked(reviews: reviews, favorites: favorites, restaurants: store)
        guard !unlocked.isEmpty, celebration?.badges.map(\.id) != unlocked.map(\.id) else { return }
        celebration = BadgeCelebration(badges: unlocked)
    }

    private var tint: Color {
        switch selection {
        case .home: .accentColor
        case .dish(let dish): dish.color
        }
    }
}
