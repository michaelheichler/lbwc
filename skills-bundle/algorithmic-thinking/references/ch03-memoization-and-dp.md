# Chapter 3: Memoization and Dynamic Programming

## Key Concepts

- **Optimization Problem**: A problem where the goal is to find the *best* (optimal) feasible solution among all possible solutions. Solutions that follow all problem rules are *feasible*. Those that do not are *infeasible*. Optimization problems are either maximization problems (maximize burgers eaten) or minimization problems (minimize cost). This distinction determines whether you use `max` or `min` when combining subproblem results.

- **Optimal Substructure**: The property that an optimal solution to a problem contains within it optimal solutions to its subproblems. If using a suboptimal solution for a subproblem were possible, the overall solution would not be optimal either. You could always improve it. This property is the prerequisite for applying memoization or dynamic programming. If it does not hold, neither technique is applicable.

- **Exponential-Time Algorithm**: An algorithm where a fixed increment in problem size leads to a roughly constant multiplicative increase in runtime (e.g., doubling). The naive recursive solution to Burger Fervor is exponential: `t=88` requires ~3 billion calls. `t=90` requires ~5 billion calls. Such algorithms are practically useless for even moderately sized inputs.

- **Overlapping Subproblems**: The phenomenon where the same subproblem instance is computed multiple times in a naive recursive solution. In Burger Fervor with `m=4, n=2, t=88`, `solve_t(4, 2, 84)` is called from both `solve_t(4, 2, 86)` and `solve_t(4, 2, 88)`, and this duplication compounds exponentially. Overlapping subproblems, combined with optimal substructure, are the signal to use memoization or dynamic programming.

- **Memoization (Top-Down)**: A technique that augments a recursive solution with a cache (`memo` array). Before computing a subproblem, check the cache. If the answer is already stored, return it immediately. If not, compute the answer and store it before returning. The key rule: *remember, don't refigure*. Memoization solves subproblems **on demand** as the recursion unfolds, making it "top-down." It only solves subproblems that are actually needed.

- **Dynamic Programming (Bottom-Up)**: A technique that eliminates recursion entirely by solving all subproblems in a deliberate order (from smallest to largest) using an explicit loop and a `dp` array. By the time subproblem `i` is needed, all smaller subproblems have already been solved and are available for lookup. Dynamic programming solves *all* subproblems in the reachable range, which may include some that memoization would never visit.

- **The `memo` / `dp` Array**: The central data structure for both techniques. For one-dimensional problems (Burger Fervor, Moneygrubbers), it is a 1D array indexed by the single subproblem parameter. For two-dimensional problems (Hockey Rivalry), it is a 2D array indexed by two parameters. The canonical name is `memo` for memoized solutions and `dp` for dynamic-programming solutions. A reserved sentinel value (e.g., `-2` or `-1`) signals "not yet computed."

- **Greedy Algorithm**: An algorithm that, at each step, makes the locally optimal choice without considering alternatives. Greedy algorithms are faster and simpler than dynamic programming when they work, but they often fail on problems requiring optimal substructure. In Moneygrubbers, the greedy "cheapest cost-per-apple" approach fails because it misses cases where a higher per-unit scheme is globally cheaper.

- **Space Optimization for 2D DP**: When each row `i` of a 2D `dp` table only depends on row `i` and row `i-1`, the full table can be replaced with two 1D arrays (`previous` and `current`). After solving all cells in `current`, copy `current` into `previous` before moving to the next row. This reduces space from O(n²) to O(n) without affecting time complexity.

---

## Problems Covered

