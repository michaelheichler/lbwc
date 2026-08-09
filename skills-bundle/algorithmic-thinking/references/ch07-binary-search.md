# Chapter 7: Binary Search

## Key Concepts

- **Binary Search (on the Answer)**: Binary search in this chapter is not used to search a sorted array. Instead, it is used to find an optimal value in a large continuous or integer range by repeatedly halving that range. The chapter never searches a sorted array. All four problems use binary search to convert a hard optimization problem into a series of tractable feasibility checks.

- **Two Ingredients for Binary Search Applicability**: A problem fits binary search when it has two properties: (1) finding the optimal solution directly is hard, but checking whether a proposed value is feasible is easy, and (2) the search space has a clean infeasible-then-feasible (or feasible-then-infeasible) split, with no alternation. If a value `v` is feasible, then all values on the same side of `v` are also feasible, so half the range can be discarded on each step.

- **Invariant-Based Binary Search Design**: Correctly implementing integer binary search requires maintaining a precise invariant throughout the loop. The standard form is: `low` and everything below it shares one property (e.g., feasible), and `high` and everything above it shares the opposite property (e.g., infeasible). The loop runs while `high - low > 1`, and the answer is whichever endpoint the invariant guarantees has the desired property. Violating this discipline leads to subtle off-by-one bugs.

- **Logarithmic Time Complexity**: Binary search takes O(log m) iterations to reduce a range of width `m` to 1. For m = 2,000,000,000, that is about 31 iterations. For four decimal digits of accuracy, the effective range width is multiplied by 10^4, giving about 48 iterations. This makes the technique practical even for ranges in the billions or trillions.

- **Floating-Point Binary Search**: When the optimal solution is a real number, the loop condition is `high - low > epsilon` (e.g., `0.00001` for four decimal digits of accuracy) rather than `high - low > 1`. The answer is reported as `high` (or `low`, since they are close by termination). Initialization must ensure `low` is certainly at or below the optimal and `high` is certainly at or above it.

- **Feasibility Check as the Core of Each Solution**: Binary search outsources all problem-specific logic to a feasibility-checking function. This function receives a proposed value and returns true/false. The complexity of the overall algorithm is O(feasibility_check_cost × log m). The feasibility function can use any technique: tree recursion, a greedy algorithm, dynamic programming, or a graph algorithm.

- **Greedy Correctness via Exchange Argument**: The chapter presents a rigorous exchange-argument proof that the left-to-right "remove if too close" greedy rule in the River Jump feasibility check is correct. The argument proceeds by assuming an optimal solution `S` that disagrees with greedy at some first rock and showing that either the optimal must agree with greedy, or a new optimal solution `U` can be constructed that does agree. This proof style is standard for establishing greedy correctness.

- **Two-Dimensional Prefix Sums**: A 2D prefix-sum array `sum[i][j]` stores the sum of all values in the rectangle from (0,0) to (i-1, j-1). Building it takes O(rc) time using the recurrence: `sum[i][j] = value[i-1][j-1] + sum[i-1][j] + sum[i][j-1] - sum[i-1][j-1]`. Any rectangle sum can then be answered in O(1): `sum[br][rc] - sum[tr-1][rc] - sum[br][lc-1] + sum[tr-1][lc-1]`. The array is indexed from 1 to allow safe boundary lookups without special-casing row 0 or column 0.

- **Value Transformation for Median Feasibility**: To check whether a rectangle contains a median at most `quality`, replace every grid value ≤ `quality` with -1 and every value > `quality` with +1. If the sum of a rectangle is ≤ 0, there are at least as many small values as large values, meaning the median is ≤ `quality`. This reduces a sorting-based O(n log n) per-rectangle operation to O(1) per rectangle (after O(rc) preprocessing), eliminating the need to sort at all.

- **Binary Search Without an Explicit Range (Cave Doors)**: Binary search can also identify an unknown element (a switch) among `n` candidates by halving the candidate set at each step. Instead of computing a midpoint of a numerical range, the algorithm partitions an index range [low, high] and toggles all switches in [low, mid]. One call to `tryCombination` determines whether the target switch lies in [low, mid] or [mid+1, high]. This finds any switch in ⌈log₂ n⌉ calls.

---

## Problems Covered

