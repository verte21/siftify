# Architecture & Benchmark Handoff — `siftify`

## 1. Architecture Summary

**`siftify`** organizes macOS folders 100% offline using deep file content inspection rather than opaque filenames (`IMG_9042.png`, `scan_02.pdf`, `attachment_04.pdf`, `document_final_v3.docx`, `download (4).stl`):

1. **Deep Native macOS Signal Extraction ([`FileXRayExtractor.swift`](./macos/Sources/SiftifyCore/FileXRayExtractor.swift) & [`swift/FileXRay.swift`](./swift/FileXRay.swift)):**
   - **Images (`.png`, `.jpg`, `.heic`, `.webp`, ...):** Runs `VNRecognizeTextRequest` (accurate OCR) + `VNClassifyImageRequest` (scene tags) on Apple Neural Engine.
   - **PDFs (`.pdf`):** Extracts up to 5 pages + title/author/subject/pageCount via `PDFKit`, with 2-page render + Apple `Vision` OCR fallback for scanned PDFs.
   - **Office, Ebooks, & iWork:** Extracts `.docx`/`.doc`/`.rtf`/`.odt` via `/usr/bin/textutil`, `.pptx` slides XML, `.xlsx` sheet names & shared strings, `.epub` OPF metadata & chapters, and `.pages`/`.key`/`.numbers` QuickLook preview OCR.
   - **Spotlight & Browser Download Provenance:** Reads `MDItem` attributes plus raw `com.apple.metadata:kMDItemWhereFroms` binary plist `xattr`.
   - **Archives, 3D Models, & Hobby RC FPV:** Lists `.zip`/`.3mf` manifests, reads `.stl` headers, extracts Blackbox `.bbl`/`.bfl` headers, and preserves `Betaflight` markers (`board_name`, `manufacturer_id`, `craft_name`).

2. **Two Standalone Zero-Python macOS Apps (`build/Siftify.app` & `build/SiftifyPro.app`):**
   - **Embedded Apple Silicon Metal Engine:** Relocated `llama-server` + `ggml` Metal/BLAS/CPU `.dylib`/`.so` binaries inside `Contents/Resources/engine/` (`32 MB` `.app` bundle, zero `/opt/homebrew` or Python dependencies).
   - **Model-Agnostic Local Classifier ([`ClassifierService.swift`](./macos/Sources/SiftifyCore/ClassifierService.swift) & [`ModelManager.swift`](./macos/Sources/SiftifyCore/ModelManager.swift)):**
     - Downloads default calibrated `basal-2.0-mini-Q8_0.gguf` (`1.70 GB`) on first launch into `~/Library/Application Support/Siftify/models/` with GGUF header validation, live transfer speed, and `CALIBRATION.llamacpp.json` bucket temperature scaling.
     - Supports **any arbitrary `.gguf` chat model** via `SIFTIFY_MODEL_PATH`, dynamically tokenizing option codes via `/tokenize` for single-step `n_predict: 1` logprob scoring.
   - **`Siftify.app` (`macos/Sources/Siftify/`):** Consumer Liquid Glass app with Aurora ambient motion, Apple Silicon privacy guarantee sheet, zero startup TCC permission prompts, uniform `168pt` folder stack cards, `0 ms` carefulness switcher, and 1-click Undo.
   - **`Siftify Pro.app` (`macos/Sources/SiftifyPro/`):** Technical workbench with File X-Ray inspector, raw probability distributions, continuous Bayes cost slider, and custom Tag/Subtag prompt editor.

---

## 2. Verified Standalone Metal `Q8_0` Results (`demo-inbox`, 10/10)

- **Warm Metal GPU startup (`MTL0: Apple M4 Pro`):** `276 ms`
- **Classification accuracy (`10/10`):**
  - `2610.04821v1.pdf` → `71.7%` → **MOVE** to `Documents/Papers & Books`
  - `attachment_04.pdf` → `75.9%` → **MOVE** to `Documents/Tickets & Travel`
  - `document_final_v3.docx` → `69.3%` → **MOVE** to `Documents/Career & Resumes`
  - `scan_02.pdf` → `73.9%` → **MOVE** to `Documents/Contracts & Official`
  - `BTFL_cli_20261103.txt` → `67.8%` → **MOVE** to `FPV & Betaflight`
  - `CleanShot 2026-11-03 at 22.14.08.png` → `74.5%` → **MOVE** to `FPV & Betaflight`
  - `download (4).stl` → `93.9%` → **MOVE** to `3D Prints & CAD`
  - `IMG_9042.png` → `81.5%` → **MOVE** to `Finance & Invoices`
  - `Raycast_v1.88.2_universal.dmg` → `89.1%` → **MOVE** to `Installers & Archives`
  - `misc_untitled.txt` → `39.4%` → **DEFER** (safely left in place)

---

## 3. Quick Commands

```bash
bun run app
bun run pro
bun run sift ~/Downloads
```
