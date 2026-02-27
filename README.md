# ClawCompare

Quantitative benchmarking and deep architectural comparison of the OpenClaw AI agent ecosystem.

## What Is This?

[OpenClaw](https://github.com/nicepkg/openclaw) is a full-featured, open-source personal AI agent platform built in TypeScript. Its success spawned an ecosystem of reimplementations optimizing for different tradeoffs: [ZeroClaw](https://github.com/zeroclaw-labs/zeroclaw) (Rust, minimal footprint) and [PicoClaw](https://github.com/pico-claw/picoclaw) (Go, embedded-first).

This repository provides two things:

1. **A 32KB deep architectural analysis** comparing all three implementations across technology stacks, plugin systems, memory models, security, and deployment strategies.
2. **A modular benchmark suite** producing reproducible, quantitative comparisons of startup time, binary size, memory usage, build time, roundtrip latency, and behavior under load.

## Key Results

Benchmarked on Apple M4 / 16 GB RAM / macOS. See `bench/results/BENCHMARK-REPORT.md` for full data.

| Metric | OpenClaw (TS) | ZeroClaw (Rust) | PicoClaw (Go) |
|--------|:---:|:---:|:---:|
| **Startup** (median) | 615 ms | 3.4 ms | 4.4 ms |
| **Binary size** | 33.6 MB | 4.5 MB | 24.6 MB |
| **Peak RSS** | 1,114 MB | 11.5 MB | 24.5 MB |
| **Roundtrip latency** (median) | 708 ms | 8.6 ms | 1,952 ms* |
| **Clean build** | 7.0 s | 69.3 s | 2.4 s |
| **SLOC** | 473K | 41K | 20K |
| **Dependencies** | 75 | 44 | 121 |

\* PicoClaw latency shows bimodal distribution — see [Latency Anomaly Notes](#latency-anomaly-notes).

## Deep Analysis

[`ANALYSIS.md`](ANALYSIS.md) is a comprehensive 32KB architectural comparison covering:

- Technology stacks and runtime models
- Message flow and core agent loops
- Plugin, skill, and tool systems
- Memory and persistence strategies
- Security architecture (encryption, sandboxing, auth)
- Multi-agent orchestration patterns
- Deployment models and tradeoff analysis

## Benchmark Suite

### Prerequisites

- **System tools:** `jq`, `bc`, `hyperfine`, `tokei`
- **Toolchains:** Node.js >= 22 + pnpm, Rust (cargo), Go >= 1.25
- **Optional:** `OPENROUTER_API_KEY` environment variable (for scripts 04-06)

### Quick Start

```bash
# Clone this repo and the three upstream projects
git clone https://github.com/your-org/ClawCompare && cd ClawCompare
git clone --depth 1 https://github.com/nicepkg/openclaw
git clone --depth 1 https://github.com/zeroclaw-labs/zeroclaw
git clone --depth 1 https://github.com/pico-claw/picoclaw

# Run all benchmarks
bash bench/run-all.sh

# Or run individual scripts
bash bench/00-preflight.sh   # Verify toolchains, build all projects
bash bench/01-static-metrics.sh  # Binary size, dependency count, SLOC
```

### Scripts

| Script | Measures | API Key Required |
|--------|----------|:---:|
| `00-preflight.sh` | Toolchain verification, project builds | No |
| `01-static-metrics.sh` | Binary size, dependency count, SLOC | No |
| `02-startup-timing.sh` | `--version` startup speed (hyperfine) | No |
| `03-build-metrics.sh` | Clean and incremental build times | No |
| `04-runtime-memory.sh` | Peak RSS during single-message invocation | Yes |
| `05-roundtrip-latency.sh` | Message send-to-response latency | Yes |
| `06-stress-compaction.sh` | Peak RSS growth across message counts | Yes |

### Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `WARMUP` | `3` | Hyperfine warmup iterations |
| `RUNS` | `10` | Measurement iterations per benchmark |
| `BENCH_MODEL` | `openrouter/auto` | LLM model for fair comparison |
| `OPENROUTER_API_KEY` | *(unset)* | Required for scripts 04-06 |

## Reproducibility Notes

- **Hardware baseline:** All published results use Apple M4 / 16 GB RAM. Cross-machine comparisons should note hardware differences.
- **Variance expectations:** Startup and build times are low-variance (< 5% CoV). Roundtrip latency depends on external API response times and can vary significantly between runs. Memory measurements may differ by ~5-10% across OS versions.
- **Publication-quality settings:** Use `WARMUP=5 RUNS=30` for publishable results. The defaults (`WARMUP=3 RUNS=10`) are sufficient for development iteration.
- **CI vs local:** CI runners introduce additional variance from shared resources and cold caches. The workflow uses `WARMUP=2 RUNS=5` to balance signal vs. cost.

## Latency Anomaly Notes

PicoClaw's roundtrip latency shows a **bimodal distribution** rather than the tight clustering seen in OpenClaw and ZeroClaw:

- **Fast cluster:** 767-843 ms (3 of 10 runs)
- **Slow cluster:** 1,772-3,436 ms (7 of 10 runs)

Likely causes:
- **Configuration loading:** PicoClaw reads config from disk on each invocation without caching
- **No connection pooling:** Each request establishes a new HTTP connection to the LLM provider
- **Workspace initialization:** Go binary performs full workspace setup on cold start

ZeroClaw's 8.6 ms median latency is also noteworthy — significantly faster than OpenClaw's 708 ms despite hitting the same API. This suggests aggressive connection reuse or response caching that warrants further investigation.

**Suggested follow-ups:** Profile PicoClaw with `GODEBUG=httptrace=1`, test ZeroClaw with cache-busting headers, run all three with a local mock API to isolate client-side overhead.

## Project Structure

```
ClawCompare/
├── ANALYSIS.md              # 32KB deep architectural comparison
├── README.md                # This file
├── bench/
│   ├── config.sh            # Shared configuration and env vars
│   ├── run-all.sh           # Master orchestrator
│   ├── 00-preflight.sh      # Toolchain + build verification
│   ├── 01-static-metrics.sh # Binary size, deps, SLOC
│   ├── 02-startup-timing.sh # Startup speed benchmarks
│   ├── 03-build-metrics.sh  # Clean + incremental build times
│   ├── 04-runtime-memory.sh # Peak RSS measurement
│   ├── 05-roundtrip-latency.sh # End-to-end message latency
│   ├── 06-stress-compaction.sh # Memory under load
│   ├── lib/
│   │   ├── measure.sh       # Timing and stats helpers
│   │   ├── platform.sh      # Platform detection
│   │   └── report.sh        # JSON → Markdown report generator
│   └── results/             # Benchmark output (JSON + report)
├── openclaw/                # ← cloned upstream (gitignored)
├── zeroclaw/                # ← cloned upstream (gitignored)
└── picoclaw/                # ← cloned upstream (gitignored)
```

## License

MIT
