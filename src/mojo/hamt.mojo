from collections import List
from memory import UnsafePointer
from testing import assert_equal, assert_true
from bit.bit import pop_count
from logger import Logger, Level
from sys.param_env import env_get_string
from os import env
from python import PythonObject
from python.bindings import PythonModuleBuilder
from os import abort


# Clears the highest 4 bits of the UInt64
# used to truncate the hash
alias FILTER: UInt64 = 0x0FFFFFFFFFFFFFFF
alias logger = Logger()


struct NodeArena[
    K: Movable & Copyable & Hashable & EqualityComparable & Stringable,
    V: Movable & Copyable & Stringable,
](Movable):
    """Arena allocator for HAMT nodes to reduce malloc overhead.

    Allocates nodes in blocks of BLOCK_SIZE, dramatically reducing
    the number of malloc calls from O(N) to O(N/BLOCK_SIZE).
    """

    var blocks: List[UnsafePointer[HAMTNode[K, V]]]
    var current_block: UnsafePointer[HAMTNode[K, V]]
    var block_size: Int
    var next_index: Int

    fn __init__(out self, block_size: Int = 1024):
        """Initialize arena with given block size (default 1024 nodes)."""
        self.blocks = List[UnsafePointer[HAMTNode[K, V]]]()
        self.block_size = block_size
        self.next_index = block_size  # Force allocation of first block
        self.current_block = UnsafePointer[HAMTNode[K, V]]()

    fn __moveinit__(out self, deinit current: Self):
        self.blocks = current.blocks^
        self.current_block = current.current_block
        self.block_size = current.block_size
        self.next_index = current.next_index

    fn allocate_node(mut self) -> UnsafePointer[HAMTNode[K, V]]:
        """Allocate a single node from the arena.

        If current block is full, allocates a new block of block_size nodes.
        Returns pointer to uninitialized memory.
        """
        # Need new block?
        if self.next_index >= self.block_size:
            self.current_block = UnsafePointer[HAMTNode[K, V]].alloc(
                self.block_size
            )
            self.blocks.append(self.current_block)
            self.next_index = 0

        # Get next slot and advance
        var node_ptr = self.current_block.offset(self.next_index)
        self.next_index += 1
        return node_ptr

    fn __del__(deinit self):
        """Free all allocated blocks."""
        for block in self.blocks:
            if block:
                # Note: We don't call destroy_pointee on individual nodes
                # The HAMT's __del__ handles node cleanup via tree traversal
                block.free()


struct HAMTLeafNode[
    K: Movable & Copyable & Hashable & EqualityComparable & Stringable,
    V: Movable & Copyable & Stringable,
](Copyable, Movable):
    var _items: List[Tuple[K, V]]

    fn __init__(out self, key: K, value: V):
        self._items = List[Tuple[K, V]]()
        _ = self.add(key, value)

    fn add(mut self, key: K, value: V) -> Bool:
        """Add or update a key-value pair. Returns True if a new key was added, False if updated.
        """
        # TODO: fix all the copying going on here and
        # in set!!
        # look here: https://github.com/modular/modular/issues/4695
        for i in range(len(self._items)):
            if self._items[i][0] == key:
                self._items[i] = (key.copy(), value.copy())
                return False
        self._items.append(Tuple(key.copy(), value.copy()))
        return True

    fn get(self, key: K) -> Optional[V]:
        for item in self._items:
            if item[0] == key:
                return Optional(item[1].copy())
        return Optional[V]()


struct HAMTNode[
    K: Movable & Copyable & Hashable & EqualityComparable & Stringable,
    V: Movable & Copyable & Stringable,
](Copyable, Movable):
    # This tells you what children are in this node
    # It represents a sparse array via an integer
    var children_bitmap: UInt64
    #
    # This gives you the actual child, it is a dense
    # array.
    var children: InlineArray[UnsafePointer[HAMTNode[K, V]], 64]
    var leaf_node: Optional[HAMTLeafNode[K, V]]

    fn __init__(out self):
        self.children_bitmap = 0
        self.children = InlineArray[UnsafePointer[HAMTNode[K, V]], 64](UnsafePointer[HAMTNode[K, V]]())
        self.leaf_node = Optional[HAMTLeafNode[K, V]]()

    fn add_value(mut self, key: K, value: V) -> Bool:
        """Add or update a key-value pair. Returns True if a new key was added, False if updated.
        """
        if self.leaf_node:
            return self.leaf_node.value().add(key, value)
        else:
            self.leaf_node = Optional(HAMTLeafNode(key, value))
            return True

    fn get_value(self, key: K) -> Optional[V]:
        if self.leaf_node:
            return self.leaf_node.value().get(key)
        return Optional[V]()

    fn collect_items(self, mut items: List[Tuple[K, V]]):
        """Recursively collect all key-value pairs from this node and its children.
        """
        # Add items from leaf node if present
        if self.leaf_node:
            for item in self.leaf_node.value()._items:
                items.append(item.copy())

        # Recursively collect from children
        var num_children = pop_count(self.children_bitmap)
        for i in range(num_children):
            var child = self.children[i]
            if child:
                child[].collect_items(items)

    fn add_child(
        mut self, chunk_index: UInt8, mut arena: NodeArena[K, V]
    ) -> UnsafePointer[HAMTNode[K, V]]:
        masked_chunked = UInt64(1) << UInt64(chunk_index)
        masked_bitmap = UInt64(masked_chunked - 1) & self.children_bitmap
        child_index = pop_count(masked_bitmap)

        # Get current number of children before updating bitmap
        var num_children = pop_count(self.children_bitmap)

        # Update bitmap to include new child
        self.children_bitmap |= UInt64(masked_chunked)

        # Shift existing children to the right to make room for new child
        # Work backwards to avoid overwriting
        for i in range(num_children, Int(child_index), -1):
            self.children[i] = self.children[i - 1]

        # Allocate from arena instead of individual malloc
        var new_node_pointer = arena.allocate_node()
        new_node_pointer.init_pointee_move(HAMTNode[K, V]())

        # Insert new child at the calculated dense index
        self.children[Int(child_index)] = new_node_pointer
        return new_node_pointer

    @always_inline
    fn get_child(
        self, chunk_index: UInt8
    ) raises -> UnsafePointer[HAMTNode[K, V]]:
        # The chunk index as an integer represents
        # the position in the sparse representation of the node
        # of where we should expect to have a value
        masked_chunked = UInt64(1) << UInt64(chunk_index)
        if (self.children_bitmap & UInt64(masked_chunked)) == 0:
            logger.debug(
                "did not find child, returning null for chunk index",
                chunk_index,
                self.children_bitmap,
            )
            return UnsafePointer[HAMTNode[K, V]]()

        # The actual index of the value, is number of 1s before
        # that position.
        masked_bitmap = UInt64(masked_chunked - 1) & self.children_bitmap
        child_index = pop_count(masked_bitmap)
        assert_true(child_index < len(self.children), "bad child index")
        return self.children[child_index]

    # NOTE: No __del__ needed - HAMT handles cleanup via _cleanup_node
    # which properly manages arena-allocated nodes


