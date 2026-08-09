# Chapter 8: Heaps and Segment Trees

## Key Concepts

- **Max-Heap**: A max-heap is a complete binary tree where every node's value is greater than or equal to its children's values (the max-heap-order property). This guarantees the maximum element is always at the root, enabling O(log n) insert and extract-max operations. The "complete binary tree" property means all levels are full except possibly the last, which fills left to right.

- **Min-Heap**: A min-heap is identical to a max-heap except the min-heap-order property holds: every node's value is less than or equal to its children's. The minimum element is always at the root. All implementation details mirror the max-heap with comparisons flipped from `>` to `<`.

- **Heap as Array (1-indexed)**: Because heaps are complete binary trees, they can be stored compactly in a 1-indexed array without pointers. For a node at index `i`: its parent is at `i/2` (integer division), its left child is at `i*2`, and its right child is at `i*2+1`. This arithmetic works only because of the complete-tree shape. Index 0 is unused. The root sits at index 1.

- **Heap Insert (Bubble Up)**: To insert into a heap, append the new element at the next available position (index `num_heap` after incrementing), then swap it upward with its parent as long as the heap-order property is violated (`i > 1` and the new element outranks its parent). Each swap moves the element one level up, so at most O(log n) swaps are needed.

- **Heap Extract (Bubble Down / Sift Down)**: To extract the root, save it, replace the root with the last element (index `num_heap`), decrement `num_heap`, then swap the displaced element downward: at each step pick the larger (for max-heap) or smaller (for min-heap) child, swap if the child outranks the current node, and stop when no violation exists or a leaf is reached. At most O(log n) swaps.

- **Priority Queue**: A heap is the standard implementation of a priority queue. When high-priority items have large values, use a max-heap. When high-priority items have small values, use a min-heap. Two heaps can be maintained simultaneously when both maximum and minimum access is needed (as in Supermarket Promotion).

- **Heapsort**: Sort n elements by inserting all into a min-heap then extracting one by one. This yields elements in ascending order. Total cost: n inserts + n extracts = O(n log n). Same asymptotic complexity as the fastest comparison sorts. Quicksort is faster in practice.

- **Segment Tree**: A segment tree is a full binary tree where each node covers a contiguous segment of an underlying array and stores the answer to a query (maximum, sum, etc.) for that segment. The root covers the entire array. Children subdivide their parent's segment at the midpoint. It is also stored in a 1-indexed array using the same parent/child index arithmetic as heaps. Building takes O(n). Each query or update takes O(log n).

- **Segment Tree Array Size**: For an underlying array of n elements, allocate 4n elements for the segment tree array. The reasoning: the smallest power of 2 at least n (call it m) satisfies m < 2n. Storing a segment tree for m elements requires 2m slots, so 2m < 4n. This conservative bound handles non-power-of-2 inputs where the tree bottom level is not filled left to right (leading to "holes" in the array representation).

- **Range Maximum Query (RMQ)**: Given an array and indices `left`/`right`, return the index of the maximum element in `a[left..right]`. Naive linear scan is O(n). Prefix arrays cannot solve RMQ because maximum is not invertible (unlike addition). A segment tree solves RMQ in O(log n) per query after O(n) preprocessing.

- **Segment Tree Query (Three Cases)**: When recursively querying a segment tree with query range `[left, right]` and visiting a node covering segment `[node.left, node.right]`: (1) **No overlap** (`right < node.left` or `left > node.right`): return a sentinel (e.g., -1). This subtree contributes nothing. (2) **Complete containment** (`left <= node.left` and `node.right <= right`): return the stored answer directly. No recursion needed. (3) **Partial overlap**: recurse into both children, then combine the two answers. In the worst case, querying traces two root-to-leaf paths, but those paths never further bifurcate, preserving O(log n).

- **Segment Tree Update**: When element `a[index]` changes, only the leaf covering `index` and all its ancestors need updating (O(log n) nodes). The update procedure recurses down toward the affected leaf, makes a single recursive call (left or right, based on whether `index <= left_child.right`), then recomputes the current node's stored values from the (now-updated) child info on the way back up.

