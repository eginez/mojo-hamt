# Phase 2 Performance Results

## Summary

Phase 2 successfully implemented a **simple bump allocator** for children arrays, achieving massive performance gains.

## Implementation

### Simple Bump Allocator (ChildrenPool)

Instead of complex freelists, we use a straightforward bump allocator:

```mojo
struct ChildrenPool:
    var pool: UnsafePointer[...]     # Pre-allocated block (64K slots)
    var next_index: Int               # Bump pointer for allocation
    var capacity: Int                 # Total pool capacity
    
    fn allocate(mut self, size: Int) -> Array:
        # Fast O(1) bump allocation
        if next_index + size <= capacity:
            ptr = pool + next_index
            next_index += size
            return ptr
        else:
            # Rare: pool exhausted, fallback to malloc
            return malloc(size)
```

**Why this works:**
- Pre-allocates 64K child pointer slots at startup (one malloc)
- All subsequent allocations are pointer arithmetic (O(1))
- No freelist management overhead
- Arrays never freed individually - entire pool freed at once
- Falls back to malloc only when pool exhausted (rare in practice)

## Benchmark Results

### Insert Performance (ops/sec)

| Scale | Before Phase 2 | After Phase 2 | Improvement | ns/op |
|-------|----------------|---------------|-------------|-------|
| 1K    | 1,650,165     | **4,950,495** | **+200%**   | 202   |
| 10K   | 1,564,456     | **2,557,545** | **+63%**    | 391   |
| 100K  | 1,234,994     | **1,750,026** | **+42%**    | 571   |

### Query Performance (ops/sec)

| Scale | Before Phase 2 | After Phase 2 | Improvement | ns/op |
|-------|----------------|---------------|-------------|-------|
| 1K    | 3,225,806     | **9,090,909** | **+182%**   | 110   |
| 10K   | 2,900,232     | **7,283,321** | **+151%**   | 137   |
| 100K  | 1,902,841     | **3,054,461** | **+62%**    | 327   |

## Comparison with libhamt (C implementation)

| Operation | mojo-hamt | libhamt | Gap |
|-----------|-----------|---------|-----|
| Insert    | ~391 ns/op | ~56 ns/op | **~7x** (was ~11x) |
| Query     | ~137 ns/op | ~41 ns/op | **~2.4x** (was ~6x) |

## Analysis

### What Worked

1. **Eliminating malloc from hot path** - The #1 bottleneck was malloc/free for small arrays
2. **Simple design** - Bump allocator is much simpler than freelists and just as effective
3. **Pre-allocation** - One large malloc at startup removes allocation jitter
4. **Cache locality** - Contiguous storage improves cache performance

### What's Still Needed

To reach libhamt performance (~56 ns/op insert):

1. **Node pool with recycling** - Currently nodes are never freed/reused
2. **SIMD hash calculations** - Mojo's hash() may have overhead
3. **Inline critical functions** - More aggressive inlining
4. **Reduce copies** - Value copying still significant overhead

### Key Insight

The 2.4x gap for queries is likely due to:
- Mojo's safety checks (bounds, null)
- Variant dispatch overhead (vs C unions)
- Pointer chasing through tree levels

The 7x gap for inserts is likely due to:
- Node allocation (even from arena)
- Value copying
- Tree traversal overhead

## Conclusion

Phase 2 was a **massive success** - query performance improved 151% and is now within 2.4x of libhamt. Insert performance improved 63% but needs more work to reach parity.

The simple bump allocator design proved that **eliminating malloc is the #1 optimization** for HAMT performance.

**Next Steps:**
- Phase 3: Node recycling with freelists
- Phase 4: Optimize hash calculations and reduce copies
- Target: Match libhamt performance (~56 ns/op)
