#!/usr/bin/env bash
# 04-runtime-memory.sh — Peak RSS during single-message roundtrip
set -euo pipefail

BENCH_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$BENCH_DIR/config.sh"
source "$BENCH_DIR/lib/platform.sh"
source "$BENCH_DIR/lib/measure.sh"

OUTPUT="$RESULTS_DIR/04-memory.json"

# ─── Require API key ────────────────────────────────────────────────────────
if [[ -z "$OPENROUTER_API_KEY" ]]; then
    warn "OPENROUTER_API_KEY not set — skipping runtime memory benchmark"
    exit 2
fi

echo '{}' > "$OUTPUT"

header "Runtime Memory (Peak RSS)"

rss_json="{}"

# Helper: create a minimal config, start gateway, send message, capture RSS
measure_gateway_rss() {
    local name="$1"
    local start_cmd="$2"
    local port="$3"
    local pid tmpdir rss_kb rss_mb

    tmpdir="$(mktemp -d)"

    info "Measuring $name peak RSS..."

    # Start gateway in background, capture PID
    eval "$start_cmd" &>"$tmpdir/gateway.log" &
    pid=$!

    # Wait for gateway to be ready (poll health/root endpoint)
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
        warn "$name gateway did not become ready in 15s"
        kill "$pid" 2>/dev/null || true
        rm -rf "$tmpdir"
        return 1
    fi

    ok "$name gateway ready on port $port"

    # Send a single message via OpenAI-compatible endpoint
    curl -sf "http://localhost:$port/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $OPENROUTER_API_KEY" \
        -d "{
            \"model\": \"$BENCH_MODEL\",
            \"messages\": [{\"role\": \"user\", \"content\": \"Say hello in exactly 3 words.\"}],
            \"max_tokens\": 20
        }" > "$tmpdir/response.json" 2>/dev/null || warn "$name: message send may have failed"

    # Capture RSS from /proc or ps
    case "$PLATFORM" in
        Darwin)
            # ps returns RSS in KB on macOS
            rss_kb="$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ' || echo 0)"
            ;;
        Linux)
            # /proc/<pid>/status VmRSS is in KB
            rss_kb="$(grep VmRSS /proc/"$pid"/status 2>/dev/null | awk '{print $2}' || echo 0)"
            ;;
    esac

    rss_mb="$(echo "scale=1; ${rss_kb:-0} / 1024" | bc)"
    info "$name peak RSS: ${rss_kb} KB (${rss_mb} MB)"

    # Cleanup
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    rm -rf "$tmpdir"

    echo "{\"kb\": ${rss_kb:-0}, \"mb\": ${rss_mb}}"
}

# ─── OpenClaw ────────────────────────────────────────────────────────────────
if [[ -f "$OPENCLAW_BIN" && -d "$OPENCLAW_DIR/dist" ]] && command -v node >/dev/null 2>&1; then
    # OpenClaw gateway: needs OPENROUTER_API_KEY in env
    res="$(measure_gateway_rss "OpenClaw" \
        "OPENROUTER_API_KEY=$OPENROUTER_API_KEY node $OPENCLAW_BIN gateway" \
        "$OPENCLAW_PORT")" || true
    if [[ -n "$res" ]]; then
        rss_json="$(echo "$rss_json" | jq --argjson v "$res" '. + {"openclaw": $v}')"
    fi
fi

# ─── ZeroClaw ────────────────────────────────────────────────────────────────
if [[ -f "$ZEROCLAW_BIN" ]]; then
    # ZeroClaw: create a minimal TOML config
    tmpconf="$(mktemp)"
    cat > "$tmpconf" <<TOML
api_key = "$OPENROUTER_API_KEY"
default_provider = "openrouter"
default_model = "$BENCH_MODEL"

[gateway]
port = $ZEROCLAW_PORT
host = "127.0.0.1"
TOML

    res="$(measure_gateway_rss "ZeroClaw" \
        "$ZEROCLAW_BIN gateway --config $tmpconf" \
        "$ZEROCLAW_PORT")" || true
    rm -f "$tmpconf"
    if [[ -n "$res" ]]; then
        rss_json="$(echo "$rss_json" | jq --argjson v "$res" '. + {"zeroclaw": $v}')"
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
    # PicoClaw: create a minimal JSON config
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

    res="$(measure_gateway_rss "PicoClaw" \
        "$picoclaw_actual gateway --config $tmpconf" \
        "$PICOCLAW_PORT")" || true
    rm -f "$tmpconf"
    if [[ -n "$res" ]]; then
        rss_json="$(echo "$rss_json" | jq --argjson v "$res" '. + {"picoclaw": $v}')"
    fi
fi

emit_json "$OUTPUT" "peak_rss" "$rss_json"

ok "Runtime memory results saved to $OUTPUT"
