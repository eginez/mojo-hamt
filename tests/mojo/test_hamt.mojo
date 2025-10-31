from testing import assert_equal, assert_true, assert_false
from hamt import HAMTLeafNode, HAMTNode, HAMT
from bit.bit import pop_count


def test_hamt_leaf_node():
    var leaf = HAMTLeafNode[String, Int]("test_key", 42)
    # Test using the new get() method instead of direct attribute access
    var result = leaf.get("test_key")
    assert_true(result, "Expected to find test_key")
    assert_equal(result.value(), 42)

    # Test that non-existent key returns None
    var missing = leaf.get("missing")
    assert_false(missing, "Expected missing key to not be found")
    print("✓ HAMTLeafNode tests passed")


def test_hamt_node_initialization():
    var node = HAMTNode[String, Int]()
    assert_equal(node.children_bitmap, 0)
    # InlineArray always has length 64, check that bitmap shows 0 children
    assert_equal(pop_count(node.children_bitmap), 0)
    print("✓ HAMTNode initialization tests passed")


def test_hamt_hash_calculation():
    var hamt = HAMT[Int, String]()

    # Test that hash calculation returns 60-bit values
    var hash1 = hamt._calculate_hash(42)
    var hash2 = hamt._calculate_hash(100)

    # Verify the top 4 bits are cleared (60-bit hash)
    assert_equal(hash1 >> 60, 0)
    assert_equal(hash2 >> 60, 0)

    # Different keys should produce different hashes (most of the time)
    # This is probabilistic but very likely to pass
    assert_equal(hash1 == hash2, False)
    print("✓ HAMT hash calculation tests passed")


def test_hamt_chunk_extraction():
    var hamt = HAMT[Int, String]()

    # Test chunk extraction at different levels
    # For a 60-bit hash split into 6-bit chunks, we have 10 levels (0-9)
    var test_hash: UInt64 = (
        0b111111000000111111000000111111000000111111000000111111010000
    )

    # Level 0: bits 0-5
    var chunk0 = hamt._get_next_chunk(test_hash, 0)
    assert_equal(chunk0, 0b010000)  # Bottom 6 bits

    # Level 1: bits 6-11
    var chunk1 = hamt._get_next_chunk(test_hash, 1)
    assert_equal(chunk1, 0b111111)

    # Level 2: bits 12-17
    var chunk2 = hamt._get_next_chunk(test_hash, 2)
    assert_equal(chunk2, 0b000000)

    # Level 9: bits 54-60
    var chunk3 = hamt._get_next_chunk(test_hash, 9)
    assert_equal(chunk3, 0b111111)

    print("✓ HAMT chunk extraction tests passed")


def test_hamt_node_get_child():
    var node = HAMTNode[String, Int]()

    # Test get_child on empty node returns null pointer
    var result = node.get_child(0)
    assert_false(result)

    var result2 = node.get_child(5)
    assert_false(result2)

    # Test bitmap operations manually
    var test_bitmap: UInt64 = 0
    test_bitmap |= UInt64(1) << 5  # Set bit 5
    assert_equal((test_bitmap >> 5) & 1, 1)


def test_hamt_value_creation():
    var node = HAMTNode[String, Int]()
    _ = node.add_value("hello", 1)
    assert_equal(node.get_value("hello").value(), 1)


def test_hamt_creation():
    var node = HAMT[Int, Int]()
    node.set(1, 1)
    var val = node.get(1).value()
    assert_true(val, "expected the key")
    assert_equal(val, 1)
    print("✓ HAMT creation tests passed")


def test_hamt_multiple_values():
    var hamt = HAMT[Int, String]()

    # Insert multiple key-value pairs
    hamt.set(1, "one")
    hamt.set(2, "two")
    hamt.set(10, "ten")
    hamt.set(100, "hundred")

    # Verify all values can be retrieved
    assert_equal(hamt.get(1).value(), "one")
    assert_equal(hamt.get(2).value(), "two")
    assert_equal(hamt.get(10).value(), "ten")
    assert_equal(hamt.get(100).value(), "hundred")
    print("✓ HAMT multiple values tests passed")


