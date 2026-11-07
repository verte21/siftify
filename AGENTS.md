# `siftify` — Workspace Context & Agent Guidelines

This workspace contains **`siftify`**, a 100% offline macOS file & folder organizer powered by Apple `Vision`, `PDFKit`, Office/EPUB deep text extraction, Spotlight/`kMDItemWhereFroms` extended attributes, and local Apple Silicon Metal `.gguf` classifiers (defaulting to calibrated `basal-2.0-mini-Q8_0.gguf`, with pluggable `SIFTIFY_MODEL_PATH` support).

For full background, architecture details, and empirical benchmark results, read [`HANDOFF.md`](./HANDOFF.md).

## Current Status
- **Shared Core (`macos/Sources/SiftifyCore/`):**
  - [`FileXRayExtractor.swift`](./macos/Sources/SiftifyCore/FileXRayExtractor.swift), [`Models.swift`](./macos/Sources/SiftifyCore/Models.swift), [`ModelManager.swift`](./macos/Sources/SiftifyCore/ModelManager.swift), and model-agnostic [`ClassifierService.swift`](./macos/Sources/SiftifyCore/ClassifierService.swift).
  - First-launch in-app downloader fetches default `basal-2.0-mini-Q8_0.gguf` (`1.70 GB`) into `~/Library/Application Support/Siftify/models/` with GGUF magic/size validation (and zero-copy APFS migration if previously downloaded under `BasalTidy`), while supporting any custom local `.gguf` via `SIFTIFY_MODEL_PATH`.
- **Consumer Liquid Glass App (`build/Siftify.app` — `bun run app`):**
  - Built via `bun run build:app` ([`scripts/build-app.sh`](./scripts/build-app.sh)) from `macos/Sources/Siftify/` + `SiftifyCore/`.
  - Features calm step-by-step Liquid Glass motion, live Apple Silicon chip badge + On-Device Privacy Guarantee sheet ([`FlowPrivacySheet.swift`](./macos/Sources/Siftify/FlowPrivacySheet.swift)), zero startup TCC folder permission prompts (`targetFolderURL` starts `nil`), uniform `168pt` 2-column folder stack cards, `0 ms` carefulness presets, per-file inspector, Apply, and 1-click Undo.
- **Power-User Workbench (`build/SiftifyPro.app` — `bun run pro`):**
  - Built via `bun run build:pro` ([`scripts/build-pro-app.sh`](./scripts/build-pro-app.sh)) from `macos/Sources/SiftifyPro/` + `SiftifyCore/`.
  - Provides deep File X-Ray payload inspection, top-level & subtag probability bars, continuous Bayes deferral slider, and custom Tag/Subtag prompt editing.
- **CLI Companion (`src/cli.ts` + `bin/file-xray` — `bun run sift`):**
  - Supports `--all`, `--limit <N>`, `--sort <newest|name>`, `--apply`, `--undo`, `--strictness`, and `--json`.

## Technical Notes & Decisions
- **Standalone App Engine Port:** `ClassifierService.swift` dynamically binds a free localhost port starting at `127.0.0.1:8766` (`-ngl 99 -c 8192 -np 1 --no-webui --offline`), avoiding collisions with `:8000` or CLI `:8765`.
- **SwiftUI SDK on macOS 27 CLT:** Both `scripts/build-app.sh` and `scripts/build-pro-app.sh` compile against `/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk` (`-target arm64-apple-macosx14.0`) to avoid missing `SwiftUIMacros` in CLT `MacOSX27.0.sdk`.
- **Calibrated Bayes Deferral Formula (`type: "act"`):** Expected cost of choosing folder $k$ is $c_{\text{wrong}} \cdot (1 - p_k)$ vs $c_{\text{defer}}$ for deferring, so a file is auto-moved iff $p_k > 1 - \frac{c_{\text{defer}}}{c_{\text{wrong}}}$. [`siftify.config.json`](./siftify.config.json) uses `wrong: 2.2, defer: 1` (`>= 54.5%` top-level confidence) and `subCostWrong: 1.8` (`>= 44.4%` subtag confidence).

## User Preferences & Constraints
- **Strictly English / Global Examples Only:** Do **not** introduce any Polish-specific examples, copy, sites, currencies, or regulations.
- **Zero Copy-Paste Friction:** Give short, single-line runnable commands (`bun run app`, `bun run pro`, `bun run demo`, `bun run sift ~/Downloads`) instead of long multi-line shell/curl snippets that wrap poorly in the terminal UI.
- **Hobby RC FPV Framing:** When referencing FPV files in rules, prompts, or docs, use clear consumer RC hobby terminology (`BetaFPV`, `Betaflight`, `TinyWhoop`, flight controller pinout, Blackbox `.bbl`).
