# InlineArray Experiment Summary

## Date
January 2026

## Objective
Replace `List[Tuple[K, V]]` with `InlineArray[Tuple[K, V], 16]` in `HAMTLeafNode` to improve performance by using stack-allocated fixed-size arrays instead of heap-allocated lists.

## Changes Made

### HAMTLeafNode Structure
- Changed `_items: List[Tuple[Self.K, Self.V]]` → `_items: InlineArray[Tuple[Self.K, Self.V], MAX_LEAF_ITEMS]`
- Added `_count: UInt8` to track actual items in the fixed-size array
- Added `count()` and `is_full()` helper methods

### Initialization Pattern
InlineArray requires special handling with tuples:
- Use `Tuple[K, V]` syntax (not `(K, V)`) to avoid constructor ambiguity
- Use `uninitialized=True` parameter for runtime initialization
- Initialize elements manually via loop after creation

### Iteration Changes
Changed from:
```mojo
for item in self._items:
    # process item
```

To:
```mojo
for i in range(self._count):
    item = self._items[i]
    # process item
```

InlineArray doesn't implement `__iter__`, so must use index-based iteration.

## Test Results
✅ **All 34 tests pass** - Implementation is functionally correct

## Performance Results

### Comparison: InlineArray vs List (Phase 4 baseline)
| Operation | Scale | InlineArray | List | Delta |
|-----------|-------|-------------|------|-------|
| Insert | 10K | 2.40M ops/sec | 2.56M ops/sec | **-6.25%** |
| Query | 10K | 5.06M ops/sec | 7.28M ops/sec | **-30.5%** |

### Randomized Benchmark Results
**Insert (10K entries):**
- Sequential: 3,021,148 ops/sec
- Shuffled: 2,248,706 ops/sec
- Random: 2,338,087 ops/sec

**Query (10K entries):**
- Sequential: 5,760,368 ops/sec
- Shuffled: 5,636,978 ops/sec
- Random: 6,053,268 ops/sec

## Root Cause Analysis

### Why InlineArray Performed Worse
1. **Fixed-size overhead**: Even with 2 items, the array always allocates 16 slots
2. **Bounds checking**: Array access includes runtime bounds checks
3. **Iteration inefficiency**: Must loop up to `_count` instead of natural iteration
4. **Memory waste**: 14 unused slots per leaf with average 2-3 items
5. **No growth flexibility**: Fixed at 16 items, must handle overflow differently

### What Worked Well
1. ✅ No heap allocations for leaf storage
2. ✅ Better memory locality for small arrays
3. ✅ All tests pass
4. ✅ Compile-time size guarantees

## Conclusion

❌ **Not recommended** - The InlineArray implementation showed **consistent performance regressions** (-6% to -30%) compared to the List implementation.

### Trade-offs
| Aspect | InlineArray | List |
|--------|-------------|------|
| Memory allocation | Stack (fixed) | Heap (dynamic) |
| Space efficiency | Poor (wastes space) | Good (exact size) |
| Insert performance | Slightly worse | Better |
| Query performance | Significantly worse | Better |
| Cache locality | Better (fixed) | Variable |
| Code complexity | Higher | Lower |

## Recommendation

✅ **Keep using List implementation** for `HAMTLeafNode._items`

The List implementation:
- Is simpler and more maintainable
- Actually performs better
- Dynamically sizes to match actual item count
- Already well-optimized in Phase 4

## Alternative Approaches to Explore

If stack allocation is desired, consider:
1. **Small object optimization**: Use InlineArray for ≤4 items, fall back to List
2. **Arena allocation**: Pre-allocate pools and reuse leaf nodes
3. **Hybrid approach**: InlineArray for common case (1-3 items) with list fallback

## Files Modified
- `src/mojo/hamt.mojo` - Reverted to original List implementation
- `tests/mojo/test_hamt.mojo` - Test discovery restored

## Performance Baseline
Final baseline performance (Phase 4 + tests):
- Insert 10K: 2.56M ops/sec
- Query 10K: 7.28M ops/sec
- All 34 tests passing
