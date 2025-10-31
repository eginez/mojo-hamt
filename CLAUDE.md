# Agent Onboarding: mojo-learning (HAMT Implementation)

Welcome, agent. This guide provides the context and instructions needed to work on this project.

## 1. Project Overview

This project is a high-performance implementation of a **Hash Array Mapped Trie (HAMT)** written in the **Mojo** programming language. A HAMT is a persistent, memory-efficient data structure for key-value storage, offering performance comparable to traditional hash tables.

The implementation supports generic key-value types and provides a standard dictionary-like interface (`__getitem__`, `__setitem__`, `__len__`, etc.).

**Performance Goal**: This implementation aims to benchmark competitively against [libhamt](https://github.com/mkirchner/hamt), a well-optimized C implementation of HAMT. Benchmark data from libhamt and other implementations (glib2, AVL trees, red-black trees, hsearch) is available in `db.sqlite` for comparison.

## 2. Technology Stack

- **Language**: [Mojo](https://www.modular.com/mojo)
- **Dependency & Environment Management**: [Pixi](https://pixi.sh/)

All necessary dependencies and tasks are defined in `pixi.toml`. You should use `pixi` for all project-related commands.

## 3. Project Structure

```
mojo-learning/
├── src/
│   └── mojo/
│       └── hamt.mojo          # Core HAMT implementation
├── tests/
│   └── mojo/
│       └── test_hamt.mojo     # Test suite
├── benchmarks/
│   ├── mojo/
│   │   └── bench_numbers.mojo    # hamt-bench compatible benchmarks
│   ├── python/                   # Python benchmarks (future)
│   ├── hamt-bench/               # Git submodule: libhamt benchmark suite
│   │   └── db/                   # Build and collect libhamt benchmarks here
│   │       └── db.sqlite         # Reference benchmark database
│   └── data/
│       └── mojo_hamt_numbers.csv # Benchmark results (hamt-bench format)
├── pixi.toml                  # Pixi configuration
├── README.md                  # Main documentation
└── CLAUDE.md                  # Agent onboarding (this file)
```

### Key Files

- `src/mojo/hamt.mojo`: The core source code for the HAMT data structure. This is the main implementation file.
- `tests/mojo/test_hamt.mojo`: The test suite for the HAMT. It contains a comprehensive set of tests covering all features and edge cases.
- `benchmarks/mojo/bench_numbers.mojo`: Main benchmark suite that outputs single operation performance metrics. Takes two arguments: measurement type (insert|query) and scale (number of entries).
- `benchmarks/python/benchmarks.py`: ASV (Airspeed Velocity) benchmark harness that runs mojo benchmarks and tracks performance over time.
- `benchmarks/data/Esteban-MBP2024.local/`: ASV benchmark results (JSON format) for Apple M4 Pro hardware.
- `benchmarks/hamt-bench/`: **Git submodule** (https://github.com/eginez/hamt-bench) - This is where we build libhamt and collect benchmark data for comparison against mojo-hamt.
- `benchmarks/hamt-bench/db/db.sqlite`: Reference benchmark database from hamt-bench. Contains libhamt, libhamt-pool, glib2, avl, rb, hsearch baseline results collected on **Apple M4 Pro** (same hardware as mojo-hamt benchmarks).
- `pixi.toml`: The project configuration file. It defines dependencies and tasks for building, running, and testing. The `[tasks]` in this file are especially important.
- `README.md`: The main project documentation, intended for human developers. It contains detailed information about architecture and benchmarking.

## 4. Development Workflow & Key Commands

The environment is managed by Pixi. Use the following commands to interact with the project.

### Setup

To install dependencies and set up the environment (if needed):
```bash
pixi install
```

### Running the Main Program

The `pixi.toml` does not define a default run command, but you can execute the main file directly:
```bash
mojo hamt.mojo
```

### **Testing (Most Important)**

The most critical command for you is the test command. **Always run the tests after making any changes to `hamt.mojo` to verify correctness.**

The `README.md` specifies the test command:
```bash
pixi run mojo tests/mojo/test_hamt.mojo
```
However, a more conventional pixi approach would be to have a `test` task. Based on the `pixi.toml` I've read, no such task is defined. You should rely on the command from the `README.md`. A successful run will print "All tests passed!".

### **Benchmarking**

This project uses **ASV (Airspeed Velocity)** for performance tracking. Benchmarks are defined in `benchmarks/python/benchmarks.py` which calls the Mojo benchmark code.

#### Building libhamt benchmarks (macOS)

The `benchmarks/hamt-bench/` submodule contains libhamt benchmarks for comparison. To build on macOS:

```bash
# First time setup: initialize the hamt submodule
git submodule update --init --recursive

# Build libhamt benchmarks (requires bdw-gc via Homebrew)
cd benchmarks/hamt-bench
./build-macos.sh

# The script automatically:
# - Checks for Homebrew and bdw-gc installation
# - Builds with proper CFLAGS and LDFLAGS for macOS
# - Outputs binary to build/bench-hamt
```

**Note**: The `build-macos.sh` script handles the necessary flags for linking with Boehm GC on macOS:
```bash
make CFLAGS="-g -O2 -I$(brew --prefix bdw-gc)/include" LDFLAGS="-L$(brew --prefix bdw-gc)/lib"
```

#### Profiling libhamt with macOS Instruments

To profile libhamt performance on macOS using Instruments:

```bash
cd benchmarks/hamt-bench

# Run Time Profiler (CPU profiling) - default
./profile-macos.sh

# Run with different profiling template
./profile-macos.sh "Allocations"    # Memory allocation tracking
./profile-macos.sh "Leaks"          # Memory leak detection
./profile-macos.sh "System Trace"   # System-level performance

# List all available templates
xctrace list templates
```

The script will:
1. Build the benchmark with debug symbols (`-g`) and optimizations (`-O2`)
2. Run Instruments with the specified template
3. Save the trace file to `benchmarks/hamt-bench/profiles/libhamt_TIMESTAMP.trace`
4. Automatically open the trace in Instruments.app

**Profiling Templates Available:**
- **Time Profiler**: CPU profiling, call stacks, hot paths
- **Allocations**: Memory allocation patterns and growth
- **Leaks**: Memory leak detection
- **System Trace**: System calls, context switches, I/O

**Analyzing Results:**
- Open trace files: `open profiles/libhamt_TIMESTAMP.trace`
- Focus on hot functions in `hamt_set`, `hamt_get`, and hash computation
- Compare against mojo-hamt performance bottlenecks

#### Running Mojo HAMT benchmarks

To run benchmarks:

```bash
# Run single benchmark (outputs ops/sec)
pixi run mojo run -I src/mojo benchmarks/mojo/bench_numbers.mojo insert 1000
pixi run mojo run -I src/mojo benchmarks/mojo/bench_numbers.mojo query 10000

# Run ASV benchmark suite
cd benchmarks
asv run

# View results in browser
asv publish
asv preview
```

Benchmark results are stored in:
- **ASV format**: `benchmarks/data/Esteban-MBP2024.local/*.json`
- **libhamt database**: `benchmarks/hamt-bench/db/db.sqlite`

#### Current Performance (Apple M4 Pro)

**mojo-hamt vs libhamt comparison:**

| Operation | Scale | mojo-hamt (ns/op) | libhamt (ns/op) | Performance Gap |
|-----------|-------|-------------------|-----------------|-----------------|
| Insert    | 1K    | 1,181.0          | 59.3            | 20x slower      |
| Insert    | 10K   | 1,284.7          | 56.3            | 23x slower      |
| Query     | 1K    | 590.0            | 41.7            | 14x slower      |
| Query     | 10K   | 703.4            | 41.4            | 17x slower      |

**Note**: Both implementations benchmarked on same hardware (Apple M4 Pro, 24GB RAM).

## 5. Agent Task Guidelines

1.  **Analyze the Request**: Understand the user's goal (e.g., fix a bug, add a feature, refactor).
2.  **Consult the Code**: Read `hamt.mojo` to understand the relevant logic.
3.  **Consult the Tests**: Read `test_hamt.mojo` to see how existing features are tested. If you're adding a new feature, you should also add a new test case.
4.  **Modify the Code**: Apply the required changes to `hamt.mojo`.
5.  **Verify with Tests**: Run `pixi run mojo test_hamt.mojo`. If the tests fail, analyze the output and fix the code until all tests pass.
6.  **Report Completion**: Inform the user once the task is complete and verified.

## 6. Benchmarking Plan

The following benchmarking plan is extracted from `README.md`.

### 6.1. Benchmark Datasets

#### 6.1.1 Synthetic Datasets ✅ IMPLEMENTED

**Location**: `benchmarks/mojo/bench_synthetic.mojo`  
**Output**: `benchmarks/data/synthetic_benchmarks.csv`

Implemented benchmarks:
- **Sequential integers**: Keys 0, 1, 2, ..., N (predictable hashing)
  - Sizes: 100, 1K, 10K, 100K, 1M entries
  - Operations: Insert, Lookup (hits/misses), Update, Contains
  
- **Random integers**: Uniform random Int64 (realistic distribution)
  - Sizes: 100, 1K, 10K, 100K, 1M entries
  - Operations: Insert, Lookup (hits/misses), Update
  
- **Collision-prone keys**: Custom hash forcing collisions (stress test)
  - Sizes: 1K, 10K, 100K entries
  - Operations: Insert, Lookup (hits), Update

**CSV Format**:
```
method,dataset_type,operation,size,total_time_ns,ops_per_sec,ns_per_op
mojo-hamt,Sequential Integers,Insert,1000,123456,8100000,123.4
...
```

The `method` column allows comparison between different implementations:
- `mojo-hamt`: This HAMT implementation
- `python-dict`: Python's built-in dict (future)
- `python-contextvar`: Python's ContextVars (future)
- `libhamt`: C implementation via CFFI (future)

#### 6.1.2 Real-World Datasets ⏳ TODO

- **Unix Dictionary Words** (235K words from `/usr/share/dict/words`)
- **Mendeley Key-Value Store Benchmark Datasets** (Twitter data)
- **EnWiki Titles Dataset** (15.9M Wikipedia article titles)

### 6.2. Operations to Benchmark

- Insert (`set`)
- Update (`set` on existing key)
- Lookup (both hits and misses)
- Contains (`in` operator)
- Mixed read/write workloads ⏳ TODO

### 6.3. Metrics to Track

Currently tracked:
- **Performance**: Throughput (ops/sec) and Latency (ns/op) ✅
- **Memory**: Memory per entry (bytes/entry) and total footprint ⏳ TODO
- **Structure**: Average tree depth, bitmap utilization, and collision rate ⏳ TODO

### 6.4. Baseline Comparisons ⏳ TODO

- **`libhamt`** (C implementation)
- **Python's `ContextVars`**
- **Mojo's `Dict[K, V]`**

## 7. Performance Optimization Roadmap: Matching libhamt

### Current Status (as of 2025-10-30)

**Performance Gap to libhamt:**
- Insert 1K: **10x slower** (596 ns/op vs 59.3 ns/op)
- Query 1K: **7x slower** (294 ns/op vs 41.7 ns/op)
- Insert 10K: **21x slower** (1,199 ns/op vs 56.3 ns/op)
- Query 10K: **22x slower** (925 ns/op vs 41.4 ns/op)

**Current Implementation:**
- Using `InlineArray[16]` for children (128 bytes per node)
- NodeArena allocator (batches allocations but still calls malloc)
- 6-bit hash chunks (max 64 children per node)
- Node size: ~160 bytes

**Root Causes of Performance Gap:**
1. Large nodes (160 bytes vs libhamt's 16 bytes = 10x larger)
2. No memory recycling (libhamt uses freelists)
3. Still calling malloc via arena for every node
4. Wasted space in InlineArray (always allocate 16 slots, may use only 2-3)

### TODO: Implement libhamt's Pool Allocator Strategy

#### Phase 1: Restructure Node to Use Pointers (not InlineArray)

**Key Change:** Separate node structure from children storage

- Change node to store **pointer to children array** instead of inline array
- Store **exact number of children** to enable exact-size allocations
- Children array allocated separately with exact size needed
- Node size drops from ~160 bytes to ~48 bytes (3.3x smaller)

**Why This Matters:**
- libhamt nodes are 16 bytes because they only store: `{pointer to array, bitmap}`
- Small nodes = better cache locality = faster
- Exact-size arrays = no wasted memory

#### Phase 2: Implement Pool Allocators for Children Arrays

**Key Change:** Pre-allocate large chunks and serve arrays from pools

- Create **32-64 separate pools**, one for each array size (1 child, 2 children, ..., 64 children)
- Each pool pre-allocates huge chunks (e.g., 1GB) of that specific array size
- Allocation = pointer arithmetic in pre-allocated chunk (no malloc!)
- Deallocation = add to freelist (no free() call!)

**Why This Matters:**
- This is how libhamt achieves ~55ns/op performance
- Most time in profiling was tcmalloc overhead - pools eliminate this
- Freelist recycling means freed arrays are immediately reusable

**How libhamt Does It:**
- 32 pools initialized at HAMT creation
- Each pool manages arrays of one specific size
- `table_allocate(h, size)` → get from pool[size-1]
- `table_free(h, ptr, size)` → return to pool[size-1] freelist

#### Phase 3: Add Node Pool with Freelist Recycling

**Key Change:** Pool for nodes themselves (not just children arrays)

- Current NodeArena allocates but doesn't recycle
- Add freelist to recycle freed nodes
- When removing entries, return nodes to freelist instead of calling free()

**Why This Matters:**
- Nodes get reused from hot cache
- Reduces allocation pressure
- Better memory locality

#### Phase 4: Optimize Array Extension/Copying

**Key Change:** Use efficient bulk copying when adding children

- When adding a child: allocate new array (size N+1), copy old N children, insert new one, free old array to pool
- Use memcpy for bulk copying (not loops)
- libhamt's `table_extend()` does this efficiently

**Why This Matters:**
- Fixes Query 10K regression (currently 22x slower)
- Copying into new contiguous array is cache-friendly
- Pool recycling makes old array immediately available

### Expected Performance Impact

| Optimization | Target Speedup | Cumulative Speedup |
|--------------|----------------|-------------------|
| Phase 1: Small nodes with pointers | 2-3x | 2-3x |
| Phase 2: Children array pools | 3-5x | 6-15x |
| Phase 3: Node pool with freelist | 1.5-2x | 9-30x |
| Phase 4: Efficient array operations | 1.5-2x | 14-60x |

**Target Result:** mojo-hamt reaching **~30-100 ns/op**, competitive with libhamt's ~55 ns/op

### Key Insights from libhamt Architecture

1. **Tiny nodes (16 bytes):** Only `{children_pointer, bitmap}` or `{key, value}`
2. **Exact-size arrays:** 3 children = 24 bytes, not 512 bytes
3. **Pool per size:** 32 pools (sizes 1-32), each with its own freelist
4. **No malloc in hot path:** Allocations served from pre-allocated chunks
5. **Immediate recycling:** Freed arrays go to freelist, reused instantly

### Reference

- libhamt source: `benchmarks/hamt-bench/lib/hamt/src/hamt.c`
- Node structure: lines 38-49
- Pool allocators: lines 147-299
- Array operations: lines 301-321
- Full profiling analysis: `benchmarks/PROFILING_REPORT.md`
