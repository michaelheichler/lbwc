# Chapter 4: Advanced Memoization and Dynamic Programming

## Key Concepts

- **Forward vs. Backward DP Formulation**
  Two complementary ways to define subproblems for the same problem. The *backward* formulation focuses on what the end of the optimal solution must look like (working from the target state inward toward a base case). The *forward* formulation focuses on where you are right now and what you can do next (working from a known starting state toward the goal). Both yield correct solutions. The forward formulation can eliminate the need for a final search over unknown parameters when the start of the solution is fully known but the end is not.

- **Two-Dimensional Subproblem Arrays**
  When a single subproblem parameter is insufficient to describe the state needed for recursion, two parameters are used. For The Jumper, both the current square and the most recent jump distance are required because neither alone determines which transitions are legal. This produces an `n × n` memo table (where `n` is the number of squares) and O(n²) time.

- **Three-Dimensional Subproblem Arrays**
  Some problems require three independent parameters to fully characterize a subproblem. Ways to Build tracks position in source string `a` (parameter `i`), position in target string `b` (parameter `j`), and the number of substrings remaining to use (parameter `k`). This yields an `m × n × k` memo table, where `m` = |a|, `n` = |b|.

- **"Exactly" vs. "At Most" Subproblem Parameters**
  Choosing whether a subproblem parameter means "exactly this value" or "at most this value" shapes the recurrence. For The Jumper, both the square and jump distance need to be "exactly" values because the next legal transition depends on precise knowledge of the current state. Using "exactly" can introduce the need for a post-processing search (iterating over unknown final parameters), while using "at most" can absorb that search into the subproblem itself.

- **Connectible Solutions**
  A concept introduced for The Jumper's backward formulation. Because the first jump is always fixed (Square 1 → Square 2 with distance 1), subproblems are defined only over solutions that are compatible with that fixed prefix. A solution is *connectible* if it could legally follow that initial jump. The cost of the initial jump is added back in a post-processing step.

- **Counting Solutions Instead of Optimizing**
  DP is not limited to min/max optimization. Ways to Build asks for the *number* of valid constructions. The recurrence accumulates counts by adding subproblem results together (instead of taking `min` or `max`), and all arithmetic is performed modulo 1,000,000,007 to prevent integer overflow.

- **Adding New Subproblems to Reduce Per-Subproblem Work**
  When a correct memoized solution is too slow due to a loop inside the recurrence, one strategy is to introduce additional subproblems that precompute the loop's aggregate result. This trades a larger memo table for O(1) per-subproblem work in the previously expensive step. The key insight is that the new subproblems can themselves be solved efficiently using the old subproblems, creating a mutually beneficial relationship.

- **Subproblem Dependency Order for Bottom-Up DP**
  When converting a memoized solution to an iterative bottom-up DP, the fill order must respect the dependency graph. For The Jumper (forward formulation), Option 1 requires a value from column `j + 1` and Option 2 from row `i` in the same column, so the correct fill order is columns from `n` down to `1`, and within each column rows from `1` to `n - 1`. Failing to identify the correct order produces incorrect results.

- **Sentinel Values in Memo Tables**
  This chapter uses two distinct sentinel values: `-2` means "not yet computed" (the uninitialized state), while `-1` means "already attempted but no valid solution exists." This two-value scheme is needed when `-1` is a meaningful result (impossible subproblem), which would be confused with the standard single-sentinel approach.

---

## Problems Covered

### Problem: The Jumper

