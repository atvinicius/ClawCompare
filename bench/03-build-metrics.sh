#!/usr/bin/env bash
# 03-build-metrics.sh — Clean build time + incremental build time
set -euo pipefail

BENCH_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$BENCH_DIR/config.sh"
source "$BENCH_DIR/lib/platform.sh"
source "$BENCH_DIR/lib/measure.sh"

OUTPUT="$RESULTS_DIR/03-build.json"
echo '{}' > "$OUTPUT"

# Helper to find first file matching pattern (pipefail-safe)
find_first() {
    find "$@" 2>/dev/null | head -1 || true
}

# ─── Clean Build ─────────────────────────────────────────────────────────────
header "Clean Build Times"

clean_json="{}"

# OpenClaw
if [[ -d "$OPENCLAW_DIR" ]] && command -v pnpm >/dev/null 2>&1; then
    info "Clean-building OpenClaw..."
    rm -rf "$OPENCLAW_DIR/dist"
    ms="$(measure_time bash -c "cd '$OPENCLAW_DIR' && pnpm build")"
    human="$(format_ms "$ms")"
    info "OpenClaw clean build: $human"
    clean_json="$(echo "$clean_json" | jq --argjson m "$ms" --arg h "$human" '. + {"openclaw": {"ms": $m, "human": $h}}')"
fi

# ZeroClaw
if [[ -d "$ZEROCLAW_DIR" ]] && command -v cargo >/dev/null 2>&1; then
    info "Clean-building ZeroClaw..."
    rm -rf "$ZEROCLAW_DIR/target/release"
    ms="$(measure_time bash -c "cd '$ZEROCLAW_DIR' && cargo build --release")"
    human="$(format_ms "$ms")"
    info "ZeroClaw clean build: $human"
    clean_json="$(echo "$clean_json" | jq --argjson m "$ms" --arg h "$human" '. + {"zeroclaw": {"ms": $m, "human": $h}}')"
fi

# PicoClaw
if [[ -d "$PICOCLAW_DIR" ]] && command -v go >/dev/null 2>&1; then
    info "Clean-building PicoClaw..."
    rm -rf "$PICOCLAW_DIR/build"
    ms="$(measure_time bash -c "cd '$PICOCLAW_DIR' && make build")"
    human="$(format_ms "$ms")"
    info "PicoClaw clean build: $human"
    clean_json="$(echo "$clean_json" | jq --argjson m "$ms" --arg h "$human" '. + {"picoclaw": {"ms": $m, "human": $h}}')"
fi

emit_json "$OUTPUT" "clean_build" "$clean_json"

# ─── Incremental Build ──────────────────────────────────────────────────────
header "Incremental Build Times"

incr_json="{}"

# OpenClaw: touch a source file, rebuild
if [[ -d "$OPENCLAW_DIR/dist" ]] && command -v pnpm >/dev/null 2>&1; then
    info "Incremental-building OpenClaw..."
    touch_file="$(find_first "$OPENCLAW_DIR/src" -name '*.ts' -type f)"
    if [[ -n "$touch_file" ]]; then
        touch "$touch_file"
        ms="$(measure_time bash -c "cd '$OPENCLAW_DIR' && pnpm build")"
        human="$(format_ms "$ms")"
        info "OpenClaw incremental build: $human"
        incr_json="$(echo "$incr_json" | jq --argjson m "$ms" --arg h "$human" '. + {"openclaw": {"ms": $m, "human": $h}}')"
    fi
fi

# ZeroClaw: touch a source file, rebuild
if [[ -f "$ZEROCLAW_BIN" ]] && command -v cargo >/dev/null 2>&1; then
    info "Incremental-building ZeroClaw..."
    touch_file="$(find_first "$ZEROCLAW_DIR/src" -name '*.rs' -type f)"
    if [[ -n "$touch_file" ]]; then
        touch "$touch_file"
        ms="$(measure_time bash -c "cd '$ZEROCLAW_DIR' && cargo build --release")"
        human="$(format_ms "$ms")"
        info "ZeroClaw incremental build: $human"
        incr_json="$(echo "$incr_json" | jq --argjson m "$ms" --arg h "$human" '. + {"zeroclaw": {"ms": $m, "human": $h}}')"
    fi
fi

# PicoClaw: touch a source file, rebuild
picoclaw_built="$(ls "$PICOCLAW_DIR/build/picoclaw-"* 2>/dev/null | head -1)" || true
if [[ -n "$picoclaw_built" ]] && command -v go >/dev/null 2>&1; then
    info "Incremental-building PicoClaw..."
    touch_file="$(find_first "$PICOCLAW_DIR/cmd" "$PICOCLAW_DIR/pkg" -name '*.go' -type f)"
    if [[ -n "$touch_file" ]]; then
        touch "$touch_file"
        ms="$(measure_time bash -c "cd '$PICOCLAW_DIR' && make build")"
        human="$(format_ms "$ms")"
        info "PicoClaw incremental build: $human"
        incr_json="$(echo "$incr_json" | jq --argjson m "$ms" --arg h "$human" '. + {"picoclaw": {"ms": $m, "human": $h}}')"
    fi
fi

emit_json "$OUTPUT" "incremental_build" "$incr_json"

ok "Build metrics saved to $OUTPUT"
