import SwiftUI

struct MeteoView: View {
    @Environment(AppModel.self) private var app
    @Namespace private var glassNS

    var body: some View {
        @Bindable var settings = app.settings
        let w = app.weather, p = app.player, m = w.mood
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Hero
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center, spacing: 18) {
                        Image(systemName: m.symbol)
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 76))
                            .symbolEffect(.breathe, options: .repeating)
                            .contentTransition(.symbolEffect(.replace))
                        VStack(alignment: .leading, spacing: 4) {
                            Label(w.place + (settings.simulated != nil ? " · simulato" : ""), systemImage: "location.fill")
                                .font(.caption.weight(.bold)).textCase(.uppercase).foregroundStyle(.secondary)
                            Text(m.name).font(.largeTitle.weight(.heavy))
                            Text(m.desc).foregroundStyle(.secondary)
                        }
                    }
                    if let t = w.temp {
                        HStack(spacing: 14) {
                            Label("\(t)°", systemImage: "thermometer.medium")
                            if let f = w.feels { Text("percepiti \(f)°").foregroundStyle(.secondary) }
                            Label("\(w.wind) km/h", systemImage: "wind")
                        }
                        .font(.subheadline.weight(.medium))
                        .contentTransition(.numericText())
                    }

                    GlassEffectContainer(spacing: 12) {
                        HStack(spacing: 12) {
                            Button {
                                Task { await p.startMix() }
                            } label: {
                                Label(p.mode == .meteo ? "Ricomincia" : "Avvia Meteo Mix", systemImage: "play.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.glassProminent)
                            Button {
                                Task { await p.regenerate() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.headline)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.glass)
                        }
                    }
                    .disabled(p.building)
                    .overlay {
                        if p.building { ProgressView() }
                    }

                    Toggle(isOn: $settings.autoAdapt) {
                        Label("La coda segue il meteo", systemImage: "sparkles")
                    }
                }
                .padding(22)
                .glassEffect(.regular.tint(m.color.opacity(0.2)), in: .rect(cornerRadius: 32))

                // Simulazione
                VStack(alignment: .leading, spacing: 10) {
                    Text("Prova un meteo").font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        GlassEffectContainer(spacing: 8) {
                            HStack(spacing: 8) {
                                chip(nil, label: "Reale", symbol: "location.fill")
                                ForEach(Mood.allCases) { mood in
                                    chip(mood, label: mood.name, symbol: mood.symbol)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .scrollClipDisabled()
                }

                // Previsioni
                if !w.hours.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Prossime ore").font(.headline)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(forecast(w), id: \.hour.id) { item in
                                    let h = item.hour, changed = item.changed
                                    VStack(spacing: 8) {
                                        Text(h.label).font(.caption).foregroundStyle(.secondary)
                                        Image(systemName: h.mood.symbol)
                                            .symbolRenderingMode(.multicolor)
                                            .font(.title2)
                                            .frame(height: 30)
                                        Text("\(h.temp)°").font(.subheadline.weight(.bold))
                                    }
                                    .frame(width: 62)
                                    .padding(.vertical, 12)
                                    .overlay(alignment: .topTrailing) {
                                        if changed {
                                            Circle().fill(.tint).frame(width: 7, height: 7).padding(7)
                                        }
                                    }
                                    .glassEffect(.regular, in: .rect(cornerRadius: 18))
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .scrollClipDisabled()
                        if settings.simulated == nil, let c = w.nextChange {
                            Label("Alle \(c.label) si passa a \(c.mood.name): " + (settings.autoAdapt ? "la coda si adatterà da sola." : "attiva l'adattamento per seguirlo."),
                                  systemImage: "sparkles")
                                .font(.footnote.weight(.semibold))
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .glassEffect(.regular.tint(m.color.opacity(0.25)), in: .rect(cornerRadius: 16))
                        }
                    }
                }

                // Coda
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "La coda del cielo")
                    if p.mode == .meteo {
                        HStack(spacing: 14) {
                            Text("**\(max(0, p.queue.count - p.idx - 1))** in arrivo")
                            Text("**\(Int(settings.mixFav))%** dai tuoi gusti")
                            Text("**\(app.learn.learnedCount(m))** imparati")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        LazyVStack(spacing: 0) {
                            ForEach(Array(p.queue.enumerated()), id: \.offset) { i, t in
                                TrackRow(track: t, index: i, showReason: true, showFeedback: true, dimmed: i < p.idx) {
                                    Task { await p.playAt(i) }
                                }
                            }
                        }
                    } else {
                        EmptyState(symbol: m.symbol, title: "Premi “Avvia Meteo Mix”",
                                   message: "Mescolo i tuoi brani preferiti e nuove scoperte in base al meteo di \(w.place). Con 👍 e 👎 impara cosa ti piace per ogni tempo.")
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(WeatherBackground())
        .navigationTitle("Meteo Mix")
        .refreshable { await w.refresh() }
    }

    private func forecast(_ w: WeatherService) -> [(hour: HourForecast, changed: Bool)] {
        var prev = w.real
        return w.hours.map { h in
            defer { prev = h.mood }
            return (h, h.mood != prev)
        }
    }

    @ViewBuilder
    private func chip(_ mood: Mood?, label: String, symbol: String) -> some View {
        let selected = app.settings.simulated == mood
        Button {
            withAnimation(.smooth) { app.settings.simulated = mood }
        } label: {
            Label(label, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .symbolRenderingMode(.multicolor)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .regular.tint((mood ?? app.weather.real).color.opacity(0.55)).interactive() : .regular.interactive(),
                     in: .capsule)
        .glassEffectID(label, in: glassNS)
    }
}
