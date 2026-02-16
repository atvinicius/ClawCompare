#!/usr/bin/env bash
# 05-roundtrip-latency.sh — Message send → response latency via gateway HTTP
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

header "Roundtrip Latency"

latency_json="{}"

# Helper: start gateway, send N messages, measure latency for each
measure_gateway_latency() {
    local name="$1"
    local start_cmd="$2"
    local port="$3"
    local pid tmpdir

    tmpdir="$(mktemp -d)"

    info "Measuring $name roundtrip latency ($RUNS iterations)..."

    # Start gateway in background
    eval "$start_cmd" &>"$tmpdir/gateway.log" &
    pid=$!

    # Wait for gateway to be ready
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

    # Warmup
    for ((i = 1; i <= WARMUP; i++)); do
        curl -sf "http://localhost:$port/v1/chat/completions" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $OPENROUTER_API_KEY" \
            -d "{
                \"model\": \"$BENCH_MODEL\",
                \"messages\": [{\"role\": \"user\", \"content\": \"Say hi.\"}],
                \"max_tokens\": 5
            }" >/dev/null 2>&1 || true
    done

    # Measure latency for each iteration
    local times=()
    for ((i = 1; i <= RUNS; i++)); do
        local start end elapsed_ms
        start="$(perl -MTime::HiRes=time -e 'printf "%.6f", time')"

        curl -sf "http://localhost:$port/v1/chat/completions" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $OPENROUTER_API_KEY" \
            -d "{
                \"model\": \"$BENCH_MODEL\",
                \"messages\": [{\"role\": \"user\", \"content\": \"Reply with the number $i only.\"}],
                \"max_tokens\": 10
            }" > "$tmpdir/response_$i.json" 2>/dev/null || true

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

    # Cleanup
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    rm -rf "$tmpdir"

    echo "{\"raw\": $times_json, \"stats\": $stats}"
}

# ─── OpenClaw ────────────────────────────────────────────────────────────────
if [[ -f "$OPENCLAW_BIN" && -d "$OPENCLAW_DIR/dist" ]] && command -v node >/dev/null 2>&1; then
    res="$(measure_gateway_latency "OpenClaw" \
        "OPENROUTER_API_KEY=$OPENROUTER_API_KEY node $OPENCLAW_BIN gateway" \
        "$OPENCLAW_PORT")" || true
    if [[ -n "$res" ]]; then
        latency_json="$(echo "$latency_json" | jq --argjson v "$res" '. + {"openclaw": $v}')"
    fi
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

    res="$(measure_gateway_latency "ZeroClaw" \
        "$ZEROCLAW_BIN gateway --config $tmpconf" \
        "$ZEROCLAW_PORT")" || true
    rm -f "$tmpconf"
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

    res="$(measure_gateway_latency "PicoClaw" \
        "$picoclaw_actual gateway --config $tmpconf" \
        "$PICOCLAW_PORT")" || true
    rm -f "$tmpconf"
    if [[ -n "$res" ]]; then
        latency_json="$(echo "$latency_json" | jq --argjson v "$res" '. + {"picoclaw": $v}')"
    fi
fi

emit_json "$OUTPUT" "roundtrip" "$latency_json"

ok "Roundtrip latency results saved to $OUTPUT"
