#!/bin/bash
# Comprehensive benchmark suite

echo "======================================================================"
echo "           COMPREHENSIVE BENCHMARK SUITE"
echo "======================================================================"
echo ""
echo "Running benchmarks at multiple scales..."
echo ""

scales=(1000 5000 10000 50000 100000)

echo "INSERT BENCHMARKS:"
echo "Scale,Ops/Sec,Ns/Op" > /tmp/insert_results.csv
for scale in "${scales[@]}"; do
    result=$(pixi run mojo run -I src/mojo benchmarks/mojo/bench_numbers.mojo insert $scale)
    ns_per_op=$(python3 -c "print(1e9 / $result)")
    echo "$scale,$result,$ns_per_op" >> /tmp/insert_results.csv
    printf "%7s entries: %12.2f ns/op (%8.2f M ops/sec)\n" "$scale" "$ns_per_op" "$(echo "scale=2; $result / 1000000" | bc)"
done

echo ""
echo "QUERY BENCHMARKS:"
echo "Scale,Ops/Sec,Ns/Op" > /tmp/query_results.csv
for scale in "${scales[@]}"; do
    result=$(pixi run mojo run -I src/mojo benchmarks/mojo/bench_numbers.mojo query $scale)
    ns_per_op=$(python3 -c "print(1e9 / $result)")
    echo "$scale,$result,$ns_per_op" >> /tmp/query_results.csv
    printf "%7s entries: %12.2f ns/op (%8.2f M ops/sec)\n" "$scale" "$ns_per_op" "$(echo "scale=2; $result / 1000000" | bc)"
done

echo ""
echo "======================================================================"
echo "Results saved to /tmp/insert_results.csv and /tmp/query_results.csv"
echo "======================================================================"
