# Chapter 9: Union-Find

## Key Concepts

- **Union-Find (Disjoint Set Union) Data Structure**: A specialized data structure for tracking a collection of objects partitioned into disjoint sets. It supports two core operations: Union (merging two sets) and Find (identifying which set an element belongs to). It is far more efficient than general graph search (BFS/Dijkstra) for problems whose primary operations are merging groups and querying membership.

- **Representative / Root**: Each set has one designated representative element, stored as the root of a tree. The `find` function returns this representative by following `parent` pointers up the tree until `parent[i] == i`. Two elements are in the same set if and only if their representatives are equal.

- **Parent Array**: The union-find tree is stored as a flat `parent[]` array of size `n+1`. `parent[i]` is the parent of node `i`. A root node satisfies `parent[i] == i`. This representation supports only upward traversal (child to parent), which is all that is needed.

- **Size Array**: An auxiliary `size[]` array where `size[i]` records the number of elements in the set whose representative is `i`. Only the size at the root node is kept accurate. Used for (a) union by size optimization and (b) answering set-size queries in O(1) after a `find`.

- **Union by Size Optimization**: When merging two sets, always fold the smaller set into the larger set (swap roots if `size[set1] > size[set2]`). This keeps tree height bounded at O(log n), because the only way a node's depth increases is when its community is absorbed by a community at least as large, which can happen at most log n times before the community reaches size n.

- **Path Compression Optimization**: During `find`, after locating the root, make a second pass to set the parent of every node along the traversal path directly to the root. This flattens the tree so future `find` calls on those nodes take O(1). The two-pass implementation uses a `temp` variable to walk the path a second time.

- **Inverse Ackermann Function (α)**: When both union by size and path compression are used, the amortized cost per operation is O(α(n)), which is effectively constant (≤ 4 for any n that fits in a computer). This is the theoretical basis for calling union-find "nearly constant time."

- **Equivalence Relation**: Union-find is valid only when the relationship being tracked is an equivalence relation: reflexive (x relates to x), symmetric (x relates to y implies y relates to x), and transitive (x relates to y and y relates to z implies x relates to z). Friendship in Social Network satisfies all three, but enemyship does not, requiring augmentation.

- **Augmentation**: Adding extra information to an existing data structure to support new operations without fundamentally changing the core structure. In Friends and Enemies, the standard union-find is augmented with an `enemy_of[]` array (one enemy per set root) to track hostile relationships.

- **Union-Find vs. BFS**: BFS on an adjacency list is O(q²) for q operations on a dynamic graph, because it restarts from scratch each call and discards all previous work. Union-find is near-O(1) amortized per operation because it incrementally updates only what changes (one parent pointer per Union).

---

## Problems Covered

