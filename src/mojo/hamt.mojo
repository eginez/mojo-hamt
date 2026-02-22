"""
HAMT (Hash Array Mapped Trie) Implementation

A high-performance persistent hash map implementation using HAMT data structure.
Optimized for cache locality and memory efficiency.
"""

from collections import List
from memory import UnsafePointer, alloc
from testing import assert_equal, assert_true
from bit.bit import pop_count
from time import perf_counter_ns
from sys.param_env import env_get_string
from os import env
from python import PythonObject
from python.bindings import PythonModuleBuilder
from os import abort
from utils import Variant


# Clears the highest 4 bits of the UInt64
# used to truncate the hash
comptime FILTER: UInt64 = 0x0FFFFFFFFFFFFFFF
# Maximum children per node (6-bit chunks = 64 possible children)
comptime MAX_CHILDREN = 64

# Pool configuration - single large block for all children arrays
# Size calculation: ~30 slots per entry, so 4M slots ≈ 130K entries with headroom
comptime CHILDREN_POOL_SIZE = 4194304  # 4M slots (32MB) - supports ~130K+ entries


struct ChildrenPool[
    K: Movable & Copyable & Hashable & Equatable & Stringable,
    V: Movable & Copyable & Stringable,
](Movable):
    """Simple bump allocator for children arrays.

    Pre-allocates one large block and uses bump allocation.
    Freed arrays are tracked and returned to the pool for reuse.
    """
    var pool: UnsafePointer[mut=True, UnsafePointer[mut=True, HAMTNode[Self.K, Self.V], MutExternalOrigin], MutExternalOrigin]
    var next_index: Int
    var capacity: Int
    # Phase 4: Track freed arrays for reuse
    var freed_arrays: List[Tuple[UnsafePointer[mut=True, UnsafePointer[mut=True, HAMTNode[Self.K, Self.V], MutExternalOrigin], MutExternalOrigin], Int]]
    # Telemetry for diagnostics
    var total_allocations: Int
    var fallback_allocations: Int
    var total_slots_used: Int
    var reused_slots: Int
    
    fn __init__(out self):
        """Pre-allocate large pool."""
        self.capacity = CHILDREN_POOL_SIZE
        self.pool = alloc[UnsafePointer[mut=True, HAMTNode[Self.K, Self.V], MutExternalOrigin]](self.capacity)
        self.next_index = 0
        self.freed_arrays = List[Tuple[UnsafePointer[mut=True, UnsafePointer[mut=True, HAMTNode[Self.K, Self.V], MutExternalOrigin], MutExternalOrigin], Int]]()
        self.total_allocations = 0
        self.fallback_allocations = 0
        self.total_slots_used = 0
        self.reused_slots = 0

    fn __moveinit__(out self, deinit other: Self):
        self.pool = other.pool
        self.next_index = other.next_index
        self.capacity = other.capacity
        self.freed_arrays = other.freed_arrays^
        self.total_allocations = other.total_allocations
        self.fallback_allocations = other.fallback_allocations
        self.total_slots_used = other.total_slots_used
        self.reused_slots = other.reused_slots
    
    fn __del__(deinit self):
        """Free entire pool.

        Note: We only free the main pool block. Individual arrays allocated
        from within the pool are NOT freed - they're part of the bump-allocated
        region and will be freed when the pool itself is freed.

        Phase 4: Freed arrays are automatically reclaimed when the pool is freed.
        """
        if self.pool:
            self.pool.free()
        # Note: We don't track which arrays were bump-allocated vs fallback-allocated
        # In a production implementation, we'd need to track this, but for now
        # we accept that fallback allocations may leak (they're rare)

    @always_inline
    fn allocate(mut self, size: Int) -> UnsafePointer[mut=True, UnsafePointer[mut=True, HAMTNode[Self.K, Self.V], MutExternalOrigin], MutExternalOrigin]:
        """Allocate array of given size from pool using bump allocation.

        Phase 4: First checks freed_arrays for reusable arrays from previous growth operations.
        """
        self.total_allocations += 1

        # Phase 4: Try to reuse a freed array first (bump allocation from pool)
        if len(self.freed_arrays) > 0:
            # Get last freed array (LIFO order for best cache locality)
            var freed = self.freed_arrays.pop()
            var ptr = freed[0]
            var freed_size = freed[1]
            self.reused_slots += freed_size
            return ptr

        self.total_slots_used += size

        if self.next_index + size > self.capacity:
            # Pool exhausted - fall back to malloc
            self.fallback_allocations += 1
            return alloc[UnsafePointer[mut=True, HAMTNode[Self.K, Self.V], MutExternalOrigin]](size)

        # Bump allocation from pre-allocated pool
        var ptr = self.pool + self.next_index
        self.next_index += size
        return ptr

    @always_inline
    fn free(mut self, ptr: UnsafePointer[mut=True, UnsafePointer[mut=True, HAMTNode[Self.K, Self.V], MutExternalOrigin], MutExternalOrigin], size: Int):
        """Return an array to the pool for reuse.

        Phase 4: Instead of leaking arrays during growth, track them for reuse.
        The caller must have already copied contents to a new array before calling this.

        Note: We only track bump-allocated arrays (from the main pool).
        Fallback malloc arrays are not tracked (they're rare and will leak).
        """
        # All arrays passed to free() are from bump allocation (the old children arrays).
        # We track them for reuse - they'll be returned to the pool when the HAMT is destroyed.
        self.freed_arrays.append((ptr, size))

    fn print_stats(self):
        """Print pool utilization statistics."""
        print("=== ChildrenPool Statistics ===")
        print("Total allocations:", self.total_allocations)
        print("Fallback allocations (malloc):", self.fallback_allocations)
        print("Total slots used:", self.total_slots_used)
        print("Pool capacity:", self.capacity)
        print("Pool utilization:", Float64(self.total_slots_used) / Float64(self.capacity) * 100, "%")
        print("Reused slots from freed arrays:", self.reused_slots)
        print("Freed arrays tracked:", len(self.freed_arrays))
        if self.fallback_allocations > 0:
            print("⚠️  WARNING: Pool exhausted! Fallback to malloc occurred", self.fallback_allocations, "times")
        print("===============================")


