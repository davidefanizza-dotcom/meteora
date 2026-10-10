import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @State private var busy = false

    var body: some View {
        @Bindable var s = app.settings
        let m = app.weather.mood
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: m.symbol)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 72))
                    .symbolEffect(.breathe, options: .repeating)
                    .padding(.top, 40)
                Text("Meteora").font(.system(size: 44, weight: .heavy))
                Text("La tua musica Spotify, con un mix che cambia insieme al meteo.")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 18) {
                    step(1, "Apri developer.spotify.com/dashboard e scegli la tua app (o creane una con **Web API**).")
                    VStack(alignment: .leading, spacing: 8) {
                        step(2, "In **Redirect URIs** aggiungi questo indirizzo:")
                        HStack {
                            Text(SpotifyAuth.redirectURI)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                            Spacer()
                            Button("Copia", systemImage: "doc.on.doc") {
                                UIPasteboard.general.string = SpotifyAuth.redirectURI
                                Toaster.shared.show("Redirect URI copiata", symbol: "doc.on.doc")
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.glass)
                        }
                        .padding(.leading, 38)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        step(3, "Incolla il **Client ID**:")
                        TextField("Client ID", text: $s.clientId)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.body.monospaced())
                            .padding(14)
                            .glassEffect(.regular, in: .rect(cornerRadius: 16))
                            .padding(.leading, 38)
                    }
                }
                .padding(20)
                .glassEffect(.regular, in: .rect(cornerRadius: 28))

                Button {
                    Task { await login() }
                } label: {
                    HStack {
                        if busy { ProgressView() } else { Image(systemName: "music.note") }
                        Text("Collega Spotify")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .disabled(busy || s.clientId.trimmingCharacters(in: .whitespaces).isEmpty)

                Text("Serve Spotify Premium. La musica suonerà nell'app Spotify, Meteora la comanda.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .background(WeatherBackground())
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.footnote.weight(.heavy))
                .frame(width: 26, height: 26)
                .glassEffect(.regular.tint(app.weather.mood.color.opacity(0.5)), in: .circle)
            Text(text)
        }
    }

    private func login() async {
        busy = true
        defer { busy = false }
        do {
            try await app.auth.login()
            Toaster.shared.show("Spotify collegato", symbol: "checkmark.circle.fill")
            await app.didLogin()
        } catch AuthError.cancelled {
        } catch {
            Toaster.shared.error(error)
        }
    }
}
