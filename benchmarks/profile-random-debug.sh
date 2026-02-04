#!/bin/bash
# Profile mojo-hamt with RANDOM keys and DEBUG SYMBOLS

set -e

BENCHMARK_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "${BENCHMARK_DIR}")"
SRC_DIR="${PROJECT_DIR}/src/mojo"
MOJO_DIR="${BENCHMARK_DIR}/mojo"
BINARY="${BENCHMARK_DIR}/profile_random_debug"
TEMPLATE="${1:-Time Profiler}"
OUTPUT_DIR="${BENCHMARK_DIR}/profiles"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TRACE_FILE="${OUTPUT_DIR}/mojo_hamt_random_debug_${TIMESTAMP}.trace"

mkdir -p "${OUTPUT_DIR}"

echo "Building mojo-hamt with DEBUG SYMBOLS..."
cd "${PROJECT_DIR}"
# Build with debug info (-g) and optimizations (-O2)
pixi run mojo build -g -O2 -I "${SRC_DIR}" -o "${BINARY}" "${MOJO_DIR}/profile_random.mojo"

echo ""
echo "Binary size with debug symbols:"
ls -lh "${BINARY}"

echo ""
echo "Profiling with random keys (debug build)..."
echo "Template: ${TEMPLATE}"
echo "Output: ${TRACE_FILE}"
echo ""

xctrace record --template "${TEMPLATE}" --output "${TRACE_FILE}" --launch -- "${BINARY}"

echo ""
echo "Profiling complete!"
echo "Trace file: ${TRACE_FILE}"
echo ""
echo "To view in Instruments:"
echo "  open ${TRACE_FILE}"
echo ""
echo "To export for analysis:"
echo "  xctrace export --input ${TRACE_FILE} --xpath '/trace-toc/run[1]/data/table[@schema=\"time-sample\"]' --output /tmp/samples.xml"
