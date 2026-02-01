"""
Enhanced HAMT Benchmark - Multiple Patterns

This benchmark suite tests various key distributions:
1. Sequential inserts (0, 1, 2, ...)
2. Random inserts (shuffled order)
3. Sequential queries (0, 1, 2, ...)
4. Shuffled queries (random order - matches libhamt)
5. Random queries (random access pattern)

Usage:
    mojo bench_enhanced.mojo <pattern> <operation> <scale>

Patterns:
    sequential: Keys 0, 1, 2, ... N-1
    shuffled:   Keys 0, 1, 2, ... N-1 in random order
    random:     Random Int64 values

Operations:
    insert: Insert N keys
    query:  Query N existing keys

Examples:
    mojo bench_enhanced.mojo sequential insert 10000
    mojo bench_enhanced.mojo shuffled query 10000
    mojo bench_enhanced.mojo random insert 10000
"""

from time import perf_counter_ns
from sys import argv
from collections import List
from random import random_si64, seed

from hamt import HAMT

# Simple Fisher-Yates shuffle for integers 0..n-1
fn shuffle_indices(n: Int) -> List[Int]:
    """Create shuffled list of indices 0..n-1."""
    var indices = List[Int]()
    for i in range(n):
        indices.append(i)
    
    # Fisher-Yates shuffle
    for i in range(n - 1, 0, -1):
        # Generate random j in [0, i]
        var j = Int(random_si64(0, i))
        # Swap indices[i] and indices[j]
        var temp = indices[i]
        indices[i] = indices[j]
        indices[j] = temp
    
    return indices^


fn bench_insert_sequential(scale: Int) raises -> Int:
    """Insert sequential keys 0..scale-1."""
    var hamt = HAMT[Int, Int]()
    
    var start = perf_counter_ns()
    for i in range(scale):
        hamt[i] = i * 10
    var end = perf_counter_ns()
    
    return Int(end - start)


fn bench_insert_shuffled(scale: Int) raises -> Int:
    """Insert keys 0..scale-1 in random order."""
    seed(42)  # Reproducible
    var indices = shuffle_indices(scale)
    
    var hamt = HAMT[Int, Int]()
    
    var start = perf_counter_ns()
    for i in range(scale):
        var idx = indices[i]
        hamt[idx] = idx * 10
    var end = perf_counter_ns()
    
    return Int(end - start)


fn bench_insert_random(scale: Int) raises -> Int:
    """Insert random Int64 keys."""
    seed(42)  # Reproducible
    
    var hamt = HAMT[Int, Int]()
    
    var start = perf_counter_ns()
    for i in range(scale):
        var key = Int(random_si64(0, scale * 10))  # Random in reasonable range
        hamt[key] = i * 10
    var end = perf_counter_ns()
    
    return Int(end - start)


fn bench_query_sequential(scale: Int) raises -> Int:
    """Query keys 0..scale-1 in sequential order."""
    var hamt = HAMT[Int, Int]()
    
    # Pre-populate
    for i in range(scale):
        hamt[i] = i * 10
    
    var start = perf_counter_ns()
    for i in range(scale):
        var value = hamt[i]
    var end = perf_counter_ns()
    
    return Int(end - start)


fn bench_query_shuffled(scale: Int) raises -> Int:
    """Query keys 0..scale-1 in random order (matches libhamt)."""
    seed(42)  # Reproducible
    
    var hamt = HAMT[Int, Int]()
    
    # Pre-populate with sequential keys
    for i in range(scale):
        hamt[i] = i * 10
    
    # Create shuffled query order
    var query_order = shuffle_indices(scale)
    
    var start = perf_counter_ns()
    for i in range(scale):
        var idx = query_order[i]
        var value = hamt[idx]
    var end = perf_counter_ns()
    
    return Int(end - start)


fn bench_query_random(scale: Int) raises -> Int:
    """Query random keys (not necessarily in the HAMT)."""
    seed(42)  # Reproducible
    
    var hamt = HAMT[Int, Int]()
    
    # Pre-populate with sequential keys
    for i in range(scale):
        hamt[i] = i * 10
    
    var start = perf_counter_ns()
    for i in range(scale):
        var key = Int(random_si64(0, scale * 10))  # Random in range
        var result = hamt.get(key)  # May or may not exist
    var end = perf_counter_ns()
    
    return Int(end - start)


fn main() raises:
    """Main entry point."""
    
    if len(argv()) != 4:
        print("Usage: bench_enhanced.mojo <pattern> <operation> <scale>")
        print("")
        print("Patterns: sequential, shuffled, random")
        print("Operations: insert, query")
        print("Scale: positive integer")
        print("")
        print("Examples:")
        print("  mojo bench_enhanced.mojo sequential insert 10000")
        print("  mojo bench_enhanced.mojo shuffled query 10000")
        raise Error("Invalid arguments")
    
    var pattern = argv()[1]
    var operation = argv()[2]
    var scale = atol(argv()[3])
    
    if scale <= 0:
        raise Error("Scale must be positive")
    
    var total_time_ns: Int
    var pattern_name: String
    
    # Route to appropriate benchmark
    if operation == "insert":
        if pattern == "sequential":
            total_time_ns = bench_insert_sequential(scale)
            pattern_name = "Sequential Insert"
        elif pattern == "shuffled":
            total_time_ns = bench_insert_shuffled(scale)
            pattern_name = "Shuffled Insert"
        elif pattern == "random":
            total_time_ns = bench_insert_random(scale)
            pattern_name = "Random Insert"
        else:
            raise Error("Invalid pattern: " + pattern)
    
    elif operation == "query":
        if pattern == "sequential":
            total_time_ns = bench_query_sequential(scale)
            pattern_name = "Sequential Query"
        elif pattern == "shuffled":
            total_time_ns = bench_query_shuffled(scale)
            pattern_name = "Shuffled Query (libhamt style)"
        elif pattern == "random":
            total_time_ns = bench_query_random(scale)
            pattern_name = "Random Query"
        else:
            raise Error("Invalid pattern: " + pattern)
    
    else:
        raise Error("Invalid operation: " + operation)
    
    # Calculate metrics
    var ns_per_op = Float64(total_time_ns) / Float64(scale)
    var ops_per_sec = 1_000_000_000 / ns_per_op
    
    # Output results
    print("")
    print("=" * 60)
    print("Benchmark Results")
    print("=" * 60)
    print("Pattern:    ", pattern_name)
    print("Scale:      ", scale, "operations")
    print("Total time: ", total_time_ns, "ns")
    print("Time/op:    ", ns_per_op, "ns")
    print("Throughput: ", Int(ops_per_sec), "ops/sec")
    print("=" * 60)
    print("")
    
    # Also output single value for scripts
    print("THROUGHPUT:", Int(ops_per_sec))
