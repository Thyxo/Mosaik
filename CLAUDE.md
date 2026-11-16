# CLAUDE.md

Mosaik: native iOS-app (Swift/SwiftUI, XcodeGen, ingen .xcodeproj i git) der ligner iPhonens Fotos (iOS 26). Zoomes der helt ud i biblioteket, danner billederne forudsigelsen. Dansk UI. Se README.md.

- Bygges i GitHub Actions (`.github/workflows/ios.yml`) uden signering → GitHub Release + `sidestore/apps.json` opdateres automatisk. Hæv `MARKETING_VERSION` i `ios/project.yml` ved større ændringer.
- `ios/Mosaik/Model/` er ren Swift (ingen UIKit) og testes med `ios/Tests/main.swift` (kører i CI før buildet).
- Billedpuljen `ios/Mosaik/Resources/Pool/` + `pool.json` laves af `scripts/fetch-pool.py` (Picsum/Unsplash-licens). Ret ikke pool.json i hånden.
- Relæet er det samme som i Noter+/Calcplus (`https://relay-production-03f5.up.railway.app`, Railway-projekt magic-relay). Mosaik læser felterne `mosaik`, `google` og `force`.
- Gitteret er UIKit (`Views/GridView.swift`) af hensyn til ~3.000 felter; resten er SwiftUI.
