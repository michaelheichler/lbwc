---
unit: "Ch 20-22"
slug: "d10-prime-factor-villages-spanning-tree"
title: "Prime factor, isolated villages, shortest spanning tree"
book: "A Discipline of Programming"
one_liner: "Three worked designs showing how 'taking a relation outside the repetitive construct' turns naive algorithms into efficient ones: incremental modular arithmetic for prime factoring, pruned minimum scans for isolation degrees, and Prim's minimum spanning tree via the ultraviolet-branch invariant."
when_to_use: "Load when optimizing a loop by carrying incremental state across iterations, pruning a min/max search with bounds, or deriving a greedy graph algorithm (minimum spanning tree) from an invariant about partial solutions."
topics: [incremental computation, strength reduction, loop optimization, prime factorization, modular arithmetic, minimum search, pruning, symmetry exploitation, minimum spanning tree, greedy algorithms, prim algorithm, graph algorithms, program simplicity, stepping stones]
key_terms: [taking a relation outside the repetitive construct, isolation degree, violet branch, ultraviolet branch, subspanning tree, mixed-radix representation, stepping stones]
related: [d04-termination-and-euclid, d08-search-permutation-flag-file-merging, d09-hamming-pattern-matching-two-squares, d11-rem-equivalence-convex-hull, d12-strong-components-manuals-retrospect]
---

# Prime factor, isolated villages, shortest spanning tree

Three medium-size derivations, each built around replacing expensive recomputation with cheap incremental maintenance of a stored relation. **Source:** A Discipline of Programming, Ch 20-22.

## TLDR

- The master move in all three chapters is "taking a relation outside the repetitive construct": store auxiliary state so each iteration updates a known relation cheaply instead of recomputing an expensive function from scratch.
- Smallest prime factor: trial division by 2, 3, 4, ... needs no prime table, because the smallest divisor >= 2 of N is automatically prime. Divisions are avoided entirely by keeping N in a mixed-radix remainder representation that is updated by additions and small multiplications when the trial factor increases by 1.
- The remainder representation gives a free end-to-end check (N = f * r1 + r0 must hold at the end), so the algorithm doubles as a machine-arithmetic reliability test.
- Most isolated villages: two independent optimizations, early exit from a minimum scan once the row minimum falls below the best max so far (a heuristic), and scanning only the upper triangle of a symmetric distance matrix while caching column minima (a guaranteed win). Combining them needs care, and Dijkstra found the clean combination only by building each optimization separately first, as "stepping stones".
- Moral of Ch 21: do not complicate a general program with a smart strategy whose payoff depends on an arbitrary probability assumption about the inputs. Simplicity is the less ambiguous target.
- Shortest subspanning tree: the red-tree invariant (branches known to be in the answer always form a tree) plus the shortest-violet-branch theorem yields a correct greedy algorithm. Introducing "ultraviolet" branches (one candidate per blue point) cuts the cost from N^3 to N^2. This is Prim's algorithm, derived rather than recalled.
- Moral of Ch 22: once an algorithm is correct, do not be content too soon. The N^3 to N^2 optimization needed no more graph theory, only the standard pattern of carrying state across loop iterations.

## When to reach for this

- A loop calls an expensive function (division, distance, hash) whose successive arguments differ only slightly, and you suspect the next value can be computed incrementally from the last.
- You are computing a min or max over rows of a matrix and only need the extremal row, so partial scans can be aborted against a running bound.
- You need a minimum spanning tree, or more generally a greedy algorithm, and want the invariant-based justification rather than a memorized recipe.
- You are tempted to add a clever heuristic to a general-purpose routine and need the argument for resisting it.
- A result is hard to verify (like "N is prime") and you want the computation itself to carry a cheap final consistency check.

## Key concepts

### Taking a relation outside the repetitive construct

If a loop repeatedly computes F(x) for x = a, a+1, a+2, ..., store extra variables tied to x by an invariant relation, and update them alongside x. The update is often far cheaper than recomputation. In Ch 20 the relation is a full mixed-radix expansion of N, in Ch 22 it is the set of best-known connections from each blue point to the red tree. Modern names: strength reduction, incremental computation, memoized frontier.

### The prime factor trick (Ch 20)

Setting: N up to about 10^16 on a machine where addition and comparison are fast but general multiplication and division are slow. Naive structure: try f = 2, 3, 4, ... while N mod f != 0 and (f+1)^2 <= N. No prime table is needed since the smallest divisor >= 2 is necessarily prime. The costs to remove are N mod f and the squaring in the guard.

Represent N relative to f by remainders r0, r1, ..., rn:

