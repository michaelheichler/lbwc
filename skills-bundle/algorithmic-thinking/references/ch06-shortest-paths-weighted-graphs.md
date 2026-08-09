# Chapter 6: Shortest Paths in Weighted Graphs

## Key Concepts

- **Weighted Graph**: A graph where each edge carries a numeric weight (e.g., time, distance, cost). The shortest path is the one that minimizes the total sum of edge weights along the path, not the number of edges. BFS cannot find shortest paths in weighted graphs when edge weights vary arbitrarily.

- **Dijkstra's Algorithm**: A greedy algorithm for solving the single-source shortest-paths problem on weighted graphs with non-negative edge weights. It maintains a `done` flag and a `min_time` (or `min_distance`) value for each node, progressively "finalizing" nodes in order of increasing shortest path distance from the source. Once a node is set to done, its shortest path is guaranteed correct and never changes.

- **`done` Array**: A boolean array where `done[i] = 1` means the shortest path to node `i` has been finalized. The key invariant: the not-done node with the smallest `min_times` value always has its true shortest path already in `min_times`, so it can safely be set to done next.

- **`min_times` / `min_distances` Array**: Stores the current best known shortest path distance from the source to each node. Initialized to `-1` (meaning "not yet reached") for all nodes except the source (initialized to `0`). Updated whenever a shorter path is discovered via a newly done node's outgoing edges.

- **Adjacency List Representation**: The primary graph representation used in this chapter. An array of linked lists, where `adj_list[i]` points to a chain of `edge` structs, each containing `to_cell`/`to_town`, `length`, and `next`. Directed graphs only add edges in one direction. Undirected graphs add edges in both directions.

- **Adjacency Matrix**: An alternative graph representation used in the Grandma Planner problem. A 2D array where `matrix[i][j]` gives the weight of the edge from node `i` to node `j`. Every row `i` lists all edges from node `i`. For undirected graphs, the matrix is symmetric. Can be read directly or converted to adjacency lists.

- **Complete Graph**: A graph where there is an edge between every pair of nodes. The Grandma Planner problem's graph is a complete graph, so there are no missing edges to skip.

- **Reversed Graph Optimization**: For problems requiring shortest paths from all nodes to a single target (e.g., exit cell), run one Dijkstra invocation from the target on the reversed graph, rather than running Dijkstra from every node. The reversed graph swaps edge directions: an edge `a → b` in the original becomes `b → a` in the reversed graph, with the same weight. This reduces `n` Dijkstra runs to one.

- **State-Augmented Graph**: A technique for modeling problems with additional conditions beyond simple node position. A second dimension (the "state") is added to every node, effectively doubling (or more) the number of nodes. Dijkstra's algorithm then runs on this expanded node space. Introduced here to handle the requirement of passing through a cookie store before reaching the destination.

- **Single-Source Shortest Paths**: Finding shortest paths from one source node to all other nodes. Dijkstra's algorithm solves this problem.

- **All-Pairs Shortest Paths**: Finding shortest paths between every pair of nodes. Achievable by running Dijkstra `n` times (once per source) for O(n³) total, matching the Floyd-Warshall algorithm.

- **Negative-Weight Edges**: Dijkstra's algorithm is invalid when edges have negative weights. The greedy "finalize the minimum" argument breaks down because a later-discovered negative edge could create a shorter path to an already-finalized node. The Bellman-Ford algorithm or Floyd-Warshall algorithm handle negative weights.

- **Number of Shortest Paths (Path Counting)**: An extension to Dijkstra's algorithm that tracks, alongside `min_distances`, a `num_paths` array. Two rules govern updates: (1) if a strictly shorter path to node `v` is found via node `u`, reset `num_paths[v]` to `num_paths[u]`. (2) If a path of equal distance to `v` is found via `u`, add `num_paths[u]` to `num_paths[v]`. The condition for updating must use `>=` rather than `>` to catch equal-distance paths.

- **Modular Arithmetic in Path Counting**: Because the number of shortest paths can be astronomically large, the problem specifies that counts should be reported modulo 1,000,000. After each update to `num_paths`, apply `%= MOD` to keep values bounded.

- **Tie-Breaking with 0-Weight Edges**: When 0-weight edges exist (as from State-0 cookie towns to State-1 in Grandma Planner), correctness of path counting requires processing State-0 nodes before State-1 nodes when their distances are equal. The nested loop structure in the code (iterating `state` from 0 to 1 inside the outer loop, with last-found winner) naturally achieves this, but it must be verified carefully.

