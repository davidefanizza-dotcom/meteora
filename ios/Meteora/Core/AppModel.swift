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
        player = PlayerController(api: api, library: lib, weather: w, settings: s, learn: l)
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
    }

    func logout() {
        player.reset()
        auth.logout()
        library.loaded = false
        library.me = nil
    }
}

enum AppTab: Hashable { case home, meteo, library, search }