### Problem: Feeding Ants
- **Source**: DMOJ `coci14c4p4` (2014 Croatian Open Competition in Informatics, Round 4)
- **Core Idea**: A tree represents a liquid-distribution network with pipes carrying fixed percentage splits. Some edges are "superpipes" that square the liquid they receive. Given ant liquid requirements at the leaves, find the minimum amount of liquid to pour into the root so every ant is satisfied.
- **Approach**: Binary search on the amount of liquid poured (range [0, 2,000,000,000]). The feasibility check is a recursive tree traversal (`can_feed`) that simulates liquid flow downward, always activating superpipe squaring (since squaring is never harmful when ≥ 1 liter). The loop condition is `high - low > 0.00001` for four decimal digits of accuracy. `high` is printed as the answer.
- **Complexity**: O(n log m) where n is the number of tree nodes and m is the range width (2 × 10^9 × 10^4 ≈ 2 × 10^13 for four-decimal accuracy, giving ~48 iterations, and each iteration traverses the tree in O(n)).
- **Key Insight**: Squaring is always safe to apply: if a superpipe receives ≥ 1 liter, squaring increases the flow. If it receives < 1 liter, the downstream ants cannot be satisfied regardless of squaring, so the check already returns false. The feasibility of any value can thus be decided greedily without worrying about which superpipes to activate.

### Problem: River Jump
- **Source**: POJ 3258 (December 2006 USA Computing Olympiad, Silver Division)
- **Core Idea**: A river of integer length L has n rocks at integer positions. Remove at most m rocks (not the endpoints) to maximize the minimum distance between any consecutive pair of remaining rocks.
- **Approach**: Binary search on the minimum jump distance d (integer range [0, L+1]). The feasibility check (`can_make_min_distance`) uses a greedy left-to-right scan: keep the current rock if it is ≥ d from the last kept rock. Otherwise, remove it. Also check whether the last kept rock is < d from the end and remove it if so. Return true if total removals ≤ m. The invariant for the integer binary search is: `low` is feasible, `high` is infeasible. Initialize `low = 0` (always feasible) and `high = L + 1` (always infeasible because L+1 > L). Output `low` when `high - low == 1`. Rocks must be sorted before calling `solve`, using `qsort`.
- **Complexity**: O(n log L) where n is the number of rocks and L is the river length.
- **Key Insight**: Initializing `high = length + 1` (not `length`) is essential for correctness. When `m = 0` and no rocks exist, the answer is `L`, which requires `high` to start at `L + 1` so the feasible value `L` is not excluded from the start. The chapter debugs two incorrect implementations to illustrate this.

### Problem: Living Quality
- **Source**: DMOJ `ioi10p3` (IOI 2010, Problem 3)
- **Core Idea**: A city is an r×c grid where each cell has a unique quality rank (1 to rc). Given rectangle dimensions h×w (both odd), find the minimum median quality rank over all h×w sub-rectangles.
- **Approach**: Binary search on the quality cutoff `quality` (integer range [0, rc+1], invariant: `low` is infeasible (no qualifying rectangle) and `high` is feasible, output `high`). The feasibility check (`can_make_quality`) replaces each grid value with -1 (if ≤ quality) or +1 (if > quality), builds a 2D prefix-sum array in O(rc), then checks every h×w rectangle sum in O(1) per rectangle. If any rectangle sum is ≤ 0, return true. Total feasibility cost is O(rc). The `rectangle` function signature `int rectangle(int r, int c, int h, int w, int q[3001][3001])` is called directly by the judge, with no `main` or I/O.
- **Complexity**: O(rc log(rc)). Binary search runs O(log(rc)) iterations, and each feasibility check is O(rc).
- **Key Insight**: Replacing values with -1/+1 around a cutoff transforms the hard problem of finding a median (requires sorting) into easy rectangle-sum comparisons. The 2D prefix sum then makes each rectangle sum O(1) after O(rc) preprocessing, removing the fourth nested loop that made the naive approach O(m^4 log m).

