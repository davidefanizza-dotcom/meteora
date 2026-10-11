import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var cityQuery = ""
    @State private var cities: [CityResult] = []
    @State private var confirmReset = false
    @State private var confirmLogout = false

    var body: some View {
        @Bindable var s = app.settings
        NavigationStack {
            Form {
                Section("Spotify") {
                    if let me = app.library.me {
                        LabeledContent("Account", value: me.displayName ?? me.id)
                    }
                    TextField("Client ID", text: $s.clientId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Redirect URI da registrare").font(.subheadline.weight(.semibold))
                        HStack {
                            Text(SpotifyAuth.redirectURI).font(.caption.monospaced()).foregroundStyle(.secondary)
                            Spacer()
                            Button("Copia", systemImage: "doc.on.doc") {
                                UIPasteboard.general.string = SpotifyAuth.redirectURI
                                Toaster.shared.show("Redirect URI copiata", symbol: "doc.on.doc")
                            }
                            .labelStyle(.iconOnly)
                        }
                    }
                    Button("Esci da Spotify", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        confirmLogout = true
                    }
                }

                Section {
                    Toggle("Usa la mia posizione", isOn: $s.useLocation)
                    if !s.useLocation {
                        TextField("Cerca una città…", text: $cityQuery)
                            .task(id: cityQuery) {
                                try? await Task.sleep(for: .milliseconds(350))
                                guard !Task.isCancelled, cityQuery.count >= 2 else { cities = []; return }
                                cities = await app.weather.searchCity(cityQuery)
                            }
                        ForEach(cities) { c in
                            Button {
                                s.cityName = c.name
                                s.lat = c.lat
                                s.lon = c.lon
                                cities = []
                                cityQuery = ""
                                Task { await app.weather.refresh() }
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(c.name)
                                    Text(c.detail).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    LabeledContent("Città attuale", value: s.cityName)
                } header: {
                    Text("Posizione")
                }

                Section("Meteo Mix") {
                    Toggle("Adattamento automatico", isOn: $s.autoAdapt)
                    Toggle(isOn: $s.keepAwake) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Funziona a schermo bloccato")
                            Text("Meteo Mix e Momenti continuano anche col telefono in tasca").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: s.keepAwake) { _, _ in app.player.updateKeepAlive() }
                    Picker("Controlla il meteo ogni", selection: $s.intervalMin) {
                        Text("5 minuti").tag(5)
                        Text("10 minuti").tag(10)
                        Text("15 minuti").tag(15)
                        Text("30 minuti").tag(30)
                        Text("1 ora").tag(60)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Preferiti o scoperte").font(.subheadline.weight(.semibold))
                        Slider(value: $s.mixFav, in: 0...100, step: 5)
                        Text("\(Int(s.mixFav))% dai tuoi gusti · \(100 - Int(s.mixFav))% nuove scoperte")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Picker("Meteo", selection: $s.simulated) {
                        Label("Reale", systemImage: "location.fill").tag(Mood?.none)
                        ForEach(Mood.allCases) { m in
                            Label(m.name, systemImage: m.symbol).tag(Mood?.some(m))
                        }
                    }
                }

                Section("Aspetto") {
                    Picker("Tema", selection: $s.theme) {
                        Text("Sistema").tag(0)
                        Text("Scuro").tag(1)
                        Text("Chiaro").tag(2)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Animazione meteo di sfondo", isOn: $s.animateWeather)
                    Toggle("Vibrazioni", isOn: $s.haptics)
                }

                Section("Dati") {
                    LabeledContent("Gusti imparati", value: "\(app.learn.totalCount) brani")
                    Button("Azzera i gusti per meteo", systemImage: "trash", role: .destructive) { confirmReset = true }
                }

                Section {
                    LabeledContent("Versione", value: Bundle.main.versionText)
                } footer: {
                    Text("La musica suona nell'app Spotify: Meteora la comanda e sceglie i brani in base al meteo.")
                }
            }
            .navigationTitle("Impostazioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine", systemImage: "checkmark") { dismiss() }
                }
            }
            .confirmationDialog("Azzerare i gusti?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Azzera", role: .destructive) {
                    app.learn.reset()
                    Toaster.shared.show("Gusti azzerati", symbol: "trash")
                }
            } message: {
                Text("Meteora dimenticherà i 👍 e 👎 che hai dato per ogni meteo.")
            }
            .confirmationDialog("Uscire da Spotify?", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("Esci", role: .destructive) {
                    dismiss()
                    app.logout()
                }
            }
        }
    }
}

extension Bundle {
    var versionText: String {
        let v = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}