```
N = r0 + f*r1 + f*(f+1)*r2 + ... + f*(f+1)*...*(f+n-1)*rn
with 0 <= r_i < f + i, and rn > 0 (leading digit)
```

Then N mod f = r0, so the divisibility test is just r0 != 0. When f increases by 1, each digit is updated by r_i := r_i - (i+1)*r_{i+1}, then normalized back into range by repeated r_i := r_i + (f+i), then r_{i+1} := r_{i+1} - 1. All operations are additions and multiplications by small integers. The guard f^2 <= N becomes n >= 1 (one nontrivial high digit left), because n < 1 implies N < (f+1)^2.

Three remarks worth keeping: (1) special-casing odd N (stepping f by 2) roughly doubles the normalization work and mostly messes up the formulae, not an improvement. (2) An execution histogram would point at the inner normalization loop, but optimizing it is the wrong move. The dominant regime is when only two or three digits remain (f past the cube root of N), so the right optimization is to exit the array loop early and handle the final two or three digits as scalars. Profilers say where time goes, not what to change. (3) Because every step reuses all previous state, the final relation N = f*r1 + r0 is an almost-free integrity check. An isolated table-driven divisibility test has no such property. The algorithm was used both for reliable factorizations and to test arithmetic units.

### Most isolated villages (Ch 21)

Given n villages and distance function f(i,j) with f(i,i) = M (an upper bound), each village's isolation degree is id(i) = min over j of f(i,j). Wanted: all k maximizing id(k). The straightforward program computes each row minimum and tracks the running max with a three-way guard (max > min: skip, max = min: append, max < min: restart the answer set).

Optimization 1 (heuristic): inside the row scan, min only decreases, and any min <= max is equivalent to any other. So abort the row scan once min <= max. The post-assertion weakens to "id(i) < min <= max or id(i) = min > max", which still suffices.

Optimization 2 (guaranteed): if f is symmetric and expensive, never compute f(i,j) and f(j,i) both. Scan only j > i, and keep an array b where b(k) = min over h < i of f(k,h), the best distance to k seen so far. Initialize min from b(i) (via lopop) instead of M.

Combining them: aborting the row scan early leaves some b(k) not yet updated. Only those with b(k) > max still matter, so a cleanup loop walks the rest of the row updating just those, placed after max has been adjusted (the larger max, the fewer updates needed).

The chapter's two lessons. First, the strategy lesson: Optimization 1's payoff depends on the unknown distance values. Any claim that a cleverer variant is "more efficient on average" silently postulates a probability distribution over inputs, which a general program has no business assuming. Dijkstra judged his own more ingenious earlier version wasted effort. Second, the method lesson: the clean combined program was found by first writing two simpler programs, each with one optimization. Stepping stones beat trying to be clever all at once.

### Shortest subspanning tree (Ch 22)

N points, given symmetric branch lengths, find the tree of N-1 branches with minimum total length. Brute force is hopeless: Cayley's theorem gives N^(N-2) trees.

Design question: what intermediate states should the computation pass through? Choose the simplest natural one: the branches already known to be in the answer form a tree themselves (the red tree). Colour its points red, the rest blue, and call red-to-blue branches violet.

Theorem: the shortest violet branch belongs to the shortest tree. Proof skeleton: take any spanning tree containing the red branches but not the shortest violet branch, add that branch, a cycle forms crossing the red/blue boundary, so it contains another, longer violet branch, remove that one, the result is a shorter tree. (Fact used: any two of "connects all N points", "has N-1 branches", "has no cycles" imply the third.)

This yields the greedy loop: colour one arbitrary point red, then repeat "select shortest violet branch, colour it and its blue endpoint red" until no blue points remain. Selecting from the k*(N-k) violet branches from scratch each time gives an N^3 algorithm.

