#!/usr/bin/env bash
set -euo pipefail

ITERATIONS=${ITERATIONS:-10}
RESULTS_FILE="${RESULTS_FILE:-benchmark-results.md}"

echo "=== Claude Code Runtime Benchmark ==="
echo "Iterations: $ITERATIONS"
echo ""

benchmark_startup() {
  local name=$1
  local binary=$2
  local total_time=0

  for i in $(seq 1 "$ITERATIONS"); do
    start=$(gdate +%s%N 2>/dev/null || date +%s%N)
    $binary --version >/dev/null 2>&1
    end=$(gdate +%s%N 2>/dev/null || date +%s%N)
    elapsed=$(( (end - start) / 1000000 ))
    total_time=$((total_time + elapsed))
  done

  echo $((total_time / ITERATIONS))
}

benchmark_memory() {
  local name=$1
  local binary=$2

  $binary --help >/dev/null 2>&1 &
  local pid=$!
  sleep 0.5

  if [[ "$(uname)" == "Darwin" ]]; then
    local rss=$(ps -o rss= -p "$pid" 2>/dev/null || echo "0")
  else
    local rss=$(ps -o rss= -p "$pid" 2>/dev/null || echo "0")
  fi

  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true

  echo "${rss:-0}"
}

benchmark_sustained() {
  local name=$1
  local binary=$2
  local total_time=0

  for i in $(seq 1 "$ITERATIONS"); do
    start=$(gdate +%s%N 2>/dev/null || date +%s%N)
    $binary --help >/dev/null 2>&1
    end=$(gdate +%s%N 2>/dev/null || date +%s%N)
    elapsed=$(( (end - start) / 1000000 ))
    total_time=$((total_time + elapsed))
  done

  echo $((total_time / ITERATIONS))
}

echo "Building Node.js variant..."
nix build .#claude-code -o result-node 2>/dev/null

echo "Building Bun variant..."
nix build .#claude-code-bun -o result-bun 2>/dev/null

NODE_BIN="./result-node/bin/claude"
BUN_BIN="./result-bun/bin/claude"

echo ""
echo "Running startup benchmark..."
NODE_STARTUP=$(benchmark_startup "node" "$NODE_BIN")
BUN_STARTUP=$(benchmark_startup "bun" "$BUN_BIN")

echo "Running memory benchmark..."
NODE_MEMORY=$(benchmark_memory "node" "$NODE_BIN")
BUN_MEMORY=$(benchmark_memory "bun" "$BUN_BIN")

echo "Running sustained operation benchmark..."
NODE_SUSTAINED=$(benchmark_sustained "node" "$NODE_BIN")
BUN_SUSTAINED=$(benchmark_sustained "bun" "$BUN_BIN")

STARTUP_DIFF=$((BUN_STARTUP - NODE_STARTUP))
MEMORY_DIFF=$((BUN_MEMORY - NODE_MEMORY))
SUSTAINED_DIFF=$((BUN_SUSTAINED - NODE_SUSTAINED))

if [ "$STARTUP_DIFF" -lt 0 ]; then
  STARTUP_NOTE="Bun is $((STARTUP_DIFF * -1))ms faster"
else
  STARTUP_NOTE="Node is ${STARTUP_DIFF}ms faster"
fi

if [ "$MEMORY_DIFF" -lt 0 ]; then
  MEMORY_NOTE="Bun uses $((MEMORY_DIFF * -1 / 1024))MB less"
else
  MEMORY_NOTE="Node uses $((MEMORY_DIFF / 1024))MB less"
fi

cat > "$RESULTS_FILE" << EOF
# Runtime Benchmark Results

**Date**: $(date -u +"%Y-%m-%d %H:%M UTC")
**System**: $(uname -s) $(uname -m)
**Iterations**: $ITERATIONS

## Results

| Metric | Node.js 22 | Bun 1.3.5 | Difference |
|--------|------------|-----------|------------|
| Startup Time (ms) | $NODE_STARTUP | $BUN_STARTUP | $STARTUP_NOTE |
| Memory Usage (KB) | $NODE_MEMORY | $BUN_MEMORY | $MEMORY_NOTE |
| Sustained Ops (ms) | $NODE_SUSTAINED | $BUN_SUSTAINED | ${SUSTAINED_DIFF}ms |

## Recommendations

- **Choose Node.js (default)** if: LTS stability is important, proven production reliability
- **Choose Bun** if: Faster startup is critical, lower memory footprint is preferred
EOF

echo ""
echo "=== Results ==="
cat "$RESULTS_FILE"
echo ""
echo "Results saved to: $RESULTS_FILE"
