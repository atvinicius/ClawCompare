#!/usr/bin/env bash
# config.sh — Shared configuration for ClawCompare benchmarks

# Resolve BENCH_DIR to the directory containing this script
BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$BENCH_DIR/.." && pwd)"

# ─── Project roots ───────────────────────────────────────────────────────────
OPENCLAW_DIR="$PROJECT_ROOT/openclaw"
ZEROCLAW_DIR="$PROJECT_ROOT/zeroclaw"
PICOCLAW_DIR="$PROJECT_ROOT/picoclaw"

# ─── Built binary paths ─────────────────────────────────────────────────────
OPENCLAW_BIN="$OPENCLAW_DIR/openclaw.mjs"
ZEROCLAW_BIN="$ZEROCLAW_DIR/target/release/zeroclaw"
PICOCLAW_BIN="$PICOCLAW_DIR/build/picoclaw-$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)"

# ─── OpenRouter API key (optional — scripts 04-06 skip if absent) ────────────
# Set in environment: export OPENROUTER_API_KEY="sk-or-..."
OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"

# ─── Benchmark parameters ───────────────────────────────────────────────────
WARMUP="${WARMUP:-3}"
RUNS="${RUNS:-10}"

# ─── Gateway ports (used by scripts 04-06) ───────────────────────────────────
OPENCLAW_PORT=18789
ZEROCLAW_PORT=8080
PICOCLAW_PORT=18790

# ─── Model for fair comparison ───────────────────────────────────────────────
BENCH_MODEL="${BENCH_MODEL:-openrouter/auto}"

# ─── Results directory ───────────────────────────────────────────────────────
RESULTS_DIR="$BENCH_DIR/results"
mkdir -p "$RESULTS_DIR"

# ─── Color output helpers ───────────────────────────────────────────────────
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' BOLD='' RESET=''
fi

info()  { echo -e "${BLUE}[INFO]${RESET}  $*" >&2; }
ok()    { echo -e "${GREEN}[OK]${RESET}    $*" >&2; }
warn()  { echo -e "${YELLOW}[WARN]${RESET}  $*" >&2; }
err()   { echo -e "${RED}[ERR]${RESET}   $*" >&2; }
header(){ echo -e "\n${BOLD}═══ $* ═══${RESET}\n" >&2; }
