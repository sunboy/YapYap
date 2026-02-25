#!/bin/bash
# run-corpus-bench.sh — Fully automated corpus benchmark runner
# Usage: ./scripts/run-corpus-bench.sh [--models all] [--contexts all] [--levels all] [--keep-models]
#
# This script:
# 1. Builds YapYapBench (Release)
# 2. Runs the corpus benchmark across all models × contexts × levels
# 3. Saves timestamped JSON results to bench-results/
# 4. Auto-compares against the most recent previous run
# 5. Prints the scored report + comparison diff

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$PROJECT_DIR/bench-results"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
OUTFILE="$RESULTS_DIR/$TIMESTAMP.json"
LATEST_LINK="$RESULTS_DIR/latest.json"
LOG_FILE="$RESULTS_DIR/$TIMESTAMP.log"

# Parse args (pass through to yapyapbench corpus)
EXTRA_ARGS=""
KEEP_MODELS=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --models) EXTRA_ARGS="$EXTRA_ARGS --llm-models $2"; shift 2 ;;
        --contexts) EXTRA_ARGS="$EXTRA_ARGS --contexts $2"; shift 2 ;;
        --levels) EXTRA_ARGS="$EXTRA_ARGS --cleanup-levels $2"; shift 2 ;;
        --keep-models) KEEP_MODELS="--keep-models"; shift ;;
        --experimental) EXTRA_ARGS="$EXTRA_ARGS --experimental"; shift ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

mkdir -p "$RESULTS_DIR"

echo "============================================"
echo " YapYap Corpus Benchmark"
echo " $(date)"
echo "============================================"
echo ""

# Step 1: Build
echo "[1/3] Building YapYapBench (Release)..."
cd "$PROJECT_DIR"
xcodebuild -project YapYap.xcodeproj -scheme YapYapBench -configuration Release build 2>&1 | tail -3

BIN=$(xcodebuild -project YapYap.xcodeproj -scheme YapYapBench -configuration Release -showBuildSettings 2>/dev/null | grep -m1 BUILT_PRODUCTS_DIR | awk '{print $3}')/YapYapBench

if [ ! -x "$BIN" ]; then
    echo "ERROR: Build failed — $BIN not found"
    exit 1
fi
echo "  Built: $BIN"
echo ""

# Step 2: Determine comparison file
COMPARE_FLAG=""
if [ -f "$LATEST_LINK" ]; then
    PREVIOUS=$(readlink "$LATEST_LINK" 2>/dev/null || echo "$LATEST_LINK")
    echo "[2/3] Previous run found: $(basename "$PREVIOUS")"
    COMPARE_FLAG="--compare $PREVIOUS"
else
    echo "[2/3] No previous run found (first run)"
fi
echo ""

# Step 3: Run
echo "[3/3] Running corpus benchmark..."
echo "  Output: $OUTFILE"
echo "  Log: $LOG_FILE"
echo ""

"$BIN" corpus \
    --table \
    --output "$OUTFILE" \
    $COMPARE_FLAG \
    $KEEP_MODELS \
    $EXTRA_ARGS \
    2>&1 | tee "$LOG_FILE"

# Update latest link
ln -sf "$OUTFILE" "$LATEST_LINK"

echo ""
echo "============================================"
echo " Benchmark complete"
echo " Results: $OUTFILE"
echo " Log:     $LOG_FILE"
if [ -n "$COMPARE_FLAG" ]; then
    echo " Compared against: $(basename "$PREVIOUS")"
fi
echo "============================================"