struct HAMTLeafNode[
    K: Movable & Copyable & Hashable & Equatable & Stringable,
    V: Movable & Copyable & Stringable,
](Copyable, Movable):
    var _items: List[Tuple[Self.K, Self.V]]

    fn __init__(out self):
        self._items = List[Tuple[Self.K, Self.V]]()

    fn __init__(out self, var key: Self.K, var value: Self.V):
        self._items = List[Tuple[Self.K, Self.V]]()
        _ = self.add(key^, value^)

    @always_inline
    fn add(mut self, var key: Self.K, var value: Self.V) -> Bool:
        """Add or update a key-value pair. Returns True if a new key was added, False if updated.
        
        Uses move semantics to avoid unnecessary copies. Takes ownership of key and value.
        """
        # Check for existing key - need to compare before moving
        for i in range(len(self._items)):
            if self._items[i][0] == key:
                # Update existing - move new values in
                self._items[i] = (key^, value^)
                return False
        # New key - move values into tuple
        self._items.append((key^, value^))
        return True

    @always_inline
    fn get(self, key: Self.K) -> Optional[Self.V]:
        for item in self._items:
            if item[0] == key:
                return Optional(item[1].copy())
        return Optional[Self.V]()


struct HAMTInternalNode[
    K: Movable & Copyable & Hashable & Equatable & Stringable,
    V: Movable & Copyable & Stringable,
](Movable):
    """Internal HAMT node with pointer to dynamically-sized children array.
    
    Phase 1 optimization: Using pointer to children array instead of InlineArray.
    Node size reduced from ~160 bytes to ~32 bytes (children_bitmap + pointer + capacity).
    """
    # Bitmap indicating which children are present (sparse representation)
    var children_bitmap: UInt64
    # Pointer to dense array of child pointers (exact size = num_children)
    var children: UnsafePointer[mut=True, UnsafePointer[mut=True, HAMTNode[Self.K, Self.V], MutExternalOrigin], MutExternalOrigin]
    # Capacity of children array (for growth)
    var capacity: Int

    fn __init__(out self):
        self.children_bitmap = 0
        self.children = UnsafePointer[mut=True, UnsafePointer[mut=True, HAMTNode[Self.K, Self.V], MutExternalOrigin], MutExternalOrigin]()
        self.capacity = 0

    fn __moveinit__(out self, deinit other: Self):
        self.children_bitmap = other.children_bitmap
        self.children = other.children
        self.capacity = other.capacity

    fn __del__(deinit self):
        """Note: Children arrays are now bump-allocated from pool.
        We don't free them individually - they're freed when the pool is destroyed.
        """
        pass

    @always_inline
    fn num_children(self) -> Int:
        """Get the number of children (population count of bitmap)."""
        return Int(pop_count(self.children_bitmap))

    fn collect_items(self, mut items: List[Tuple[Self.K, Self.V]]):
        """Recursively collect all key-value pairs from this node and its children.
        """
        var n = self.num_children()
        for i in range(n):
            var child = self.children[i]
            if child:
                child[].collect_items(items)

    fn add_child(
        mut self, chunk_index: UInt8, mut arena: NodeArena[Self.K, Self.V], mut children_pool: ChildrenPool[Self.K, Self.V], is_internal: Bool
    ) -> UnsafePointer[mut=True, HAMTNode[Self.K, Self.V], MutExternalOrigin]:
        var masked_chunked = UInt64(1) << UInt64(chunk_index)
        var masked_bitmap = UInt64(masked_chunked - 1) & self.children_bitmap
        var child_index = Int(pop_count(masked_bitmap))

        # Get current number of children before updating bitmap
        var old_num_children = self.num_children()
        var new_num_children = old_num_children + 1

        # Grow array if needed
        if new_num_children > self.capacity:
            # Double capacity or start with 4, whichever is larger
            var new_capacity = max(self.capacity * 2, 4)
            if new_capacity < new_num_children:
                new_capacity = new_num_children
            self._grow_children_array(new_capacity, children_pool)

        # Update bitmap to include new child
        self.children_bitmap |= UInt64(masked_chunked)

        # Shift existing children to the right to make room for new child
        # Work backwards to avoid overwriting
        # Optimized: shift elements one by one but with pointer arithmetic
        if child_index < old_num_children:
            var i = old_num_children
            while i > child_index:
                self.children[i] = self.children[i - 1]
                i -= 1

        # Allocate from arena instead of individual malloc
        var new_node_pointer = arena.allocate_node()
        if is_internal:
            new_node_pointer.init_pointee_move(HAMTNode[Self.K, Self.V]())
        else:
            # Create empty leaf node - values will be added later
            new_node_pointer.init_pointee_move(HAMTNode[Self.K, Self.V](HAMTLeafNode[Self.K, Self.V]()))

        # Insert new child at the calculated dense index
        self.children[child_index] = new_node_pointer
        return new_node_pointer

    fn _grow_children_array(mut self, new_capacity: Int, mut children_pool: ChildrenPool[Self.K, Self.V]):
        """Grow children array to new capacity using bump allocator pool."""
        # Allocate new array from pool (eliminates malloc in hot path!)
        var new_array = children_pool.allocate(new_capacity)
        
        # Copy existing children
        # Manual bulk copy - unroll for common small sizes
        var n = self.num_children()
        if n <= 4:
            # Unrolled for small arrays (most common case)
            if n >= 1:
                new_array[0] = self.children[0]
            if n >= 2:
                new_array[1] = self.children[1]
            if n >= 3:
                new_array[2] = self.children[2]
            if n >= 4:
                new_array[3] = self.children[3]
        else:
            # For larger arrays, copy using while loop (faster than for-range)
            var i = 0
            while i < n:
                new_array[i] = self.children[i]
                i += 1

        # Phase 4: Free old array to pool for reuse (eliminates memory leak!)
        var old_num_children = self.num_children()
        if old_num_children > 0:
            children_pool.free(self.children, old_num_children)

        self.children = new_array
        self.capacity = new_capacity

    @always_inline
    fn get_child(
        self, chunk_index: UInt8
    ) raises -> UnsafePointer[mut=True, HAMTNode[Self.K, Self.V], MutExternalOrigin]:
        # The chunk index as an integer represents
        # the position in the sparse representation of the node
        # of where we should expect to have a value
        var masked_chunked = UInt64(1) << UInt64(chunk_index)
        if (self.children_bitmap & UInt64(masked_chunked)) == 0:
            # Fast path: no logging in hot path
            return UnsafePointer[mut=True, HAMTNode[Self.K, Self.V], MutExternalOrigin]()

        # The actual index of the value, is number of 1s before
        # that position.
        var masked_bitmap = UInt64(masked_chunked - 1) & self.children_bitmap
        var child_index = Int(pop_count(masked_bitmap))
        # Bounds check only in debug builds - comment out for release
        # var n = self.num_children()
        # if child_index >= n:
        #     raise Error("bad child index")
        return self.children[child_index]