def test_hamt_overwrite_values():
    var hamt = HAMT[Int, Int]()

    # Set initial value
    hamt.set(42, 100)
    assert_equal(hamt.get(42).value(), 100)

    # Overwrite with new value
    hamt.set(42, 200)
    assert_equal(hamt.get(42).value(), 200)
    print("✓ HAMT overwrite tests passed")


def test_hamt_nonexistent_keys():
    var hamt = HAMT[Int, String]()

    # Add some values
    hamt.set(1, "exists")
    hamt.set(5, "also exists")

    # Try to get non-existent keys
    var result1 = hamt.get(99)
    assert_false(result1, "Key 99 should not exist")

    var result2 = hamt.get(-1)
    assert_false(result2, "Key -1 should not exist")
    print("✓ HAMT nonexistent keys tests passed")


def test_hamt_string_keys():
    var hamt = HAMT[String, Int]()

    hamt.set("apple", 1)
    hamt.set("banana", 2)
    hamt.set("cherry", 3)
    hamt.set("date", 4)

    assert_equal(hamt.get("apple").value(), 1)
    assert_equal(hamt.get("banana").value(), 2)
    assert_equal(hamt.get("cherry").value(), 3)
    assert_equal(hamt.get("date").value(), 4)

    # Test non-existent string key
    assert_false(hamt.get("elderberry"))
    print("✓ HAMT string keys tests passed")


def test_hamt_large_numbers():
    var hamt = HAMT[Int, Int]()

    # Test with large numbers that might cause hash collisions
    var large_keys = List[Int]()
    large_keys.append(1000000)
    large_keys.append(2000000)
    large_keys.append(3000000)
    large_keys.append(9999999)

    for i in range(len(large_keys)):
        var key = large_keys[i]
        hamt.set(key, key * 2)

    for i in range(len(large_keys)):
        var key = large_keys[i]
        assert_equal(hamt.get(key).value(), key * 2)

    print("✓ HAMT large numbers tests passed")


def test_hamt_sequential_keys():
    var hamt = HAMT[Int, Int]()

    # Insert sequential keys (might have similar hash patterns)
    for i in range(20):
        hamt.set(i, i * 10)

    # Verify all sequential keys
    for i in range(20):
        assert_equal(hamt.get(i).value(), i * 10)

    print("✓ HAMT sequential keys tests passed")


def test_hamt_zero_and_negative():
    var hamt = HAMT[Int, String]()

    # Test zero key
    hamt.set(0, "zero")
    assert_equal(hamt.get(0).value(), "zero")

    # Test negative keys
    hamt.set(-1, "negative one")
    hamt.set(-100, "negative hundred")
    hamt.set(-999999, "large negative")

    assert_equal(hamt.get(-1).value(), "negative one")
    assert_equal(hamt.get(-100).value(), "negative hundred")
    assert_equal(hamt.get(-999999).value(), "large negative")
    print("✓ HAMT zero and negative tests passed")


def test_hamt_sparse_keys():
    var hamt = HAMT[Int, Int]()

    # Test very sparse key distribution
    var sparse_keys = List[Int]()
    sparse_keys.append(1)
    sparse_keys.append(1000)
    sparse_keys.append(1000000)
    sparse_keys.append(1000000000)

    for i in range(len(sparse_keys)):
        var key = sparse_keys[i]
        hamt.set(key, key + 1)

    for i in range(len(sparse_keys)):
        var key = sparse_keys[i]
        assert_equal(hamt.get(key).value(), key + 1)

    print("✓ HAMT sparse keys tests passed")


