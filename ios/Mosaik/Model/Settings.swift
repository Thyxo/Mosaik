// Indstillinger (hemmeligt panel). Gemmes i UserDefaults; manglende nøgler får standardværdien.
import Foundation

struct Settings: Codable, Equatable {
    var itemCount = 2589          // antal emner i biblioteket
    var itemsWord = "emner"       // "2.589 emner"
    var maxCols = 36              // kolonner ved maks zoom (mosaikken)
    var tintBase = 0.30           // mindste farvetone ved maks zoom (0…1)
    var tintCap = 0.92            // højeste farvetone
    var textTint = 0.55           // mindste farvetone når målet er tekst
    var contrast = 1.15           // kontrast på målbilledet
    var faceCrop = true           // find ansigt og beskær omkring det
    var textInvert = false        // tekst: mørk på lys i stedet for lys på mørk
    var realCount = 30            // antal ægte (nyeste) fotos nederst
    var source = "relay"          // relay | fixed
    var room = ""                 // relæ-rum (samme kode som i de andre apps)
    var listenMosaik = true       // feltet "mosaik" i rummet
    var listenGoogle = true       // feltet "google" (søgning fra fx Google-appen)
    var listenForce = false       // feltet "force" (navn fra Noter+)
    var badge = true              // rødt 1-tal på Bibliotek når mosaikken er klar
    var wikiLang = "da"           // Wikipedia-sprog til billedopslag
    var seed: UInt64 = 0          // 0 = vælg et nyt ved første start

    init() {}

    static let key = "mosaik.settings.v1"

    static func load() -> Settings {
        let def = Settings()
        guard let data = UserDefaults.standard.data(forKey: key),
              let stored = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let defData = try? JSONEncoder().encode(def),
              var dict = try? JSONSerialization.jsonObject(with: defData) as? [String: Any] else { return def }
        dict.merge(stored) { _, new in new }
        guard let merged = try? JSONSerialization.data(withJSONObject: dict),
              let s = try? JSONDecoder().decode(Settings.self, from: merged) else { return def }
        return s
    }

    func save() {
        if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Settings.key) }
    }
}
