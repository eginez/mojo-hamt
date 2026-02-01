# HAMT - Hash Array Mapped Trie

A high-performance Hash Array Mapped Trie (HAMT) implementation in Mojo, providing an efficient persistent data structure for key-value storage.

📊 **[View Live Benchmarks](https://eginez.github.io/mojo-hamt/)**

## Overview

This project implements a HAMT data structure that offers:
- **Memory efficiency**: Sparse array representation using bitmaps
- **Fast lookups**: Near hash-table performance with O(log n) complexity
- **Collision handling**: Leaf nodes can store multiple key-value pairs with identical hashes
- **Generic types**: Supports any key-value types that are `Movable`, `Copyable`, `Hashable`, `EqualityComparable`, and `Stringable`

## Features

- **Standard dict-like interface**: Implements `__getitem__`, `__setitem__`, `__contains__`, `__len__`, `__str__`, and `__repr__`
- **Custom hash functions**: Optional custom hash function support for specialized use cases
- **60-bit hashing**: Uses 60-bit hashes split into 10 levels of 6-bit chunks
- **Bitmap-based indexing**: Efficient sparse array representation using population count (popcount)

## Installation

This project uses [Pixi](https://pixi.sh/) for dependency management.

```bash
# Install dependencies
pixi install

# Build
pixi run mojo build hamt.mojo

# Run tests
pixi run mojo test_hamt.mojo
```

## Usage

### Basic Operations

```mojo
from hamt import HAMT

# Create a new HAMT
var map = HAMT[String, Int]()

# Set values
map["apple"] = 1
map["banana"] = 2
map.set("cherry", 3)

# Get values
var value = map["apple"]  # Returns 1
var opt_value = map.get("orange")  # Returns Optional[Int]()

# Check membership
if "apple" in map:
    print("Found apple!")

# Get size
print(len(map))  # Prints: 3

# String representation
print(map)  # Prints: {apple: 1, banana: 2, cherry: 3}
```

### Custom Hash Functions

For specialized use cases (e.g., testing collision handling):

```mojo
fn custom_hash(key: Int) -> UInt64:
    return UInt64(key % 1000)  # Force collisions

var map = HAMT[Int, String](custom_hash)
map.set(1, "one")
map.set(1001, "one thousand one")  # Will collide, handled by leaf node
```

## Architecture

### Data Structure

The HAMT consists of three main components:

1. **HAMT**: The main structure holding the root node and metadata
2. **HAMTNode**: Internal nodes using bitmap-based sparse arrays
3. **HAMTLeafNode**: Leaf nodes storing actual key-value pairs

### Hash Strategy

- Hash values are truncated to 60 bits (top 4 bits cleared)
- 60 bits are divided into 10 levels × 6 bits per level
- Each 6-bit chunk (0-63) indexes into a node's sparse array
- Bitmap representation: bit `i` set means child at index `i` exists
- Dense array index calculated using `popcount(bitmap & (2^i - 1))`

### Example Tree Structure

```
Root Node (bitmap: 000...0100010)
  ├─ chunk[1] → Node (bitmap: 000...1000001)
  │               ├─ chunk[0] → Leaf {key1: val1}
  │               └─ chunk[6] → Leaf {key2: val2, key3: val3}
  └─ chunk[5] → Node (bitmap: 000...0010000)
                  └─ chunk[4] → Leaf {key4: val4}
```

### Arena Allocator

To optimize memory allocation performance, this implementation uses an **arena allocator** for HAMT nodes:

**Key concept:**
- Nodes are allocated in large blocks (default: 1024 nodes per block)
- Individual node allocations become O(1) pointer arithmetic instead of malloc calls
- Reduces malloc overhead from O(N) to O(N/1024) for N insertions

**Performance impact:**
- **50-58% faster** insert operations
- **30-58% faster** query operations
- Better cache locality from contiguous memory allocation

**Trade-offs:**
- Small memory overhead (last block may be partially unused)
- Optimized for immutable/persistent use cases
- Not suitable for HAMTs with frequent node deletions

### Phase 2: Children Array Pool

Building on the arena allocator, Phase 2 introduces a **bump allocator** for children arrays:

**Problem with Phase 1:**
- Each internal node allocates its children array separately via malloc
- Small allocations (4-16 elements) dominate for typical HAMT usage
- Malloc/free overhead was ~60% of total runtime

**Solution - Simple Bump Allocator:**
- Pre-allocate one large pool (64K child pointers) at startup
- Children arrays are "bump allocated" from this pool via pointer arithmetic
- No individual array frees - entire pool freed when HAMT destroyed
- Falls back to malloc only when pool exhausted (rare)

**Performance Results:**

| Operation | Before Phase 2 | After Phase 2 | Improvement | vs libhamt (C) |
|-----------|----------------|---------------|-------------|----------------|
| **Insert 10K** | 1.56M ops/sec | **2.56M ops/sec** | **+63%** | ~7x slower |
| **Insert 100K** | 1.21M ops/sec | **1.75M ops/sec** | **+42%** | ~7x slower |
| **Query 10K** | 2.90M ops/sec | **7.28M ops/sec** | **+151%** | ~2.4x slower |
| **Query 100K** | 1.90M ops/sec | **3.05M ops/sec** | **+62%** | ~2.4x slower |

**Key Achievement:**
- Query performance now within **2.4x of libhamt** (was ~6x before)
- Insert performance improved to **~391 ns/op** (target: ~56 ns/op)
- Eliminated malloc from hot path entirely

**Implementation Details:**
```mojo
struct ChildrenPool:
    var pool: UnsafePointer[...]  # 64K pre-allocated slots
    var next_index: Int           # Bump pointer
    
    fn allocate(self, size: Int) -> Array:
        # O(1) pointer arithmetic - no malloc!
        ptr = pool + next_index
        next_index += size
        return ptr
```

**Trade-offs:**
- Memory not freed until HAMT destroyed (acceptable for persistent data structures)
- Fixed pool size (64K slots) - rare fallbacks to malloc if exceeded
- Best for HAMTs with <64K total children arrays (most use cases)

## Testing

Comprehensive test suite covering:
- Basic operations (insert, lookup, update, delete)
- Hash collision handling
- Edge cases (empty strings, negative numbers, large datasets)
- Dict-like interface (`__getitem__`, `__setitem__`, `__contains__`, etc.)
- String representations (`__str__`, `__repr__`)

Run all tests:
```bash
pixi run mojo test_hamt.mojo
```

## Benchmarking

### Benchmark Plan

This project includes a comprehensive benchmarking strategy to measure performance and memory characteristics of the HAMT implementation.

#### 1. Benchmark Datasets

We use a mix of **synthetic** and **real-world** datasets to ensure comprehensive coverage:

##### Synthetic Datasets (Controlled Testing)

These datasets are generated programmatically to test specific performance characteristics:

- **Sequential integers**: Keys `0, 1, 2, ..., N`
  - **What it tests**: Best-case insertion and lookup performance
  - **Why**: Tests HAMT behavior with predictable, non-colliding hash patterns
  - **HAMT usage**: Insert all keys, then benchmark lookups (both hits and misses)
  - **Sizes**: 100, 1K, 10K, 100K, 1M, 10M entries

- **Random integers**: Uniformly distributed random Int64 values
  - **What it tests**: Average-case performance with realistic hash distribution
  - **Why**: Simulates real-world integer keys (IDs, timestamps, etc.)
  - **HAMT usage**: Insert keys in random order, measure tree depth and bitmap utilization
  - **Sizes**: 100, 1K, 10K, 100K, 1M, 10M entries

- **Collision-prone keys**: Keys with custom hash function forcing collisions
  - **What it tests**: Worst-case performance when many keys hash to same path
  - **Why**: Tests leaf node collision handling and tree depth under stress
  - **HAMT usage**: Use custom hash returning `hash(key) % 1000` to force collisions
  - **Expected behavior**: Multiple key-value pairs in same leaf nodes
  - **Sizes**: 1K, 10K, 100K entries

##### Real-World Datasets

These datasets contain actual data from production systems and are used to validate real-world performance:

1. **Unix Dictionary Words**
   - **What it is**: Standard English dictionary with ~235K words (newline-delimited text)
   - **Download**: `/usr/share/dict/words`
   - **What it tests**: String key hashing, realistic word-based lookup patterns
   - **Why**: Common benchmark for dictionary/trie implementations, tests string handling
   - **HAMT usage**:
     - Insert all 235K words as keys (with integer values 0..235K)
     - Benchmark lookup times for existing words (hit ratio)
     - Test lookups for non-existent words (miss ratio)
     - Measure memory per entry for string keys
   - **Key questions**: How does HAMT handle variable-length strings? Memory overhead vs Dict?

2. **Mendeley Key-Value Store Benchmark Datasets**
   - **What it is**: Real Twitter data and synthetic datasets specifically designed for key-value store benchmarking
   - **Download**: [Mendeley Data Repository](https://data.mendeley.com/datasets/kxcb3tnr3t/2) (DOI: 10.17632/kxcb3tnr3t.2)
   - **Paper**: ["Real and synthetic data sets for benchmarking key-value stores"](https://www.sciencedirect.com/science/article/pii/S2352340920303358)

   **Real Twitter datasets**:
   - `ID-Geo`: 2.6M tweet IDs → geographic coordinates
     - **What it tests**: Int64 keys, compound values (simulated with strings in Mojo)
     - **HAMT usage**: `HAMT[Int, String]` with serialized coordinates
   - `ID-Hashtag`: 173K tweet IDs → hashtag strings
     - **What it tests**: Int64 keys, variable-length string values
     - **HAMT usage**: `HAMT[Int, String]` benchmark realistic social media data
   - `ID-Tweet`: 1.5M tweet IDs → tweet text (234MB)
     - **What it tests**: Large dataset with longer string values
     - **HAMT usage**: Memory efficiency test, scalability with larger values
   - `User-Followers`: 140K user IDs → follower counts
     - **What it tests**: Int64 → Int key-value pairs
     - **HAMT usage**: `HAMT[Int, Int]` pure integer benchmark

   **Synthetic scalability datasets**:
   - `KVData1`: 10K entries (560KB) - Int → String
   - `KVData2`: 100K entries (5.7MB) - Int → String
   - `KVData3`: 1M entries (58MB) - Int → String
   - `KVData4`: 10M entries (589MB) - Int → String
   - **What it tests**: How performance scales from small to very large datasets
   - **Why**: Systematic scalability testing with consistent key-value types
   - **HAMT usage**: Run identical benchmark suite across all 4 sizes
   - **Key questions**: Does performance degrade linearly? When does memory become an issue?

3. **EnWiki Titles Dataset**
   - **What it is**: 15.9M Wikipedia article titles (alphabetically sorted)
   - **Download**: [Wikipedia Database Dumps](https://dumps.wikimedia.org/enwiki/) - look for `enwiki-YYYYMMDD-all-titles-in-ns0.gz`
   - **Direct example**: [enwiki-20170320-all-titles](https://dumps.wikimedia.org/enwiki/20170320/enwiki-20170320-all-titles-in-ns0.gz) (check for latest date)
   - **What it tests**: Very large-scale string key performance
   - **Why**: Standard benchmark for trie implementations, tests memory efficiency with millions of strings
   - **HAMT usage**:
     - Insert all 15.9M titles as keys
     - Measure total memory footprint (bytes per entry)
     - Benchmark lookup performance on large dataset
     - Compare tree depth vs smaller datasets
     - Test prefix-based access patterns (simulated with partial title lookups)
   - **Key questions**: Can HAMT handle 10M+ entries efficiently? Memory vs Dict at scale?

#### 2. Operations to Benchmark

Each dataset will be tested with the following operations:

- **Insert** (`set`): Adding fresh keys
- **Update** (`set`): Overwriting existing keys
- **Lookup** (`get`):
  - Hit ratio: Keys that exist
  - Miss ratio: Keys that don't exist
- **Contains**: Membership testing
- **Mixed workloads**: Realistic read/write ratios

#### 4. Metrics to Track

**Performance Metrics:**
- Throughput: operations per second
- Latency: mean, p50, p95, p99 (nanoseconds per operation)
- Scalability: performance change from 1K → 10M entries

**Memory Metrics:**
- Memory per entry (bytes/entry)
- Total memory footprint
- Memory overhead vs. Mojo's built-in `Dict`

**Structure Metrics:**
- Average tree depth
- Bitmap utilization
- Collision rate (keys per leaf node)

#### 5. Baseline Comparisons

Benchmark against:
- **libhamt `https://github.com/mkirchner/hamt`**: Primary Hash Array Mapped Trie implementation in C
- **Python's `[ContextVars](https://docs.python.org/3/library/contextvars.html)`**: Secondary comparison (standard library)
- **Mojo's `Dict[K, V]`**: Another comparison (standard library)

##### Local Development
```bash
# Run basic benchmarks
pixi run mojo benchmark_hamt.mojo

# Run specific benchmark suite
pixi run mojo benchmark_hamt.mojo --dataset=words
pixi run mojo benchmark_hamt.mojo --dataset=synthetic --size=1000000
```

## References

- [Hash Array Mapped Trie - Wikipedia](https://en.wikipedia.org/wiki/Hash_array_mapped_trie)
- [Ideal Hash Trees (Phil Bagwell, 2001)](https://infoscience.epfl.ch/record/64398)
- [CHAMP: Fast Compressed Hash-Array Mapped Prefix-trees](https://michael.steindorfer.name/publications/oopsla15.pdf)

## License

[MIT License](LICENSE)

## Author

Eginez ([@eginez](https://github.com/eginez))