### Problem: Cave Doors
- **Source**: DMOJ `ioi13p4` (IOI 2013, Problem 4)
- **Core Idea**: A cave has n doors and n switches. Each switch controls exactly one door. The correspondence and correct switch positions are unknown. A judge function `tryCombination(switch_positions[])` returns the first closed door index (or -1 if all open). Determine both correct positions and door-switch assignments using at most 70,000 calls to `tryCombination`, for up to n = 5,000 switches.
- **Approach**: Process each door in order 0..n-1. For door i, use binary search over the switches not yet assigned. Set all unassigned switches to one position, then call `tryCombination` to determine whether door i is open or closed. If open, flip all unassigned switches to close it. Then binary search [low, high] over switch indices: toggle all unassigned switches in [low, mid]. Call `tryCombination`. If door i is now open, the target switch is in [low, mid] (set `high = mid`, then flip [low, mid] back to re-close door). If door i is still closed, target is in [mid+1, high] (set `low = mid+1`, no flip needed). When `low == high`, the switch is found. Flip it once more to open door i permanently. Report with `answer(switch_positions, door_for_switch)`.
- **Complexity**: O(n log n) calls to `tryCombination`. Each of n doors requires at most ⌈log₂ n⌉ + 1 calls. For n = 5,000: ≤ 14 calls per door × 5,000 doors = 70,000 calls total, just within the limit.
- **Key Insight**: The 70,000 call limit and 5,000 door count together encode the solution: log₂(5,000) ≈ 13, and 13 × 5,000 = 65,000 < 70,000. Binary search is the only feasible approach. Linear search would require up to 5,000 calls per door, totaling ~12.5 million calls.

---

## Algorithm Patterns

- **Binary Search on the Answer**: Identify the optimal value you seek. Define a feasibility predicate `can_achieve(v)` that is monotone (all values below some threshold are infeasible, all above are feasible, or vice versa). Binary search over the range to find the boundary. The feasibility function contains the real algorithmic work. Recognition signals: the problem asks for a minimum or maximum value. Finding the optimal directly seems intractable. Given a proposed value, checking whether it can be achieved is straightforward. The answer space is monotone: "if X liters is insufficient, more is needed" or "if minimum distance d is achievable, any smaller d is also achievable."

- **Invariant-Based Integer Binary Search Template**: Maintain: `low` is feasible (or infeasible), `high` is infeasible (or feasible). Initialize so these hold unconditionally, often requiring `high = max_possible + 1`. Loop while `high - low > 1`. On each step, compute `mid = (low + high) / 2`, test `mid`, and update exactly one of `low` or `high` to `mid`. Output `low` (when invariant says low is feasible) or `high` (when invariant says high is feasible/smallest-feasible).

- **Floating-Point Binary Search Template**: Use `while (high - low > epsilon)` with `epsilon` set to one order of magnitude smaller than the required precision. Output either endpoint. They are indistinguishable at the required precision.

- **Value Transformation (-1/+1) for Median/Threshold Queries**: To check whether any region contains a median (or count of qualifying elements) at or below a threshold `q`: replace each value with -1 if ≤ q, +1 if > q. Sum over a region: ≤ 0 means the median is ≤ q. This converts order-statistics questions into sum questions, enabling prefix-sum acceleration.

- **2D Prefix Sums for Rectangle Queries**: Precompute `sum[i][j]` = sum of all `zero_one[r][c]` for `0 ≤ r < i, 0 ≤ c < j` (1-indexed, with row 0 and column 0 set to 0). Build in O(rc) with: `sum[i][j] = val[i-1][j-1] + sum[i-1][j] + sum[i][j-1] - sum[i-1][j-1]`. Query any rectangle (top_row..bottom_row, left_col..right_col) in O(1): `sum[bottom_row][right_col] - sum[top_row-1][right_col] - sum[bottom_row][left_col-1] + sum[top_row-1][left_col-1]`.

- **Binary Search to Identify an Unknown Element**: When n candidates each have an unknown boolean state affecting an observable outcome, binary search can identify the responsible candidate in O(log n) probes. Set up the probe to toggle an entire half of the candidate set. The result tells you which half contains the target.

- **Lock-In and Move Forward**: In Cave Doors, once a door-switch pair is identified and the door is opened, that switch is never changed again. This isolation pattern, permanently resolving one element before moving to the next, enables correctness across all subsequent iterations.

---

## Common Pitfalls

