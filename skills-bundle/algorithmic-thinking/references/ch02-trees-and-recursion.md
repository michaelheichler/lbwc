# Chapter 2: Trees and Recursion

## Key Concepts

- **Binary Tree**: A hierarchical data structure of nodes connected by edges, where each node has at most two children (left and right). The topmost node is the root. Nodes with no children are leaves. Binary trees are suited to problems where data has a recursive, branching structure. This chapter uses *full* binary trees specifically, every non-leaf has exactly two children, never one.

- **Tree Terminology**: Root (top node), parent/child (nodes connected by an edge), sibling (same parent), leaf (no children), subtree (any node plus all its descendants), height (maximum number of edges on a downward root-to-leaf path), descendant (reachable by moving down from a given node). These terms map directly to family-tree vocabulary.

- **General (n-ary) Tree**: A tree where each node may have any number of children, not just two. Represented using a `children` array and a `num_children` count per node rather than fixed `left`/`right` pointers. Used in Problem 2 (Descendant Distance), where family-tree nodes have variable fan-out.

- **Stack (LIFO)**: A data structure supporting push (add to top) and pop (remove from top) in last-in, first-out order. The book implements a stack as an array with a `highest_used` index. A stack can be used to manually simulate tree traversal by storing pending subtrees, but the chapter motivates moving away from explicit stacks toward recursion.

- **Recursion**: A problem-solving technique where a function calls itself on smaller subproblems. Every recursive solution needs at least one **base case** (solved directly, no recursion) and at least one **recursive case** (solution expressed in terms of smaller subproblems). The author argues strongly against trying to mentally trace recursive call stacks. Instead, trust the recursive rules at the level of problem structure.

- **Recursive Definition**: A two-rule pattern where Rule 1 is the base case (e.g., a leaf node) and Rule 2 is the recursive case (e.g., a non-leaf node whose answer depends on answers from its subtrees). This mirrors the recursive structure of the tree itself and maps cleanly to code.

- **Tree Traversal**: Visiting every node in a tree. With a loop, tracking which subtrees remain pending requires an explicit stack. With recursion, the call stack handles this implicitly. Both approaches yield O(n) time, but the recursive version is far simpler to write and reason about.

- **Helper Function with Pointer Parameter**: When a recursive function needs to both consume input (e.g., a string position) and communicate progress back to the caller, adding an `int *pos` parameter solves the problem cleanly. The caller passes a pointer. The recursive call advances `*pos` and the caller sees the updated value. This pattern, adding a pointer parameter to pass information both into and out of recursive calls, is broadly applicable.

- **Character-to-Integer Conversion**: Characters in C are stored as their ASCII codes. Digit characters `'0'` to `'9'` are consecutive, so `ch - '0'` converts a digit character to its integer value. For multi-digit numbers, accumulate: `value = value * 10 + (ch - '0')`.

- **Linear Search**: An O(n) element-by-element scan of an array, used in Descendant Distance to look up nodes by name. The book notes this could be replaced with a hash table for better performance but is acceptable given the small input size (≤1,000 nodes).

- **qsort with Custom Comparator**: C's standard library `qsort` is used to sort nodes. The comparison function receives two `const void *` pointers to array elements. Since the array holds `node *` pointers, the cast is `const node *n = *(const node **)v`. Return negative/zero/positive to indicate less-than/equal/greater-than ordering.

---

## Problems Covered

### Problem: Halloween Haul

