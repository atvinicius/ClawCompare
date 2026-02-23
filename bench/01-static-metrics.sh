#!/usr/bin/env bash
# 01-static-metrics.sh — Binary size, dependency count, SLOC
set -euo pipefail

BENCH_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$BENCH_DIR/config.sh"
source "$BENCH_DIR/lib/platform.sh"
source "$BENCH_DIR/lib/measure.sh"

OUTPUT="$RESULTS_DIR/01-static.json"
echo '{}' > "$OUTPUT"

# ─── Binary / Artifact Size ─────────────────────────────────────────────────
header "Binary / Artifact Size"

binary_json="{}"

# OpenClaw: total dist/ directory size (it's a Node.js project — no single binary)
if [[ -d "$OPENCLAW_DIR/dist" ]]; then
    size="$(measure_dir_size "$OPENCLAW_DIR/dist")"
    human="$(format_bytes "$size")"
    info "OpenClaw dist/: $human ($size bytes)"
    binary_json="$(echo "$binary_json" | jq --argjson b "$size" --arg h "$human" '. + {"openclaw": {"bytes": $b, "human": $h}}')"
elif [[ -d "$OPENCLAW_DIR" ]]; then
    warn "OpenClaw dist/ not found — was it built?"
fi

# ZeroClaw: release binary
if [[ -f "$ZEROCLAW_BIN" ]]; then
    size="$(get_file_size "$ZEROCLAW_BIN")"
    human="$(format_bytes "$size")"
    info "ZeroClaw binary: $human ($size bytes)"
    binary_json="$(echo "$binary_json" | jq --argjson b "$size" --arg h "$human" '. + {"zeroclaw": {"bytes": $b, "human": $h}}')"
elif [[ -d "$ZEROCLAW_DIR" ]]; then
    warn "ZeroClaw binary not found at $ZEROCLAW_BIN"
fi

# PicoClaw: built binary
if [[ -f "$PICOCLAW_BIN" ]]; then
    size="$(get_file_size "$PICOCLAW_BIN")"
    human="$(format_bytes "$size")"
    info "PicoClaw binary: $human ($size bytes)"
    binary_json="$(echo "$binary_json" | jq --argjson b "$size" --arg h "$human" '. + {"picoclaw": {"bytes": $b, "human": $h}}')"
elif [[ -d "$PICOCLAW_DIR" ]]; then
    # Try to find any picoclaw binary in build/
    found_bin="$(ls "$PICOCLAW_DIR/build/picoclaw-"* 2>/dev/null | head -1)" || true
    if [[ -n "$found_bin" ]]; then
        size="$(get_file_size "$found_bin")"
        human="$(format_bytes "$size")"
        info "PicoClaw binary ($found_bin): $human ($size bytes)"
        binary_json="$(echo "$binary_json" | jq --argjson b "$size" --arg h "$human" '. + {"picoclaw": {"bytes": $b, "human": $h}}')"
    else
        warn "PicoClaw binary not found in $PICOCLAW_DIR/build/"
    fi
fi

emit_json "$OUTPUT" "binary_size" "$binary_json"

# ─── Dependency Count ────────────────────────────────────────────────────────
header "Dependency Count"

deps_json="{}"

# OpenClaw
if [[ -d "$OPENCLAW_DIR" ]] && command -v pnpm >/dev/null 2>&1; then
    count="$(cd "$OPENCLAW_DIR" && pnpm list --depth=0 --parseable 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')"
    info "OpenClaw: $count direct dependencies"
    deps_json="$(echo "$deps_json" | jq --argjson c "$count" '. + {"openclaw": $c}')"
fi

# ZeroClaw
if [[ -d "$ZEROCLAW_DIR" ]] && command -v cargo >/dev/null 2>&1; then
    count="$(cd "$ZEROCLAW_DIR" && cargo tree --depth=1 2>/dev/null | grep -c '├\|└' || echo 0)"
    info "ZeroClaw: $count direct dependencies"
    deps_json="$(echo "$deps_json" | jq --argjson c "$count" '. + {"zeroclaw": $c}')"
fi

