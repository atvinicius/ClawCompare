#!/usr/bin/env bash
# 06-stress-compaction.sh — Peak RSS growth across increasing message counts
set -euo pipefail

BENCH_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$BENCH_DIR/config.sh"
source "$BENCH_DIR/lib/platform.sh"
source "$BENCH_DIR/lib/measure.sh"

OUTPUT="$RESULTS_DIR/06-stress.json"

# ─── Require API key ────────────────────────────────────────────────────────
if [[ -z "$OPENROUTER_API_KEY" ]]; then
    warn "OPENROUTER_API_KEY not set — skipping stress/compaction benchmark"
    exit 2
fi

echo '{}' > "$OUTPUT"

header "Stress Test: Peak RSS Growth (agent CLI)"

growth_json="{}"

MESSAGE_COUNTS=(1 5 10)
BENCH_MODEL_ID="google/gemini-2.0-flash-001"

# Helper: measure peak RSS for N sequential agent invocations
# Uses /usr/bin/time -l to capture peak RSS of the entire sequence
measure_rss_at_count() {
    local agent_cmd="$1"
    local count="$2"
    local tmpfile rss_raw rss_kb

    tmpfile="$(mktemp)"

    # Build a script that runs the agent N times sequentially
    local script=""
    for ((i = 1; i <= count; i++)); do
        script+="$agent_cmd $i >/dev/null 2>&1 || true; "
    done

    /usr/bin/time -l bash -c "$script" >/dev/null 2>"$tmpfile" || true

    rss_raw="$(grep "$TIME_RSS_PATTERN" "$tmpfile" | awk '{print $1}')"
    rss_kb="$(echo "${rss_raw:-0} / 1024" | bc)"
    rm -f "$tmpfile"

    echo "${rss_kb:-0}"
}

# Run stress test for one project
run_stress_test() {
    local name="$1"
    local agent_cmd="$2"
    local rss_readings="{}"

    info "Stress testing $name..."

    for target_count in "${MESSAGE_COUNTS[@]}"; do
        local rss_now
        rss_now="$(measure_rss_at_count "$agent_cmd" "$target_count")"
        info "  After $target_count message(s): ${rss_now} KB"
        rss_readings="$(echo "$rss_readings" | jq --arg k "$target_count" --argjson v "$rss_now" '. + {($k): $v}')"
    done

    echo "$rss_readings"
}

# ─── OpenClaw ────────────────────────────────────────────────────────────────
if [[ -f "$OPENCLAW_BIN" && -d "$OPENCLAW_DIR/dist" ]] && command -v node >/dev/null 2>&1; then
    res="$(run_stress_test "OpenClaw" \
        "OPENROUTER_API_KEY=$OPENROUTER_API_KEY node '$OPENCLAW_BIN' agent --local --message 'Reply with the number' --session-id bench-stress --json")" || true
    if [[ -n "$res" ]]; then
        growth_json="$(echo "$growth_json" | jq --argjson v "$res" '. + {"openclaw": $v}')"
    fi
fi

# ─── ZeroClaw ────────────────────────────────────────────────────────────────
if [[ -f "$ZEROCLAW_BIN" ]]; then
    res="$(run_stress_test "ZeroClaw" \
        "OPENROUTER_API_KEY=$OPENROUTER_API_KEY '$ZEROCLAW_BIN' agent -m 'Reply with the number' -p openrouter --model '$BENCH_MODEL_ID'")" || true
    if [[ -n "$res" ]]; then
        growth_json="$(echo "$growth_json" | jq --argjson v "$res" '. + {"zeroclaw": $v}')"
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

    res="$(run_stress_test "PicoClaw" \
        "'$picoclaw_actual' agent -m 'Reply with the number'")" || true
    if [[ -n "$res" ]]; then
        growth_json="$(echo "$growth_json" | jq --argjson v "$res" '. + {"picoclaw": $v}')"
    fi

    # Restore original config
    if [[ -n "$picoclaw_conf_backup" ]]; then
        mv "$picoclaw_conf_backup" "$picoclaw_conf"
    else
        rm -f "$picoclaw_conf"
    fi
fi

emit_json "$OUTPUT" "growth" "$growth_json"

ok "Stress/compaction results saved to $OUTPUT"
