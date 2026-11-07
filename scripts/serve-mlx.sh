#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -x ".venv/bin/basal-serve" ]]; then
  echo "Error: .venv/bin/basal-serve not found. Run 'bun run setup' first." >&2
  exit 1
fi

MODEL="${BASAL_MODEL:-Remek/basal-2.0-mini-MLX-8bit}"
PORT="${PORT:-8765}"

echo "==> Starting native Apple Silicon MLX engine ($MODEL) on http://127.0.0.1:${PORT} ..."
exec .venv/bin/basal-serve \
  --model "$MODEL" \
  --mode mlx \
  --host 127.0.0.1 \
  --port "$PORT" \
  --ui "${BASAL_UI:-full}"