# PicoClaw
if [[ -d "$PICOCLAW_DIR" ]] && command -v go >/dev/null 2>&1; then
    count="$(cd "$PICOCLAW_DIR" && go list -m all 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')"
    info "PicoClaw: $count dependencies (go list -m all)"
    deps_json="$(echo "$deps_json" | jq --argjson c "$count" '. + {"picoclaw": $c}')"
fi

emit_json "$OUTPUT" "dependencies" "$deps_json"

# ─── SLOC ────────────────────────────────────────────────────────────────────
header "Source Lines of Code"

sloc_json="{}"

if command -v tokei >/dev/null 2>&1; then
    info "Using tokei for SLOC counting"

    if [[ -d "$OPENCLAW_DIR/src" ]]; then
        count="$(tokei "$OPENCLAW_DIR/src" -t TypeScript 2>/dev/null | grep 'TypeScript' | awk '{print $4}' || echo 0)"
        [[ "$count" == "0" || -z "$count" ]] && count="$(tokei "$OPENCLAW_DIR/src" 2>/dev/null | grep 'Total' | awk '{print $4}' || echo 0)"
        info "OpenClaw: $count SLOC"
        sloc_json="$(echo "$sloc_json" | jq --argjson c "${count:-0}" '. + {"openclaw": $c}')"
    fi

    if [[ -d "$ZEROCLAW_DIR/src" ]]; then
        count="$(tokei "$ZEROCLAW_DIR/src" -t Rust 2>/dev/null | grep 'Rust' | awk '{print $4}' || echo 0)"
        [[ "$count" == "0" || -z "$count" ]] && count="$(tokei "$ZEROCLAW_DIR/src" 2>/dev/null | grep 'Total' | awk '{print $4}' || echo 0)"
        info "ZeroClaw: $count SLOC"
        sloc_json="$(echo "$sloc_json" | jq --argjson c "${count:-0}" '. + {"zeroclaw": $c}')"
    fi

    if [[ -d "$PICOCLAW_DIR" ]]; then
        count="$(tokei "$PICOCLAW_DIR" -t Go 2>/dev/null | grep 'Go' | awk '{print $4}' || echo 0)"
        [[ "$count" == "0" || -z "$count" ]] && count="$(tokei "$PICOCLAW_DIR/cmd" "$PICOCLAW_DIR/pkg" 2>/dev/null | grep 'Total' | awk '{print $4}' || echo 0)"
        info "PicoClaw: $count SLOC"
        sloc_json="$(echo "$sloc_json" | jq --argjson c "${count:-0}" '. + {"picoclaw": $c}')"
    fi
else
    info "tokei not found — using wc -l fallback"

    if [[ -d "$OPENCLAW_DIR/src" ]]; then
        count="$(find "$OPENCLAW_DIR/src" \( -name '*.ts' -o -name '*.tsx' \) -not -path '*/node_modules/*' -not -path '*/.next/*' -not -name '*.d.ts' | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')"
        info "OpenClaw: ${count:-0} lines (*.ts + *.tsx, excl. node_modules)"
        sloc_json="$(echo "$sloc_json" | jq --argjson c "${count:-0}" '. + {"openclaw": $c}')"
    fi

    if [[ -d "$ZEROCLAW_DIR/src" ]]; then
        count="$(find "$ZEROCLAW_DIR/src" -name '*.rs' | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')"
        info "ZeroClaw: ${count:-0} lines (*.rs)"
        sloc_json="$(echo "$sloc_json" | jq --argjson c "${count:-0}" '. + {"zeroclaw": $c}')"
    fi

    if [[ -d "$PICOCLAW_DIR" ]]; then
        count="$(find "$PICOCLAW_DIR/cmd" "$PICOCLAW_DIR/pkg" -name '*.go' 2>/dev/null | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')"
        info "PicoClaw: ${count:-0} lines (*.go)"
        sloc_json="$(echo "$sloc_json" | jq --argjson c "${count:-0}" '. + {"picoclaw": $c}')"
    fi
fi

emit_json "$OUTPUT" "sloc" "$sloc_json"

ok "Static metrics saved to $OUTPUT"
