"""
Profiling workload with RANDOM keys for realistic performance analysis.
This uses random keys to defeat cache prefetching and show true HAMT performance.
"""

from time import perf_counter_ns
from random import random_si64, seed
from collections import List
from hamt import HAMT

fn profile_random_insert(scale: Int) raises:
    """Profile inserts with random keys."""
    seed(42)  # Reproducible
    
    var hamt = HAMT[Int, Int]()
    
    print("Profiling random insert for", scale, "operations...")
    var start = perf_counter_ns()
    
    for i in range(scale):
        var key = Int(random_si64(0, scale * 10))
        hamt[key] = i * 10
    
    var end = perf_counter_ns()
    var total_time_ns = end - start
    var ns_per_op = Float64(total_time_ns) / Float64(scale)
    
    print("Random insert completed:")
    print("  Operations:", scale)
    print("  Total time:", total_time_ns, "ns")
    print("  Time per op:", ns_per_op, "ns/op")
    print("  Throughput:", Int(1_000_000_000 / ns_per_op), "ops/sec")
    print()
    
    hamt.print_tree_stats()
    hamt.print_pool_stats()

fn profile_random_query(scale: Int) raises:
    """Profile queries with random access pattern."""
    seed(42)  # Reproducible
    
    var hamt = HAMT[Int, Int]()
    
    # Pre-populate with random keys
    print("Pre-populating with", scale, "random entries...")
    var keys = List[Int]()
    for i in range(scale):
        var key = Int(random_si64(0, scale * 10))
        hamt[key] = i * 10
        keys.append(key)
    
    print("Pre-population complete. Size:", len(hamt))
    hamt.print_pool_stats()
    print()
    
    # Shuffle query order
    print("Shuffling query order...")
    for i in range(scale - 1, 0, -1):
        var j = Int(random_si64(0, i))
        var temp = keys[i]
        keys[i] = keys[j]
        keys[j] = temp
    
    print("Profiling random query for", scale, "operations...")
    var start = perf_counter_ns()
    
    for i in range(scale):
        var value = hamt[keys[i]]
    
    var end = perf_counter_ns()
    var total_time_ns = end - start
    var ns_per_op = Float64(total_time_ns) / Float64(scale)
    
    print("Random query completed:")
    print("  Operations:", scale)
    print("  Total time:", total_time_ns, "ns")
    print("  Time per op:", ns_per_op, "ns/op")
    print("  Throughput:", Int(1_000_000_000 / ns_per_op), "ops/sec")

fn main() raises:
    print("=" * 60)
    print("       HAMT Profiling with RANDOM Keys")
    print("=" * 60)
    print()
    
    var scale = 100_000
    
    profile_random_insert(scale)
    print()
    profile_random_query(scale)
    
    print()
    print("=" * 60)
    print("       Profiling Complete")
    print("=" * 60)