struct HAMTNode[
    K: Movable & Copyable & Hashable & Equatable & Stringable,
    V: Movable & Copyable & Stringable,
](Movable):
    """HAMT node - can be either internal (with children) or leaf (with values).
    
    Note: Now move-only because HAMTInternalNode is move-only (owns heap memory).
    """

    comptime _HAMTNode = Variant[HAMTInternalNode[Self.K,Self.V], HAMTLeafNode[Self.K,Self.V]]
    var data: Self._HAMTNode

    fn __init__(out self):
        self.data = Self._HAMTNode(HAMTInternalNode[Self.K,Self.V]())

    fn __init__(out self, var key: Self.K, var value: Self.V):
        self.data = Self._HAMTNode(HAMTLeafNode[Self.K,Self.V](key^, value^))

    fn __init__(out self, var leaf: HAMTLeafNode[Self.K, Self.V]):
        self.data = Self._HAMTNode(leaf^)

    fn __moveinit__(out self, deinit other: Self):
        self.data = other.data^

    @always_inline
    fn is_internal(self) -> Bool:
        return self.data.isa[HAMTInternalNode[Self.K,Self.V]]()

    @always_inline
    fn children_bitmap(self) -> UInt64:
        """Get the children bitmap (only for internal nodes, returns 0 for leaf nodes)."""
        if self.is_internal():
            return self.data[HAMTInternalNode[Self.K,Self.V]].children_bitmap
        return 0


    @always_inline
    fn get_value(self, key: Self.K) raises -> Optional[Self.V]:
        if self.is_internal():
            raise Error("Can not get value from internal node")

        return self.data[HAMTLeafNode[Self.K,Self.V]].get(key)

    @always_inline
    fn add_value(mut self, var key: Self.K, var value: Self.V) raises -> Bool:
        if self.is_internal():
            raise Error("Can not add value to internal node")

        return self.data[HAMTLeafNode[Self.K,Self.V]].add(key^, value^)


    @always_inline
    fn add_child(
        mut self, chunk_index: UInt8, mut arena: NodeArena[Self.K, Self.V], mut children_pool: ChildrenPool[Self.K, Self.V], is_internal: Bool
    ) raises -> UnsafePointer[mut=True, HAMTNode[Self.K, Self.V], MutExternalOrigin]:
        if self.is_internal():
            return self.data[HAMTInternalNode[Self.K, Self.V]].add_child(chunk_index, arena, children_pool, is_internal)

        raise Error("Can not add child to leaf node")

    @always_inline
    fn get_child(self, chunk_index: UInt8) raises -> UnsafePointer[mut=True, HAMTNode[Self.K,Self.V], MutExternalOrigin]:
        if self.is_internal():
            return self.data[HAMTInternalNode[Self.K,Self.V]].get_child(chunk_index)
        raise Error("Can not grow a leaf node")

    fn collect_items(self, mut items: List[Tuple[Self.K, Self.V]]):
        """Recursively collect all key-value pairs from this node."""
        if self.is_internal():
            # Internal node - recurse into children
            self.data[HAMTInternalNode[Self.K,Self.V]].collect_items(items)
        else:
            # Leaf node - add items
            for item in self.data[HAMTLeafNode[Self.K,Self.V]]._items:
                items.append(item.copy())