### Off-by-One in Integer Binary Search
The book debugs two consecutive broken implementations of River Jump's `solve` function. Printing `high` instead of `low` (or vice versa) is wrong, but so is an incorrect initialization. The fix is always to set up and maintain a precise invariant and initialize `high` to one past the known maximum feasible value. Do not guess at whether to output `low` or `high` without proving the invariant holds.

### Incorrect Initialization Boundaries
Setting `high = length` in River Jump (instead of `length + 1`) fails when the answer equals `length` exactly (e.g., when there are no intermediate rocks). The invariant must hold unconditionally at initialization, which sometimes requires using a sentinel value beyond the domain.

### Assuming Greedy Works Without Proof
The chapter presents a greedy algorithm for River Jump that looks intuitive (remove the two rocks that are closest together, picking the one closest to its other neighbor), then shows it is wrong with a counterexample. The correct greedy is for the feasibility check only, not for direct optimization. Always verify greedy correctness carefully.

### Incorrect Superpipe Decision in Feeding Ants
A student might think the superpipe squaring needs a case analysis (do we activate it or not?). The correct insight is that squaring is always beneficial when the liquid is ≥ 1, so always activating it produces the most liquid and the most conservative feasibility answer. The edge case where squaring < 1 makes it smaller is harmless: if there is less than 1 liter reaching a node, the ants below it cannot be satisfied regardless.

### Applying Binary Search When the Monotone Property Fails
Binary search requires a clean infeasible/feasible split with no alternation. If the feasibility function is not monotone (e.g., small values infeasible, middle values feasible, large values infeasible again), binary search produces wrong answers silently. Always verify monotonicity before applying the pattern.

### Exceeding Call Limits in Interactive Problems
In Cave Doors, a linear search uses O(n²) calls, far exceeding the 70,000 limit. The problem's parameters encode the expected complexity: always estimate call count before implementing a naive approach on interactive problems.

### Missing the Sort Step
In River Jump, rocks are read in arbitrary order. The greedy feasibility check requires them sorted by position. Forgetting `qsort` produces wrong outputs without an obvious error.

### Four Nested Loops Before Dynamic Programming
The naive feasibility check for Living Quality has four nested loops (rows × columns for rectangles, plus rows × columns per rectangle for summation), giving O(m^4). The 2D prefix sum eliminates two levels of nesting (the inner rectangle summation), reducing the check to O(m^2). Without this optimization the binary search delivers no net speedup over the naive sort-every-rectangle approach.

---

## Connections to Other Chapters

### Chapter 2 (Trees)
Feeding Ants reuses tree traversal with recursion and the adjacency-list-with-edge-struct representation introduced in Chapter 2. The `can_feed` function is a recursive descent analogous to the Halloween Haul and Descendant Distance tree functions. Chapter 7 extends tree problems by applying binary search on top of a tree traversal.

### Chapter 3 (Dynamic Programming / Greedy)
River Jump revisits the notion of greedy algorithms from the Moneygrubbers problem in Chapter 3 and shows that the apparently natural greedy fails. The feasibility check for Living Quality uses the same spirit of precomputed "prefix" tables as DP memoization, and Chapter 8 is mentioned as doing a deep dive into range queries. The book explicitly notes that some binary-search-solvable problems can also be solved by DP, but binary search is often easier to design.

### Chapter 5 (Graphs and Adjacency Lists)
Feeding Ants uses the adjacency-list and edge-struct representation from Chapter 5's Book Translation problem. The deliberate choice to store only forward edges (no backward edges) reflects the same reasoning about directed flow.

### Chapter 6 (Shortest Paths / Dijkstra)
The chapter notes that Dijkstra's algorithm is itself a greedy algorithm. It commits permanently to shortest-path decisions. This frames the greedy-correctness discussion in River Jump within the broader context of greedy algorithm design seen in Chapter 6.

### Chapter 8 (Range Queries, Forward Reference)
The one-dimensional and two-dimensional prefix-sum technique introduced in Living Quality is described as a preview of Chapter 8, which covers range queries in depth.

### Chapter 10 (Divide and Conquer / Merge Sort, Forward Reference)
The chapter's Notes section identifies binary search as a manifestation of divide and conquer (D&C). Chapter 10 will introduce multi-subproblem D&C algorithms (such as merge sort), where the binary search on a sorted array also appears.
