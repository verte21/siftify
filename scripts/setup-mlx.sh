#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

PYTHON_BIN="/opt/homebrew/bin/python3.13"
if [[ ! -x "$PYTHON_BIN" ]]; then
  PYTHON_BIN="$(command -v python3)"
fi

echo "==> 1/3 Creating Python venv with $($PYTHON_BIN --version)..."
"$PYTHON_BIN" -m venv .venv
.venv/bin/pip install --upgrade pip

echo "==> 2/3 Installing basal[mlx] (Apple Silicon Metal / MLX engine)..."
.venv/bin/pip install "basal[mlx] @ https://github.com/rkinas/basal/archive/refs/tags/v2.5.2.tar.gz"

echo "==> 3/3 Compiling native macOS FileXRay (Apple Vision + PDFKit + Spotlight)..."
mkdir -p bin
swiftc -O swift/FileXRay.swift -o bin/file-xray

echo ""
echo "✓ Setup complete!"
echo "  1. Start local MLX GPU engine:  bun run serve"
echo "  2. Run dry-run on any folder:   bun run sift ~/Downloads"