struct NodeArena[
    K: Movable & Copyable & Hashable & Equatable & Stringable,
    V: Movable & Copyable & Stringable,
](Movable):
    """Arena allocator for HAMT nodes with freelist recycling.

    Phase 3 optimization: Allocates nodes in blocks and recycles freed nodes
    through a freelist, reducing both malloc overhead and memory fragmentation.
    """

    var blocks: List[UnsafePointer[mut=True, HAMTNode[Self.K, Self.V], MutExternalOrigin]]
    var current_block: UnsafePointer[mut=True, HAMTNode[Self.K, Self.V], MutExternalOrigin]
    var block_size: Int
    var next_index: Int
    # Phase 3: Freelist for recycling nodes
    var freelist: List[UnsafePointer[mut=True, HAMTNode[Self.K, Self.V], MutExternalOrigin]]

    fn __init__(out self, block_size: Int = 1024):
        """Initialize arena with given block size (default 1024 nodes)."""
        self.blocks = List[UnsafePointer[mut=True, HAMTNode[Self.K, Self.V], MutExternalOrigin]]()
        self.block_size = block_size
        self.next_index = block_size  # Force allocation of first block
        self.current_block = UnsafePointer[mut=True, HAMTNode[Self.K, Self.V], MutExternalOrigin]()
        self.freelist = List[UnsafePointer[mut=True, HAMTNode[Self.K, Self.V], MutExternalOrigin]]()

    fn __moveinit__(out self, deinit current: Self):
        self.blocks = current.blocks^
        self.current_block = current.current_block
        self.block_size = current.block_size
        self.next_index = current.next_index
        self.freelist = current.freelist^

    fn allocate_node(mut self) -> UnsafePointer[mut=True, HAMTNode[Self.K, Self.V], MutExternalOrigin]:
        """Allocate a single node from the arena.

        Phase 3: First tries to reuse a node from the freelist. If freelist is empty,
        allocates from the current block. If current block is full, allocates a new block.
        Returns pointer to uninitialized memory.
        """
        # Phase 3: Try freelist first (hot cache, zero malloc!)
        if len(self.freelist) > 0:
            return self.freelist.pop()
        
        # Need new block?
        if self.next_index >= self.block_size:
            self.current_block = alloc[HAMTNode[Self.K, Self.V]](
                self.block_size
            )
            self.blocks.append(self.current_block)
            self.next_index = 0

        # Get next slot and advance
        var node_ptr = self.current_block + self.next_index
        self.next_index += 1
        return node_ptr

    fn free_node(mut self, node: UnsafePointer[mut=True, HAMTNode[Self.K, Self.V], MutExternalOrigin]):
        """Return a node to the freelist for reuse.
        
        Phase 3: Instead of leaking freed nodes, add them to the freelist.
        The caller is responsible for cleaning up the node's contents before calling this.
        """
        if node:
            self.freelist.append(node)

    fn __del__(deinit self):
        """Free all allocated blocks."""
        for block in self.blocks:
            if block:
                # Note: We don't call destroy_pointee on individual nodes
                # The HAMT's __del__ handles node cleanup via tree traversal
                block.free()


