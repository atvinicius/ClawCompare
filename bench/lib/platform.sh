#!/usr/bin/env bash
# lib/platform.sh — macOS/Linux platform detection & tool adaptation

detect_platform() {
    PLATFORM="$(uname -s)"
    ARCH="$(uname -m)"

    case "$PLATFORM" in
        Darwin)
            PLATFORM_NAME="macOS"
            # macOS: /usr/bin/time -l reports "maximum resident set size" in bytes
            TIME_CMD="/usr/bin/time -l"
            TIME_RSS_PATTERN="maximum resident set size"
            TIME_RSS_UNIT="bytes"
            STAT_SIZE_CMD="stat -f%z"
            NPROC_CMD="sysctl -n hw.ncpu"
            MEM_TOTAL_CMD="sysctl -n hw.memsize"
            ;;
        Linux)
            PLATFORM_NAME="Linux"
            # Linux: /usr/bin/time -v reports "Maximum resident set size" in KB
            TIME_CMD="/usr/bin/time -v"
            TIME_RSS_PATTERN="Maximum resident set size"
            TIME_RSS_UNIT="kbytes"
            STAT_SIZE_CMD="stat -c%s"
            NPROC_CMD="nproc"
            MEM_TOTAL_CMD="free -b | awk '/Mem:/{print \$2}'"
            ;;
        *)
            err "Unsupported platform: $PLATFORM"
            exit 1
            ;;
    esac

    export PLATFORM PLATFORM_NAME ARCH
    export TIME_CMD TIME_RSS_PATTERN TIME_RSS_UNIT
    export STAT_SIZE_CMD NPROC_CMD MEM_TOTAL_CMD
}

get_system_info() {
    local cpu_model nproc mem_total_bytes mem_total_gb os_version

    case "$PLATFORM" in
        Darwin)
            cpu_model="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'unknown')"
            nproc="$(sysctl -n hw.ncpu)"
            mem_total_bytes="$(sysctl -n hw.memsize)"
            os_version="$(sw_vers -productVersion 2>/dev/null || echo 'unknown')"
            ;;
        Linux)
            cpu_model="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo 'unknown')"
            nproc="$(nproc)"
            mem_total_bytes="$(free -b | awk '/Mem:/{print $2}')"
            os_version="$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"' || uname -r)"
            ;;
    esac

    mem_total_gb="$(echo "scale=1; $mem_total_bytes / 1073741824" | bc)"

    echo "{\"platform\": \"$PLATFORM_NAME\", \"arch\": \"$ARCH\", \"cpu\": \"$cpu_model\", \"cores\": $nproc, \"ram_gb\": $mem_total_gb, \"os_version\": \"$os_version\"}"
}

get_file_size() {
    local path="$1"
    if [[ ! -f "$path" ]]; then
        echo "0"
        return
    fi
    $STAT_SIZE_CMD "$path"
}

# Initialize platform detection on source
detect_platform