- **Source**: DMOJ problem `dwite12c1p4` (2012 DWITE Programming Competition, Round 1)
- **Core Idea**: A neighborhood is shaped as a full binary tree. Houses (leaves) contain candy values. Starting at the root, collect all candy while walking the minimum number of streets. You do not need to return to the root after collecting the last piece of candy.
- **Approach**: Represent the neighborhood as a binary tree using a `node` struct with `candy`, `left`, and `right` fields. Solve three recursive subproblems: (1) `tree_candy`, sum all candy values in the tree. (2) `tree_streets`, count streets walked if you *do* return to the root (each non-leaf adds 4: down-left, up-left, down-right, up-right). (3) `tree_height`, maximum depth of any leaf. The final answer for streets is `tree_streets(root) - tree_height(root)`, because ending at the deepest leaf saves exactly `height` return-trip edges. The tree itself is encoded as a recursive string expression (e.g., `((4 9) 15)`) and parsed with a recursive `read_tree_helper(char *line, int *pos)` function that advances `*pos` as it consumes characters.
- **Complexity**: All three recursive tree functions (`tree_candy`, `tree_streets`, `tree_height`) are O(n) time and O(n) space (call stack depth proportional to tree height, which is at most n). Parsing the string is also O(n).
- **Key Insight**: If you must return to the root, the number of streets is deterministic: 4 per non-leaf node (two edges per child, traversed twice). Since you *don't* have to return, you save the edges on the path from the last visited house back to the root. To maximize savings, end at the house furthest from the root, i.e., a leaf at maximum depth, which is exactly the tree's height. Therefore: `min_streets = tree_streets - tree_height`.

---

### Problem: Descendant Distance

- **Source**: DMOJ problem `ecna05b` (2005 East Central North America Regional Programming Contest)
- **Core Idea**: Given a general (n-ary) family tree and a distance `d`, compute for every node how many descendants it has at exactly distance `d` edges below it. Output the nodes with the highest such scores, following specific tie-breaking and count rules.
- **Approach**: Build the tree incrementally from unordered input lines using an array of `node *` pointers and a `find_node` linear search. Each node stores `name`, `num_children`, a `children` array, and a `score`. Because lines can arrive in any order, nodes may be created before their parent-child relationships are fully known. The `num_children` is filled in only when that node's own line is processed. Score each node with `score_one(node *n, int d)`: the base case is `d == 1`, returning `n->num_children`, and the recursive case sums `score_one(child, d-1)` over all children. After scoring all nodes with `score_all`, sort using `qsort` with a comparator that orders by descending score, then alphabetically by name on ties. Output up to three nodes plus all ties at the third score level using nested while loops.
- **Complexity**: `score_one` for a single node is O(n) in the worst case (it traverses the subtree up to depth `d`). Calling `score_all` on all `n` nodes is O(n²) in the worst case. `qsort` is O(n log n). With n ≤ 1,000, this is well within the 0.6-second time limit.
- **Key Insight**: To count descendants at distance `d` from node `n`, do not look at children at distance `d` directly. Instead, ask each child how many descendants *it* has at distance `d-1`. This reduces the problem by one level at each recursive call, until the base case (`d == 1`) is reached where the answer is simply `num_children`.

---

## Algorithm Patterns

- **Recursive Tree Processing (Two-Rule Pattern)**: Almost every function on a tree follows the same skeleton: Rule 1 handles the leaf/base case and returns a simple value, and Rule 2 handles the internal node/recursive case by combining results from recursive calls on the left and right (or all) subtrees. Identifying which two rules apply is the core design step. Functions `tree_candy`, `tree_nodes`, `tree_leaves`, `tree_streets`, `tree_height`, and `score_one` all follow this pattern.

- **Overshoot-and-Correct**: When the optimal version of a problem is hard to compute directly (e.g., minimum streets without returning to root), solve a slightly relaxed version that is easy (streets with mandatory return to root), then subtract the known overshoot (tree height). This works whenever you can characterize the difference between the relaxed and optimal answers analytically.

- **Recursive String Parsing with Position Pointer**: When parsing a recursively structured string (like a tree encoded as nested parentheses), use a helper function that takes an `int *pos` parameter tracking the current parse position. The recursive call advances `*pos`. The caller reads the updated position to know where to continue. This eliminates the need to pre-scan string lengths and makes the parser mirror the grammar of the string format exactly.

