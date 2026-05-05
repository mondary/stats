# Stats (Fork LLM by mondary)

![Project icon](icon.png)

[🇫🇷 FR](README.md) · [🇬🇧 EN](README_en.md)

✨ Fork de Stats orienté suivi d’usage LLM dans la barre de menu macOS.

## ✅ Fonctionnalités
- Monitoring système complet de Stats (CPU, RAM, Disk, Network, Battery, Sensors, etc.).
- Module **LLM** ajouté: **Codex, Claude, Gemini, GLM (z.ai)**.
- Affichage Codex orienté quota: `5h` et `Weekly`.
- Widget stack compatible affichage en 2 lignes (`5h` au-dessus de `Weekly`).

## 🧠 Utilisation
- Ouvrir Stats puis activer le module **LLM** dans les réglages modules.
- Choisir le widget `Stack` pour obtenir l’affichage vertical `5h/Weekly`.
- Le popup LLM affiche le détail par provider (requêtes/tokens/coût selon données disponibles).

## ⚙️ Réglages
- Chemins configurables pour logs providers:
- Codex: `~/.codex/sessions`, `~/.codex/archived_sessions`
- Claude: `~/.claude/projects`, `~/.config/claude/projects`
- Gemini: `~/.gemini`, `~/.config/gemini`
- GLM: `~/.glm`, `~/.zai`, `~/.config/zai`

## 🧾 Commandes
- Build local:
```bash
xcodebuild -project Stats.xcodeproj -scheme Stats -configuration Debug CODE_SIGNING_ALLOWED=NO build
```
- Lancer app debug build:
```bash
open -na ~/Library/Developer/Xcode/DerivedData/Stats-*/Build/Products/Debug/Stats.app
```

## 📦 Build & Package
- Le fork suit la structure projet Xcode upstream.
- Signature désactivable localement via `CODE_SIGNING_ALLOWED=NO` pour tests rapides.

## 🧪 Installation (Antigravity)
- N/A pour ce projet (app macOS native, pas extension Antigravity).

## 🧾 Changelog
- 0.1.0: Fork initial + module LLM (Codex, Claude, Gemini, GLM).
- 0.1.1: Parsing logs LLM renforcé + affichage quota Codex (`5h/Weekly`).
- 0.1.2: Widget stack LLM vertical (`5h` au-dessus de `Weekly`) + ajustements UI.

## 🔗 Liens
- Upstream: https://github.com/exelban/stats
- Fork: https://github.com/mondary/stats
- EN README: [README_en.md](README_en.md)