### Problem: Burger Fervor
- **Source**: UVa 10465
- **Core Idea**: Homer Simpson has `t` minutes and can eat burgers of two kinds: one takes `m` minutes and one takes `n` minutes. Maximize the number of burgers eaten, prioritizing time spent eating (minimize beer time). Output the maximum burger count, and if `t` minutes cannot be exactly filled, also output the leftover beer-drinking minutes.
- **Approach**: Characterize an optimal solution by focusing on the *last* burger eaten: it must be an `m`-minute or `n`-minute burger. This yields two subproblems: solve for `t - m` and `t - n` minutes. The answer for `t` is `max(solve_t(t-m), solve_t(t-n)) + 1`. A sentinel value of `-1` means "exact fill is impossible." An outer `solve` function tries `t`, `t-1`, `t-2`, ... until an exact fill is found. After confirming exponential behavior in the naive recursive version, memoize with a 1D `memo[10000]` array initialized to `-2`. The dynamic-programming version fills a `dp[0..t]` array from index 0 to `t` in a single loop.
- **Complexity**: O(t) time and O(t) space (both memoized and DP).
- **Key Insight**: The sentinel value of `-1` (no solution possible) is distinct from the `memo` sentinel `-2` (not yet computed) and from valid answers (≥ 0). All three states must be representable and distinguishable. The outer loop from `t` down to 0 in `solve` terminates because `solve_t(m, n, 0)` always returns 0.

---

### Problem: Moneygrubbers
- **Source**: UVa 10980
- **Core Idea**: Buy at least `k` apples as cheaply as possible from a store that offers a unit price plus `m` bulk-pricing schemes (each scheme gives `n_i` apples for price `p_i`, with `n_i ≤ 100` and `k ≤ 100`). Multiple values of `k` may be queried per test case. The `memo` array is shared across all queries for the same test case.
- **Approach**: Define `solve_k(num_apples)` as the minimum cost to buy *exactly* `num_apples` apples. The final "purchase action" must be either buying one apple at unit price or using one of the `m` bulk schemes, giving `m + 1` subproblems per call. The outer `solve` function tries `num_apples`, `num_apples + 1`, ..., up to `SIZE - 1 = 199`, keeping the running minimum. The upper bound of 199 follows from the constraint that any bulk scheme has at most 100 apples: if buying ≥ 200 apples were optimal for k=100, removing the final scheme would yield a cheaper solution for ≥ 100 apples. The `memo` array (size 200, initialized to `-1`) is declared in `main` and shared across all `k` queries in the same test case.
- **Complexity**: O(k × m) per subproblem, O(SIZE × m) total per test case. Space O(SIZE).
- **Key Insight**: The problem asks for "at least k" not "exactly k": sometimes buying more apples is cheaper (e.g., a bulk scheme for 4 apples may be cheaper than buying 3 individually). The bound of 199 on the search space comes from the maximum scheme size of 100 apples. Unlike Burger Fervor, `solve_k` always finds a solution (unit price is always available), so no `-1` sentinel for "no solution" is needed. Sharing the `memo` across multiple `k` queries within a test case is critical for efficiency.

---

### Problem: Hockey Rivalry
- **Source**: DMOJ cco18p1 (2018 Canadian Computing Olympiad)
- **Core Idea**: The Geese and Hawks each played `n` games (n ≤ 1000), each a win (W) or loss (L). A "rivalry game" is a game where the Geese played the Hawks: for it to be valid, one team must have won and the other lost, and the winner must have scored more goals than the loser. Games must be matched in chronological order (Geese game `i` paired with Hawks game `j` requires `i` and `j` to be used consistently, later games cannot be paired with earlier ones in conflicting ways). Maximize total goals in all possible rivalry games.
- **Approach**: Characterize optimal solutions for the first `i` Geese games and first `j` Hawks games. There are four options: (1) use game `i` and game `j` as a rivalry game (if valid), adding their goals to `solve(i-1, j-1)`. (2) skip both game `i` and game `j`, solving `solve(i-1, j-1)`. (3) skip only Geese game `i`, solving `solve(i-1, j)`. (4) skip only Hawks game `j`, solving `solve(i, j-1)`. The answer is `max(option1, option2, option3, option4)`. Options 3 and 4 require that `i` and `j` are independent parameters, necessitating a 2D `memo[i][j]` or `dp[i][j]` table. Arrays are 1-indexed to avoid off-by-one confusion (index 0 = zero games = base case returning 0). The `memo` array is declared `static` in `main` because it exceeds stack size (1001 × 1001 ints). For DP, fill the table row by row (outer loop over `i` from 1 to `n`), left to right (inner loop over `j` from 1 to `n`). The space optimization uses two 1D arrays (`previous` and `current`) instead of the full 2D table.
- **Complexity**: O(n²) time and O(n²) space (memoization/DP). O(n) space with the rolling-array optimization.
- **Key Insight**: Options 3 and 4 are the non-obvious cases that force two subproblem parameters. Without them, the problem would be solvable with one parameter, but the optimal pairing can require dropping a game from one team without dropping the corresponding game from the other. Also notable: unlike Burger Fervor and Moneygrubbers, the subproblems here are defined as "the first `i`/`j` games" (not "exactly" a specific game), which avoids needing a separate outer search loop: `dp[n][n]` is the direct answer.