- **Source**: DMOJ problem `crci07p2` (originally from the 2007 Croatian Regional Competition in Informatics)
- **Core Idea**: Nikola starts on Square 1 of an `n`-square row and must reach Square `n`. The first jump is always exactly 1 square to the right (to Square 2). Subsequent jumps may go right by (previous distance + 1) or left by (previous distance). Every landing incurs an entry cost. Find the minimum total cost.
- **Approach (Solution 1: Backward)**: Define `solve_ij(i, j)` as the minimum cost of a connectible path from Square 2 to Square `i` using a final jump distance of exactly `j`. For any target `(i, j)`, either Nikola jumped right from Square `i - j` (which required a prior distance of `j - 1`) or left from Square `i + j` (which required a prior distance of `j`). Base case: `(i=2, j=1)` costs 0. After solving all subproblems, iterate over all possible final jump distances `j` from 1 to `n`, calling `solve_ij(n, j)` and adding `cost[2]` to find the global minimum.
- **Approach (Solution 2: Forward)**: Define `solve(i, j)` as the minimum cost to travel from Square `i` (reached with jump distance `j`) to Square `n`. From `(i, j)`, Nikola can jump right to Square `i + j + 1` (new distance `j + 1`) or left to Square `i - j` (same distance `j`). Base case: `i == n` costs 0. The single entry point is `solve(2, 1)` plus `cost[2]`, requiring no final search over unknown parameters.
- **Complexity**: O(n²) time, O(n²) space for the memo array. With `n ≤ 1,000`, this is approximately 10⁶ operations, well within the 0.6-second limit.
- **Key Insight**: The forward formulation avoids the final loop over all possible ending jump distances that the backward formulation requires, because the starting jump distance (1) is known exactly. The trade-off is that forward formulations can require more careful reasoning about which subproblems feed into which. The bottom-up fill order for the forward DP is non-obvious: columns must be filled from `n` down to `1` (not left-to-right), because Option 1 depends on column `j + 1`.

---

### Problem: Ways to Build

- **Source**: DMOJ problem `noip15p5` (originally from the 2015 National Olympiad in Informatics in Provinces)
- **Core Idea**: Given source string `a`, target string `b`, and integer `k`, count the number of ways to build `b` by selecting exactly `k` non-overlapping, non-empty substrings of `a` (taken in order) and concatenating them. Output the count modulo 1,000,000,007.
- **Approach (Solution 1: Three-Parameter Memoization)**: Define `solve_ijk(i, j, k)` as the number of ways to choose exactly `k` substrings from `a[0..i]` to build exactly `b[0..j]`, with the constraint that the rightmost substring ends at `a[i]`. Two categories of solutions: (1) `a[i]` is a single-character final substring, so loop over all `q < i` summing `solve_ijk(q, j-1, k-1)`. (2) `a[i]` extends a longer final substring, so it equals `solve_ijk(i-1, j-1, k)`. Requires iterating over all `i` in a post-processing step to sum answers (since the rightmost character of `a` used is unknown). This is correct but O(m²nk) time, too slow for given constraints.
- **Approach (Solution 2: Auxiliary "Total" Subproblems)**: Introduce a paired subproblem `total(i, j, k)` = number of ways to choose exactly `k` substrings from `a[0..i]` to build `b[0..j]` (no restriction on where the rightmost substring ends). Store both `end_at_i` (old subproblem) and `total` (new subproblem) in a `pair` struct per memo cell. The Category 1 loop is eliminated: instead of summing `solve_ijk(q, j-1, k-1)` for all `q < i`, a single lookup of `total(i-1, j-1, k-1)` provides the same aggregate. Computing `total(i, j, k)` is then O(1) given `end_at_i(i, j, k)` and `total(i-1, j, k)`. The final answer is the single value `total(m-1, n-1, k)` with no outer loop needed.
- **Complexity**: Solution 1 is O(m²nk), too slow. Solution 2 is O(mnk) time and O(mnk) space. With `m ≤ 1,000`, `n ≤ 200`, `k ≤ 200`, this is at most 40,000,000 operations, feasible within 2 seconds.
- **Key Insight**: Adding more subproblems can *speed up* an existing DP solution rather than slow it down. The new `total` subproblems act as prefix sums over the first parameter of the old subproblems, converting an O(m) loop into an O(1) lookup. The two subproblem types have a mutually beneficial relationship: `end_at_i` uses `total` to skip a loop, and `total` is updated in O(1) using `end_at_i`.

---

## Algorithm Patterns

- **Forward vs. Backward as a Debugging/Design Tool**: Always try the backward formulation first if it feels natural (it mirrors standard recursive thinking). If you find yourself struggling because the problem description is naturally forward-directed (i.e., you know the start state precisely but not the end state), switch to a forward formulation to eliminate a post-processing search loop.

- **Recognize When a Post-Processing Search Is Needed**: In backward formulations, if one subproblem parameter (like final jump distance) is not known at the top level, you must iterate over all possible values of that parameter at the end and pick the best. In forward formulations anchored at a known start state, this search is usually unnecessary.

