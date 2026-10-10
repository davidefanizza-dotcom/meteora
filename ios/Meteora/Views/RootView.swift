import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Namespace private var ns

    var body: some View {
        @Bindable var app = app
        ZStack(alignment: .top) {
            if app.auth.isLoggedIn {
                tabs
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
            ToastView()
        }
        .animation(.smooth, value: app.auth.isLoggedIn)
        .onChange(of: app.weather.mood) { _, new in
            app.player.moodChanged(to: new)
        }
        .task {
            await app.weather.refreshIfStale()
        }
    }

    private var tabs: some View {
        @Bindable var app = app
        return TabView(selection: $app.tab) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                NavigationStack { HomeView() }
            }
            Tab("Meteo Mix", systemImage: app.weather.mood.symbol, value: AppTab.meteo) {
                NavigationStack { MeteoView() }
            }
            Tab("Libreria", systemImage: "square.stack.fill", value: AppTab.library) {
                NavigationStack { LibraryView() }
            }
            Tab(value: AppTab.search, role: .search) {
                NavigationStack { SearchView() }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            MiniPlayer()
                .matchedTransitionSource(id: "nowplaying", in: ns)
        }
        .fullScreenCover(isPresented: $app.showNowPlaying) {
            NowPlayingView()
                .navigationTransition(.zoom(sourceID: "nowplaying", in: ns))
        }
        .sheet(isPresented: $app.showSettings) {
            SettingsView()
        }
        .task {
            if !app.library.loaded { await app.library.load() }
            app.player.startPolling()
        }
    }
}

struct ToastView: View {
    var body: some View {
        let t = Toaster.shared
        Group {
            if let item = t.current {
                HStack(spacing: 10) {
                    Image(systemName: item.symbol)
                        .symbolEffect(.bounce, value: item.id)
                        .foregroundStyle(.tint)
                    Text(item.text)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: .capsule)
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .id(item.id)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { t.current = nil }
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.3), value: t.current)
    }
}

/// Mini player nella barra in basso: in iOS 26 è un accessorio di vetro della tab bar.
struct MiniPlayer: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let p = app.player
        HStack(spacing: 12) {
            Cover(url: p.current?.imageURL, radius: 8)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 0) {
                Text(p.current?.name ?? "Niente in riproduzione")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(p.current?.artistLine ?? "Tocca ▶︎ per il Meteo Mix")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button {
                Task { await p.toggle() }
            } label: {
                Image(systemName: p.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            Button {
                Task { await p.next() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.body)
                    .frame(width: 32, height: 36)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .contentShape(.rect)
        .onTapGesture {
            if p.current != nil { app.showNowPlaying = true }
        }
        .sensoryFeedback(.selection, trigger: p.isPlaying) { _, _ in app.settings.haptics }
    }
}
