# Mosaik – falsk Fotos-app med mosaik-afsløring

En iPhone-app, der ligner **Fotos** (iOS 26, Liquid Glass). Tilskueren ser et helt almindeligt fotobibliotek. Kniber du for at zoome helt ud, danner de ~2.600 små billeder **forudsigelsen**: et ansigt, et billede eller et navn.

Native Swift/SwiftUI-app, der installeres med **SideStore** (ligesom Number Reader). Den bygges i GitHub Actions uden Mac.

---

## Rutine (relæ)

1. Tilskueren vælger frit, fx en kendt person: *Kim Larsen*.
2. Navnet kommer til Mosaik via **relæet**, fx fra Google-appen, Noter+, en Genvej eller en medhjælper (se nedenfor).
3. Mosaik slår navnet op på Wikipedia, henter et billede og bygger mosaikken. Det tager 1–3 sekunder. Når den er klar, får **Bibliotek** et lille rødt **1**-tal, ligesom på referencen.
4. Giv telefonen til tilskueren, eller vis den selv. Scroll lidt rundt i "dine" billeder nederst. Det er dine ægte, nyeste fotos.
5. Knib for at zoome ud: 3 → 5 → 15 → **30 kolonner**, de samme niveauer som Fotos. Motivet træder frem på de yderste niveauer.

Findes der intet billede, bliver navnet skrevet med billederne som **tekst**.

## Hemmeligt panel

**5 hurtige tryk på titlen "Bibliotek".**

| Område | Indhold |
|---|---|
| Mosaik | Målbillede + forhåndsvisning af mosaikken, status, *Ryd mosaik* |
| Kilde | **Relæ** (rum-kode og hvilke felter der lyttes på) eller **Fast billede** (vælg fra kamerarullen) |
| Manuelt / test | Skriv et navn: *Find billede*, *Som tekst* eller *Via relæ* (sender gennem relæet som en anden app ville) |
| Udseende | Antal emner (2.589), ord ("emner"), kolonner ved maks zoom, farvetone min/maks, kontrast, beskæring omkring ansigt, tekstfarve, rødt 1-tal |
| Kamerarulle | Antal ægte fotos nederst (standard 30) + adgang til Fotos |
| Øvrigt | Wikipedia-sprog, *Bland biblioteket igen* |

## Relæet

Samme relæ som Noter+ og Lommeregneren: `https://relay-production-03f5.up.railway.app`. Skriv den samme **rum-kode** i alle apps.

Mosaik lytter på disse felter (det nyeste vinder; beskeder over 6 timer gamle ignoreres):

| Felt | Indhold | Standard |
|---|---|---|
| `mosaik` | `{ "q": "Kim Larsen", "at": <ms> }` → find billede (ellers tekst)<br>`{ "text": "42", "at": … }` → tekst<br>`{ "url": "https://…jpg", "at": … }` → billede fra adresse<br>`{ "img": "data:image/jpeg;base64,…", "at": … }` → billedet selv (maks ~16 KB) | til |
| `google` | `{ "q": …, "at": … }` (søgning fra en falsk Google) | til |
| `force` | `{ "name": …, "at": … }` (navnet fra Noter+) | fra |

**Send fra en iPhone-Genvej:** *Hent indholdet af URL* → `https://relay-production-03f5.up.railway.app/r/<rum>` · Metode **POST** · Brødtekst **JSON**: `mosaik` = ordbog med `q` (tekst) og `at` (tal, *Aktuel dato* som Unix-tid × 1000).

**Fra en computer:**
```bash
curl -X POST https://relay-production-03f5.up.railway.app/r/<rum> \
  -d '{"mosaik":{"q":"Kim Larsen","at":'$(date +%s000)'}}'
```

## Sådan virker mosaikken

