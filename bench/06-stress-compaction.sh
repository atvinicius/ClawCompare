#!/usr/bin/env bash
# 06-stress-compaction.sh — Memory growth at 5/10/20/50 messages, compaction detection
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

header "Stress Test: Memory Growth & Compaction"

growth_json="{}"
compaction_json="{}"

MESSAGE_COUNTS=(5 10 20 50)

# Shared temp dir for compaction side-channel files
STRESS_TMPDIR="$(mktemp -d)"

# Get RSS for a process
get_rss_kb() {
    local pid="$1"
    case "$PLATFORM" in
        Darwin)
            ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ' || echo 0
            ;;
        Linux)
            grep VmRSS /proc/"$pid"/status 2>/dev/null | awk '{print $2}' || echo 0
            ;;
    esac
}

# Send a single message and wait for response
send_message() {
    local port="$1" msg_num="$2"
    curl -sf "http://localhost:$port/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $OPENROUTER_API_KEY" \
        -d "{
            \"model\": \"$BENCH_MODEL\",
            \"messages\": [{\"role\": \"user\", \"content\": \"Message number $msg_num. Reply with just the number.\"}],
            \"max_tokens\": 10
        }" >/dev/null 2>&1
}

# Run stress test for one project
# Outputs growth JSON to stdout, writes compaction JSON to $STRESS_TMPDIR/<project>.compaction
run_stress_test() {
    local name="$1"
    local start_cmd="$2"
    local port="$3"
    local project_key="$4"
    local pid tmpdir

    tmpdir="$(mktemp -d)"

    info "Stress testing $name..."

    # Start gateway
    eval "$start_cmd" &>"$tmpdir/gateway.log" &
    pid=$!

    # Wait for ready
    local ready=false
    for i in $(seq 1 30); do
        if curl -sf "http://localhost:$port/" >/dev/null 2>&1 || \
           curl -sf "http://localhost:$port/health" >/dev/null 2>&1 || \
           curl -sf "http://localhost:$port/v1/chat/completions" -X OPTIONS >/dev/null 2>&1; then
            ready=true
            break
        fi
        sleep 0.5
    done

    if [[ "$ready" != "true" ]]; then
        warn "$name gateway did not become ready"
        kill "$pid" 2>/dev/null || true
        rm -rf "$tmpdir"
        return 1
    fi

    ok "$name gateway ready on port $port"

    local rss_readings="{}"
    local prev_rss=0
    local compaction_detected=false
    local compaction_at_msg=""
    local compaction_before=0
    local compaction_after=0
    local msg_counter=0

    for target_count in "${MESSAGE_COUNTS[@]}"; do
        # Send messages from current count to target
        while (( msg_counter < target_count )); do
            ((msg_counter++))
            send_message "$port" "$msg_counter" || true

            # Check for compaction (RSS dropping significantly)
            local current_rss
            current_rss="$(get_rss_kb "$pid")"
            if [[ "$compaction_detected" == "false" && "$prev_rss" -gt 0 ]]; then
                # Compaction = RSS drops by more than 10%
                local threshold
                threshold="$(echo "$prev_rss * 0.9" | bc | cut -d. -f1)"
                if (( current_rss < threshold && current_rss > 0 )); then
                    compaction_detected=true
                    compaction_at_msg="$msg_counter"
                    compaction_before="$prev_rss"
                    compaction_after="$current_rss"
                    info "  Compaction detected at message $msg_counter! RSS: ${prev_rss}KB → ${current_rss}KB"
                fi
            fi
            prev_rss="$current_rss"
        done

        # Record RSS at this checkpoint
        local rss_now
        rss_now="$(get_rss_kb "$pid")"
        info "  After $target_count messages: ${rss_now} KB"
        rss_readings="$(echo "$rss_readings" | jq --arg k "$target_count" --argjson v "$rss_now" '. + {($k): $v}')"
    done

    # Cleanup
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    rm -rf "$tmpdir"

    # Output growth data to stdout
    echo "$rss_readings"

    # Write compaction data to deterministic side-channel file
    if [[ "$compaction_detected" == "true" ]]; then
        echo "{\"detected\": true, \"at_message\": $compaction_at_msg, \"rss_before_kb\": $compaction_before, \"rss_after_kb\": $compaction_after}" > "$STRESS_TMPDIR/${project_key}.compaction"
    else
        echo "{\"detected\": false}" > "$STRESS_TMPDIR/${project_key}.compaction"
    fi
}