### Problem: Social Network
- **Source**: SPOJ problem SOCNETC
- **Core Idea**: Track n people (up to 100,000) in a dynamic social network. Support three operations: Add (make two people friends, merging communities), Examine (are two people in the same community?), and Size (how many people are in a given person's community?). A constraint m bans any Add that would create a community larger than m.
- **Approach**: Model as union-find. Each community is a set. `find` returns the representative of a person's community. `union_communities` merges two sets only if they are different and the combined size does not exceed m. The `size[]` array tracks community size at each root. Examine is two `find` calls compared for equality. Size is `size[find(person, parent)]`.
- **Complexity**: O(q · α(n)) time, O(n) space. The BFS-based Solution 1 is O(q²) and fails the time limit, while the union-find Solution 2 passes.
- **Key Insight**: BFS produces too much (shortest paths, not just connectivity) and remembers nothing (restarts on every query). Union-find inverts both properties: it stores only what it needs (set membership via parent pointers) and updates incrementally.

### Problem: Friends and Enemies
- **Source**: UVa problem 10158
- **Core Idea**: n people (up to 10,000), initially unknown relationships. Support four operations: SetFriends (record two people as friends), SetEnemies (record two people as enemies), AreFriends (are they definitely friends?), AreEnemies (are they definitely enemies?). Operations that conflict with known information output -1 and are ignored. The "enemy of an enemy is a friend" rule applies transitively.
- **Approach**: Augmented union-find. Maintain `parent[]` and `size[]` for the friend-group sets, plus `enemy_of[]` where `enemy_of[root]` stores one representative enemy of the set (or -1 if none). SetFriends performs two Unions: (1) union the two friend sets, and (2) if both have enemies, union those enemy sets. SetEnemies performs two conditional operations on each set: if the set has no enemy, record the other person as enemy. If it does have an enemy, union that existing enemy set with the other person's set. AreFriends is two `find` calls, and AreEnemies checks that `enemy_of[find(person1)]` is non-(-1) and that its find equals `find(person2)`.
- **Complexity**: O(q · α(n)) time, O(n) space with union by size and path compression.
- **Key Insight**: Although "enemy" is not an equivalence relation, enemy groups still form coherent sets because of the "enemy of an enemy is a friend" rule. Storing just one enemy per set root is sufficient: that one enemy's `find` gives the representative of the entire enemy group. When a SetFriends union causes two previously separate friend-groups to merge, their enemy groups must also merge.

### Problem: Drawer Chore
- **Source**: DMOJ problem coci13c5p6
- **Core Idea**: n items (up to 300,000) and d drawers (up to 300,000), each holding at most one item. Each item specifies Drawer A and Drawer B. Process items in order using five priority rules: (1) place in A if A empty, (2) place in B if B empty, (3) if A's chain terminates in an empty drawer, place in A, (4) if B's chain terminates in an empty drawer, place in B, (5) otherwise discard (SMECE). Output LADICA or SMECE per item.
- **Approach**: Union-find where each set represents drawers that form a chain terminating at a single empty drawer (the set's representative). The representative is always the one empty drawer in that chain. When an item is placed in drawer X using Rule 1/3, union X's set with Y's set keeping Y's representative (because X is now full). When an item is placed in Y using Rule 2/4, union Y's set with X's set keeping X's representative. When two drawers A and B are already in the same set and placement happens (Rules 3/4 on a set with an empty drawer), the empty drawer becomes full, so set the representative of the combined set to 0. A representative of 0 means the set has no empty drawer. Rules 3 and 4 detect a valid chain by checking `find(drawer, parent) > 0`. SMECE occurs when both finds return 0 or the drawers share a root with no empty slot. Union by size is NOT used because the choice of root is semantically significant (must be the empty drawer).
- **Complexity**: O(n · α(d)) time, O(d) space. Path compression is required (without it, TLE is observed).
- **Key Insight**: The "chain of drawers that terminates somewhere" concept maps exactly to a union-find set where the root is the terminal empty drawer. Rather than simulating the chain of item moves, union-find compresses all chain traversals into a single `find` call. Representing "no empty drawer available" as representative 0 (an invalid drawer index) elegantly handles the SMECE case without extra flags.

---

## Algorithm Patterns

- **Core Union-Find Template**: Use arrays `parent[]` and `size[]` of size `n+1` (or `n` if 0-indexed). Initialize `parent[i] = i` and `size[i] = 1`. The `find` function walks parent pointers to the root, with an optional second pass for path compression. The `union_sets` function calls `find` on both arguments, swaps if needed so the smaller set is absorbed into the larger, then sets `parent[smaller_root] = larger_root` and updates `size[larger_root]`.

- **Recognizing Union-Find Problems**: Ask: Is there a relationship between objects that is reflexive, symmetric, and transitive (an equivalence relation)? Are the primary operations "merge two groups" (Union) and "check if two objects are in the same group" (Find)? Is the graph dynamic (edges are added over time)? If yes to all three, union-find is likely the right tool.

- **When Union by Size Cannot Be Used**: When the root of a set carries semantic meaning that must be preserved (as in Drawer Chore, where the root is always the empty drawer), union by size cannot be applied because it would elect the wrong root. Path compression can still be used safely. In such cases, the union function always makes the second argument's root the new root.

- **Augmentation Pattern for Extended Relationships**: When the problem requires tracking a secondary relationship (like enemy groups in Friends and Enemies), augment the union-find with one extra pointer per root. Store one member of the related group at each root. This is sufficient because `find` on that stored member recovers the full group's representative. When two sets merge via a primary-relationship Union, propagate enemy pointers: if the surviving root has no enemy but the absorbed root did, copy the absorbed root's enemy pointer to the surviving root.

- **Sentinel Representatives for "Dead" Sets**: When a set transitions into a state where no valid operation can ever succeed (as in Drawer Chore after a cycle forms), assign that set a sentinel representative (e.g., 0) that cannot be confused with a real element. Subsequent `find` calls automatically return 0, allowing the caller to detect the invalid state in O(1).

- **Union Returning the New Root**: In problems where the caller needs to know which set survived a Union (e.g., to copy over augmented data such as enemy pointers), have `union_sets` return the representative of the merged set. This avoids a redundant `find` call immediately after the union.

---

## Common Pitfalls

- **Only update `size` at the root**: The `size[]` array is only accurate for root nodes. After a Union, the absorbed root is no longer a root, and its `size` value becomes stale. Always call `find` before reading `size` to ensure you're looking at a root.

- **Checking same-community before union**: When there is a constraint (like the maximum community size in Social Network), always check `community1 != community2` before attempting a Union. Unioning a set with itself would corrupt the `size` value.

- **Union by size requires swapping before linking**: The swap ensures `community1` is the smaller set and `community2` is the larger, so `parent[community1] = community2` always folds the smaller into the larger.

- **Path compression second loop off-by-one**: The second `while` loop in path compression uses `parent[person] != community` (not `parent[person] != person`) as the stop condition, so it processes all nodes from the original query node up to (but not including) the root.

- **enemy_of must be propagated on every Union**: In the Friends and Enemies problem, after unioning two friend-sets, if the surviving root has `enemy_of == -1` but the absorbed root had a valid enemy, you must copy the enemy pointer. Forgetting this leaves the combined set unable to find its enemies.

- **Do not use union by size when root identity matters**: In Drawer Chore, applying union by size would elect a full drawer as the set representative, breaking the invariant that the representative is always the empty drawer. The symptom would be incorrect LADICA/SMECE outputs.

- **Running BFS repeatedly on a dynamic graph is O(q²)**: The chapter demonstrates explicitly that BFS-per-query times out on large inputs. The fix is to switch to union-find, not to optimize the BFS.

- **`union` is a C reserved word**: The chapter names the union function `union_communities` or `union_sets` to avoid this conflict.

---

## Connections to Other Chapters

- **Chapters 5 and 6 (BFS and Dijkstra)**: Union-find solves a strict subset of the problems solvable by BFS/Dijkstra. BFS and Dijkstra compute distances between nodes, while union-find only answers reachability and group membership. When distance information is not needed and the graph is dynamic, union-find is dramatically faster. The chapter opens by explicitly comparing the two approaches on the Social Network problem, showing that BFS gives TLE while union-find passes easily.

- **Chapter 8 (Heaps and Segment Trees)**: Like heaps and segment trees, union-find stores a tree in a flat array. However, unlike binary heaps (which use index arithmetic `2i` and `2i+1` to navigate), union-find trees are not binary and use explicit parent pointers. The array-based tree representation is a recurring theme across all three chapters.

- **General Graph Modeling (Chapters 5-6)**: Every union-find problem has an underlying graph problem. The chapter notes explicitly that you could model any union-find problem with an adjacency list and BFS, but union-find is much faster for the constrained class of problems it handles. The skill of translating real-world relationships into graph nodes and edges (practiced in Chapters 5-6) is a prerequisite for recognizing when union-find applies.
