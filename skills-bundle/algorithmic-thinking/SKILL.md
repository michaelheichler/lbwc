---
name: algorithmic-thinking
description: "Guide for solving competitive programming and algorithmic problems using techniques from Daniel Zingaro's 'Algorithmic Thinking' (2nd Ed, 2024). Covers hash tables, trees, recursion, memoization, dynamic programming, graphs, BFS, Dijkstra's algorithm, binary search, heaps, segment trees, union-find, and randomized algorithms. Use this skill whenever the user needs help with: algorithmic problem solving, competitive programming, data structure selection, dynamic programming formulation, graph traversal, optimization problems, or understanding time/space complexity tradeoffs. Also use when the user is working on problems from online judges (DMOJ, USACO, Codeforces, LeetCode) or needs to recognize which algorithmic pattern fits their problem."
---

# Algorithmic Thinking, Problem-Based Algorithm Guide

Based on "Algorithmic Thinking: Unlock Your Programming Potential" (2nd Edition) by Daniel Zingaro, No Starch Press, 2024.

## How to Use This Skill

This skill helps you guide programmers through algorithmic problem solving. When a user presents a problem:

1. **Identify the pattern.** Match the problem to one of the algorithmic families below.
2. **Read the relevant reference.** Each chapter's reference file has detailed problem breakdowns and solution strategies.
3. **Guide, don't solve.** Help the user discover the approach through the problem-solving framework.

All reference files live in `references/` relative to this skill.

## Problem-Solving Framework

The book teaches a consistent workflow for attacking any algorithmic problem:

1. **Read the problem statement precisely.** Pay attention to exact wording ("at least" vs. "exactly"), value ranges, number of test cases, output format. Misreading constraints is a leading cause of wrong answers.
2. **Estimate complexity before coding.** Combine the input bounds with a rough operations-per-second budget (~tens of millions/sec). If a candidate approach is O(n²) and n can be 10⁶, reject it analytically. Don't implement and hope. (See `references/appendix-a-algorithm-runtime.md`.)
3. **Start with a correct-but-slow solution conceptually.** Then diagnose the bottleneck (usually a nested loop or repeated search) and replace it with the right data structure or algorithm. This "naive, diagnose, accelerate" loop is the book's central pattern.
4. **Decompose into helper functions and solve before reading input.** Write and test the core logic with hard-coded values first. Wire up input parsing last.
5. **Model the problem, don't mirror it.** The graph, states, or subproblems you compute over need not match the real-world structure one-for-one. An equivalent model with fewer edges or smaller state space gives the same answer faster.
6. **Verify against judge feedback.** AC means accepted, WA means logic bug, TLE means wrong complexity class. WA bugs may hide behind a TLE, so a timeout proves nothing about correctness.

## Quick Reference: When to Use What

| Problem characteristic | Technique | Reference |
|---|---|---|
| Repeated search in a growing collection, naive O(n²) pairwise matching, custom equality definitions | Hash tables | `ch01-hash-tables.md` |
| Hierarchical/recursive structure, "if I knew the subtree answers, the whole answer is easy" | Trees & recursion | `ch02-trees-and-recursion.md` |
| Optimization (max/min) + optimal substructure + **overlapping** subproblems | Memoization / DP | `ch03-memoization-and-dp.md` |
| DP needing 2-3 state parameters, counting (not optimizing), or per-subproblem loops that are too slow | Advanced DP | `ch04-advanced-memoization-and-dp.md` |
| Minimum number of moves/steps between states, transitions all cost the same (or 0/1), state space can **cycle** | Graphs & BFS | `ch05-graphs-and-bfs.md` |
| Shortest path where edges have arbitrary non-negative weights, counting shortest paths | Dijkstra's algorithm | `ch06-shortest-paths-weighted-graphs.md` |
| Optimal value hard to compute, but feasibility of a guessed value is easy to check, monotone feasible/infeasible split | Binary search on the answer | `ch07-binary-search.md` |
| Repeated extraction of current max/min from a changing set, range queries (max/sum) with updates | Heaps / segment trees | `ch08-heaps-and-segment-trees.md` |
| Dynamic "merge groups" + "same group?" queries, equivalence relations, connectivity without distances | Union-find | `ch09-union-find.md` |
| YES-instances have a "large fraction" property samplable at random, or a divide-and-conquer with an exploitable fixed pivot | Randomization | `ch10-randomization.md` |

Key disambiguations:

- **DP vs. BFS.** Both cache results. If subproblems are always strictly smaller (no cycles in the dependency graph), use DP. If you can return to a previously visited state, use BFS.
- **BFS vs. Dijkstra.** To minimize *edge count* (or edges cost only 0/1, then 0-1 BFS), use BFS. To minimize *total weight* with arbitrary non-negative weights, use Dijkstra. Negative weights need neither (Bellman-Ford/Floyd-Warshall, mentioned but not covered).
- **BFS/Dijkstra vs. union-find.** If you need distances, use graph search. If you need only "same group?" on a graph that grows over time, use union-find (per-query BFS is O(q²) and will TLE).
- **Hash table vs. heap vs. segment tree.** Lookup by key goes to a hash table. Extract max/min goes to a heap. Range queries over array indices (especially with updates) go to a segment tree. Prefix sums handle static range *sums* but not range max (max is not invertible).
- **Greedy vs. DP.** Greedy commits to the locally best choice and is often provably wrong (Moneygrubbers, River Jump direct-greedy). DP tries all options. Greedy correctness needs an exchange-argument proof, which Chapter 7 shows how to build.
- **Direct optimization too hard?** Try binary search on the answer (Ch. 7), pushing all problem-specific logic into a feasibility check.
- **Everything else failed and a tiny error probability is OK?** Consider Monte Carlo sampling (Ch. 10).

