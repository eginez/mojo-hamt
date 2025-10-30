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
│   └── data/
│       └── mojo_hamt_numbers.csv # Benchmark results (hamt-bench format)
├── db.sqlite                  # Reference benchmark database (hamt-bench)
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
