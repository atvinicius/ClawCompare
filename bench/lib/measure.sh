#!/usr/bin/env bash
# lib/measure.sh — Timing and memory measurement helpers

# measure_time <cmd...>
# Run a command, print wall-clock time in milliseconds to stdout.
# Command output goes to /dev/null.
measure_time() {
    local start end elapsed_ms
    start="$(perl -MTime::HiRes=time -e 'printf "%.6f", time')"
    "$@" >/dev/null 2>&1
    end="$(perl -MTime::HiRes=time -e 'printf "%.6f", time')"
    elapsed_ms="$(echo "($end - $start) * 1000" | bc)"
    printf "%.2f" "$elapsed_ms"
}

# measure_peak_rss <cmd...>
# Run a command, print peak RSS in KB to stdout.
# Command output goes to /dev/null.
measure_peak_rss() {
    local tmpfile rss_raw rss_kb
    tmpfile="$(mktemp)"

    case "$PLATFORM" in
        Darwin)
            # macOS: /usr/bin/time -l outputs to stderr, RSS is in bytes
            /usr/bin/time -l "$@" >/dev/null 2>"$tmpfile"
            rss_raw="$(grep "$TIME_RSS_PATTERN" "$tmpfile" | awk '{print $1}')"
            rss_kb="$(echo "$rss_raw / 1024" | bc)"
            ;;
        Linux)
            # Linux: /usr/bin/time -v outputs to stderr, RSS is in KB
            /usr/bin/time -v "$@" >/dev/null 2>"$tmpfile"
            rss_kb="$(grep "$TIME_RSS_PATTERN" "$tmpfile" | awk '{print $NF}')"
            ;;
    esac

    rm -f "$tmpfile"
    echo "${rss_kb:-0}"
}

# measure_binary_size <path>
# Return file size in bytes.
measure_binary_size() {
    get_file_size "$1"
}

# measure_dir_size <path>
# Return total directory size in bytes.
measure_dir_size() {
    local path="$1"
    if [[ ! -d "$path" ]]; then
        echo "0"
        return
    fi

    case "$PLATFORM" in
        Darwin)
            # du on macOS: -s summary, output in 512-byte blocks by default
            echo "$(du -sk "$path" 2>/dev/null | awk '{print $1}') * 1024" | bc
            ;;
        Linux)
            du -sb "$path" 2>/dev/null | awk '{print $1}'
            ;;
    esac
}

# run_iterations <runs> <cmd...>
# Run a command N times, collect wall-clock times, output JSON array.
run_iterations() {
    local runs="$1"
    shift
    local times=()
    local i

    for ((i = 1; i <= runs; i++)); do
        times+=("$(measure_time "$@")")
    done

    # Output as JSON array
    local json="["
    for ((i = 0; i < ${#times[@]}; i++)); do
        [[ $i -gt 0 ]] && json+=","
        json+="${times[$i]}"
    done
    json+="]"
    echo "$json"
}

# compute_stats <json_array>
# Given a JSON array of numbers, compute min/median/mean/p95/max.
compute_stats() {
    local arr="$1"
    echo "$arr" | jq -c '
        sort |
        {
            min: .[0],
            max: .[-1],
            mean: (add / length | . * 100 | round / 100),
            median: (
                if (length % 2) == 1 then
                    .[length / 2 | floor]
                else
                    (.[length / 2 - 1] + .[length / 2]) / 2
                end | . * 100 | round / 100
            ),
            p95: .[((length - 1) * 0.95) | floor],
            count: length
        }
    '
}

# emit_json <file> <key> <value>
# Set a key in a JSON file (creates if doesn't exist).
emit_json() {
    local file="$1" key="$2" value="$3"

    if [[ ! -f "$file" ]]; then
        echo "{}" > "$file"
    fi

    local tmp
    tmp="$(jq --argjson val "$value" ". + {\"$key\": \$val}" "$file")"
    echo "$tmp" > "$file"
}

# emit_json_str <file> <key> <string_value>
# Set a string key in a JSON file.
emit_json_str() {
    local file="$1" key="$2" value="$3"

    if [[ ! -f "$file" ]]; then
        echo "{}" > "$file"
    fi

    local tmp
    tmp="$(jq --arg val "$value" ". + {\"$key\": \$val}" "$file")"
    echo "$tmp" > "$file"
}

# format_bytes <bytes>
# Human-readable byte size.
format_bytes() {
    local bytes="$1"
    if (( bytes >= 1073741824 )); then
        echo "$(echo "scale=1; $bytes / 1073741824" | bc) GB"
    elif (( bytes >= 1048576 )); then
        echo "$(echo "scale=1; $bytes / 1048576" | bc) MB"
    elif (( bytes >= 1024 )); then
        echo "$(echo "scale=1; $bytes / 1024" | bc) KB"
    else
        echo "${bytes} B"
    fi
}

# format_ms <ms>
# Human-readable millisecond duration.
format_ms() {
    local ms="$1"
    local int_ms="${ms%.*}"
    if (( int_ms >= 1000 )); then
        echo "$(echo "scale=2; $ms / 1000" | bc)s"
    else
        echo "${ms}ms"
    fi
}