def test_hamt_mixed_operations():
    var hamt = HAMT[String, String]()

    # Mix of sets and gets
    hamt.set("first", "1st")
    assert_equal(hamt.get("first").value(), "1st")

    hamt.set("second", "2nd")
    hamt.set("third", "3rd")

    # Verify first key still works after adding more
    assert_equal(hamt.get("first").value(), "1st")
    assert_equal(hamt.get("second").value(), "2nd")
    assert_equal(hamt.get("third").value(), "3rd")

    # Update existing key
    hamt.set("second", "SECOND")
    assert_equal(hamt.get("second").value(), "SECOND")

    # Other keys should be unchanged
    assert_equal(hamt.get("first").value(), "1st")
    assert_equal(hamt.get("third").value(), "3rd")
    print("✓ HAMT mixed operations tests passed")


def test_hamt_empty_string_keys():
    var hamt = HAMT[String, Int]()

    # Test empty string as key
    hamt.set("", 42)
    assert_equal(hamt.get("").value(), 42)

    # Test single character keys
    hamt.set("a", 1)
    hamt.set("z", 26)

    assert_equal(hamt.get("").value(), 42)
    assert_equal(hamt.get("a").value(), 1)
    assert_equal(hamt.get("z").value(), 26)
    print("✓ HAMT empty string keys tests passed")


def test_hamt_similar_keys():
    var hamt = HAMT[String, Int]()

    # Test keys that might have similar hash patterns
    hamt.set("test1", 1)
    hamt.set("test2", 2)
    hamt.set("test3", 3)
    hamt.set("1test", 4)
    hamt.set("2test", 5)

    assert_equal(hamt.get("test1").value(), 1)
    assert_equal(hamt.get("test2").value(), 2)
    assert_equal(hamt.get("test3").value(), 3)
    assert_equal(hamt.get("1test").value(), 4)
    assert_equal(hamt.get("2test").value(), 5)
    print("✓ HAMT similar keys tests passed")


def test_hamt_boundary_chunk_indices():
    var hamt = HAMT[Int, String]()

    # Test keys that produce boundary chunk indices (0, 63)
    # This tests edge cases in bit manipulation
    var test_pairs = List[Tuple[Int, String]]()

    # Add various keys to test different chunk patterns
    for i in range(100):
        var key = i * 1000 + i  # Create varied hash patterns
        var value = "val_" + i.__str__()
        hamt.set(key, value)
        test_pairs.append((key, value))

    # Verify all insertions
    for i in range(len(test_pairs)):
        var pair = test_pairs[i]
        assert_equal(hamt.get(pair[0]).value(), pair[1])

    print("✓ HAMT boundary chunk indices tests passed")


def test_hamt_deep_tree():
    var hamt = HAMT[Int, Int]()

    # Create keys that force maximum tree depth
    # Since we have 10 levels max, try to create a scenario
    # that uses multiple levels
    var base_key = 1
    for level in range(5):  # Test multiple levels
        for offset in range(10):
            var key = base_key + (offset << (level * 6))
            hamt.set(key, key * 2)

    # Verify all keys still retrievable
    for level in range(5):
        for offset in range(10):
            var key = base_key + (offset << (level * 6))
            assert_equal(hamt.get(key).value(), key * 2)

    print("✓ HAMT deep tree tests passed")


def test_update_values():
    var hamt = HAMT[Int, String]()

    # Since hash is 60-bit and we use 6-bit chunks, we have 10 levels
    # If two keys have the same hash, they'll follow the same path
    # and end up at the same leaf node

    # Let's create a scenario where keys will definitely collide
    # by using the internal structure knowledge

    # Insert first key
    hamt.set(123, "first_value")

    # Now let's try to insert a key that will traverse the same path
    # For now, let's just test what happens when we update the same key
    hamt.set(123, "updated_value")

    # This should update, not collide
    var result = hamt.get(123)
    assert_equal(result.value(), "updated_value")

    print("✓ Basic key update works")

    # The real test is: what happens when two DIFFERENT keys
    # hash to the same value? Current implementation will fail.
    print("✓ Hash collision behavior test completed (limited)")