- **Prefix-Sum Subproblems to Eliminate Loops**: When a recurrence contains a loop that sums (or takes the min/max of) a range of subproblem answers where only the first parameter varies, introduce a new "prefix aggregate" subproblem. This subproblem stores the running aggregate up to index `i`, computable in O(1) from the aggregate at `i - 1`. This pattern reduces the per-subproblem cost by one factor, often turning an infeasible O(m²nk) into a feasible O(mnk).

- **Counting DP with Modular Arithmetic**: When the problem asks for a count (not an optimal value), replace `min`/`max` with `+`. Apply `% MOD` after every addition to prevent overflow. Ensure all base cases return 0 or 1 (not -1 for "impossible"), as the count of impossible configurations is 0.

- **Two-Sentinel Memo Initialization**: When `-1` is a meaningful return value (representing "no valid solution"), initialize the memo table to a different sentinel (e.g., `-2`) to distinguish "not yet computed" from "computed and infeasible."

- **Using a Struct/Pair for Multiple Subproblems at the Same Index**: When introducing auxiliary subproblems that share the same parameter space as existing ones, store both results in a struct rather than maintaining two parallel memo arrays. This keeps lookups cache-friendly and the logic co-located.

- **Bottom-Up Fill Order Analysis**: Before writing a bottom-up DP, determine which existing cells each new cell depends on. Draw out one or two examples. If a cell at `(i, j)` depends on `(i, j+1)` (a higher column), fill columns in decreasing order. If it depends on `(i-1, j)` (same column, earlier row), fill rows in increasing order within each column.

---

## Common Pitfalls

- **Forgetting the Fixed Initial Jump**: In The Jumper, the jump from Square 1 to Square 2 (distance 1) is mandatory and must be accounted for separately. In the backward formulation, subproblems are defined starting from Square 2, and `cost[2]` is added back in the final step. In the forward formulation, the entry point is explicitly `(i=2, j=1)` with `cost[2]` added in `main`. Omitting this leads to off-by-one errors in the total cost.

- **Incorrect Bottom-Up Order**: For The Jumper's forward DP, a naive row-by-row, left-to-right fill fails because Option 1 (jump right) depends on column `j + 1`. The correct order is columns from `n` to `1`, rows from `1` to `n - 1`. This is a common mistake when the dependency graph is non-standard.

- **Assuming Memoization Guarantees Efficiency**: Memoization eliminates redundant recomputation, but the total work is still `(number of subproblems) × (work per subproblem)`. If each subproblem requires an O(m) loop, the total is O(m) times higher than the table size. Always analyze the per-subproblem cost, not just the number of subproblems.

- **Confusing "Exactly" and "At Most" Semantics**: Using "at most" for parameters that must be exact allows spurious solutions. For Ways to Build, using "exactly `k` substrings" is essential. An "at most" version would conflate configurations with different substring counts and produce wrong totals.

- **Incomplete Base Cases for Three-Parameter DP**: In Ways to Build, there are three distinct base cases: (1) `j == 0 && k == 1 && a[i] == b[j]` → 1 way. (2) any of `i == 0`, `j == 0`, `k == 0` (except the above) → 0 ways. (3) `a[i] != b[j]` (non-base-case position) → 0 ways (early exit). Missing any of these produces incorrect results, especially case (1) being tested before case (2) since they overlap in the `j == 0` condition.

- **Failing to Apply Modular Arithmetic Consistently**: Because the answer can be astronomically large, `% MOD` must be applied after every addition in both the subproblem recurrence and the final aggregation step. Applying it only at the end or only in certain branches causes overflow.

---

## Connections to Other Chapters

- **Chapter 3 (Memoization and Dynamic Programming foundations)**: Chapter 4 builds directly on the techniques introduced in Chapter 3. The backward formulation used for The Jumper mirrors the approach used for Burger Fervor (Chapter 3), where the end of the optimal solution is analyzed. The concept of "connectible" solutions and the post-processing search for an unknown final parameter echo the approach taken for Moneygrubbers and Burger Fervor. The "exactly" vs. "at most" subproblem design choice was first introduced in Chapter 3 with Hockey Rivalry.

- **Chapter 5**: Chapter 4's closing remark notes that storing results for later lookup (the core idea of memoization) reappears in Chapter 5 as a supporting technique within a different primary algorithm.

- **Chapter 7**: Dynamic programming plays a supporting role in Chapter 7 to speed up computation inside a larger algorithm. This foreshadows a common pattern in advanced algorithm design: DP as a subroutine rather than the central technique.
