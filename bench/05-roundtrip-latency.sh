#!/usr/bin/env bash
# 05-roundtrip-latency.sh — Message send → response latency via agent CLI
set -euo pipefail

BENCH_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$BENCH_DIR/config.sh"
source "$BENCH_DIR/lib/platform.sh"
source "$BENCH_DIR/lib/measure.sh"

OUTPUT="$RESULTS_DIR/05-latency.json"

# ─── Require API key ────────────────────────────────────────────────────────
if [[ -z "$OPENROUTER_API_KEY" ]]; then
    warn "OPENROUTER_API_KEY not set — skipping roundtrip latency benchmark"
    exit 2
fi

echo '{}' > "$OUTPUT"

header "Roundtrip Latency (agent CLI single-message mode)"

latency_json="{}"

BENCH_PROMPT="Reply with the number"
BENCH_MODEL_ID="google/gemini-2.0-flash-001"

# Helper: measure latency for one project's agent CLI
measure_agent_latency() {
    local name="$1"
    local agent_cmd="$2"

    info "Measuring $name roundtrip latency ($RUNS iterations)..."

    # Warmup
    for ((i = 1; i <= WARMUP; i++)); do
        eval "$agent_cmd $i" >/dev/null 2>&1 || true
    done

    # Measure latency for each iteration
    local times=()
    for ((i = 1; i <= RUNS; i++)); do
        local start end elapsed_ms
        start="$(perl -MTime::HiRes=time -e 'printf "%.6f", time')"

        eval "$agent_cmd $i" >/dev/null 2>&1 || true

        end="$(perl -MTime::HiRes=time -e 'printf "%.6f", time')"
        elapsed_ms="$(echo "($end - $start) * 1000" | bc)"
        times+=("$elapsed_ms")
        info "  Iteration $i: ${elapsed_ms}ms"
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

    echo "{\"raw\": $times_json, \"stats\": $stats}"
}

# ─── OpenClaw ────────────────────────────────────────────────────────────────
if [[ -f "$OPENCLAW_BIN" && -d "$OPENCLAW_DIR/dist" ]] && command -v node >/dev/null 2>&1; then
    res="$(measure_agent_latency "OpenClaw" \
        "OPENROUTER_API_KEY=$OPENROUTER_API_KEY node '$OPENCLAW_BIN' agent --local --message '$BENCH_PROMPT' --session-id bench-lat --json")" || true
    if [[ -n "$res" ]]; then
        latency_json="$(echo "$latency_json" | jq --argjson v "$res" '. + {"openclaw": $v}')"
    fi
fi

# ─── ZeroClaw ────────────────────────────────────────────────────────────────
if [[ -f "$ZEROCLAW_BIN" ]]; then
    res="$(measure_agent_latency "ZeroClaw" \
        "OPENROUTER_API_KEY=$OPENROUTER_API_KEY '$ZEROCLAW_BIN' agent -m '$BENCH_PROMPT' -p openrouter --model '$BENCH_MODEL_ID'")" || true
    if [[ -n "$res" ]]; then
        latency_json="$(echo "$latency_json" | jq --argjson v "$res" '. + {"zeroclaw": $v}')"
    fi
fi

# ─── PicoClaw ────────────────────────────────────────────────────────────────
picoclaw_actual=""
if [[ -f "$PICOCLAW_BIN" ]]; then
    picoclaw_actual="$PICOCLAW_BIN"
else
    picoclaw_actual="$(ls "$PICOCLAW_DIR/build/picoclaw-"* 2>/dev/null | head -1)" || true
fi

if [[ -n "$picoclaw_actual" && -f "$picoclaw_actual" ]]; then
    # Set up PicoClaw config
    picoclaw_conf_dir="$HOME/.picoclaw"
    picoclaw_conf="$picoclaw_conf_dir/config.json"
    picoclaw_conf_backup=""

    if [[ -f "$picoclaw_conf" ]]; then
        picoclaw_conf_backup="$(mktemp)"
        cp "$picoclaw_conf" "$picoclaw_conf_backup"
    fi

    mkdir -p "$picoclaw_conf_dir"
    cat > "$picoclaw_conf" <<PCJSON
{
    "agents": {
        "defaults": {
            "model": "$BENCH_MODEL_ID"
        }
    },
    "providers": {
        "openrouter": {
            "api_key": "$OPENROUTER_API_KEY"
        }
    }
}
PCJSON

    res="$(measure_agent_latency "PicoClaw" \
        "'$picoclaw_actual' agent -m '$BENCH_PROMPT'")" || true
    if [[ -n "$res" ]]; then
        latency_json="$(echo "$latency_json" | jq --argjson v "$res" '. + {"picoclaw": $v}')"
    fi

    # Restore original config
    if [[ -n "$picoclaw_conf_backup" ]]; then
        mv "$picoclaw_conf_backup" "$picoclaw_conf"
    else
        rm -f "$picoclaw_conf"
    fi
fi

emit_json "$OUTPUT" "roundtrip" "$latency_json"

ok "Roundtrip latency results saved to $OUTPUT"
