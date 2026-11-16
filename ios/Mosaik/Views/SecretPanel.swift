// Hemmeligt panel (5 hurtige tryk på "Bibliotek"): kilde, relæ, fast billede, test og udseende.
import PhotosUI
import SwiftUI

struct SecretPanel: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var pick: PhotosPickerItem?
    @State private var startSettings = Settings()

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        preview(app.targetPreview)
                        preview(app.mosaicPreview)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(app.targetLabel.isEmpty ? "Ingen mosaik" : app.targetLabel).font(.headline)
                            if app.busy { ProgressView().controlSize(.small) }
                            Text(app.status).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    if !app.targetLabel.isEmpty {
                        Button("Ryd mosaik", role: .destructive) { app.clearTarget() }
                    }
                } header: { Text("Mosaik") } footer: {
                    Text("Ses kun ved maks zoom ud. Venstre: målbillede, højre: sådan ser mosaikken ud.")
                }

                Section("Kilde") {
                    Picker("Kilde", selection: $app.s.source) {
                        Text("Relæ").tag("relay")
                        Text("Fast billede").tag("fixed")
                    }
                    .pickerStyle(.segmented)
                    if app.s.source == "relay" {
                        HStack {
                            TextField("Rum-kode", text: $app.s.room)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                            Circle().fill(statusColor).frame(width: 10, height: 10)
                            Text(statusText).font(.footnote).foregroundStyle(.secondary)
                        }
                        Toggle("Feltet \"mosaik\"", isOn: $app.s.listenMosaik)
                        Toggle("Google-søgning (\"google\")", isOn: $app.s.listenGoogle)
                        Toggle("Navn fra Noter+ (\"force\")", isOn: $app.s.listenForce)
                        Picker("Peek i fanebjælken", selection: $app.s.peek) {
                            Text("Til mosaikken vises").tag("reveal")
                            Text("I 10 sekunder").tag("10s")
                            Text("Fra").tag("off")
                        }
                    } else {
                        PhotosPicker(selection: $pick, matching: .images) {
                            Label("Vælg billede …", systemImage: "photo")
                        }
                    }
                }

                Section {
                    TextField("Navn, ting eller tal", text: $query)
                        .autocorrectionDisabled()
                    HStack {
                        Button("Find billede") { go("q") }.buttonStyle(.borderless)
                        Spacer()
                        Button("Som tekst") { go("text") }.buttonStyle(.borderless)
                        if app.s.source == "relay" {
                            Spacer()
                            Button("Via relæ") {
                                let q = query
                                Task { await app.relayTest(q) }
                            }.buttonStyle(.borderless)
                        }
                    }
                } header: { Text("Manuelt / test") } footer: {
                    Text("\"Find billede\" slår op på Wikipedia (\(app.s.wikiLang), så en). Findes intet, bliver det tekst.")
                }

                Section("Udseende") {
                    Stepper("Emner: \(Dates.number(app.s.itemCount))", value: $app.s.itemCount, in: 300...20000, step: 100)
                    TextField("Ord efter antal", text: $app.s.itemsWord)
                    Stepper("Kolonner ved maks zoom: \(app.s.maxCols)", value: $app.s.maxCols, in: 20...50)
                    VStack(alignment: .leading) {
                        Text("Mindste farvetone: \(Int(app.s.tintBase * 100)) %")
                        Slider(value: $app.s.tintBase, in: 0...0.8)
                    }
                    VStack(alignment: .leading) {
                        Text("Højeste farvetone: \(Int(app.s.tintCap * 100)) %")
                        Slider(value: $app.s.tintCap, in: 0.3...1)
                    }
                    VStack(alignment: .leading) {
                        Text("Kontrast: \(String(format: "%.2f", app.s.contrast))")
                        Slider(value: $app.s.contrast, in: 0.8...1.6)
                    }
                    Toggle("Beskær omkring ansigt", isOn: $app.s.faceCrop)
                    Toggle("Tekst: mørk på lys", isOn: $app.s.textInvert)
                    Toggle("Rødt 1-tal når klar", isOn: $app.s.badge)
                }

                Section {
                    Stepper("Ægte fotos nederst: \(app.s.realCount)", value: $app.s.realCount, in: 0...300, step: 6)
                    if app.s.realCount > 0 && !RealPhotos.shared.authorized {
                        Button("Giv adgang til fotos") { Task { await app.requestPhotos() } }
                    } else if app.s.realCount > 0 {
                        Text("\(app.realLoaded) indlæst").font(.footnote).foregroundStyle(.secondary)
                    }
                } header: { Text("Kamerarulle") } footer: {
                    Text("De nyeste fotos fra din kamerarulle ligger nederst. Resten er fra den indbyggede pulje.")
                }

                Section {
                    Picker("Wikipedia", selection: $app.s.wikiLang) {
                        Text("Dansk").tag("da"); Text("Engelsk").tag("en"); Text("Svensk").tag("sv"); Text("Norsk").tag("no")
                    }
                    Button("Bland biblioteket igen") {
                        app.s.seed = UInt64.random(in: 1...UInt64.max / 2)
                        Task { await app.rebuild() }
                    }
                }
            }
            .navigationTitle("Mosaik")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Færdig") { dismiss() } }
            }
        }
        .onAppear { startSettings = app.s }
        .onDisappear { applyChanges() }
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task {
                if let d = try? await item.loadTransferable(type: Data.self), let img = ImageStore.downsample(data: d, px: 1400) {
                    await app.apply(image: img, label: "Fast billede")
                }
                pick = nil
            }
        }
    }

    private func go(_ kind: String) {
        let q = query
        Task { await app.run(kind: kind, value: q) }
    }

    private func applyChanges() {
        let a = startSettings, b = app.s
        if a.room != b.room || a.source != b.source { app.connectRelay() }
        if a.itemCount != b.itemCount || a.maxCols != b.maxCols || a.realCount != b.realCount
            || a.tintBase != b.tintBase || a.tintCap != b.tintCap || a.contrast != b.contrast
            || a.faceCrop != b.faceCrop || a.textInvert != b.textInvert {
            Task { await app.rebuild() }
        }
    }

    private var statusColor: Color {
        switch app.relayStatus {
        case "online": return .green
        case "connecting": return .orange
        case "offline": return .red
        default: return .gray
        }
    }
    private var statusText: String {
        switch app.relayStatus {
        case "online": return "Forbundet"
        case "connecting": return "Forbinder …"
        case "offline": return "Offline"
        default: return "Fra"
        }
    }

    private func preview(_ img: UIImage?) -> some View {
        Group {
            if let img { Image(uiImage: img).resizable().interpolation(.none).scaledToFill() }
            else { Color.secondary.opacity(0.2) }
        }
        .frame(width: 54, height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