struct HAMT[
    K: Movable & Copyable & Hashable & Equatable & Stringable,
    V: Movable & Copyable & Stringable,
](Defaultable, Movable, Representable, Sized, Stringable):
    # Profiling counters
    var _profile_internal_visits: Int
    var _profile_leaf_visits: Int
    var _profile_bitmap_hits: Int
    var _profile_bitmap_misses: Int
    var _profile_getchild_calls: Int
    
    # Timing instrumentation (nanoseconds)
    var _time_hash_total: Int
    var _time_traverse_total: Int
    var _time_leaf_total: Int
    var _time_total: Int
    var _op_count: Int
    
    var root: UnsafePointer[mut=True, HAMTNode[Self.K, Self.V], MutExternalOrigin]
    var _size: Int
    var _max_level: UInt16
    var _custom_hash_fn: Optional[fn (Self.K) -> UInt64]
    var arena: NodeArena[Self.K, Self.V]
    var children_pool: ChildrenPool[Self.K, Self.V]  # Simple bump allocator for children arrays

    fn __init__(out self):
        # Initialize profiling counters
        self._profile_internal_visits = 0
        self._profile_leaf_visits = 0
        self._profile_bitmap_hits = 0
        self._profile_bitmap_misses = 0
        self._profile_getchild_calls = 0
        # Initialize timing fields
        self._time_hash_total = 0
        self._time_traverse_total = 0
        self._time_leaf_total = 0
        self._time_total = 0
        self._op_count = 0
        # Initialize arena and children pool
        self.arena = NodeArena[Self.K, Self.V](block_size=1024)
        self.children_pool = ChildrenPool[Self.K, Self.V]()
        # Allocate root from arena
        self.root = self.arena.allocate_node()
        self.root.init_pointee_move(HAMTNode[Self.K, Self.V]())
        self._custom_hash_fn = Optional[fn (Self.K) -> UInt64]()
        # TODO make this a comptime var
        self._max_level = 10
        self._size = 0

    fn __init__(out self, hash_fn: fn (Self.K) -> UInt64):
        # Initialize profiling counters
        self._profile_internal_visits = 0
        self._profile_leaf_visits = 0
        self._profile_bitmap_hits = 0
        self._profile_bitmap_misses = 0
        self._profile_getchild_calls = 0
        # Initialize timing fields
        self._time_hash_total = 0
        self._time_traverse_total = 0
        self._time_leaf_total = 0
        self._time_total = 0
        self._op_count = 0
        # Initialize arena and children pool
        self.arena = NodeArena[Self.K, Self.V](block_size=1024)
        self.children_pool = ChildrenPool[Self.K, Self.V]()
        # Allocate root from arena
        self.root = self.arena.allocate_node()
        self.root.init_pointee_move(HAMTNode[Self.K, Self.V]())
        self._custom_hash_fn = Optional(hash_fn)
        self._max_level = 10
        self._size = 0

    fn __moveinit__(out self, deinit current: Self):
        self._profile_internal_visits = current._profile_internal_visits
        self._profile_leaf_visits = current._profile_leaf_visits
        self._profile_bitmap_hits = current._profile_bitmap_hits
        self._profile_bitmap_misses = current._profile_bitmap_misses
        self._profile_getchild_calls = current._profile_getchild_calls
        self._time_hash_total = current._time_hash_total
        self._time_traverse_total = current._time_traverse_total
        self._time_leaf_total = current._time_leaf_total
        self._time_total = current._time_total
        self._op_count = current._op_count
        self.root = current.root
        self._custom_hash_fn = current._custom_hash_fn^
        self._max_level = current._max_level
        self._size = current._size
        self.arena = current.arena^
        self.children_pool = current.children_pool^

    @always_inline
    fn _get_next_chunk(self, hashed_key: UInt64, level: UInt16) -> UInt8:
        return UInt8((hashed_key >> UInt64(6 * level)) & 0x3F)

    fn _calculate_hash(self, key: Self.K) -> UInt64:
        """Returns an integer of size 60 bits, by clearing the top 4 bits."""
        var hashed_key: UInt64
        if self._custom_hash_fn:
            hashed_key = self._custom_hash_fn.value()(key)
        else:
            hashed_key = hash(key)

        var filtered_key = hashed_key & FILTER

        # logger.debug("Original " + bin(hashed_key)[2:].rjust(64, "0"))
        # logger.debug("Filtered " + bin(filtered_key)[2:].rjust(64, "0"))

        return filtered_key

    @always_inline
    fn get(self, key: Self.K) raises -> Optional[Self.V]:
        var curr_level: UInt16 = 0
        var curr_node = self.root
        var hashed_key = self._calculate_hash(key)

        # The tree only allows for 10 levels, since we are
        # splitting the hashed keys into chunks of 6
        # and the hash key is of size 60 bits
        while curr_level < self._max_level:
            chunk_index = self._get_next_chunk(hashed_key, curr_level)
            curr_node = curr_node[].get_child(chunk_index)
            if not curr_node:
                return Optional[Self.V]()
            curr_level += 1

        return curr_node[].get_value(key)

    @always_inline
    fn set(mut self, var key: Self.K, var value: Self.V) raises:
        var curr_level: UInt16 = 0
        var curr_node = self.root
        # Hash before moving (need to borrow key)
        var hashed_key = self._calculate_hash(key)

        while curr_level < self._max_level:
            chunk_index = self._get_next_chunk(hashed_key, curr_level)
            var next_node = curr_node[].get_child(chunk_index)
            if not next_node:
                # insert node in the parent at index chunk_index
                # Create internal node if not at second-to-last level, leaf otherwise
                var is_internal = curr_level < self._max_level - 1
                next_node = curr_node[].add_child(chunk_index, self.arena, self.children_pool, is_internal)
            curr_node = next_node
            curr_level += 1

        # Move key and value into leaf node
        var is_new_key = curr_node[].add_value(key^, value^)
        if is_new_key:
            self._size += 1
    
    fn _count_tree_depth(self, node: UnsafePointer[mut=True, HAMTNode[Self.K, Self.V], MutExternalOrigin], current_depth: Int) -> Int:
        """Recursively count max tree depth for diagnostics."""
        if not node:
            return current_depth
        
        if node[].is_internal():
            var max_depth = current_depth
            var num_children = node[].data[HAMTInternalNode[Self.K,Self.V]].num_children()
            for i in range(num_children):
                var child = node[].data[HAMTInternalNode[Self.K,Self.V]].children[i]
                var child_depth = self._count_tree_depth(child, current_depth + 1)
                if child_depth > max_depth:
                    max_depth = child_depth
            return max_depth
        else:
            # Leaf node - return current depth
            return current_depth
    
    fn _count_internal_nodes(self, node: UnsafePointer[mut=True, HAMTNode[Self.K, Self.V], MutExternalOrigin]) -> Int:
        """Recursively count internal nodes for diagnostics."""
        if not node or not node[].is_internal():
            return 0
        
        var count = 1  # Count this internal node
        var num_children = node[].data[HAMTInternalNode[Self.K,Self.V]].num_children()
        for i in range(num_children):
            var child = node[].data[HAMTInternalNode[Self.K,Self.V]].children[i]
            count += self._count_internal_nodes(child)
        return count
    
    fn _count_leaf_nodes(self, node: UnsafePointer[mut=True, HAMTNode[Self.K, Self.V], MutExternalOrigin]) -> Int:
        """Recursively count leaf nodes for diagnostics."""
        if not node:
            return 0
        
        if not node[].is_internal():
            return 1  # This is a leaf
        
        var count = 0
        var num_children = node[].data[HAMTInternalNode[Self.K,Self.V]].num_children()
        for i in range(num_children):
            var child = node[].data[HAMTInternalNode[Self.K,Self.V]].children[i]
            count += self._count_leaf_nodes(child)
        return count
    
    fn _calc_avg_children_per_internal_node(self, node: UnsafePointer[mut=True, HAMTNode[Self.K, Self.V], MutExternalOrigin]) -> Tuple[Int, Int, Float64]:
        """Calculate average children per internal node.
        
        Returns: (total_internal_nodes, total_children, avg_children_per_node)
        """
        if not node or not node[].is_internal():
            return (0, 0, 0.0)
        
        var internal_count = self._count_internal_nodes(node)
        
        # Count total children across all internal nodes using iterative stack
        var total_children = 0
        var stack = List[UnsafePointer[mut=True, HAMTNode[Self.K, Self.V], MutExternalOrigin]]()
        stack.append(node)
        
        while len(stack) > 0:
            var current = stack.pop()
            if not current or not current[].is_internal():
                continue
            
            var num = current[].data[HAMTInternalNode[Self.K,Self.V]].num_children()
            total_children += num
            
            for i in range(num):
                var child = current[].data[HAMTInternalNode[Self.K,Self.V]].children[i]
                if child:
                    stack.append(child)
        
        var avg = Float64(total_children) / Float64(internal_count) if internal_count > 0 else 0.0
        return (internal_count, total_children, avg)
    
    fn print_tree_stats(self):
        """Print detailed tree structure statistics for performance analysis."""
        print("\n=== HAMT Tree Structure Statistics ===")
        print("Total entries:", self._size)
        print("Max tree depth:", self._count_tree_depth(self.root, 0), "/", self._max_level)
        print("Internal nodes:", self._count_internal_nodes(self.root))
        print("Leaf nodes:", self._count_leaf_nodes(self.root))
        var (internal_count, total_children, avg_children) = self._calc_avg_children_per_internal_node(self.root)
        print("Avg children per internal node:", avg_children)
        print("Total children pointers:", total_children)
        print("======================================\n")

    fn print_timing_stats(self):
        """Print detailed timing statistics for performance analysis."""
        print("\n=== HAMT Timing Statistics ===")
        print("Operation count:", self._op_count)
        if self._op_count > 0:
            print("Avg time per op (ns):", self._time_total // self._op_count)
            print("Time hashing (ns):", self._time_hash_total)
            print("Time traversing (ns):", self._time_traverse_total)
            print("Time leaf operations (ns):", self._time_leaf_total)
            print("Time total (ns):", self._time_total)
        print("=============================\n")

    fn __del__(deinit self):
        # Clean up node contents (Lists, etc.) but don't free individual nodes
        # The arena will free all blocks when it's destroyed
        if self.root:
            self._cleanup_node(self.root)
        # Arena's __del__ will free all blocks

    fn _cleanup_node(self, node: UnsafePointer[mut=True, HAMTNode[Self.K, Self.V], MutExternalOrigin]):
        """Recursively cleanup node contents without freeing the node itself."""
        if not node:
            return

        # Only internal nodes have children
        if node[].is_internal():
            # Take ownership of internal node temporarily to access children
            # This is safe because we're in __del__ and no one else has references
            var internal = node[].data.unsafe_take[HAMTInternalNode[Self.K,Self.V]]()
            var num_children = internal.num_children()
            for i in range(num_children):
                var child = internal.children[i]
                if child:
                    self._cleanup_node(child)
            # Internal node and its children array will be freed when 'internal' goes out of scope

        # Destroy this node's contents (frees internal Lists)
        # but DON'T call node.free() - arena owns the memory
        node.destroy_pointee()

    ### dict implementations

    fn __len__(self) -> Int:
        return Int(self._size)

    fn __contains__(self, key: Self.K) raises -> Bool:
        var val = self.get(key)
        if val:
            return True
        return False

    fn __getitem__(self, key: Self.K) raises -> Self.V:
        var result = self.get(key)
        if not result:
            raise Error("KeyError: key not found in HAMT")

        # TODO: why copy??
        return result.value().copy()

    fn __setitem__(mut self, var key: Self.K, var value: Self.V) raises:
        self.set(key^, value^)

    fn __str__(self) -> String:
        """Returns string representation of the HAMT in dict-like format."""
        if self._size == 0:
            return "{}"

        var items = List[Tuple[Self.K, Self.V]]()
        self.root[].collect_items(items)

        var result = String("{")
        for i in range(len(items)):
            if i > 0:
                result += ", "
            result += String(items[i][0]) + ": " + String(items[i][1])
        result += "}"
        return result

    fn print_pool_stats(self):
        """Print ChildrenPool utilization statistics for diagnostics."""
        self.children_pool.print_stats()
    

    
    fn __repr__(self) -> String:
        """Returns repr representation of the HAMT."""
        return "HAMT(" + self.__str__() + ")"


# fn main() raises:
#    var node = HAMT[Int, Int]()
#    node.set(1, 1)
#    node.set(2, 200)
#    print(node.__str__())
