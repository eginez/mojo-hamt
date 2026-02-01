# Phase 2 Performance Comparison

## Current State
Phase 2 branch currently contains Phase 1 optimizations only (smaller nodes with dynamic children arrays).

## Benchmark Results

### Insert Performance (ops/sec)
| Scale | Main Branch | Phase 2 Branch | Difference |
|-------|-------------|----------------|------------|
| 1K    | 2,083,333   | 1,650,165      | -20.8%     |
| 10K   | 1,384,083   | 1,621,797      | +17.2%     |
| 100K  | 1,322,541   | 1,211,945      | -8.4%      |

### Query Performance (ops/sec)
| Scale | Main Branch | Phase 2 Branch | Difference |
|-------|-------------|----------------|------------|
| 1K    | 6,849,315   | 3,225,806      | -52.9%     |
| 10K   | 2,262,443   | 2,981,515      | +31.8%     |
| 100K  | 1,944,694   | 1,902,841      | -2.2%      |

## Analysis
- Phase 1 shows improvement at medium scale (10K) for both insert and query
- Phase 1 shows regression at small scale (1K) - likely due to malloc overhead for small arrays
- The dynamic array allocation is hurting small-scale performance
- Need Phase 2 pool allocator to fix the malloc overhead

## Next Steps
Implement pool allocator to eliminate malloc/free overhead, especially for small arrays.
