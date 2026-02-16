#!/usr/bin/env bash
# 02-startup-timing.sh — Startup speed benchmarks
set -euo pipefail

BENCH_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$BENCH_DIR/config.sh"
source "$BENCH_DIR/lib/platform.sh"
source "$BENCH_DIR/lib/measure.sh"

OUTPUT="$RESULTS_DIR/02-startup.json"
echo '{}' > "$OUTPUT"

has_hyperfine=false
command -v hyperfine >/dev/null 2>&1 && has_hyperfine=true

# ─── Version flag timing ────────────────────────────────────────────────────
header "Startup Timing: --version flag"

version_json="{}"

bench_version_flag() {
    local name="$1" cmd="$2"
    local result

    info "Benchmarking $name --version..."

    if [[ "$has_hyperfine" == "true" ]]; then
        # Use hyperfine for statistical rigor
        local hf_json
        hf_json="$(hyperfine \
            --warmup "$WARMUP" \
            --runs "$RUNS" \
            --export-json /dev/stdout \
            --style none \
            "$cmd" 2>/dev/null)" || true

        if [[ -z "$hf_json" ]]; then
            warn "  hyperfine returned no data for $name"
            return 1
        fi

        local mean_s min_s max_s median_s
        mean_s="$(echo "$hf_json" | jq '.results[0].mean')"
        min_s="$(echo "$hf_json" | jq '.results[0].min')"
        max_s="$(echo "$hf_json" | jq '.results[0].max')"
        median_s="$(echo "$hf_json" | jq '.results[0].median')"

        # Convert to ms
        local mean_ms min_ms max_ms median_ms
        mean_ms="$(echo "$mean_s * 1000" | bc)"
        min_ms="$(echo "$min_s * 1000" | bc)"
        max_ms="$(echo "$max_s * 1000" | bc)"
        median_ms="$(echo "$median_s * 1000" | bc)"

        result="{\"tool\": \"hyperfine\", \"stats\": {\"min\": $min_ms, \"median\": $median_ms, \"mean\": $mean_ms, \"max\": $max_ms, \"p95\": $max_ms, \"count\": $RUNS}}"
    else
        # Fallback: manual timing
        info "  (using manual timing — install hyperfine for better results)"

        # Warmup
        local i
        for ((i = 1; i <= WARMUP; i++)); do
            eval "$cmd" >/dev/null 2>&1 || true
        done

        # Collect times individually
        local times=()
        for ((i = 1; i <= RUNS; i++)); do
            local t
            t="$(measure_time bash -c "$cmd")"
            times+=("$t")
        done

        # Build JSON array
        local times_json="["
        for ((i = 0; i < ${#times[@]}; i++)); do
            [[ $i -gt 0 ]] && times_json+=","
            times_json+="${times[$i]}"
        done
        times_json+="]"

        local stats
        stats="$(compute_stats "$times_json")"

        result="{\"tool\": \"manual\", \"raw\": $times_json, \"stats\": $stats}"
    fi

    info "  $name: $(echo "$result" | jq -r '.stats.median')ms median"
    echo "$result"
}

# OpenClaw — check that it can actually run
if [[ -f "$OPENCLAW_BIN" && -d "$OPENCLAW_DIR/dist" ]]; then
    res="$(bench_version_flag "OpenClaw" "node $OPENCLAW_BIN --version")" || true
    if [[ -n "$res" ]]; then
        version_json="$(echo "$version_json" | jq --argjson v "$res" '. + {"openclaw": $v}')"
    fi
elif [[ -d "$OPENCLAW_DIR" ]]; then
    warn "OpenClaw not built (missing dist/) — skipping"
fi

# ZeroClaw
if [[ -f "$ZEROCLAW_BIN" ]]; then
    res="$(bench_version_flag "ZeroClaw" "$ZEROCLAW_BIN --version")" || true
    if [[ -n "$res" ]]; then
        version_json="$(echo "$version_json" | jq --argjson v "$res" '. + {"zeroclaw": $v}')"
    fi
elif [[ -d "$ZEROCLAW_DIR" ]]; then
    warn "ZeroClaw binary not found — skipping"
fi

# PicoClaw
picoclaw_actual=""
if [[ -f "$PICOCLAW_BIN" ]]; then
    picoclaw_actual="$PICOCLAW_BIN"
else
    # Try to find any built binary (use subshell to avoid SIGPIPE with pipefail)
    picoclaw_actual="$(ls "$PICOCLAW_DIR/build/picoclaw-"* 2>/dev/null | head -1)" || true
fi

if [[ -n "$picoclaw_actual" && -f "$picoclaw_actual" ]]; then
    res="$(bench_version_flag "PicoClaw" "$picoclaw_actual version")" || true
    if [[ -n "$res" ]]; then
        version_json="$(echo "$version_json" | jq --argjson v "$res" '. + {"picoclaw": $v}')"
    fi
elif [[ -d "$PICOCLAW_DIR" ]]; then
    warn "PicoClaw binary not found — skipping"
fi

emit_json "$OUTPUT" "version_flag" "$version_json"

ok "Startup timing saved to $OUTPUT"