- **Incremental Tree Building from Unordered Input**: When input lines describe a tree but may arrive in arbitrary order, maintain a flat array of all known nodes. Use `find_node` (or a hash table) to check for existing nodes before creating new ones. Set `num_children = 0` as a default. Fill it in only when that node's own line is processed. Parent-child links are wired as lines are read, regardless of order.

- **When to Use Recursion**: The clearest signal is: "If someone told me the answers for the smaller subproblems, could I easily compute the answer for the whole problem?" If yes, recursion applies. Tree problems almost always satisfy this condition because a tree is defined recursively (a root plus subtrees).

- **Stack vs. Recursion for Tree Traversal**: Both are O(n). An explicit stack requires manually tracking pending subtrees and control flow. Recursion eliminates this bookkeeping by using the call stack implicitly. For anything beyond trivial tree traversal, recursion is strongly preferred. The book uses the explicit-stack approach only to motivate why recursion is superior.

---

## Common Pitfalls

- **Forgetting to return the recursive result**: Writing `tree_candy(tree->left) + tree_candy(tree->right)` without `return` silently discards the computed value. Always `return` the expression from a recursive case.

- **Infinite recursion from a non-shrinking call**: Calling `return tree_candy(tree)` instead of recursing on a subtree creates an infinite loop. The recursive call must be on a strictly smaller subproblem (a child or subtree, never the same node).

- **Uninitialized `left`/`right` pointers**: Newly allocated nodes must have `left = NULL` and `right = NULL` explicitly set. Uninitialized pointers contain garbage values. Dereferencing them causes undefined behavior.

- **Printing a pointer as an integer**: `printf("%d\n", node->left)` prints a raw address, not a candy value. Always dereference to the intended field.

- **Accessing `candy` on a non-house node**: Non-leaf nodes have uninitialized `candy`. The `candy` field is only meaningful for house (leaf) nodes. Guard with a `left == NULL && right == NULL` check before reading `candy`.

- **Off-by-one in `pos` advancement**: In the recursive string parser, failing to advance past the opening parenthesis, the space between subtrees, or the closing parenthesis will misalign subsequent parsing. Each structural character must be explicitly skipped with `(*pos)++`.

- **Freeing vs. reusing the name string**: In `read_tree` for Descendant Distance, when a node is found to already exist in the array, the newly allocated `parent_name` or `child_name` buffer must be freed (since the existing node already has its own name pointer). Failing to free it leaks memory.

- **Casting in `qsort` comparators**: Because `qsort` passes pointers to array elements, and the array holds `node *` values, the correct cast is `const node *n = *(const node **)v`, not `*(const node *)v`. Getting this wrong causes a crash or silent misread.

- **Trying to trace recursive calls mentally**: The book explicitly warns against this. Reasoning about recursion at the level of individual call frames is error-prone and unnecessary. Work at the level of the recursive rules ("what does this function return for a leaf? for a non-leaf?") rather than simulating execution.

---

## Connections to Other Chapters

- **Chapter 1 (Unique Snowflakes / Hash Tables)**: The `node` struct for binary trees mirrors the linked-list node from Chapter 1, replacing a single `next` pointer with `left` and `right` pointers. The `find_node` linear search in Descendant Distance is explicitly flagged as a candidate for replacement with a hash table (as introduced in Chapter 1) for better performance.

- **Chapter 3 (Memoization and Dynamic Programming)**: Chapter 2 closes by noting that recursion sometimes recomputes the same subproblems. Chapter 3 builds directly on this chapter's recursion foundation by introducing memoization, caching recursive results to avoid redundant work, and dynamic programming. The author signals that the question of "when do subproblems overlap?" will be central there.

- **General Recursion Theme**: The two-rule (base case / recursive case) pattern introduced here is the structural foundation for all subsequent chapters that involve divide-and-conquer, dynamic programming, or any algorithm that decomposes a problem into smaller instances of the same problem.