- **Treap**: A treap is a binary tree where each node has a label and a priority. It satisfies two properties simultaneously: the BST property on labels (left subtree labels < node label < right subtree labels) and the max-heap-order property on priorities (node priority > children's priorities). The node with maximum priority is uniquely determined as the root. The BST property on labels then dictates which remaining nodes go left and which go right, recursively. A treap has no shape constraint (unlike a heap it need not be a complete tree).

- **Lazy/Used-Flag Technique for Dual Heaps**: When maintaining two heaps over the same set of elements (e.g., one max-heap and one min-heap), it is impractical to remove an element from both heaps simultaneously because its position in the second heap is unknown. Instead, mark elements as `used` in a separate boolean array. After extracting from one heap, skip over any extracted elements that are already marked used (via a `while` loop) before accepting a result.

---

## Problems Covered

### Problem: Supermarket Promotion
- **Source**: SPOJ problem PRO (originally 2000 Polish Olympiad in Informatics, Stage 3)
- **Core Idea**: A promotion runs for n days. Each day, k new receipts are added to a ballot box, then the receipt with maximum cost x and the receipt with minimum cost y are removed. The prize is `x - y`. Receipts not removed persist into future days. Compute total prize money over all n days. Total receipts up to 1,000,000, n up to 5,000.
- **Approach (Solution 1, too slow)**: Store all receipts in an array with a `used` flag. Each day, linearly scan for max and min, mark them used. Correctness: yes. Performance: O(n * total_receipts), up to 10 billion operations, which exceeds the 0.6 second limit.
- **Approach (Solution 2, heaps)**: Maintain both a max-heap and a min-heap over all receipts. Each new receipt is inserted into both heaps at O(log n) cost. Each day, extract from the max-heap. Use a `while` loop to skip any already-used receipts. Mark the accepted receipt used. Repeat symmetrically with the min-heap. Accumulate `max_element.cost - min_element.cost` into a `long long total_prizes`.
- **Complexity**: O(total_receipts * log(total_receipts)) time, and O(total_receipts) space for both heaps plus the used array.
- **Key Insight**: When two heaps share the same element universe, they will inevitably extract elements the other heap hasn't discarded yet. Rather than tracking each element's position in both heaps, maintain a `used` array and skip stale extractions with a while loop. Each element is extracted at most once per heap, so total extra work is bounded.

---

### Problem: Building Treaps
- **Source**: POJ problem 1785 (originally 2004 Ulm University Local Contest)
- **Core Idea**: Given n nodes each with a string label and integer priority (all unique), assemble and output the unique treap satisfying the BST property on labels and the max-heap-order property on priorities. Output format is parenthesized: `(<left_subtreap><label>/<priority><right_subtreap>)`. n up to 50,000.
- **Approach (Solution 1, recursive, too slow)**: Sort nodes by label. The root of any subtreap spanning indices `left..right` is the node with maximum priority in that range. Recursively solve for `left..root_index-1` and `root_index+1..right`. Finding the max-priority node is a linear scan: `max_priority_index` iterates from `left` to `right`. Correctness: yes. Performance: O(n²) in the worst case (when priorities are in increasing label order, producing a right-skewed treap).
- **Approach (Solution 2, segment tree RMQ)**: Replace the linear `max_priority_index` scan with `query_segtree`. After sorting by label, build a segment tree over the priority array: `init_segtree` sets up the segments. `fill_segtree` stores the index of the maximum priority in each segment. The `solve` function calls `query_segtree(segtree, 1, treap_nodes, left, right)` to find the root in O(log n), then recurses as before.
- **Complexity**: O(n log n) for sorting + O(n) to build the segment tree + O(n log n) for all queries during recursion = O(n log n) total. O(4n) space for the segment tree.
- **Key Insight**: The recursion naturally decomposes into a series of RMQ calls on decreasing subranges. Once you recognize this as RMQ, the segment tree drops right in to replace the linear scan. Sorting by label up front avoids copying subarrays: each recursive call is fully described by its `left`/`right` index bounds.

---

### Problem: Two Sum
- **Source**: SPOJ problem KGSS (originally 2009 Kurukshetra Online Programming Contest)
- **Core Idea**: Given a sequence a[1..n] (each element >= 0), support two interleaved operations: Update (change a[x] to y) and Query (return the maximum sum of any two distinct elements in a[x..y]). n and q up to 100,000.
- **Approach**: Build a segment tree where each node stores two values: `max_element` (the maximum single element in the segment) and `max_sum` (the maximum sum of two elements in the segment, -1 for single-element segments). When combining two children, `max_sum` has three candidate values: the left child's `max_sum`, the right child's `max_sum`, and `left.max_element + right.max_element`. Take the maximum of valid candidates (ignoring -1 entries). Updates use `update_segtree`, which recurses only into the child containing the changed index (the other child's info is reused unchanged), then recomputes the current node's values on the way up.
- **Complexity**: O(n) to build the segment tree, O(log n) per query, and O(log n) per update.
- **Key Insight**: The maximum sum of two elements in a merged segment cannot be derived solely from the two children's maximum sums. It might span the boundary (one element from each child). The segment tree must therefore store the maximum single element in addition to the maximum sum. This is a general lesson: sometimes the answer to a parent query depends on auxiliary information from children beyond the query answer itself.

---

## Algorithm Patterns

- **Heap for Dynamic Max/Min**: Any time you have a stream of incoming values and periodically need to extract the current maximum or minimum, use a heap. The heap gives O(log n) insert and O(log n) extract, replacing O(n) linear scans. This pattern applies to: Dijkstra's algorithm (min-heap for next-closest node), scheduling problems (earliest deadline, highest priority), and merge k sorted lists.

- **Dual-Heap with Used Flags**: When you need both max and min of the same set and elements can be independently consumed from either end, maintain a max-heap and min-heap simultaneously plus a `used` boolean array indexed by element identity. After extraction, consume and discard stale (already-used) elements via a while loop before accepting a result. The amortized cost remains O(log n) per logical operation.

- **Segment Tree for Static Range Queries**: If an array never changes and you need to answer many range queries (maximum, minimum, sum, count), build a segment tree in O(n) and answer each query in O(log n). The array segment tree with 4n allocation and 1-indexed storage with `node*2` / `node*2+1` children is the standard template.

- **Segment Tree for Dynamic Range Queries (with Updates)**: When the array can change, the segment tree update procedure recurses only down the path from root to the affected leaf (O(log n) nodes), recomputing node values on the way back up. This makes both updates and queries O(log n), a massive improvement over the O(n) cost of rebuilding from scratch.

- **Combining Child Answers (Auxiliary Information)**: When a parent's query answer cannot be computed from just the children's query answers, store additional auxiliary information in each node. For Two Sum, the parent needs children's `max_element` values even though the query answer is `max_sum`. Identify what information enables O(1) combination at each node and store that alongside the primary answer.

- **Recursion + Sort to Avoid Array Copying**: When a recursive divide-and-conquer problem repeatedly splits an array, sort the array once by the splitting criterion, then represent each recursive subproblem as a `(left, right)` index range into the sorted array. This avoids O(n) copying at each recursive call.

- **Recognizing RMQ**: If a recursive algorithm repeatedly needs the index of the maximum (or minimum) element in a shrinking subrange of a fixed array, the bottleneck is RMQ. Replace each linear scan with a segment tree query to reduce the recursion's overall cost from O(n²) to O(n log n).

---

## Common Pitfalls

### Using int Instead of long long for Accumulated Sums
Prize money in Supermarket Promotion can reach 5,000 × 1,000,000 = 5 billion, exceeding the ~4 billion limit of a 32-bit integer. Use `long long` for any accumulated total that could exceed `2^31 - 1`.

### Heap Indexing Starting at 1, Not 0
Heaps stored in arrays must be 1-indexed for the parent/child arithmetic (`i/2`, `i*2`, `i*2+1`) to work correctly. Allocate `MAX_ELEMENTS + 1` slots and leave index 0 unused.

### Failing to Handle Stale Heap Entries
In the dual-heap pattern, failing to skip already-used elements (omitting the `while (used[element.receipt_index])` loop) causes a logical correctness error: you process an element that was already consumed on a prior day.

### Insufficient Segment Tree Array Size
Allocating 2n for a segment tree is enough only when n is a power of 2. For arbitrary n, allocate 4n to account for the holes introduced by non-power-of-2 sizes. Using exactly 2n with a non-power-of-2 input causes out-of-bounds writes.

### Prefix Arrays Cannot Solve RMQ
The prefix-array trick for range sums relies on invertibility (subtraction undoes addition). Range maximum has no inverse: if the prefix max to index 5 is 10 and the prefix max to index 1 is also 10, you cannot determine the max in [2..5]. Do not attempt to adapt prefix arrays for RMQ.

### Linear RMQ in Recursive Treap Building
The worst case for linear RMQ arises when priorities are sorted in increasing label order, producing a chain-shaped treap. Each of the n recursive calls scans a shrinking but still-large subarray, leading to O(n²) total work. The problem does not reveal this worst case from the sample input. It must be reasoned about analytically.

### Extracting Wrong Child in Heap Sift-Down
During extract-max (or extract-min), always swap with the *larger* (or *smaller*) child, not just the first child in violation. Swapping with the smaller child (in a max-heap) fixes one violation but may introduce a new one between the node and the other child.

### Combining max_sum Without Checking -1
In the Two Sum segment tree, leaf nodes have `max_sum = -1` (only one element, no valid two-element sum). When combining children, treat -1 as "no valid sum from this child" rather than a real value. Failing to handle this leads to incorrect sums (e.g., treating -1 + something as a valid candidate).

---

## Connections to Other Chapters

### Chapter 1: Hash Tables
Chapter 1 introduced hash tables as the data structure for fast lookup of specific items. Chapter 8 reinforces the general lesson: choose the data structure matched to the operation you need. A hash table cannot efficiently find the minimum element. A min-heap cannot efficiently look up an arbitrary element. Data structure selection is problem-specific.

### Chapter 2: Binary Trees (Halloween Haul)
Chapter 2 introduced binary trees with `left`, `right`, and `parent` pointers. Chapter 8 shows that heaps' complete-binary-tree property allows a dramatically simpler array-based representation with no pointers, using index arithmetic instead. Both heaps and segment trees exploit this same array layout.

### Chapter 5: Graphs and BFS / Reading Strings
The `read_label` function in Building Treaps reuses the dynamic string reading pattern from Listing 5-15 (Chapter 5's Book Translation problem), growing a buffer with `realloc` until the label fits.

### Chapter 6: Dijkstra's Algorithm
Chapter 6 implemented Dijkstra's algorithm. Chapter 8 notes that replacing the linear scan for the minimum-distance node with a min-heap reduces Dijkstra's complexity. Appendix B demonstrates this optimization explicitly. This illustrates the theme: data structures accelerate algorithmic bottlenecks.

### Chapter 7: Prefix Sums / Range Sum Queries
Chapter 7 solved range sum queries with a prefix array in O(1) per query. Chapter 8 shows that the same trick fails for range maximum queries (because maximum is not invertible) and introduces segment trees as the general solution. Segment trees can also handle range sum queries, making them a superset of the prefix-sum technique when updates are required.

### Chapter 10: Quicksort
Chapter 8 introduces heapsort as an O(n log n) sorting algorithm and notes that quicksort (covered in Chapter 10) is faster in practice. The `qsort` function used throughout the book likely implements quicksort internally.

### Appendix B: Heap-Accelerated Dijkstra
Chapter 8 defers the full heap-based Dijkstra implementation to Appendix B, establishing a direct connection between this chapter's heap material and the graph algorithms of Chapter 6.