## Cross-Cutting Themes

- **Naive, diagnose, accelerate.** Nearly every chapter starts with a correct O(n²)-or-worse solution, identifies the bottleneck operation (search, min-finding, range query, connectivity), and swaps in the data structure purpose-built for that operation. Hash table for search, heap for max/min, segment tree for range query, union-find for membership. Data structures are accelerators for specific operations.
- **Complexity as a design gate.** Input bounds times time limit encode the intended complexity class. 10⁵ elements with nested loops won't pass. Interactive call limits (Cave Doors, 70,000 ≈ 5,000 × log 5,000) literally spell out the expected algorithm.
- **Store-and-reuse.** Memoization, DP tables, BFS visited arrays, prefix sums, flavor index arrays, and segment trees all embody one idea, never recompute what you can look up. The variants differ in whether the dependency structure has cycles and what gets cached.
- **State augmentation.** When position alone doesn't determine legal moves or remaining obligations, add a state dimension to nodes (Rope Climb's second rope, Grandma Planner's cookie bit) or a parameter to subproblems (The Jumper's jump distance, Ways to Build's k). Same trick across BFS, Dijkstra, and DP.
- **Reframe the model.** Equivalent-but-cheaper models win. Reverse the graph for single-target shortest paths, decompose arbitrary falls into free unit steps, replace median-finding with -1/+1 sums, turn "find the optimum" into "binary search over feasibility checks".
- **Sentinels and invariants.** Distinguish "not computed" from "infeasible" from valid answers (-2/-1/≥0). State and maintain the binary-search invariant before deciding to output low or high. Keep size[] accurate only at union-find roots. Most off-by-one bugs in the book trace back to a fuzzy invariant.
- **Greedy needs proof.** Greedy choices are fast but frequently wrong (Moneygrubbers, the direct River Jump greedy). When greedy works (River Jump feasibility, Dijkstra itself), the book justifies it with an exchange argument. Default to DP/exhaustive options unless a proof exists.
- **Bound the search space analytically.** "At least k" problems cap at (k + max-scheme-size) minus 1. Rope Climb caps the board at (2h) minus 1. Deriving such bounds from constraints converts unbounded searches into finite ones.
- **C implementation hygiene.** Use `static` for large arrays (stack overflow), `long long` for big accumulations, two directed edges per undirected edge, clearing adjacency lists between test cases, seeding the RNG, and 1-indexed arrays for clean base cases.

## Reference Files

| File | One-line description |
|---|---|
| `references/ch00-introduction.md` | Judge workflow, C mechanics, problem-statement reading habits, Food Lines warm-up |
| `references/ch01-hash-tables.md` | Hash tables, hash function design, chaining, Snowflakes, Login Mayhem, Spelling Check |
| `references/ch02-trees-and-recursion.md` | Binary/n-ary trees, two-rule recursion, recursive parsing, Halloween Haul, Descendant Distance |
| `references/ch03-memoization-and-dp.md` | Optimal substructure, memo/DP template, 1D & 2D DP, Burger Fervor, Moneygrubbers, Hockey Rivalry |
| `references/ch04-advanced-memoization-and-dp.md` | Forward vs. backward DP, 3D state, counting DP, prefix-aggregate subproblems, The Jumper, Ways to Build |
| `references/ch05-graphs-and-bfs.md` | Graph modeling, BFS, 0-1 BFS, state augmentation, Knight Chase, Rope Climb, Book Translation |
| `references/ch06-shortest-paths-weighted-graphs.md` | Dijkstra, graph reversal, path counting, Mice Maze, Grandma Planner |
| `references/ch07-binary-search.md` | Binary search on the answer, feasibility checks, 2D prefix sums, Feeding Ants, River Jump, Living Quality, Cave Doors |
| `references/ch08-heaps-and-segment-trees.md` | Heaps, priority queues, segment trees, RMQ, Supermarket Promotion, Building Treaps, Two Sum |
| `references/ch09-union-find.md` | Disjoint sets, union by size, path compression, augmentation, Social Network, Friends and Enemies, Drawer Chore |
| `references/ch10-randomization.md` | Monte Carlo & Las Vegas algorithms, randomized quicksort, Yōkan, Caps and Bottles |
| `references/appendix-a-algorithm-runtime.md` | Big O notation, complexity classes, pre-implementation analysis |
| `references/appendix-b-extras.md` | Implicit linked lists, DP reconstruction, heap-based Dijkstra, in-place partitioning |
| `references/appendix-c-problem-credits.md` | Original titles, competitions, and authors for every problem in the book |
| `references/code-examples.md` | Annotated C code snippets for every major algorithm and data structure (hash tables through quicksort) |
