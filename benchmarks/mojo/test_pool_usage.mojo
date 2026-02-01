"""
Test pool usage at different scales
"""

from time import perf_counter_ns
from hamt import HAMT


fn test_scale(scale: Int) raises:
    print("=" * 60)
    print("Testing at scale:", scale)
    print("=" * 60)
    
    var hamt = HAMT[Int, Int]()
    
    for i in range(scale):
        hamt[i] = i * 10
    
    hamt.print_pool_stats()
    print()


fn main() raises:
    test_scale(1_000)
    test_scale(10_000)
    test_scale(50_000)
    test_scale(100_000)