The N^2 refinement: shrink the candidate set to "ultraviolet" branches, chosen so that (1) the shortest violet branch is always among them, (2) the set is small, (3) it is cheap to adjust when a point turns red. Two natural choices: per red point, its shortest violet branch (k candidates), or per blue point, its shortest violet branch (N-k candidates). The second wins, not by size but by adjustment cost and structure: each blue point has exactly one candidate connection, so red plus ultraviolet branches form a spanning tree at all times, and when point P turns red, adjusting means one comparison per blue point B (is dist(B,P) shorter than B's current candidate?). Selection and adjustment fuse into one linear pass carrying "lcr", the point last coloured red. Total cost N^2. This is Prim's algorithm. The program is two nested loops over arrays from, to, uvl, with the red branches occupying positions below k and ultraviolet ones above, swapped into place as they are selected.

Alternative sketched and deferred: sort all branches by length and add each unless it closes a cycle (Kruskal). Rejected here because of the sort and because cycle detection is its own problem (solved in a later chapter with equivalence classes). A second variant, insert branches in arbitrary order and delete the longest branch of any cycle formed, is mentioned as an exercise seed.

If branch lengths are not all distinct, the shortest tree may not be unique and the algorithm may deliver any of them.

## Derivation playbook

1. Get a correct naive algorithm first. Mathematical analysis of the problem (like the violet-branch theorem) happens here, optimization comes after and usually needs no new theory.
2. Choose simple intermediate states. Prefer partial answers with structure (a subtree, a prefix of processed rows) over arbitrary subsets. The structure is what makes the invariant statable.
3. Find the expensive operation inside the loop and ask what stored relation would make its next execution cheap. Write the relation down as an equation (the r-expansion of N, the meaning of b(k), the meaning of uvl(h)) before writing update code.
4. Derive the update from the relation: perturb the changing variable (f := f+1, i := i+1, one point turns red) and compute what compensating changes restore the relation. Range violations get their own inner normalization loop.
5. Check the guard can be re-expressed in the new state (f^2 <= N becomes n >= 1, min > max prunes the scan).
6. When two optimizations interact, build each alone as a stepping stone, then merge.
7. Reject strategies whose benefit relies on an assumed input distribution, unless the program stays simple anyway.

Essences: Ch 20 invariant is the mixed-radix equation for N with digit bounds, variant is the decreasing high-digit count times remaining f-range. Ch 21 invariant is "b(k) = best distance to k over processed rows" plus "max = best isolation degree over processed rows", variant is the count of unprocessed rows. Ch 22 invariant is "red branches form a subtree of the shortest tree, and each blue point's ultraviolet branch is its shortest connection to the red tree", variant is the count of blue points.

## Applying it in modern code

- Strength-reduce hot loops: when successive iterations call an expensive function on nearby arguments, maintain the delta (rolling hashes, running sums, incremental distances) and assert the defining relation in debug builds.
- Prune extremum searches with a running bound (branch and bound in miniature): abort an inner min-scan as soon as it drops below the best max, and document with an assertion which weaker postcondition still holds.
- Exploit symmetry explicitly: for symmetric cost matrices, scan the upper triangle and cache the transposed contributions, as with b(k). Halving calls to an expensive metric is a guaranteed, distribution-free win.
- Prim's algorithm in practice: keep per-node best-edge arrays (uvl, from) and update them in one pass per added node. For sparse graphs a priority queue replaces the linear scan, but the invariant is identical.
- Turn maintained relations into cheap end-of-run integrity checks (the N = f*r1 + r0 test): after any incremental computation, verify the invariant once against a from-scratch evaluation, in tests or even in production.
- Trust profilers for where time goes, not for what to change: the right fix for a hot inner loop may be restructuring the outer phases (scalar final stage) rather than micro-optimizing the loop body.
- Prefer the simple general program over a heuristic tuned to an imagined input distribution. If a heuristic is added, keep it separable so it can be removed.

## Pitfalls

- Optimizing the loop the profiler points at instead of asking which regime dominates. In Ch 20 the honest fix was a scalar epilogue, not a faster array loop.
- Justifying complexity with "faster on average" without saying over what distribution. A general program tailored to an arbitrary input model is worse, not better.
- Merging two optimizations directly instead of via stepping stones, and getting an interaction bug (early exit leaving cached bounds stale, as with the unupdated b(k)).
- Choosing the candidate-set representation by size alone. The two ultraviolet definitions have symmetric sizes, and the winner is decided by adjustment cost and structural cleanliness.
- Growing partial answers without structure. If the known-correct branches did not form a tree, the shortest-violet theorem, the k-versus-branch bookkeeping, and the cycle-freedom argument would all collapse.
- Forgetting that a maintained relation can drift: incremental state needs its defining equation checked (at least in tests), or corruption propagates silently, exactly the failure mode the table-lookup factorizer suffers from.

## Cross-refs

- [[d04-termination-and-euclid]] for the invariant and variant machinery these derivations assume.
- [[d08-search-permutation-flag-file-merging]] for the Linear Search Theorem used to justify trying factors in increasing order, and the Dutch national flag as the earlier "choose your intermediate states" example.
- [[d09-hamming-pattern-matching-two-squares]] for the neighboring worked examples that also live or die by carrying state across iterations.
- [[d11-rem-equivalence-convex-hull]] for the equivalence-class machinery that makes the deferred Kruskal-style cycle test tractable.
- [[d12-strong-components-manuals-retrospect]] for the retrospective view on why derived algorithms beat recalled ones.