read_compaction() {
    local project_key="$1"
    local comp_file="$STRESS_TMPDIR/${project_key}.compaction"
    if [[ -f "$comp_file" ]]; then
        cat "$comp_file"
    else
        echo '{"detected": false}'
    fi
}

# ─── OpenClaw ────────────────────────────────────────────────────────────────
if [[ -f "$OPENCLAW_BIN" && -d "$OPENCLAW_DIR/dist" ]] && command -v node >/dev/null 2>&1; then
    res="$(run_stress_test "OpenClaw" \
        "OPENROUTER_API_KEY=$OPENROUTER_API_KEY node $OPENCLAW_BIN gateway" \
        "$OPENCLAW_PORT" "openclaw")" || true
    if [[ -n "$res" ]]; then
        growth_json="$(echo "$growth_json" | jq --argjson v "$res" '. + {"openclaw": $v}')"
    fi
    comp="$(read_compaction "openclaw")"
    compaction_json="$(echo "$compaction_json" | jq --argjson v "$comp" '. + {"openclaw": $v}')"
fi

# ─── ZeroClaw ────────────────────────────────────────────────────────────────
if [[ -f "$ZEROCLAW_BIN" ]]; then
    tmpconf="$(mktemp)"
    cat > "$tmpconf" <<TOML
api_key = "$OPENROUTER_API_KEY"
default_provider = "openrouter"
default_model = "$BENCH_MODEL"

[gateway]
port = $ZEROCLAW_PORT
host = "127.0.0.1"
TOML

    res="$(run_stress_test "ZeroClaw" \
        "$ZEROCLAW_BIN gateway --config $tmpconf" \
        "$ZEROCLAW_PORT" "zeroclaw")" || true
    rm -f "$tmpconf"
    if [[ -n "$res" ]]; then
        growth_json="$(echo "$growth_json" | jq --argjson v "$res" '. + {"zeroclaw": $v}')"
    fi
    comp="$(read_compaction "zeroclaw")"
    compaction_json="$(echo "$compaction_json" | jq --argjson v "$comp" '. + {"zeroclaw": $v}')"
fi

# ─── PicoClaw ────────────────────────────────────────────────────────────────
picoclaw_actual=""
if [[ -f "$PICOCLAW_BIN" ]]; then
    picoclaw_actual="$PICOCLAW_BIN"
else
    picoclaw_actual="$(ls "$PICOCLAW_DIR/build/picoclaw-"* 2>/dev/null | head -1)" || true
fi

if [[ -n "$picoclaw_actual" && -f "$picoclaw_actual" ]]; then
    tmpconf="$(mktemp)"
    cat > "$tmpconf" <<JSON
{
    "agent": {
        "default_model": "$BENCH_MODEL"
    },
    "providers": {
        "openrouter": {
            "api_key": "$OPENROUTER_API_KEY"
        }
    },
    "gateway": {
        "port": $PICOCLAW_PORT
    }
}
JSON

    res="$(run_stress_test "PicoClaw" \
        "$picoclaw_actual gateway --config $tmpconf" \
        "$PICOCLAW_PORT" "picoclaw")" || true
    rm -f "$tmpconf"
    if [[ -n "$res" ]]; then
        growth_json="$(echo "$growth_json" | jq --argjson v "$res" '. + {"picoclaw": $v}')"
    fi
    comp="$(read_compaction "picoclaw")"
    compaction_json="$(echo "$compaction_json" | jq --argjson v "$comp" '. + {"picoclaw": $v}')"
fi

# Cleanup temp dir
rm -rf "$STRESS_TMPDIR"

emit_json "$OUTPUT" "growth" "$growth_json"
emit_json "$OUTPUT" "compaction" "$compaction_json"

ok "Stress/compaction results saved to $OUTPUT"