---

## Algorithm Patterns

- **The Four-Step Memoization/DP Template**: 1. **Characterize optimal substructure**: Ask "what must the last decision in an optimal solution look like?" Enumerate all candidates for that last decision. Each yields a smaller subproblem. Verify that optimal solutions to subproblems are embedded in the optimal overall solution. 2. **Write a recursive solution**: For each candidate last decision, recursively solve the resulting subproblem. Return the best result (max or min) across all candidates. Identify the base case(s) (typically the "zero input" case). 3. **Add memoization**: Declare a `memo` array initialized to a sentinel value (not a valid answer). At the start of the recursive function, return `memo[t]` if it is not the sentinel. Before every `return`, store the value in `memo[t]`. 4. **Convert to dynamic programming** (optional): Replace recursion with an explicit loop that fills `dp` from smallest subproblem to largest. Determine a valid fill order by ensuring that all dependencies of `dp[i]` (or `dp[i][j]`) are computed before it.

- **Recognizing When to Use This Chapter's Techniques**: The problem is an optimization (maximize or minimize something). A recursive solution is correct but exponentially slow due to repeated subproblems. Optimal substructure holds: a better solution to a subproblem would improve the overall solution. Subproblems can be defined by a small number of integer parameters (typically 1-3). The problem asks for the *value* of an optimal solution (not necessarily the decisions themselves).

- **Choosing Between "Exactly k" and "At Least/Most k" Framing**: In Burger Fervor, solving for "exactly `t`" minutes and then searching downward was chosen because it simplified the subproblem structure. In Moneygrubbers, solving for "exactly `k`" apples and then searching upward (up to `k + max_scheme_size - 1`) handles the "at least `k`" requirement. In Hockey Rivalry, using "first `i` games" (not "exactly game `i`") avoids a separate outer search loop entirely. When stuck, try switching between "exactly" and "at least/first" framings. One often leads to a simpler solution.

- **Determining the Search Bound in "At Least k" Problems**: When buying at least `k` items, the upper search limit is `k + (max_items_per_scheme - 1)`. Buying more than this is never optimal: removing the final scheme from any such solution yields a cheaper solution for at least `k` items. This technique generalizes: if a scheme covers at most `S` items, the safe upper bound is `k + S - 1`.

- **Handling Infeasibility Sentinels**: Use distinct sentinel values for "not yet computed" and "no valid solution." Example: `-2` = not computed, `-1` = no solution, `≥ 0` = valid answer (Burger Fervor). Choose sentinels that cannot appear as valid outputs or as each other.

- **1-Based Array Indexing for Subproblem Parameters**: When subproblem parameters represent counts (0 = "zero items" base case), store actual data starting at index 1. This ensures that `dp[0]` or `memo[0]` is the base case representing "nothing," and parameter `k` maps directly to array index `k`. Avoids off-by-one errors, especially in 2D problems.

- **2D DP Fill Order**: For a 2D `dp[i][j]` table where `dp[i][j]` depends on `dp[i-1][j-1]`, `dp[i-1][j]`, and `dp[i][j-1]`: Outer loop: `i` from 0 to `n` (rows, ascending). Inner loop: `j` from 0 to `n` (columns, ascending within each row). This guarantees all three dependencies are filled before `dp[i][j]`.

