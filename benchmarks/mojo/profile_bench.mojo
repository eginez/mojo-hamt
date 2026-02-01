"""
HAMT Profile Benchmark - Designed for Instruments Profiling

This creates a workload suitable for profiling with macOS Instruments.
Runs 100K insert and query operations to generate enough samples.
"""

from time import perf_counter_ns
from hamt import HAMT


fn profile_inserts(scale: Int) raises:
    """Run insert benchmark for profiling."""
    var hamt = HAMT[Int, Int]()
    
    print("Starting insert profiling for", scale, "operations...")
    var start = perf_counter_ns()
    
    for i in range(scale):
        hamt[i] = i * 10
    
    var end = perf_counter_ns()
    var total_time_ns = end - start
    var ns_per_op = Float64(total_time_ns) / Float64(scale)
    
    print("Insert completed:")
    print("  Operations:", scale)
    print("  Total time:", total_time_ns, "ns")
    print("  Time per op:", ns_per_op, "ns/op")
    print("  Throughput:", Int(1_000_000_000 / ns_per_op), "ops/sec")
    print()
    hamt.print_pool_stats()


fn profile_queries(scale: Int) raises:
    """Run query benchmark for profiling."""
    var hamt = HAMT[Int, Int]()
    
    # Pre-populate
    print("Pre-populating HAMT with", scale, "entries...")
    for i in range(scale):
        hamt[i] = i * 10
    
    print("Pre-population pool stats:")
    hamt.print_pool_stats()
    print()
    
    print("Starting query profiling for", scale, "operations...")
    var start = perf_counter_ns()
    
    for i in range(scale):
        var value = hamt[i]
    
    var end = perf_counter_ns()
    var total_time_ns = end - start
    var ns_per_op = Float64(total_time_ns) / Float64(scale)
    
    print("Query completed:")
    print("  Operations:", scale)
    print("  Total time:", total_time_ns, "ns")
    print("  Time per op:", ns_per_op, "ns/op")
    print("  Throughput:", Int(1_000_000_000 / ns_per_op), "ops/sec")


fn main() raises:
    print("=" * 60)
    print("       HAMT Profiling Benchmark")
    print("=" * 60)
    print()
    
    # Run with 100K operations for good profiling samples
    var scale = 100_000
    
    profile_inserts(scale)
    print()
    profile_queries(scale)
    
    print()
    print("=" * 60)
    print("       Profiling Complete")
    print("=" * 60)
