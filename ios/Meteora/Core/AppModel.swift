import SwiftUI

@MainActor @Observable
final class AppModel {
    let settings: Settings
    let auth: SpotifyAuth
    let api: SpotifyAPI
    let weather: WeatherService
    let library: LibraryStore
    let learn: LearnStore
    let player: PlayerController
    let analysis: AnalysisStore
    let moments: MomentsStore

    var showNowPlaying = false
    var showSettings = false
    var tab: AppTab = .home

    init() {
        let s = Settings()
        settings = s
        let a = SpotifyAuth(clientId: { s.clientId })
        auth = a
        let api = SpotifyAPI(auth: a)
        self.api = api
        let w = WeatherService(settings: s)
        weather = w
        let lib = LibraryStore(api: api)
        library = lib
        let l = LearnStore()
        learn = l
        let an = AnalysisStore()
        analysis = an
        moments = MomentsStore()
        player = PlayerController(api: api, library: lib, weather: w, settings: s, learn: l, analysis: an)
    }

    func becameActive() {
        Task { await weather.refreshIfStale() }
        guard auth.isLoggedIn else { return }
        if !library.loaded { Task { await library.load() } }
        player.becameActive()
    }

    func didLogin() async {
        await library.load()
        player.startPolling()
        analyzeLibrary()
    }

    func analyzeLibrary() {
        guard library.loaded else { return }
        let favs = library.favorites
        Task { await analysis.analyzeLibrary(favs) }
    }

    var momentEditor: MomentDraft?

    func logout() {
        player.reset()
        auth.logout()
        library.loaded = false
        library.me = nil
    }
}

enum AppTab: Hashable { case home, meteo, moments, library, search }

/// Cosa aprire nell'editor dei momenti.
struct MomentDraft: Identifiable {
    let id = UUID()
    let track: Track
    var item: MomentItem? = nil
    var listId: String? = nil
}