def test_hamt_forced_hash_collision():
    """Test HAMT with custom hash function that forces collisions."""

    # Define a collision hash function that always returns the same value
    fn collision_hash(key: Int) -> UInt64:
        return UInt64(42)  # All keys hash to the same value!

    # Create HAMT with collision-inducing hash function
    var hamt = HAMT[Int, String](collision_hash)

    # Test data: keys and expected values
    var test_keys = List[Int]()
    var expected_values = List[String]()
    test_keys.append(1)
    test_keys.append(2)
    test_keys.append(100)
    expected_values.append("one")
    expected_values.append("two")
    expected_values.append("hundred")

    # Insert all keys - they will all have the same hash
    for i in range(len(test_keys)):
        hamt.set(test_keys[i], expected_values[i])

    # Verify all keys can be retrieved correctly
    for i in range(len(test_keys)):
        var result = hamt.get(test_keys[i])
        if result:
            assert_equal(result.value(), expected_values[i])
        else:
            assert_true(False, "Value expected")


fn test_collision() raises:
    # Create HAMT with custom hash that always returns 0 (force collisions)
    fn collision_hash(x: Int) -> UInt64:
        return 0

    var hamt = HAMT[Int, Int](collision_hash)
    hamt.set(1, 100)
    hamt.set(2, 200)  # This should collide with key 1

    assert_equal(hamt.get(1).or_else(-1), 100)
    assert_equal(hamt.get(2).or_else(-1), 200)


def test_dunder_getitem():
    """Test __getitem__ dunder method (bracket notation for reading)."""
    var hamt = HAMT[Int, String]()
    hamt.set(1, "one")
    hamt.set(2, "two")
    hamt.set(3, "three")

    # Test successful retrieval using bracket notation
    assert_equal(hamt[1], "one")
    assert_equal(hamt[2], "two")
    assert_equal(hamt[3], "three")


def test_dunder_getitem_raises():
    """Test that __getitem__ raises error for missing keys."""
    var hamt = HAMT[Int, String]()
    hamt.set(1, "one")

    var raised = False
    try:
        _ = hamt[999]  # This key doesn't exist
    except:
        raised = True

    assert_true(raised, "Expected KeyError for missing key")


def test_dunder_setitem():
    """Test __setitem__ dunder method (bracket notation for writing)."""
    var hamt = HAMT[String, Int]()

    # Test setting values using bracket notation
    hamt["apple"] = 1
    hamt["banana"] = 2
    hamt["cherry"] = 3

    # Verify values were set correctly
    assert_equal(hamt["apple"], 1)
    assert_equal(hamt["banana"], 2)
    assert_equal(hamt["cherry"], 3)

    # Test overwriting existing key
    hamt["apple"] = 100
    assert_equal(hamt["apple"], 100)


def test_dunder_contains():
    """Test __contains__ dunder method (in operator)."""
    var hamt = HAMT[Int, String]()
    hamt.set(1, "one")
    hamt.set(5, "five")
    hamt.set(10, "ten")

    # Test keys that exist
    assert_true(1 in hamt, "Key 1 should be in HAMT")
    assert_true(5 in hamt, "Key 5 should be in HAMT")
    assert_true(10 in hamt, "Key 10 should be in HAMT")

    # Test keys that don't exist
    assert_false(2 in hamt, "Key 2 should not be in HAMT")
    assert_false(999 in hamt, "Key 999 should not be in HAMT")
    assert_false(-1 in hamt, "Key -1 should not be in HAMT")


def test_dunder_len():
    """Test __len__ dunder method."""
    var hamt = HAMT[Int, Int]()

    # Empty HAMT should have length 0
    assert_equal(len(hamt), 0)

    # Add items and check length increases
    hamt.set(1, 100)
    assert_equal(len(hamt), 1)

    hamt.set(2, 200)
    assert_equal(len(hamt), 2)

    hamt.set(3, 300)
    assert_equal(len(hamt), 3)

    # Overwriting a key shouldn't change length
    hamt.set(2, 999)
    assert_equal(len(hamt), 3)


