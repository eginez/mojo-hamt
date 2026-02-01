#!/bin/bash
# Enhanced Benchmark Suite - Multiple Patterns
# Runs all benchmark combinations and produces comparison table

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MOJO_DIR="${SCRIPT_DIR}/mojo"
SRC_DIR="${SCRIPT_DIR}/../src/mojo"

# Benchmark configuration
SCALES=(1000 10000 100000)
PATTERNS=("sequential" "shuffled" "random")
OPERATIONS=("insert" "query")

echo "============================================================"
echo "    Enhanced HAMT Benchmark Suite"
echo "============================================================"
echo ""
echo "Running benchmarks at scales: ${SCALES[@]}"
echo "Patterns: ${PATTERNS[@]}"
echo "Operations: ${OPERATIONS[@]}"
echo ""

# Header
printf "%-12s %-12s %-10s %-15s %-15s\n" "Operation" "Pattern" "Scale" "Time (ns/op)" "Throughput"
printf "%-12s %-12s %-10s %-15s %-15s\n" "--------" "-------" "-----" "------------" "----------"

# Run all combinations
for operation in "${OPERATIONS[@]}"; do
    for pattern in "${PATTERNS[@]}"; do
        for scale in "${SCALES[@]}"; do
            # Skip random insert/query at large scales (slow)
            if [[ "$pattern" == "random" && $scale -gt 10000 ]]; then
                continue
            fi
            
            # Run benchmark and extract throughput
            result=$(cd "${SCRIPT_DIR}/.." && pixi run mojo run -I "${SRC_DIR}" "${MOJO_DIR}/bench_enhanced.mojo" "$pattern" "$operation" "$scale" 2>&1 | grep "THROUGHPUT:" | cut -d: -f2 | tr -d ' ')
            
            # Calculate ns/op from throughput
            if [[ -n "$result" && "$result" =~ ^[0-9]+$ ]]; then
                ns_per_op=$(echo "scale=2; 1000000000 / $result" | bc)
                printf "%-12s %-12s %-10s %-15s %-15s\n" "$operation" "$pattern" "$scale" "$ns_per_op" "$result"
            else
                printf "%-12s %-12s %-10s %-15s %-15s\n" "$operation" "$pattern" "$scale" "ERROR" "ERROR"
            fi
        done
    done
done

echo ""
echo "============================================================"
echo "    Benchmark Suite Complete"
echo "============================================================"