- **Billedpuljen:** 993 fotos (Picsum/Unsplash-licens) ligger i appen (`ios/Mosaik/Resources/Pool`, 300 px). `pool.json` har hvert billedes gennemsnitsfarve og 2×2 delfarver (Lab). Fremviseren henter den fulde version fra Picsum, når et billede åbnes (caches).
- **Ægte fotos:** de N nyeste fra kamerarullen ligger nederst (de første man ser). Resten er puljen.
- **Mål:** billedet beskæres til gitterets format, omkring et ansigt hvis Vision finder et (ansigtet fylder ca. 62 % af bredden). Tekst tegnes med ét ord pr. linje.
- **Løseren** (`Model/Solver.swift`) vælger et puljebillede til hvert felt i det område, der ses ved maks zoom, nederst i biblioteket. Den er grådig: sjældne farver vælges først, og hvert billede bruges højst ca. 4 gange. Det samme billede står aldrig tæt på sig selv, hverken i 36- eller 3/5-kolonne-visningen. Det tager under 0,1 sek.
- **Farvetone:** hvert felt får en farve lagt over. Den er beregnet, så feltets gennemsnit bliver præcis målfarven. Den mindste nødvendige styrke bruges, dog mindst *Mindste farvetone*. Tonen er 0 ved 3 og 5 kolonner og vokser frem mod maks zoom. Tæt på ser billederne helt normale ud.
- Felter, der er på skærmen, i det øjeblik mosaikken bygges, bliver ikke byttet ud. Et relæ-skifte kan derfor ikke ses, mens tilskueren kigger.

## Lighed med Fotos

Mål er taget fra skærmbilleder af den rigtige Fotos-app (iOS 26, dansk) i `ref/`:
- Titlen "Bibliotek" er 35 pt fed. "4.487 emner" står **kun nederst** i biblioteket.
- Glasknapperne: sortér (44 pt) og "Vælg" (44 pt høj).
- Fanebjælken er iOS' egen: Bibliotek, Samlinger og en separat søg-knap. Det røde 1-tal er fanens badge.
- Datomærker: "Okt. 2026" ved 15 kolonner og "2026" ved maks zoom. De sidder fast under titlen og skubbes op af det næste.
- Mellemrum: 2 pt ved 3–5 kolonner, 1 pt ved 15 og 1 pixel ved maks. Sidste rækkes yderste hjørner er runde.
- Ikonet er klippet ud af et skærmbillede af hjemmeskærmen (`scripts/make-icon.py`, mørkt ikon).

## Installér (SideStore)

**SideStore-source:** `https://raw.githubusercontent.com/Thyxo/mosaik/main/sidestore/apps.json`

1. Åbn SideStore → **Sources** → **+** → indsæt linket.
2. Installér **Fotos**. Giv adgang til fotos første gang via panelet (*Giv adgang til fotos*).
3. Læg ikonet i Dock i stedet for den rigtige Fotos, og læg den rigtige i en mappe.
4. Husk at SideStore skal opdateres hver 7. dag. Gør det før et show.

## Udvikling

| Fil | Indhold |
|---|---|
| `ios/project.yml` | XcodeGen (iOS 18+, `dk.thyxo.mosaik`, navn "Fotos") |
| `ios/Mosaik/Model/` | Farver (Lab, farvetone), mosaikløser, indstillinger. Ren Swift |
| `ios/Mosaik/Library/` | Pulje, kamerarulle (PhotoKit), billedcache, mål (Vision), Wikipedia-opslag, relæ (SSE), datoer |
| `ios/Mosaik/Views/GridView.swift` | Gitteret i UIKit: knib-zoom med animerede niveauskift og farvetone |
| `ios/Mosaik/Views/` | Bibliotek (titel, glasknapper, fanebjælke), fremviser, hemmeligt panel |
| `ios/Tests/main.swift` | Test af farveregning og løser (kører i CI) |
| `scripts/fetch-pool.py` | Henter puljen og beregner farverne |
| `scripts/make-icon.py` | App-ikonet |

Lokalt på en Mac: `brew install xcodegen && cd ios && xcodegen && open Mosaik.xcodeproj`.
Test uden Xcode: `swiftc ios/Mosaik/Model/*.swift ios/Tests/main.swift -o /tmp/t && /tmp/t`.
