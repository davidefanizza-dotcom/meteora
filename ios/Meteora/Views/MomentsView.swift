import SwiftUI
import UniformTypeIdentifiers

/// Copertina a mosaico di una playlist di momenti.
struct MomentMosaic: View {
    let list: MomentList
    var radius: CGFloat = 14

    var body: some View {
        let covers = list.covers
        ZStack(alignment: .topTrailing) {
            Group {
                if covers.count >= 4 {
                    Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                        GridRow { Cover(url: covers[0], radius: 0); Cover(url: covers[1], radius: 0) }
                        GridRow { Cover(url: covers[2], radius: 0); Cover(url: covers[3], radius: 0) }
                    }
                } else if let first = covers.first {
                    Cover(url: first, radius: 0)
                } else {
                    LinearGradient(colors: [.accentColor, .accentColor.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay(Image(systemName: "scissors").font(.system(size: 40, weight: .semibold)).foregroundStyle(.white))
                }
            }
            .aspectRatio(1, contentMode: .fit)
            if !covers.isEmpty {
                Image(systemName: "scissors")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .glassEffect(.regular.tint(.black.opacity(0.3)), in: .circle)
                    .padding(8)
            }
        }
        .clipShape(.rect(cornerRadius: radius))
    }
}

struct MomentsView: View {
    @Environment(AppModel.self) private var app
    @State private var newName = ""
    @State private var askNew = false
    @State private var importing = false
    private let cols = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        let store = app.moments
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Solo i pezzi che ami: ritornelli, assoli, drop. Ogni momento parte e finisce dove vuoi tu.")
                    .foregroundStyle(.secondary)

                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        Button {
                            if let t = app.player.current { app.momentEditor = MomentDraft(track: t) }
                        } label: {
                            Label("Dal brano in ascolto", systemImage: "scissors")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(app.player.current == nil)
                        Button {
                            newName = "I miei ritornelli"
                            askNew = true
                        } label: {
                            Image(systemName: "plus").font(.headline).padding(.vertical, 4)
                        }
                        .buttonStyle(.glass)
                    }
                }