## Problems Covered

### Problem: Mice Maze
- **Source**: UVa problem 1112 (originally from the 2001 Southwestern Europe Regional Contest)
- **Core Idea**: A directed weighted graph of maze cells and passages. Each mouse starts in its own cell and must reach the designated exit cell. Given a time limit, count how many mice can reach the exit within that limit.
- **Approach**: For each cell, run Dijkstra's algorithm from that cell to find the shortest time to the exit. Count cells whose shortest path time is between 0 and the time limit inclusive. Returns `-1` from `find_time` when no path exists. An optimized approach builds the reversed graph and runs Dijkstra once from the exit cell, finding shortest distances from the exit to all other cells.
- **Complexity**: Naive approach: O(n³), running O(n²) Dijkstra `n` times. Optimized reversed-graph approach: O(n²), one Dijkstra invocation on a graph of `n` nodes.
- **Key Insight**: Instead of running Dijkstra from every cell to the exit (n separate runs), reverse the graph's edges and run Dijkstra once from the exit cell. The single-source shortest paths in the reversed graph give exactly the shortest times from each cell to the exit in the original graph.

### Problem: Grandma Planner
- **Source**: DMOJ problem `saco08p3` (originally from the 2008 South African Programming Olympiad, Final Round)
- **Core Idea**: Bruce travels from Town 1 to Town `n` in an undirected weighted complete graph, but must pass through at least one town with a cookie store. Find both the minimum travel distance and the number of minimum-distance routes (mod 1,000,000).
- **Approach**: Model the problem with a state-augmented graph: each town exists in two states, State 0 (no cookies) and State 1 (has cookies). From any State-0 cookie town, add a 0-weight directed edge to its State-1 counterpart. All regular road edges exist in both State 0 and State 1 separately, but transitions only go from State 0 to State 1 (never back). Run Dijkstra on this doubled graph starting from (Town 1, State 0). The answer is the shortest path to (Town `n`, State 1). Track `num_paths` alongside `min_distances` by applying the two path-counting rules and taking mod 1,000,000 after every update.
- **Complexity**: O(n²) in the number of towns `n` (Dijkstra on a graph of 2n nodes, each with up to 2n edges).
- **Key Insight**: The same town can be visited twice in a valid path, once without cookies (State 0) and once with cookies (State 1), without creating a true cycle, because the two visits differ in state. Treating (town, state) pairs as distinct nodes cleanly handles this. Additionally, the path-count update condition must use `>=` (not `>`) so that equal-length paths are also accumulated, not just strictly shorter ones.

## Algorithm Patterns

- **Dijkstra's Algorithm Template**: Initialize `done[i] = 0` and `min_times[i] = -1` for all nodes. Set `min_times[source] = 0`. Outer loop runs up to `n` times. Inner loop scans all not-done nodes with `min_times >= 0` to find the one with minimum `min_times`, then set it to done. Then walk its adjacency list: for each neighbor, if `old_time == -1 || old_time > min_time + edge_length`, update `min_times[neighbor]`.

- **Graph Reversal for Single-Target Problems**: When the problem asks "what is the shortest path from every node to a single target T?", build the reversed graph (flip all edge directions) and run Dijkstra once from T. The result gives shortest distances from T in the reversed graph, which equal shortest distances to T in the original graph.

- **State Augmentation**: When the shortest path problem has a conditional requirement (must visit a certain type of node, must carry an item, etc.), augment each node with a state dimension. Nodes become (location, state) pairs. Add 0-weight directed transitions between states at qualifying nodes. Run Dijkstra on the augmented graph. This is the weighted-graph analog of the BFS state expansion seen in Chapter 5's Rope Climb problem.

- **Counting Shortest Paths with Dijkstra**: Augment Dijkstra with a `num_paths` array initialized to 0 everywhere except the source (set to 1). During edge relaxation, change the condition from `old > new` to `old >= new`. If the new distance is strictly less than old, reset `num_paths[neighbor] = num_paths[current]`. If the new distance equals old, add: `num_paths[neighbor] += num_paths[current]`. Apply modular reduction after every update.