def test_dunder_str_empty():
    """Test __str__ dunder method with empty HAMT."""
    var hamt = HAMT[Int, Int]()
    var str_repr = hamt.__str__()
    assert_equal(str_repr, "{}")


def test_dunder_str_single_item():
    """Test __str__ dunder method with single item."""
    var hamt = HAMT[Int, String]()
    hamt.set(42, "answer")

    var str_repr = hamt.__str__()
    # Should contain the key-value pair
    assert_true("42" in str_repr, "String should contain key")
    assert_true("answer" in str_repr, "String should contain value")
    assert_true("{" in str_repr, "String should start with {")
    assert_true("}" in str_repr, "String should end with }")


def test_dunder_str_multiple_items():
    """Test __str__ dunder method with multiple items."""
    var hamt = HAMT[Int, Int]()
    hamt.set(1, 100)
    hamt.set(2, 200)
    hamt.set(3, 300)

    var str_repr = hamt.__str__()

    # Should be dict-like format
    assert_true("{" in str_repr, "String should start with {")
    assert_true("}" in str_repr, "String should end with }")

    # Should contain all keys and values
    assert_true("1" in str_repr, "String should contain key 1")
    assert_true("2" in str_repr, "String should contain key 2")
    assert_true("3" in str_repr, "String should contain key 3")
    assert_true("100" in str_repr, "String should contain value 100")
    assert_true("200" in str_repr, "String should contain value 200")
    assert_true("300" in str_repr, "String should contain value 300")


def test_dunder_str_strings():
    """Test __str__ with string keys and values."""
    var hamt = HAMT[String, String]()
    hamt.set("key1", "value1")
    hamt.set("key2", "value2")

    var str_repr = hamt.__str__()

    assert_true("key1" in str_repr, "String should contain key1")
    assert_true("key2" in str_repr, "String should contain key2")
    assert_true("value1" in str_repr, "String should contain value1")
    assert_true("value2" in str_repr, "String should contain value2")


def test_dunder_repr_empty():
    """Test __repr__ dunder method with empty HAMT."""
    var hamt = HAMT[Int, Int]()
    var repr_str = hamt.__repr__()

    assert_true("HAMT" in repr_str, "Repr should contain HAMT")
    assert_true("{}" in repr_str, "Repr should contain {}")


def test_dunder_repr_with_items():
    """Test __repr__ dunder method with items."""
    var hamt = HAMT[Int, String]()
    hamt.set(1, "one")
    hamt.set(2, "two")

    var repr_str = hamt.__repr__()

    # Should have HAMT prefix
    assert_true("HAMT" in repr_str, "Repr should contain HAMT")

    # Should contain the dict representation
    assert_true("1" in repr_str, "Repr should contain key 1")
    assert_true("2" in repr_str, "Repr should contain key 2")
    assert_true("one" in repr_str, "Repr should contain value 'one'")
    assert_true("two" in repr_str, "Repr should contain value 'two'")


def test_combined_dunder_methods():
    """Test using multiple dunder methods together."""
    var hamt = HAMT[Int, Int]()

    # Use __setitem__ to add values
    hamt[1] = 10
    hamt[2] = 20
    hamt[3] = 30

    # Use __len__
    assert_equal(len(hamt), 3)

    # Use __contains__
    assert_true(1 in hamt)
    assert_true(2 in hamt)
    assert_false(999 in hamt)

    # Use __getitem__
    assert_equal(hamt[1], 10)
    assert_equal(hamt[2], 20)
    assert_equal(hamt[3], 30)

    # Update using __setitem__
    hamt[1] = 100
    assert_equal(hamt[1], 100)
    assert_equal(len(hamt), 3)  # Length shouldn't change

    # Check __str__ contains updated value
    var str_repr = hamt.__str__()
    assert_true("100" in str_repr, "String should contain updated value")
