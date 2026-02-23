#!/usr/bin/env bash
# 04-runtime-memory.sh — Peak RSS during single-message agent invocation
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

header "Runtime Memory (Peak RSS via agent CLI)"

rss_json="{}"

BENCH_PROMPT="Reply with the single word hello."
# Model ID without provider prefix — each project adds its own
BENCH_MODEL_ID="google/gemini-2.0-flash-001"

# ─── OpenClaw ────────────────────────────────────────────────────────────────
if [[ -f "$OPENCLAW_BIN" && -d "$OPENCLAW_DIR/dist" ]] && command -v node >/dev/null 2>&1; then
    info "Measuring OpenClaw peak RSS (agent --local)..."
    tmpfile="$(mktemp)"

    /usr/bin/time -l bash -c "
        OPENROUTER_API_KEY='$OPENROUTER_API_KEY' \
        node '$OPENCLAW_BIN' agent --local \
            --message '$BENCH_PROMPT' \
            --session-id bench-mem \
            --json 2>/dev/null
    " >/dev/null 2>"$tmpfile" || true

    rss_raw="$(grep "$TIME_RSS_PATTERN" "$tmpfile" | awk '{print $1}')"
    rss_kb="$(echo "${rss_raw:-0} / 1024" | bc)"
    rss_mb="$(echo "scale=1; ${rss_kb:-0} / 1024" | bc)"
    info "OpenClaw peak RSS: ${rss_kb} KB (${rss_mb} MB)"
    rss_json="$(echo "$rss_json" | jq --argjson kb "${rss_kb:-0}" --arg mb "$rss_mb" '. + {"openclaw": {"kb": $kb, "mb": $mb}}')"
    rm -f "$tmpfile"
fi

# ─── ZeroClaw ────────────────────────────────────────────────────────────────
if [[ -f "$ZEROCLAW_BIN" ]]; then
    info "Measuring ZeroClaw peak RSS (agent -m)..."
    tmpfile="$(mktemp)"

    /usr/bin/time -l bash -c "
        OPENROUTER_API_KEY='$OPENROUTER_API_KEY' \
        '$ZEROCLAW_BIN' agent \
            -m '$BENCH_PROMPT' \
            -p openrouter \
            --model '$BENCH_MODEL_ID' 2>/dev/null
    " >/dev/null 2>"$tmpfile" || true

    rss_raw="$(grep "$TIME_RSS_PATTERN" "$tmpfile" | awk '{print $1}')"
    rss_kb="$(echo "${rss_raw:-0} / 1024" | bc)"
    rss_mb="$(echo "scale=1; ${rss_kb:-0} / 1024" | bc)"
    info "ZeroClaw peak RSS: ${rss_kb} KB (${rss_mb} MB)"
    rss_json="$(echo "$rss_json" | jq --argjson kb "${rss_kb:-0}" --arg mb "$rss_mb" '. + {"zeroclaw": {"kb": $kb, "mb": $mb}}')"
    rm -f "$tmpfile"
fi

# ─── PicoClaw ────────────────────────────────────────────────────────────────
picoclaw_actual=""
if [[ -f "$PICOCLAW_BIN" ]]; then
    picoclaw_actual="$PICOCLAW_BIN"
else
    picoclaw_actual="$(ls "$PICOCLAW_DIR/build/picoclaw-"* 2>/dev/null | head -1)" || true
fi

if [[ -n "$picoclaw_actual" && -f "$picoclaw_actual" ]]; then
    info "Measuring PicoClaw peak RSS (agent)..."

    # PicoClaw reads config from ~/.picoclaw/config.json — create minimal config
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

    tmpfile="$(mktemp)"

    /usr/bin/time -l bash -c "
        '$picoclaw_actual' agent \
            -m '$BENCH_PROMPT' 2>/dev/null
    " >/dev/null 2>"$tmpfile" || true

    rss_raw="$(grep "$TIME_RSS_PATTERN" "$tmpfile" | awk '{print $1}')"
    rss_kb="$(echo "${rss_raw:-0} / 1024" | bc)"
    rss_mb="$(echo "scale=1; ${rss_kb:-0} / 1024" | bc)"
    info "PicoClaw peak RSS: ${rss_kb} KB (${rss_mb} MB)"
    rss_json="$(echo "$rss_json" | jq --argjson kb "${rss_kb:-0}" --arg mb "$rss_mb" '. + {"picoclaw": {"kb": $kb, "mb": $mb}}')"
    rm -f "$tmpfile"

    # Restore original config
    if [[ -n "$picoclaw_conf_backup" ]]; then
        mv "$picoclaw_conf_backup" "$picoclaw_conf"
    else
        rm -f "$picoclaw_conf"
    fi
fi

emit_json "$OUTPUT" "peak_rss" "$rss_json"

ok "Runtime memory results saved to $OUTPUT"
