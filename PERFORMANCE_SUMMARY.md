# Performance Summary - Phase 2.5 (Pool Exhaustion Fix)

**Date**: 2026-02-01  
**Commit**: dd6a7ea  
**Hardware**: Apple M4 Pro, 24GB RAM

---

## Current Performance

### Benchmark Results (After Pool Fix)

| Scale | Operation | Throughput | Latency | vs libhamt |
|-------|-----------|------------|---------|------------|
| 1K | Insert | 4.83M ops/sec | 207 ns/op | 3.7x slower |
| 1K | Query | 8.92M ops/sec | 112 ns/op | 2.7x slower |
| 10K | Insert | 4.74M ops/sec | 210 ns/op | **3.8x slower** |
| 10K | Query | 7.29M ops/sec | 137 ns/op | **3.3x slower** |
| 50K | Insert | 2.71M ops/sec | 368 ns/op | 6.6x slower |
| 50K | Query | 3.82M ops/sec | 261 ns/op | 6.3x slower |
| 100K | Insert | 2.24M ops/sec | 445 ns/op | 7.9x slower |
| 100K | Query | 3.34M ops/sec | 299 ns/op | 7.3x slower |

**Note**: Some regression at larger scales (50K+) suggests further optimization opportunities.

---

## Performance Evolution

### Phase-by-Phase Improvements

| Phase | Description | Insert 10K | Query 10K | Key Achievement |
|-------|-------------|------------|-----------|-----------------|
| **Baseline** | Original implementation | 1,284 ns | 703 ns | Initial version |
| **Phase 1** | Pointer-based nodes | ~800 ns | ~400 ns | Smaller nodes |
| **Phase 2** | Bump allocator | 352 ns | 121 ns | Eliminated malloc |
| **Phase 2.5** | Pool size fix | **210 ns** | **137 ns** | **Fixed exhaustion** |
| | | | | |
| **Total Improvement** | Baseline → Now | **+511%** | **+413%** | **6x faster!** |

---

## Root Cause: Pool Exhaustion

### The Problem

At 100K scale with original 65K pool:
- **Pool utilization**: 4,525% (45x over capacity!)
- **Fallback rate**: 98% (683,500 malloc calls)
- **Performance**: All Phase 2 benefits lost

### The Fix

Increased pool size from 65K → 4M slots:
- **Pool utilization**: 70.7% (healthy headroom)
- **Fallback rate**: 0% (zero malloc calls)
- **Performance**: 2x improvement at scale

### Memory Cost

- **Added**: 31.5 MB (65K → 4M slots)
- **Trade-off**: Acceptable for 2x speedup
- **Capacity**: Supports ~130K entries

---

## Remaining Performance Gap

### Current Gap to libhamt

| Operation | mojo-hamt | libhamt | Gap | Status |
|-----------|-----------|---------|-----|--------|
| Insert 10K | 210 ns | 56 ns | **3.8x slower** | ✅ Much improved |
| Query 10K | 137 ns | 41 ns | **3.3x slower** | ✅ Good |

**Progress**: Closed the gap from 6.3x → 3.8x (38% improvement!)

### Identified Bottlenecks

With pool exhaustion fixed, the true hotspots are:

1. **Leaf node copies** (~48 ns per insert)
   - `Tuple(key.copy(), value.copy())`
   - **Fix**: Move semantics or InlineArray
   - **Expected gain**: 2-3x

2. **Array growth** (~30 ns per operation)
   - Manual pointer-by-pointer copying
   - **Fix**: memcpy or reduce growth frequency
   - **Expected gain**: 1.5-2x

3. **Variant dispatch** (~20 ns per operation)
   - Runtime type checking overhead
   - **Fix**: `@always_inline` or tagged union
   - **Expected gain**: 1.3-1.5x

---

## Next Optimization Targets

### Quick Wins (1-2 days)
1. ✅ ~~Pool size fix~~ - **DONE! +100% at 100K**
2. ⏳ Move semantics for leaf nodes - Expected: +40-50%
3. ⏳ Add `@always_inline` hints - Expected: +10-15%

### Medium Term (1-2 weeks)
4. ⏳ Replace List with InlineArray - Expected: +50%
5. ⏳ Optimize array copying - Expected: +20-30%
6. ⏳ Node recycling (Phase 3) - Expected: +15-20%

### Goal: 100 ns/op inserts
- Current: 210 ns/op
- Target: ~100 ns/op (2x faster)
- Gap to libhamt: ~2x (acceptable!)

---

## Key Learnings

### 1. Scale Matters
Performance at 1K ≠ 10K ≠ 100K. Must test at realistic scales.

### 2. Telemetry is Critical
Simple counters revealed pool exhaustion immediately. Always instrument!

### 3. Fallback Paths Matter
Even "rare" fallbacks (2% at 10K) become dominant at scale (98% at 100K).

### 4. Memory is a Trade-off
31.5 MB for 2x speedup is worth it. Pool sizing is critical.

---

## Profiling Tools Added

New diagnostics for future investigations:

1. **benchmarks/mojo/profile_bench.mojo**
   - Profiling workload with telemetry
   - Measures insert + query performance
   - Prints pool statistics

2. **benchmarks/mojo/test_pool_usage.mojo**
   - Multi-scale pool utilization test
   - Detects exhaustion early

3. **benchmarks/profile-mojo-hamt.sh**
   - Instruments Time Profiler integration
   - Automated profiling workflow

4. **benchmarks/run_comprehensive_bench.sh**
   - Multi-scale benchmark suite
   - CSV output for analysis

---

## Documentation

Complete investigation documented in:
- **INVESTIGATION_FINDINGS.md** - Detailed root cause analysis
- **PROFILING_REPORT_2026-02-01.md** - Profiling methodology
- This file - Performance summary

---

**Status**: Phase 2.5 complete - Pool exhaustion eliminated!  
**Next**: Optimize leaf storage and array operations (Phase 3)