struct HAMT[
    K: Movable & Copyable & Hashable & EqualityComparable & Stringable,
    V: Movable & Copyable & Stringable,
](Defaultable, Movable, Representable, Sized, Stringable):
    var root: UnsafePointer[HAMTNode[K, V]]
    var _size: Int
    var _max_level: UInt16
    var _custom_hash_fn: Optional[fn (K) -> UInt64]
    var arena: NodeArena[K, V]

    fn __init__(out self):
        # Initialize arena first
        self.arena = NodeArena[K, V](block_size=1024)
        # Allocate root from arena
        self.root = self.arena.allocate_node()
        self.root.init_pointee_move(HAMTNode[K, V]())
        self._custom_hash_fn = Optional[fn (K) -> UInt64]()
        # TODO make this a comptime var
        self._max_level = 10
        self._size = 0

    fn __init__(out self, hash_fn: fn (K) -> UInt64):
        # Initialize arena first
        self.arena = NodeArena[K, V](block_size=1024)
        # Allocate root from arena
        self.root = self.arena.allocate_node()
        self.root.init_pointee_move(HAMTNode[K, V]())
        self._custom_hash_fn = Optional(hash_fn)
        self._max_level = 10
        self._size = 0

    fn __moveinit__(out self, deinit current: Self):
        self.root = current.root
        self._custom_hash_fn = current._custom_hash_fn^
        self._max_level = current._max_level
        self._size = current._size
        self.arena = current.arena^

    @always_inline
    fn _get_next_chunk(self, hashed_key: UInt64, level: UInt16) -> UInt8:
        return UInt8((hashed_key >> UInt64(6 * level)) & 0x3F)

    @always_inline
    fn _calculate_hash(self, key: K) -> UInt64:
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

    fn get(self, key: K) raises -> Optional[V]:
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
                return Optional[V]()
            curr_level += 1

        return curr_node[].get_value(key)

    fn set(mut self, key: K, value: V) raises:
        var curr_level: UInt16 = 0
        var curr_node = self.root
        var hashed_key = self._calculate_hash(key)

        while curr_level < self._max_level:
            chunk_index = self._get_next_chunk(hashed_key, curr_level)
            var next_node = curr_node[].get_child(chunk_index)
            if not next_node:
                # insert node in the parent at index chunk_index
                next_node = curr_node[].add_child(chunk_index, self.arena)
            curr_node = next_node
            curr_level += 1

        var is_new_key = curr_node[].add_value(key, value)
        if is_new_key:
            self._size += 1

    fn __del__(deinit self):
        # Clean up node contents (Lists, etc.) but don't free individual nodes
        # The arena will free all blocks when it's destroyed
        if self.root:
            self._cleanup_node(self.root)
        # Arena's __del__ will free all blocks

    fn _cleanup_node(self, node: UnsafePointer[HAMTNode[K, V]]):
        """Recursively cleanup node contents without freeing the node itself."""
        if not node:
            return

        # Recursively cleanup children first
        for i in range(len(node[].children)):
            var child = node[].children[i]
            if child:
                self._cleanup_node(child)

        # Destroy this node's contents (frees internal Lists)
        # but DON'T call node.free() - arena owns the memory
        node.destroy_pointee()

    ### dict implementations

    fn __len__(self) -> Int:
        return Int(self._size)

    fn __contains__(self, key: K) raises -> Bool:
        var val = self.get(key)
        if val:
            return True
        return False

    fn __getitem__(self, key: K) raises -> V:
        var result = self.get(key)
        if not result:
            raise Error("KeyError: key not found in HAMT")

        # TODO: why copy??
        return result.value().copy()

    fn __setitem__(mut self, key: K, value: V) raises:
        self.set(key, value)

    fn __str__(self) -> String:
        """Returns string representation of the HAMT in dict-like format."""
        if self._size == 0:
            return "{}"

        var items = List[Tuple[K, V]]()
        self.root[].collect_items(items)

        var result = String("{")
        for i in range(len(items)):
            if i > 0:
                result += ", "
            result += String(items[i][0]) + ": " + String(items[i][1])
        result += "}"
        return result

    fn __repr__(self) -> String:
        """Returns repr representation of the HAMT."""
        return "HAMT(" + self.__str__() + ")"


# fn main() raises:
#    var node = HAMT[Int, Int]()
#    node.set(1, 1)
#    node.set(2, 200)
#    print(node.__str__())
