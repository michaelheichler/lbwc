# Chapter 5: Graphs and Breadth-First Search

## Key Concepts

- **Breadth-First Search (BFS)**: BFS explores all positions reachable in zero moves, then one move, then two moves, and so on, processing the full range (breadth) of reachable nodes before advancing to the next distance level. It is the canonical algorithm for finding the minimum number of edges (moves) between a starting node and any other node in an unweighted graph. The runtime is linear in the number of edges reachable from the starting node.

- **Graphs**: A graph consists of nodes (vertices) and edges between them. Unlike trees, graphs can contain cycles (paths that return to the starting node), can be directed (edges have a specified direction of travel), and can be disconnected (not all nodes are reachable from all others). Every tree is a graph, but not every graph is a tree.

- **Undirected vs. Directed Graphs**: An undirected graph allows travel along an edge in both directions. A directed graph restricts travel to only the specified direction. Knight moves on a board form an undirected graph (you can undo a move). Course prerequisites form a directed graph (Software Design → C Programming, not the reverse).

- **Connected vs. Disconnected Graphs**: A connected graph allows travel from any node to any other node. A disconnected graph has at least one pair of nodes with no path between them. The BFS algorithm naturally handles disconnected graphs. Nodes unreachable from the source simply never get their distance recorded (remain -1).

- **Weighted Graphs**: A weighted graph assigns a cost or weight to each edge. The Book Translation problem introduces weighted edges (translation costs). Standard BFS finds paths minimizing the number of edges. When edges have weights, more specialized algorithms are needed (covered in Chapter 6). However, BFS is still useful when minimizing edge count first and minimizing total weight second (a lexicographic objective).

- **Single-Source Shortest Paths**: BFS solves the single-source shortest-paths problem: given one starting node, it finds the shortest path (in number of edges) from that node to every other node in the graph. One BFS call from a fixed source populates a `min_moves` array for the entire board or graph.

- **Adjacency List**: An adjacency list represents a graph as an array where each index (node) stores a linked list of its outgoing edges. Each `edge` struct contains the destination node (`to_lang`) and edge weight (`cost`), plus a pointer to the next edge in the list. Adjacency lists are preferred over adjacency matrices when edges are sparse relative to the number of possible edges.

- **0-1 BFS**: A variant of BFS for graphs whose edges cost either 0 or 1. Free (zero-cost) edges connect nodes that belong to the same BFS round (same distance from the source). When a free edge is followed, the new position is added to `cur_positions` (the current round), not `new_positions` (the next round). One-cost edges add to `new_positions` as in standard BFS. This allows BFS to correctly handle mixed-cost graphs without Dijkstra's algorithm.

- **Graph Modeling**: The key insight is that the same BFS code structure applies across radically different problem domains (chess boards, ropes, translation networks). The art is in identifying the nodes (states) and edges (allowed moves) that correctly model the problem. The graph does not need to mirror the real-world structure one-for-one. A different graph that produces the same answer can be used if it has fewer edges and runs faster.

- **State Nodes**: When a position alone is insufficient to capture the full state of a system, a "state" dimension is added to the node representation. In Rope Climb, Bob's position is (height, state), where state 0 means he is on the real rope and state 1 means he is in a "falling" mode. Adding a state dimension converts an O(h²) edge-count problem into O(h).

- **BFS vs. Dynamic Programming**: Both BFS and DP avoid recomputation by storing previously computed values. The distinction: DP applies when subproblems combine without cycles (always recurse into strictly smaller subproblems). BFS applies when the state space can cycle. If you can get back to a previously visited state, use BFS rather than DP.

- **Parity of Knight Moves**: Each knight move changes the parity of exactly one of the two coordinates (row or column). Therefore, if the minimum number of moves from point A to point B is `m`, then B is also reachable in `m + 2`, `m + 4`, etc. moves, but never in `m + 1`, `m + 3`, etc. moves. The parity of reachability is fixed by `m`.

---

## Problems Covered

### Problem: Knight Chase
- **Source**: DMOJ `ccc99s4` (1999 Canadian Computing Competition)
- **Core Idea**: A pawn marches up its column one row per turn. A knight (up to 8 moves) tries to land on the pawn (win) or the square above the pawn (stalemate). Determine the best achievable outcome and the minimum number of knight moves to reach it.
- **Approach**: Run BFS once from the knight's starting square to compute the minimum number of moves to every board square. Then simulate the pawn's march, checking at each pawn position whether the knight can reach it in the same parity of moves (accounting for the +2 loopback trick). Check wins first. If no win is possible, check stalemates.
- **Complexity**: One BFS call costs O(r·c) time (at most 8 edges per node). Checking pawn positions is O(r). Overall: O(r·c) time, O(r·c) space for `min_moves`.
- **Key Insight**: The knight can reach a square in minimum `m` moves but also in `m+2`, `m+4`, … moves (by leaving and returning). The correct win/stalemate condition is `knight_takes >= 0 && num_moves >= knight_takes && (num_moves - knight_takes) % 2 == 0`, not simply `knight_takes == num_moves`. Eliminating the early-exit optimization (computing all distances in one BFS call instead of one call per pawn position) gives a 5× speedup.

