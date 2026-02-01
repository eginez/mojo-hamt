#!/bin/bash
# macOS Instruments profiling script for mojo-hamt
# This script builds the benchmark and runs Instruments

set -e

# Configuration
BENCHMARK_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$BENCHMARK_DIR")"
SRC_DIR="${PROJECT_DIR}/src/mojo"
MOJO_DIR="${BENCHMARK_DIR}/mojo"
BINARY="${BENCHMARK_DIR}/profile_bench"
TEMPLATE="${1:-Time Profiler}"  # Default to Time Profiler, can override with arg
OUTPUT_DIR="${BENCHMARK_DIR}/profiles"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TRACE_FILE="${OUTPUT_DIR}/mojo_hamt_${TIMESTAMP}.trace"

# Create output directory
mkdir -p "${OUTPUT_DIR}"

# Check if Instruments is available
if ! command -v xctrace &> /dev/null; then
    echo "Error: xctrace (Instruments CLI) not found."
    echo "Please install Xcode Command Line Tools."
    exit 1
fi

# Check if pixi is available
if ! command -v pixi &> /dev/null; then
    echo "Error: pixi not found."
    echo "Please install pixi: https://pixi.sh/"
    exit 1
fi

echo "Building mojo-hamt benchmark with debug symbols..."
# Build with debug symbols (-D for debug mode, or use default optimizations)
cd "${PROJECT_DIR}"
pixi run mojo build -I "${SRC_DIR}" -o "${BINARY}" "${MOJO_DIR}/profile_bench.mojo"

if [ ! -f "${BINARY}" ]; then
    echo "Error: Build failed, ${BINARY} not found"
    exit 1
fi

echo ""
echo "Starting Instruments profiling..."
echo "Template: ${TEMPLATE}"
echo "Output: ${TRACE_FILE}"
echo ""

# Run Instruments
# Available templates: "Time Profiler", "Allocations", "Leaks", "System Trace", etc.
# To list all templates: xctrace list templates
xctrace record --template "${TEMPLATE}" --output "${TRACE_FILE}" --launch -- "${BINARY}"

echo ""
echo "Profiling complete!"
echo "Trace file saved to: ${TRACE_FILE}"
echo ""
echo "To view the trace:"
echo "  open ${TRACE_FILE}"
echo ""
echo "Available profiling templates:"
echo "  Time Profiler    - CPU profiling (default)"
echo "  Allocations      - Memory allocation tracking"
echo "  Leaks            - Memory leak detection"
echo "  System Trace     - System-level performance"
echo ""
echo "To use a different template:"
echo "  ./profile-mojo-hamt.sh 'Allocations'"
echo ""
echo "To list all available templates:"
echo "  xctrace list templates"
echo ""
