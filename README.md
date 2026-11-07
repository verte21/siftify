# Siftify

**100% offline macOS file & folder organizer powered by Apple Silicon Metal, Apple `Vision`, `PDFKit`, and calibrated Bayes deferral.**

Most folder cleaners only look at file extensions — so `IMG_9042.png`, `scan_02.pdf`, `attachment_04.pdf`, `document_final_v3.docx`, and `download (4).stl` all end up dumped into generic `Images` or `Documents` buckets.

**Siftify** inspects what is *inside* each loose file directly on your Mac (with zero cloud calls and zero internet required), routes confident matches into clean folders & subfolders, and **leaves ambiguous files safely untouched** instead of guessing.

---

## Highlights

- **Deep Native macOS File X-Ray:**
  - **Apple `Vision.framework` (`Neural Engine`):** Runs accurate OCR (`VNRecognizeTextRequest`) + visual scene classification (`VNClassifyImageRequest`) on screenshots, photos, and receipts.
  - **`PDFKit` + Scanned PDF OCR Fallback:** Extracts multi-page text, title, author, and subject — automatically falling back to Apple `Vision` OCR on scanned PDFs.
  - **Office, Ebooks, & iWork:** Reads `.docx`/`.doc`/`.rtf`/`.odt`, `.pptx` slide decks, `.xlsx` workbooks, `.epub` chapters, and `.pages`/`.key`/`.numbers` previews.
  - **Download Provenance (`kMDItemWhereFroms`):** Rescues opaque filenames like `download (4).stl` by inspecting the exact domain/URL Safari or Chrome downloaded them from (`printables.com`, `arxiv.org`, `github.com`, etc.).
  - **3D Models, Archives, & Hobby RC FPV:** Inspects `.zip`/`.3mf` manifests, `.stl` headers, `Betaflight` CLI dumps, flight controller pinouts, and Blackbox `.bbl` headers.
- **Two Standalone Native macOS Apps (Zero Python Required):**
  - **`Siftify.app`** — Calm Liquid Glass interface built for everyday Mac users: drag-and-drop folder portal, on-device Apple Silicon privacy badge, uniform folder stack preview cards, `0 ms` carefulness switcher (`Relaxed` · `Balanced` · `Extra Careful`), per-file overrides, and 1-click Undo.
  - **`Siftify Pro.app`** — Power-user workbench with full File X-Ray payload inspection, top-level & subfolder probability bars, continuous Bayes cost-ratio tuning, and custom category/subtag prompt authoring.
- **Calibrated Bayes Deferral (Never Guesses):**
  - Moves a file into folder $k$ only when expected risk beats deferring ($p_k > 1 - \frac{c_{\text{defer}}}{c_{\text{wrong}}}$). At default `Balanced` (`wrong = 2.2, defer = 1.0`, `>= 54.5%`), mystery files stay safely in place.
- **Model-Agnostic Local Metal Engine:**
  - Bundles a self-contained Apple Silicon Metal inference engine (`llama-server` + `ggml`, strictly bound to `127.0.0.1` with `--offline`).
  - Downloads calibrated `basal-2.0-mini-Q8_0.gguf` (`1.70 GB`) on first launch, or runs **any local `.gguf` chat model** (`Qwen3`, `Llama-3.2`, `Gemma-3`, `SmolLM2`) via `SIFTIFY_MODEL_PATH`.

---

## Quickstart (Standalone macOS Apps)

Build and launch **`Siftify.app`** (Liquid Glass app):

```bash
bun run app
```

Build and launch **`Siftify Pro.app`** (X-Ray & Probability Workbench):

```bash
bun run pro
```

> **Privacy by Default:** Neither app pre-selects `~/Downloads`, `~/Desktop`, or `~/Documents` on launch, so macOS never prompts for folder permissions until you explicitly pick or drop a folder.

---

## Using Another Local `.gguf` Classifier

`ClassifierService` (`macos/Sources/SiftifyCore/ClassifierService.swift`) is decoupled from any single model:
- **Default (Calibrated):** Uses `basal-2.0-mini-Q8_0.gguf` stored in `~/Library/Application Support/Siftify/models/` with single-token logprob readout and `CALIBRATION.llamacpp.json` bucket temperature scaling.
- **Custom `.gguf` Model:** Point `SIFTIFY_MODEL_PATH` at any instruction-tuned `.gguf` file on disk (`Qwen3`, `Llama-3.2`, `Gemma-3`, etc.) — `ClassifierService` dynamically resolves option-code token IDs via `/tokenize` and scores folder probabilities in a single forward pass:

```bash
SIFTIFY_MODEL_PATH=~/Models/Qwen3-1.7B-Q8_0.gguf open build/Siftify.app
```

---

## CLI Companion (`siftify`)

If you prefer sorting from the terminal against a local MLX server:

```bash
bun run setup
```

Start the local Apple Silicon classifier server in one tab:

```bash
bun run serve
```

Run a safe dry-run on generated sample files or any folder:

```bash
bun run demo
```

```bash
bun run sift ~/Downloads
```

Apply confident moves (and revert anytime with `--undo`):

```bash
bun run sift ~/Downloads --apply
```

```bash
bun run sift --undo
```

---

## Repository Structure

```text
siftify/
├── macos/
│   ├── Resources/CALIBRATION.llamacpp.json
│   └── Sources/
│       ├── SiftifyCore/      # Shared FileXRayExtractor, ModelManager, ClassifierService, & Models
│       ├── Siftify/          # Siftify.app — Consumer Liquid Glass SwiftUI app + MenuBarExtra
│       └── SiftifyPro/       # Siftify Pro.app — Power-user X-Ray & probability workbench
├── scripts/
│   ├── build-app.sh          # Builds standalone arm64 build/Siftify.app
│   ├── build-pro-app.sh      # Builds standalone arm64 build/SiftifyPro.app
│   ├── setup-mlx.sh          # Optional Python/MLX environment setup for CLI
│   └── serve-mlx.sh          # Optional localhost:8765 MLX server for CLI
├── src/
│   ├── cli.ts                # CLI dry-run, --apply, --undo, --strictness, & --json
│   └── demo.ts               # Generates demo-inbox & runs end-to-end CLI preview
├── swift/
│   ├── FileXRay.swift        # Standalone CLI X-Ray extractor binary source
│   ├── MakeAppIcon.swift     # Generates Siftify Glass-Aurora AppIcon.icns
│   ├── MakeProAppIcon.swift  # Generates Siftify Pro AppIcon.icns
│   └── MakeDemoSamples.swift # Synthesizes realistic PDFs, receipts, DOCX, STL, & FPV samples
└── siftify.config.json       # Default folder categories, subfolders, & Bayes deferral costs
```