### Problem: Rope Climb
- **Source**: DMOJ `wc18c1s3` (2018 Woburn Challenge, Online Round 1, Senior Division)
- **Core Idea**: Bob starts at height 0 and must reach height ≥ h. He can jump up exactly j meters (one move) or fall any number of meters (one move). Some rope segments have itching powder and cannot be landed on. Find the minimum number of moves.
- **Approach (Solution 1, TLE)**: Model the rope as a 1D board up to height 2h. Run one BFS using j as the single jump edge and a loop over all lower heights as fall edges. This is correct but O(h²) due to the quadratic number of fall edges.
- **Approach (Solution 2, Accepted)**: Introduce a second "rope" (state dimension). State 0 = real rope. State 1 = falling mode. Moving from state 0 to state 1 costs 1 move. Falling one meter within state 1 costs 0 moves. Moving from state 1 back to state 0 costs 0 moves (only allowed at non-itchy heights). Use 0-1 BFS: free-edge moves go into `cur_positions`. Cost-1 moves go into `new_positions`. This reduces edges to O(h) and passes within the 1.8-second limit.
- **Complexity**: O(h) time and space with the two-state model.
- **Key Insight**: Any multi-step fall can be decomposed into free unit-falls along a virtual second rope, so the total cost remains one move regardless of fall distance. The graph need not mirror the real problem structure. An equivalent graph with fewer edges gives the same answer faster.

### Problem: Book Translation
- **Source**: DMOJ `ecna16d` (2016 East Central North America Regional Programming Contest)
- **Core Idea**: Translate a book from English into n target languages via m bidirectional translators, each with a cost. Primary objective: minimize the number of translations to each target language. Secondary objective: among all minimum-translation solutions, minimize total cost.
- **Approach**: Model languages as nodes and translators as undirected weighted edges. Run BFS from English (node 0) to find the minimum number of translations to each language (`min_moves`). After each BFS round, scan the newly discovered languages and for each one find the cheapest edge that leads to it from the previous BFS round (edge cost used to discover it with minimum moves). Sum those cheapest-edge costs for all target languages. If any target is unreachable, output "Impossible".
- **Complexity**: O(n + m) for BFS (each edge traversed at most twice). O(n·m) in the worst case for the cost-selection pass (iterating edges of newly discovered nodes). Space: O(n + m) for the adjacency list.
- **Key Insight**: BFS handles the primary objective (minimum number of translations). The secondary cost objective is resolved by a separate pass after each BFS round: for each newly reached node, pick the minimum-cost incoming edge from a node one level closer to English. The graph must be stored explicitly as an adjacency list because it is given as input rather than implicitly defined by movement rules.

---

## Algorithm Patterns

- **BFS for Minimum Moves on an Implicit Graph**: When moves are defined by a rule (e.g., knight moves, jumps), build the graph implicitly during BFS. Maintain `cur_positions` and `new_positions` arrays. Initialize `min_moves` to -1. Set `min_moves[start] = 0`. Add start to `cur_positions`. Each round, call `add_position` for all neighbors. `add_position` only accepts a node if `min_moves[node] == -1` (not yet visited). Swap `new_positions` into `cur_positions` after each round.

- **Single Full-Board BFS**: Rather than calling BFS once per query destination (expensive), call BFS once with no early exit to populate `min_moves` for every node. Then answer all queries with O(1) lookups. Applies whenever multiple destinations share the same source.

- **0-1 BFS for Mixed-Cost Graphs**: When edges cost either 0 or 1, use 0-1 BFS. Free-edge destinations are appended to `cur_positions` (processed in the current round). Cost-1 edge destinations go into `new_positions` (processed in the next round). The `add_position` functions must use `pos` and `num_pos` as generic parameters (passed either `cur_positions` or `new_positions`) rather than hardcoded `new_positions`.

- **State-Augmented Graph**: When a single position value is insufficient to determine which moves are available, add a state dimension. Create a 2D board `min_moves[position][state]`. The `position` struct holds both the position and state. Use state transitions (some free, some costly) to model mode changes. The Rope Climb "two ropes" trick is a canonical example.

- **Bounding the Search Space**: For problems with no explicit upper bound, derive one from problem constraints. If the jump distance j ≤ h, then getting Bob to height ≥ 2h would mean the previous position was already ≥ h, making the extra jump redundant. Cap the BFS at `2h - 1`. Similar reasoning appeared in Chapter 3's Moneygrubbers (cap at `2 × quantity` when a single pricing scheme gives at most that many items).

- **Adjacency List for Explicit Graphs**: When the graph is given as input (nodes and edges listed), store it as an adjacency list: `edge *adj_list[MAX_NODES]` where each element is a linked list of `edge` structs. For undirected graphs, add two directed edges per input edge (A→B and B→A). Prepend to the linked list for O(1) insertion.

