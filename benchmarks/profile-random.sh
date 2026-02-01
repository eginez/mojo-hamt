#!/bin/bash
# Profile mojo-hamt with RANDOM keys

set -e

BENCHMARK_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$${BENCHMARK_DIR}")"
SRC_DIR="${PROJECT_DIR}/src/mojo"
MOJO_DIR="${BENCHMARK_DIR}/mojo"
BINARY="${BENCHMARK_DIR}/profile_random"
TEMPLATE="${1:-Time Profiler}"
OUTPUT_DIR="${BENCHMARK_DIR}/profiles"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TRACE_FILE="${OUTPUT_DIR}/mojo_hamt_random_${TIMESTAMP}.trace"

mkdir -p "${OUTPUT_DIR}"

echo "Building mojo-hamt with random keys..."
cd "${PROJECT_DIR}"
pixi run mojo build -I "${SRC_DIR}" -o "${BINARY}" "${MOJO_DIR}/profile_random.mojo"

echo ""
echo "Profiling with random keys..."
echo "Template: ${TEMPLATE}"
echo "Output: ${TRACE_FILE}"
echo ""

xctrace record --template "${TEMPLATE}" --output "${TRACE_FILE}" --launch -- "${BINARY}"

echo ""
echo "Profiling complete!"
echo "Trace file: ${TRACE_FILE}"
echo "To view: open ${TRACE_FILE}"
