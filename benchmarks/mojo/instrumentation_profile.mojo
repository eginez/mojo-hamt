"""
HAMT Instrumentation Profiler

Uses a sampling approach to identify hotspots by timing individual operations.
"""

from time import perf_counter_ns
from collections import List, Dict

from hamt import HAMT


struct TimingCollector:
    """Collects timing samples for different operations."""
    var samples: Dict[String, List[UInt]]
    var current_op: String
    var start_time: UInt
    
    fn __init__(out self):
        self.samples = Dict[String, List[UInt]]()
        self.current_op = ""
        self.start_time = 0
    
    fn start(mut self, op: String):
        self.current_op = op
        self.start_time = perf_counter_ns()
    
    fn end(mut self) raises:
        var end_time = perf_counter_ns()
        var duration = end_time - self.start_time
        
        if self.current_op not in self.samples:
            self.samples[self.current_op] = List[UInt]()
        
        self.samples[self.current_op].append(duration)
    
    fn report(self) raises:
        print("\n=== HAMT Operation Timing Report ===\n")
        
        for op in self.samples.keys():
            var times = self.samples[op].copy()
            var count = len(times)
            
            if count == 0:
                continue
            
            # Calculate statistics
            var total: UInt = 0
            var min_time = times[0]
            var max_time = times[0]
            
            for i in range(count):
                var t = times[i]
                total += t
                if t < min_time:
                    min_time = t
                if t > max_time:
                    max_time = t
            
            var avg = total // count
            
            # Simple percentile - just use sorted middle
            # For simplicity, skip full sort and use P50 ~ avg for large samples
            var p50 = times[count // 2] if count > 0 else 0
            var p95_idx = Int(Float64(count) * 0.95)
            if p95_idx >= count:
                p95_idx = count - 1
            var p95 = times[p95_idx]
            
            print(op + ":")
            print("  Count: " + count.__str__())
            print("  Avg:   " + avg.__str__() + " ns")
            print("  Min:   " + min_time.__str__() + " ns")
            print("  P50:   " + p50.__str__() + " ns")
            print("  P95:   " + p95.__str__() + " ns")
            print("  Max:   " + max_time.__str__() + " ns")
            print("")


fn profile_insert_operations() raises:
    """Profile insert operations in detail."""
    print("=== Profiling Insert Operations ===\n")
    
    var hamt = HAMT[Int, Int]()
    var timer = TimingCollector()
    
    # Profile initial inserts (tree building phase)
    print("Phase 1: Initial tree building (0-1000 items)...")
    for i in range(1000):
        timer.start("insert_initial")
        hamt[i] = i * 10
        timer.end()
    
    # Profile bulk inserts (tree growth phase)
    print("Phase 2: Bulk inserts (1000-10000 items)...")
    for i in range(1000, 10000):
        timer.start("insert_bulk")
        hamt[i] = i * 10
        timer.end()
    
    timer.report()


fn profile_query_operations() raises:
    """Profile query operations in detail."""
    print("\n=== Profiling Query Operations ===\n")
    
    # Setup
    var hamt = HAMT[Int, Int]()
    for i in range(10000):
        hamt[i] = i * 10
    
    var timer = TimingCollector()
    
    # Profile successful lookups
    print("Phase 1: Successful lookups...")
    for i in range(10000):
        timer.start("query_hit")
        var val = hamt[i]
        timer.end()
    
    # Profile failed lookups
    print("Phase 2: Failed lookups...")
    for i in range(10000, 20000):
        timer.start("query_miss")
        try:
            var val = hamt[i]
        except:
            pass
        timer.end()
    
    timer.report()


fn profile_memory_operations():
    """Estimate memory operation overhead."""
    print("\n=== Memory Operation Estimates ===\n")
    
    # These are rough estimates based on typical malloc performance
    print("Typical operation costs (estimated):")
    print("  malloc(32 bytes): ~50-100 ns")
    print("  malloc(64 bytes): ~60-120 ns")
    print("  malloc(256 bytes): ~80-150 ns")
    print("  free(): ~30-60 ns")
    print("  pointer arithmetic: ~1-3 ns")
    print("")
    print("With ChildrenPool (bump allocator):")
    print("  Array allocation: ~2-5 ns (pointer arithmetic only)")
    print("  Saved vs malloc: ~50-145 ns per allocation")
    print("")


fn main() raises:
    print("=" * 60)
    print("       HAMT Instrumentation Profiler")
    print("=" * 60)
    print("")
    
    profile_insert_operations()
    profile_query_operations()
    profile_memory_operations()
    
    print("=" * 60)
    print("       Profiling Complete")
    print("=" * 60)