- **Two-Objective BFS (Min Edges, Then Min Cost)**: When the primary goal is minimum edge count and secondary goal is minimum cost, run standard BFS to get `min_moves`. Then for each newly discovered node per round, scan its adjacency list to find the minimum-cost edge that arrives from a node exactly one step closer (condition: `min_moves[neighbor] + 1 == min_moves[current]`). Store in a separate `min_costs` array.

- **When to Recognize a BFS Problem**: The problem asks for the minimum number of moves, steps, or transitions. There is a set of states and a set of allowed transitions between states. The transition costs are all equal (standard BFS) or 0/1 (0-1 BFS). Unlike DP problems, cycles are possible in the state space. The answer is "how many steps to go from state A to state B (or the best reachable B)."

---

## Common Pitfalls

### Off-by-One in Win/Stalemate Detection
Checking `knight_takes == num_moves` is too strict. The knight can delay by an even number of moves (leave and return to any square). The correct check is `knight_takes >= 0 && num_moves >= knight_takes && (num_moves - knight_takes) % 2 == 0`.

### Re-Visiting Already-Discovered Nodes
Failing to check `min_moves[to] == -1` before adding a node to `new_positions` causes nodes to be added multiple times, bloating the queue and potentially overwriting a correct (smaller) distance with a larger one. The check `min_moves[to] == -1` (or `> distance` in 0-1 BFS) is the guard against this.

### Multiple BFS Calls When One Suffices
Calling BFS once per query destination (as in the initial Knight Chase `solve` function) is far slower than calling BFS once to populate all distances. For a 99×99 board with repeated queries, multiple calls can result in 8r²c steps instead of 8rc steps.

### Quadratic Fall Edges in Rope Climb
Directly modeling "fall any distance" as individual edges creates h(h+1)/2 fall edges, quadratic in h, which causes TLE. The fix is to decompose falls into unit steps along a virtual second rope with zero-cost edges.

### Incorrect 0-1 BFS Routing of Free Edges
In 0-1 BFS, free-edge destinations must go into the current round (`cur_positions`), not the next round (`new_positions`). Routing them to `new_positions` inflates their distance by 1, producing wrong minimum-move counts.

### Undirected Graph Requires Two Directed Edges
For an undirected graph stored as an adjacency list, each bidirectional relationship must be stored as two directed edges (A→B and B→A). Storing only one direction means BFS cannot traverse the edge in the other direction.

### Language Name Length Unknown
When input string lengths are unknown, a fixed buffer can overflow. Use a dynamically resizing `read_word` function that starts at a small buffer (e.g., 16 bytes) and doubles via `realloc` when the buffer fills.

### Confusing Nodes and Edges in Graph Design
In trees (Chapter 2), nodes carry data and edges are structural. In weighted graph problems like Book Translation, edges carry data (translation costs) and nodes are plain identifiers. Choose `struct edge { int to_lang, cost; struct edge *next; }` rather than a node-centric design.

---

## Connections to Other Chapters

### Chapter 1 (Unique Snowflakes)
The formula for total fall edges, h(h+1)/2, is the same quadratic O(h²) formula seen when counting pairs of snowflakes. Recognizing this pattern signals that a quadratic approach will be too slow for large inputs.

### Chapter 2 (Trees)
Trees are introduced in Chapter 2 using node-centric structs with `left`/`right` child pointers. Chapter 5 generalizes to graphs by using edge-centric linked-list adjacency lists. Trees are acyclic connected graphs. The absence of cycles in trees is what makes recursive DP safe in Chapter 2.

### Chapter 3 (Dynamic Programming / Memoization)
BFS uses the same "store and look up" trick as memoization to avoid recomputation. The distinction is cycles: DP requires no cycles in the subproblem dependency graph. BFS handles cycles explicitly via the visited-check (`min_moves[node] == -1`). The upper-bound capping technique (stop at 2h) mirrors the Moneygrubbers technique (buy at most 2×quantity apples).

### Chapter 4 (Advanced Memoization and Dynamic Programming)
Chapter 4's Jumper problem appears to have cycles but does not: jumping right increases the jump distance monotonically, so no true cycle exists. Chapter 5 explicitly shows why BFS is needed when cycles are present and DP is not applicable.

### Chapter 6 (Weighted Shortest Paths)
Chapter 5 notes that minimizing total translation cost (without the min-edges constraint) requires more powerful tools introduced in Chapter 6, specifically Dijkstra's algorithm for weighted shortest paths. BFS is the special case where all edge weights are equal (or 0/1 for 0-1 BFS). Chapter 6 generalizes to arbitrary non-negative weights.

### Appendix B (Knight Chase Move Encoding)
Appendix B shows a code-simplification technique for encoding the eight knight moves as a delta array rather than eight separate `add_position` calls. This reduces code repetition when a node has many structurally similar move options.
