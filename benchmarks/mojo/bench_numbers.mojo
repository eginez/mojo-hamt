"""
Simplified HAMT Benchmark - Single Measurement Mode.

This benchmark runs a single operation at a single scale and outputs
operations per second to stdout. Designed for integration with asv
(Airspeed Velocity) or other benchmark harnesses.

Usage:
    mojo bench_numbers.mojo <measurement> <scale>

Examples:
    mojo bench_numbers.mojo insert 1000
    mojo bench_numbers.mojo query 10000

Arguments:
    measurement: Operation type (insert | query)
    scale: Number of entries (positive integer)

Output:
    Single number (operations per second) to stdout
"""

from std.time import perf_counter_ns
from std.sys import argv
from std.testing import assert_equal

from hamt import HAMT


def bench_insert(scale: Int) raises -> Int:
    """Insert N sequential keys, return total time in nanoseconds.

    Creates an empty HAMT and inserts sequential integer keys from 0 to scale-1.

    Args:
        scale: Number of items to insert.

    Returns:
        Total time in nanoseconds.
    """
    var hamt = HAMT[Int, Int]()

    var start = perf_counter_ns()
    for i in range(scale):
        hamt[i] = i * 10
    var end = perf_counter_ns()

    # Verify correctness
    #assert_equal(len(hamt), scale, "HAMT size mismatch after insert")

    return Int(end - start)


def bench_query(scale: Int) raises -> Int:
    """Query N existing keys, return total time in nanoseconds.

    Pre-populates a HAMT with sequential keys, then looks up all of them.

    Args:
        scale: Number of items to query.

    Returns:
        Total time in nanoseconds.
    """
    var hamt = HAMT[Int, Int]()

    # Pre-populate
    for i in range(scale):
        hamt[i] = i * 10

    # Benchmark lookups
    var start = perf_counter_ns()
    for i in range(scale):
        var value = hamt[i]
        #assert_equal(value, i * 10, "Value mismatch during query")
    var end = perf_counter_ns()

    return Int(end - start)


def main() raises:
    """Main entry point - parse arguments and run benchmark."""

    # Parse arguments
    if len(argv()) != 3:
        raise Error("Usage: bench_numbers.mojo <measurement> <scale>")

    var measurement = argv()[1]
    var scale = atol(argv()[2])

    # Validate measurement type
    if measurement != "insert" and measurement != "query":
        raise Error("Invalid measurement type: " + measurement + " (must be 'insert' or 'query')")

    # Validate scale
    if scale <= 0:
        raise Error("Invalid scale: " + String(scale) + " (must be positive)")

    # Run benchmark
    var total_time_ns: Int
    if measurement == "insert":
        total_time_ns = bench_insert(scale)
    else:  # measurement == "query"
        total_time_ns = bench_query(scale)

    # Calculate operations per second
    var ns_per_op = Float64(total_time_ns) / Float64(scale)
    var ops_per_sec = 1_000_000_000 / ns_per_op

    # Output single value to stdout
    print(ops_per_sec)
