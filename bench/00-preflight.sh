#!/usr/bin/env bash
# 00-preflight.sh — Verify toolchains and build all three projects
set -euo pipefail

BENCH_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$BENCH_DIR/config.sh"
source "$BENCH_DIR/lib/platform.sh"
source "$BENCH_DIR/lib/measure.sh"

OUTPUT="$RESULTS_DIR/00-preflight.json"
echo '{}' > "$OUTPUT"

# ─── Check required tools ────────────────────────────────────────────────────
header "Checking required tools"

# Use a simple JSON object to accumulate tool versions (bash 3.2 compatible)
tools_json="{}"

check_tool() {
    local name="$1" cmd="$2"
    if command -v "$name" >/dev/null 2>&1; then
        local ver
        ver="$(eval "$cmd" 2>&1 | head -1 || echo 'unknown')"
        tools_json="$(echo "$tools_json" | jq --arg k "$name" --arg v "$ver" '. + {($k): $v}')"
        ok "$name: $ver"
        return 0
    else
        warn "$name: not found"
        return 1
    fi
}

# Required tools
required_ok=true
check_tool "bash"  "bash --version | head -1" || required_ok=false
check_tool "jq"    "jq --version"              || required_ok=false
check_tool "bc"    "echo 'bc available'"       || required_ok=false
check_tool "curl"  "curl --version | head -1"  || required_ok=false
check_tool "perl"  "perl -v | grep version | head -1" || required_ok=false

if [[ "$required_ok" != "true" ]]; then
    err "Missing required tools. Install jq, bc, curl and try again."
    exit 1
fi

# Optional tools
check_tool "hyperfine" "hyperfine --version" || true
check_tool "tokei"     "tokei --version"     || true

# Per-project toolchains
has_node=false
has_cargo=false
has_go=false

check_tool "node" "node --version" && has_node=true || true
check_tool "pnpm" "pnpm --version" && true || has_node=false
check_tool "cargo" "cargo --version" && has_cargo=true || true
check_tool "go" "go version" && has_go=true || true

emit_json "$OUTPUT" "tools" "$tools_json"

# ─── Build projects ──────────────────────────────────────────────────────────
header "Building projects"

builds_json="{}"

# OpenClaw (TypeScript / pnpm)
if [[ "$has_node" == "true" && -d "$OPENCLAW_DIR" ]]; then
    info "Building OpenClaw..."
    if (cd "$OPENCLAW_DIR" && pnpm install --frozen-lockfile 2>&1 && pnpm build 2>&1) | tail -5; then
        ok "OpenClaw build succeeded"
        builds_json="$(echo "$builds_json" | jq '. + {"openclaw": "ok"}')"
    else
        warn "OpenClaw build failed"
        builds_json="$(echo "$builds_json" | jq '. + {"openclaw": "failed"}')"
    fi
else
    warn "Skipping OpenClaw (node/pnpm not available or directory missing)"
    builds_json="$(echo "$builds_json" | jq '. + {"openclaw": "skipped"}')"
fi

# ZeroClaw (Rust / cargo)
if [[ "$has_cargo" == "true" && -d "$ZEROCLAW_DIR" ]]; then
    info "Building ZeroClaw..."
    if (cd "$ZEROCLAW_DIR" && cargo build --release 2>&1) | tail -5; then
        ok "ZeroClaw build succeeded"
        builds_json="$(echo "$builds_json" | jq '. + {"zeroclaw": "ok"}')"
    else
        warn "ZeroClaw build failed"
        builds_json="$(echo "$builds_json" | jq '. + {"zeroclaw": "failed"}')"
    fi
else
    warn "Skipping ZeroClaw (cargo not available or directory missing)"
    builds_json="$(echo "$builds_json" | jq '. + {"zeroclaw": "skipped"}')"
fi

# PicoClaw (Go / make)
if [[ "$has_go" == "true" && -d "$PICOCLAW_DIR" ]]; then
    info "Building PicoClaw..."
    if (cd "$PICOCLAW_DIR" && make build 2>&1) | tail -5; then
        ok "PicoClaw build succeeded"
        builds_json="$(echo "$builds_json" | jq '. + {"picoclaw": "ok"}')"
    else
        warn "PicoClaw build failed"
        builds_json="$(echo "$builds_json" | jq '. + {"picoclaw": "failed"}')"
    fi
else
    warn "Skipping PicoClaw (go not available or directory missing)"
    builds_json="$(echo "$builds_json" | jq '. + {"picoclaw": "skipped"}')"
fi

emit_json "$OUTPUT" "builds" "$builds_json"

ok "Preflight results saved to $OUTPUT"
