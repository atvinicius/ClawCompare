#!/usr/bin/env bash
# run-all.sh — Master orchestrator for ClawCompare benchmarks
set -euo pipefail

BENCH_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$BENCH_DIR/config.sh"
source "$BENCH_DIR/lib/platform.sh"
source "$BENCH_DIR/lib/measure.sh"
source "$BENCH_DIR/lib/report.sh"

header "ClawCompare Benchmark Suite"
info "Platform: $PLATFORM_NAME $ARCH"
info "Results:  $RESULTS_DIR"
info "Warmup:   $WARMUP iterations"
info "Runs:     $RUNS iterations"

if [[ -n "$OPENROUTER_API_KEY" ]]; then
    ok "OPENROUTER_API_KEY set — API benchmarks will run"
else
    warn "OPENROUTER_API_KEY not set — scripts 04-06 will be skipped"
fi

echo ""

# Record system info
get_system_info > "$RESULTS_DIR/system-info.json"

# Track overall timing
suite_start="$(perl -MTime::HiRes=time -e 'printf "%.6f", time')"

scripts=(
    "00-preflight.sh"
    "01-static-metrics.sh"
    "02-startup-timing.sh"
    "03-build-metrics.sh"
    "04-runtime-memory.sh"
    "05-roundtrip-latency.sh"
    "06-stress-compaction.sh"
)

passed=0
skipped=0
failed=0

for script in "${scripts[@]}"; do
    script_path="$BENCH_DIR/$script"

    if [[ ! -f "$script_path" ]]; then
        warn "Script not found: $script — skipping"
        ((skipped++))
        continue
    fi

    header "$script"

    if bash "$script_path"; then
        ok "$script completed"
        ((passed++))
    else
        exit_code=$?
        if [[ $exit_code -eq 2 ]]; then
            warn "$script skipped (missing requirements)"
            ((skipped++))
        else
            err "$script failed (exit code $exit_code)"
            ((failed++))
        fi
    fi
done

# Generate report
header "Report Generation"
generate_report "$RESULTS_DIR"

suite_end="$(perl -MTime::HiRes=time -e 'printf "%.6f", time')"
suite_elapsed="$(echo "($suite_end - $suite_start) * 1000" | bc | cut -d. -f1)"

header "Summary"
info "Passed:  $passed"
info "Skipped: $skipped"
info "Failed:  $failed"
info "Total time: $(format_ms "$suite_elapsed")"
info "Report: $RESULTS_DIR/BENCHMARK-REPORT.md"

if [[ $failed -gt 0 ]]; then
    exit 1
fi