- **Recognizing When to Use Dijkstra vs. BFS**: Use Dijkstra when edge weights are arbitrary positive integers and the goal is to minimize total weight (not edge count). Use BFS when minimizing edge count or when edge weights are constrained (0 or 1 only, as in Rope Climb). Dijkstra can handle unweighted graphs (set all weights to 1), but BFS is simpler and faster in that case.

- **Adjacency List Clearing Between Test Cases**: When solving multiple test cases in one program run, always reset `adj_list[i] = NULL` for every node at the start of each test case. Failing to do so causes edges from prior test cases to persist, a subtle, hard-to-debug error.

- **Reading Adjacency Matrix into Adjacency List**: Use a double loop over `from_node` and `to_node`. Skip self-edges (`from_node == to_node`). For symmetric (undirected) matrices, both directions are read naturally by iterating over all rows, so no special handling is needed for the reverse edge.

## Common Pitfalls

- **Forgetting to clear the adjacency list between test cases**: If `adj_list[i]` is not reset to `NULL` before each test case, edges from previous test cases accumulate, corrupting the graph. The book explicitly warns: "Not doing that results in a horrible bug where each test case includes edges from prior test cases."

- **Using BFS on an arbitrary weighted graph**: BFS minimizes edge count, not total weight. On a graph where the minimum-weight path uses more edges than a heavier path, BFS will return the wrong answer.

- **Applying Dijkstra to graphs with negative-weight edges**: The algorithm's core correctness argument, that the not-done node with the smallest `min_times` has its true shortest path, fails when negative edges exist. A later node could offer a shorter path through a negative edge back to an already-finalized node.

- **Missing the `>=` condition when counting paths**: Using `old_distance > new_distance` instead of `old_distance >= new_distance` means equal-length paths are never counted, causing the path count to be wrong (typically undercounting).

- **Incorrect tie-breaking with 0-weight edges**: When 0-weight edges connect State-0 nodes to State-1 nodes (as in Grandma Planner), State-0 nodes must be processed before State-1 nodes when distances are equal. The natural code ordering (iterating state 0 before state 1 in the minimum-finding loop) achieves this, but swapping the order produces wrong path counts while leaving the minimum distance correct.

- **Infinite path counts with 0-weight cycles**: If the graph had 0-weight cycles, there would be infinitely many shortest paths (traverse the cycle any number of times). The book notes this cannot happen in Grandma Planner because 0-weight edges only go from State 0 to State 1, and there is no way to return from State 1 to State 0, so no 0-weight cycle is possible.

- **Not returning `-1` for unreachable nodes**: Dijkstra's algorithm only computes shortest paths for nodes that are reachable from the source. If a node's `min_times` remains `-1`, it means the node was never discovered. The `find_time` function returns `-1` in this case, and the caller must check for it before comparing to the time limit.

## Connections to Other Chapters

- **Chapter 5 (BFS and Unweighted Shortest Paths)**: Dijkstra's algorithm is explicitly positioned as the generalization of BFS to weighted graphs. Both solve single-source shortest paths: BFS on unweighted graphs, Dijkstra on weighted graphs. The state-augmentation technique (adding an extra dimension to nodes to encode conditions like "carrying an item") was introduced in Chapter 5 (Rope Climb problem) and reused here with Dijkstra instead of BFS.

- **Chapter 8 (Heaps)**: The book previews that heaps provide the most dramatic general speedup for Dijkstra's algorithm. The current O(n²) implementation uses a linear scan to find the next minimum node. A heap-based priority queue with lazy deletion (no decrease-key) reduces this to O(m log m) where `m` is the number of edges. This improvement is deferred to Chapter 8 and demonstrated in Appendix B.

- **Chapter 1 (Hash Tables)**: The O(n²) quadratic runtime of Dijkstra is placed in context alongside Chapter 1's discussion of quadratic algorithms. The book notes that while O(n²) was inadequate for Unique Snowflakes (Chapter 1), it is acceptable here because a single Dijkstra run solves `n` shortest-path subproblems simultaneously.

- **Floyd-Warshall Algorithm (mentioned but not implemented)**: The book names Floyd-Warshall as an O(n³) all-pairs shortest-paths algorithm that also handles negative edge weights (without negative cycles). Running Dijkstra `n` times achieves the same O(n³) all-pairs result but without negative-weight support.

- **Bellman-Ford Algorithm (mentioned but not implemented)**: Named as the correct algorithm for graphs with negative-weight edges, where Dijkstra fails. Not covered in detail in this chapter.