- **Rolling Array Space Optimization**: When row `i` only depends on rows `i-1` and `i` (never `i-2` or earlier), replace the 2D array with two 1D arrays: `previous` (row `i-1`) and `current` (row `i`). After filling all of `current`, copy it into `previous`. Return `current[n]` as the final answer. This reduces space from O(n²) to O(n).

---

## Common Pitfalls

### Confusing Sentinel Values
Using `-1` for both "no solution" and "not yet computed" causes memoization to incorrectly treat unsolved subproblems as having no solution. Always reserve distinct sentinel values for each meaning.

### Forgetting the "At Least k" Distinction
Solving for exactly `k` when the problem asks for at least `k` will miss cases where buying more items is cheaper (e.g., Moneygrubbers: buying 4 apples with a bulk scheme may be cheaper than buying exactly 3). Always check whether the problem allows overshoot.

### The Greedy Trap
Sorting by cost-per-unit and greedily choosing the best option at each step is intuitively appealing but provably wrong for many DP problems. Memoization/DP avoids this by trying *all* valid options at each step and choosing the globally optimal one.

### Initializing Only the Needed Range
In Burger Fervor's DP solution, `dp[0]` is initialized explicitly and the loop runs from `i = 1` to `t`. Only indices 0 through `t` need to be initialized. Indices beyond `t` are irrelevant. Over-initializing wastes time. Under-initializing causes undefined behavior on array reads.

### Stack Overflow with Large Arrays
A 1001×1001 `int` array is ~4MB, which exceeds most systems' default stack sizes. Declare large arrays as `static` (stored in the data segment, not the stack) to avoid runtime crashes.

### Not Sharing the `memo` Across Queries
In Moneygrubbers, multiple `k` values are queried per test case. Re-initializing the `memo` array between queries throws away already-computed results. Initialize once per test case (in `main`), not once per query.

### Incorrect Fill Order in 2D DP
For Hockey Rivalry, filling the table in column-major order (outer loop over `j`) would compute `dp[i][j-1]` (Option 4 dependency) correctly but `dp[i-1][j]` (Option 3 dependency) incorrectly, it would reference a cell from the *same* pass, not a previously completed row. Always verify that the chosen fill order satisfies all dependency requirements before coding.

### Subproblem Parameters Not Independent
Assuming subproblem parameters are always linked (e.g., always decrementing both `i` and `j` together) fails when Options 3 or 4 (dropping one parameter while holding the other fixed) are required. Verify independently whether each parameter changes or stays fixed in each option.

---

## Connections to Other Chapters

### Chapter 2 (Recursion / Trees)
The recursive solutions in this chapter build directly on the recursive thinking introduced in Chapter 2. The key difference is that Chapter 2's problems (e.g., Halloween Haul on a tree) have *no overlapping subproblems*: each subproblem is solved exactly once, so pure recursion suffices. Chapter 3 introduces the techniques needed when subproblems do overlap.

### Chapter 4 (Advanced DP)
Chapter 3 introduces one- and two-dimensional DP. Chapter 4 extends these techniques to harder problems, including cases with three or more dimensions and problems where a change in perspective (e.g., reframing what "exactly" means) unlocks a simpler or faster solution. Chapter 3 explicitly notes that subproblems in Chapter 5 cannot always be easily ordered by size, requiring additional techniques.

### Chapter 5 (Graphs and BFS)
Chapter 3 assumes subproblems are strictly smaller than the original problem (e.g., `t-m < t`), guaranteeing termination and no cycles in the dependency graph. Chapter 5 introduces graphs where states *can* cycle (e.g., a knight revisiting a square), making DP inapplicable and requiring BFS with explicit visited tracking instead.

### Chapter 1 (Hash Tables)
Chapter 1 introduced hash tables as a way to speed up algorithms by avoiding redundant work. Memoization serves a similar purpose (caching results to avoid redundant computation) but operates on recursion trees rather than search structures.

### Appendix B (Reconstructing Solutions)
The chapter focuses solely on computing the *value* of the optimal solution (e.g., number of burgers, minimum cost, maximum goals). Appendix B covers Burger Fervor as a case study for *reconstructing* the actual sequence of decisions (which burgers to eat) from the `dp` array, a technique that generalizes to all DP problems.