                if store.lists.isEmpty {
                    EmptyState(symbol: "scissors", title: "Nessun momento ancora",
                               message: "Mentre ascolti un brano tocca ✂ nella schermata del brano (o “Crea momento” dal menu di un brano), scegli inizio e fine e salvalo in una playlist.")
                } else {
                    LazyVGrid(columns: cols, alignment: .leading, spacing: 20) {
                        ForEach(store.lists) { l in
                            NavigationLink(value: l.id) {
                                VStack(alignment: .leading, spacing: 6) {
                                    MomentMosaic(list: l)
                                        .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
                                    Text(l.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text("\(l.items.count) moment\(l.items.count == 1 ? "o" : "i") · \(formatTime(Double(l.totalMs)))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Riproduci", systemImage: "play.fill") { Task { await app.player.playMoments(l) } }
                                    .disabled(l.items.isEmpty)
                                Button("Casuale", systemImage: "shuffle") { Task { await app.player.playMoments(l, shuffle: true) } }
                                    .disabled(l.items.count < 2)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(WeatherBackground())
        .navigationTitle("Momenti")
        .navigationDestination(for: String.self) { MomentListView(listId: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let data = store.exportData(), !store.lists.isEmpty {
                        ShareLink(item: MomentsFile(data: data), preview: SharePreview("Momenti di Meteora")) {
                            Label("Esporta tutti", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button("Importa…", systemImage: "square.and.arrow.down") { importing = true }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .alert("Nuova playlist di momenti", isPresented: $askNew) {
            TextField("Nome", text: $newName)
            Button("Annulla", role: .cancel) {}
            Button("Crea") {
                let n = newName.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty { store.createList(n) }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { r in
            guard case .success(let url) = r else { return }
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            do {
                let n = try store.importData(Data(contentsOf: url))
                Toaster.shared.show("\(n) momenti importati", symbol: "square.and.arrow.down")
            } catch {
                Toaster.shared.show("File non valido", symbol: "exclamationmark.triangle.fill")
            }
        }
    }
}

/// File JSON condivisibile.
struct MomentsFile: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
            .suggestedFileName("meteora-momenti.json")
    }
}

struct MomentListView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let listId: String
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false

    var body: some View {
        let store = app.moments
        if let l = store.list(listId) {
            List {
                Section {
                    VStack(spacing: 14) {
                        MomentMosaic(list: l, radius: 20)
                            .frame(width: 200, height: 200)
                            .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
                        Text(l.name).font(.title.weight(.bold)).multilineTextAlignment(.center)
                        Text("\(l.items.count) moment\(l.items.count == 1 ? "o" : "i") · \(formatTime(Double(l.totalMs))) in tutto")
                            .font(.subheadline).foregroundStyle(.secondary)
                        GlassEffectContainer(spacing: 12) {
                            HStack(spacing: 12) {
                                Button {
                                    Task { await app.player.playMoments(l) }
                                } label: {
                                    Label("Riproduci", systemImage: "play.fill").font(.headline).padding(.horizontal, 6).padding(.vertical, 4)
                                }
                                .buttonStyle(.glassProminent)
                                .disabled(l.items.isEmpty)
                                Button {
                                    Task { await app.player.playMoments(l, shuffle: true) }
                                } label: {
                                    Image(systemName: "shuffle").font(.headline).padding(.vertical, 4)
                                }
                                .buttonStyle(.glass)
                                .disabled(l.items.count < 2)
                                Button {
                                    store.setRepeat(l.id, !(l.repeatOn ?? false))
                                    if app.player.momentListId == l.id { app.player.momentRepeat = !(l.repeatOn ?? false) }
                                } label: {
                                    Image(systemName: "repeat").font(.headline).padding(.vertical, 4)
                                        .foregroundStyle((l.repeatOn ?? false) ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                                }
                                .buttonStyle(.glass)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                Section {
                    if l.items.isEmpty {
                        Text("Ancora nessun momento: aggiungili con ✂ dalla schermata del brano.")
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                    }
                    ForEach(Array(l.items.enumerated()), id: \.element.id) { i, it in
                        MomentRow(item: it, index: i, playing: app.player.currentMoment?.id == it.id)
                            .contentShape(.rect)
                            .onTapGesture { Task { await app.player.playMoments(l, at: i) } }
                            .swipeActions(edge: .trailing) {
                                Button("Rimuovi", systemImage: "trash", role: .destructive) { store.remove(itemAt: i, from: l.id) }
                                Button("Modifica", systemImage: "slider.horizontal.3") {
                                    app.momentEditor = MomentDraft(track: it.asTrack, item: it, listId: l.id)
                                }
                                .tint(.accentColor)
                            }
                            .contextMenu {
                                Button("Riproduci da qui", systemImage: "play.fill") { Task { await app.player.playMoments(l, at: i) } }
                                Button("Modifica inizio e fine", systemImage: "slider.horizontal.3") {
                                    app.momentEditor = MomentDraft(track: it.asTrack, item: it, listId: l.id)
                                }
                                Button("Ascolta il brano intero", systemImage: "music.note") {
                                    Task { await app.player.playList([it.asTrack], at: 0, label: it.name) }
                                }
                                Button("Rimuovi", systemImage: "trash", role: .destructive) { store.remove(itemAt: i, from: l.id) }
                            }
                            .listRowBackground(Color.clear)
                    }
                    .onMove { from, to in store.move(in: l.id, from: from, to: to) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(WeatherBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Rinomina", systemImage: "pencil") { newName = l.name; renaming = true }
                        if let t = app.player.current {
                            Button("Aggiungi il brano in ascolto", systemImage: "scissors") {
                                app.momentEditor = MomentDraft(track: t, listId: l.id)
                            }
                        }
                        if let data = store.exportData([l]) {
                            ShareLink(item: MomentsFile(data: data), preview: SharePreview(l.name)) {
                                Label("Esporta", systemImage: "square.and.arrow.up")
                            }
                        }
                        Divider()
                        Button("Elimina playlist", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
            .alert("Rinomina playlist", isPresented: $renaming) {
                TextField("Nome", text: $newName)
                Button("Annulla", role: .cancel) {}
                Button("Salva") {
                    let n = newName.trimmingCharacters(in: .whitespaces)
                    if !n.isEmpty { store.rename(l.id, to: n) }
                }
            }
            .confirmationDialog("Eliminare “\(l.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Elimina", role: .destructive) {
                    store.delete(l.id)
                    dismiss()
                }
            }
        } else {
            EmptyState(symbol: "scissors", title: "Playlist non trovata").padding()
        }
    }
}

struct MomentRow: View {
    let item: MomentItem
    let index: Int
    var playing = false

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if playing {
                    Image(systemName: "waveform").symbolEffect(.variableColor.iterative).foregroundStyle(.tint)
                } else {
                    Text("\(index + 1)").foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .font(.footnote)
            .frame(width: 22)
            Cover(url: item.imageURL, radius: 6).frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.body.weight(.medium)).lineLimit(1)
                    .foregroundStyle(playing ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                HStack(spacing: 6) {
                    Text(item.label ?? "Momento")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(.tint.opacity(0.2), in: .capsule)
                    Text(item.artistLine).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(formatTime(Double(item.start)))–\(formatTime(Double(item.end)))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Text(formatTime(Double(item.length))).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Editor: scegli inizio (A) e fine (B) del momento.
struct MomentEditorView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let draft: MomentDraft

    @State private var a = 0.0
    @State private var b = 30000.0
    @State private var label = "Ritornello"
    @State private var target = ""
    @State private var newList = "I miei ritornelli"
    @State private var dragging: Character?

    private var dur: Double { Double(max(draft.track.durationMs, draft.item?.trackDur ?? 0, 1)) }
    private var playingThis: Bool { app.player.current?.id == draft.track.id }
    private let labels = ["Ritornello", "Strofa", "Assolo", "Drop", "Intro", "Finale", "Bridge"]

    var body: some View {
        let store = app.moments
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 14) {
                        Cover(url: draft.track.imageURL, radius: 10).frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(draft.track.name).font(.headline).lineLimit(1)
                            Text(draft.track.artistLine).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }

                    timeline

                    HStack {
                        Text("Inizio **\(formatTime(a))**")
                        Spacer()
                        Text(lengthText).font(.headline).foregroundStyle(.tint)
                        Spacer()
                        Text("Fine **\(formatTime(b))**")
                    }
                    .font(.subheadline.monospacedDigit())

                    VStack(spacing: 10) {
                        nudgeRow(title: "Inizio qui", key: "A")
                        nudgeRow(title: "Fine qui", key: "B")
                    }

                    Button {
                        Task { await app.player.previewMoment(draft.track, start: Int(a), end: Int(b)) }
                    } label: {
                        Label("Ascolta il momento", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("NOME").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        TextField("Ritornello, Assolo, Drop…", text: $label)
                            .padding(14)
                            .glassEffect(.regular, in: .rect(cornerRadius: 16))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(labels, id: \.self) { l in
                                    Button(l) { label = l }
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 12).padding(.vertical, 7)
                                        .glassEffect(label == l ? .regular.tint(.accentColor.opacity(0.5)).interactive() : .regular.interactive(), in: .capsule)
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                        .scrollClipDisabled()
                    }

                    if draft.item == nil {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("SALVA IN").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(store.lists) { l in
                                        listChip(l.name, id: l.id, symbol: "scissors")
                                    }
                                    listChip("Nuova playlist", id: "__new", symbol: "plus")
                                }
                            }
                            .scrollClipDisabled()
                            if target == "__new" {
                                TextField("Nome della playlist", text: $newList)
                                    .padding(14)
                                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
                            }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle(draft.item == nil ? "Nuovo momento" : "Modifica momento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva", systemImage: "checkmark") { save() }
                }
            }
        }
        .presentationDetents([.large])
        .onAppear(perform: setup)
    }

    private var lengthText: String {
        let s = Int((b - a) / 1000)
        return s < 60 ? "\(s) s" : formatTime(b - a)
    }

    private var timeline: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            GeometryReader { geo in
                let w = geo.size.width
                let xa = a / dur * w, xb = b / dur * w
                ZStack(alignment: .leading) {
                    // barre decorative (non è la forma d'onda reale)
                    HStack(spacing: 2) {
                        ForEach(0..<70, id: \.self) { i in
                            let pos = (Double(i) + 0.5) / 70 * dur
                            Capsule()
                                .fill(pos >= a && pos <= b ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary.opacity(0.35)))
                                .frame(height: barHeight(i) * 52)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 6)

                    Rectangle().fill(.tint.opacity(0.16))
                        .frame(width: max(2, xb - xa))
                        .offset(x: xa)
                    handle("A").offset(x: xa - 11)
                    handle("B").offset(x: xb - 11)
                    if playingThis {
                        Capsule().fill(.white).frame(width: 2)
                            .shadow(color: .white.opacity(0.6), radius: 4)
                            .offset(x: Double(app.player.position) / dur * w - 1)
                    }
                }
                .contentShape(.rect)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let x = max(0, min(dur, v.location.x / w * dur))
                        if dragging == nil { dragging = abs(x - a) <= abs(x - b) ? "A" : "B" }
                        if dragging == "A" { a = min(x, b - 1000) } else { b = max(x, a + 1000) }
                    }
                    .onEnded { _ in dragging = nil })
            }
            .frame(height: 84)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
        }
        .sensoryFeedback(.selection, trigger: Int(a / 1000) + Int(b / 1000) * 1000)
    }

    private func handle(_ t: String) -> some View {
        VStack(spacing: 0) {
            Text(t).font(.caption2.weight(.heavy)).foregroundStyle(.white)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(.tint, in: .rect(cornerRadius: 5))
            Capsule().fill(.tint).frame(width: 4).frame(maxHeight: .infinity)
        }
        .frame(width: 22)
        .padding(.vertical, -10)
    }

    private func barHeight(_ i: Int) -> Double {
        var h = 0
        for c in draft.track.id.unicodeScalars { h = (h * 31 + Int(c.value) * (i + 7)) % 997 }
        return min(1, 0.25 + Double(h % 60) / 100 + sin(Double(i) / 4) * 0.12)
    }

    private func nudgeRow(title: String, key: Character) -> some View {
        HStack(spacing: 8) {
            Button("−1s") { if key == "A" { a = max(0, a - 1000) } else { b = max(a + 1000, b - 1000) } }
                .buttonStyle(.glass)
            Button {
                let p = Double(app.player.position)
                if key == "A" {
                    a = p
                    if b <= a + 1000 { b = min(dur, a + 30000) }
                } else {
                    b = p
                    if b <= a + 1000 { a = max(0, b - 30000) }
                }
            } label: {
                Label(title, systemImage: "mappin").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .disabled(!playingThis)
            Button("+1s") { if key == "A" { a = min(b - 1000, a + 1000) } else { b = min(dur, b + 1000) } }
                .buttonStyle(.glass)
        }
        .font(.subheadline.weight(.semibold))
    }

    private func listChip(_ name: String, id: String, symbol: String) -> some View {
        Button {
            target = id
        } label: {
            Label(name, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .glassEffect(target == id ? .regular.tint(.accentColor.opacity(0.5)).interactive() : .regular.interactive(), in: .capsule)
    }

    private func setup() {
        if let it = draft.item {
            a = Double(it.start)
            b = Double(it.end)
            label = it.label ?? "Momento"
        } else if playingThis {
            a = max(0, Double(app.player.position) - 15000)
            b = min(dur, a + 30000)
        } else {
            a = (dur * 0.28).rounded()
            b = min(dur, a + 30000)
        }
        let s = app.moments
        target = draft.listId ?? s.lastListId ?? ""
        if s.list(target) == nil { target = s.lists.first?.id ?? "__new" }
    }

    private func save() {
        let s = app.moments
        let name = label.trimmingCharacters(in: .whitespaces).isEmpty ? "Momento" : label.trimmingCharacters(in: .whitespaces)
        if var it = draft.item, let lid = draft.listId {
            it.start = Int(a)
            it.end = Int(b)
            it.label = name
            s.update(it, in: lid)
            Toaster.shared.show("Momento aggiornato", symbol: "checkmark.circle.fill")
            dismiss()
            return
        }
        var lid = target
        if lid == "__new" || s.list(lid) == nil {
            let n = newList.trimmingCharacters(in: .whitespaces)
            lid = s.createList(n.isEmpty ? "I miei ritornelli" : n)
        }
        let t = draft.track
        let item = MomentItem(id: MomentsStore.newId(), trackId: t.id, uri: t.uri, name: t.name, artists: t.artists,
                              album: t.album, img: t.imageURL?.absoluteString, trackDur: Int(dur),
                              start: Int(a), end: Int(b), label: name)
        s.add(item, to: lid)
        Toaster.shared.show("Salvato in “\(s.list(lid)?.name ?? "")”", symbol: "scissors")
        dismiss()
    }
}
