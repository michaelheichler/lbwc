---
unit: "Ch 17-19"
slug: "d09-hamming-pattern-matching-two-squares"
title: "Hamming's sequence, pattern matching, and sums of two squares"
book: "A Discipline of Programming"
one_liner: "Three worked derivations that introduce two reusable strategies: taking a relation outside the repetitive construct (incremental recomputation) and the Search for the Small Superset (shrinking the candidate set before you enumerate it)."
when_to_use: "Load when generating ordered sequences from production rules, writing substring or pattern matching code, enumerating solution pairs under a numeric constraint, or when a loop recomputes from scratch something that changes only slightly per iteration."
topics: [hamming numbers, smooth numbers, sequence generation, pattern matching, string search, kmp, failure function, incremental computation, invariants, candidate pruning, two squares, two-pointer, loop derivation, caching derived values]
key_terms: [taking a relation outside the repetitive construct, search for the small superset, match function, dif function, shift table d(k), q.high, hiext, linear search theorem]
related: [d07-array-variables, d08-search-permutation-flag-file-merging, d10-prime-factor-villages-spanning-tree, d03-wp-semantics-of-the-language]
---

# Hamming's sequence, pattern matching, and sums of two squares

Three classic derivations that each turn an obvious quadratic algorithm into a near linear one by the same two moves. **Source:** A Discipline of Programming, Ch 17-19.

## TLDR

- All three programs are built the standard way: postcondition first, invariant next, then a loop that grows the answer while keeping the invariant true.
- "Taking a relation outside the repetitive construct": when a value is a function of slowly changing state, do not recompute it from scratch inside the loop. Establish it once before the loop and adjust it incrementally after each change. Today this is caching plus incremental update.
- "Search for the Small Superset": to generate the members of a hard set A, generate an easy superset B and filter. Performance demands that B be cheap to enumerate, cheap to test, and as small as you can make it. Consciously shrink B before coding.
- Hamming's problem (all numbers of the form 2^a * 3^b * 5^c in order) is solved by keeping three cached candidates x2, x3, x5, each the smallest multiple of 2, 3, 5 (by an element already in the output) that exceeds the current maximum. Append the minimum, then advance the three lazily.
- The pattern matching chapter derives what is essentially the Knuth-Morris-Pratt algorithm: a second invariant records how much of the pattern already matches, and a precomputed shift table over the pattern alone lets the match position jump by more than 1. Running time proportional to M+N instead of M*N.
- The two squares problem (all pairs x >= y >= 0 with x*x + y*y = r) becomes a two pointer scan: x only increases, y only decreases, and the invariant x*x + (y+1)*(y+1) > r survives across outer iterations, so y never restarts.
- Dijkstra prefers a `do ... od` loop even when the body runs at most once. "Zero or one times" is just a special case of "at most k times" and deserves no special syntax.
- Keep guarded commands in separate successive loops when executing one cannot change the truth of the others' guards. The sequential order is then over-specification of what could run concurrently, and that is fine.

## When to reach for this

- You are generating an ordered stream from rules like "if x is in the set, so is f(x)" (Hamming numbers, ugly numbers, BFS-like generation by monotone functions).
- You are writing substring search or any scan where a partial match can be reused instead of thrown away after a mismatch.
- You are enumerating pairs or tuples satisfying a numeric equation and a naive nested loop looks quadratic (two pointer opportunities).
- A profiler shows a loop recomputing a derived value (a min, an index, an aggregate) whose inputs change only slightly each iteration.
- You need to enumerate a set with no direct successor function and are choosing which superset to generate and filter.

## Key concepts

### The axiomatic generation problem (Ch 17)

The Hamming sequence is defined by axioms: 1 is in it, and if x is in it then so are 2x, 3x, 5x, and nothing else is. The output invariant is P0(n, q): array q holds the first n values in increasing order. The whole derivation hinges on one argument: the next value xnext is the smallest value greater than q.high (the current maximum) of the form 2x, 3x, or 5x with x in the sequence. Since those functions all exceed their argument, that x must be smaller than xnext, and it cannot lie strictly between q.high and xnext (that would contradict minimality of xnext), so x is already in q. The next output is therefore always computable from the outputs so far. This is why the loop is seeded with n = 1 rather than n = 0: q.high must be defined for the argument to work.

Note the generalization at the chapter's end: the method works for any monotonically increasing functions f, g, h with f(x) > x. If nothing were known about the functions, the problem would be unsolvable. Knowing exactly which properties your derivation used tells you how far the code generalizes.

### Search for the Small Superset

The straightforward candidate set qq (every multiple 2x, 3x, 5x exceeding q.high, for every x in q) is correct but expensive to maintain in order. The insight is that a much smaller set of three candidates suffices: x2, x3, x5, where x2 is the least multiple of 2 by an element of q that exceeds q.high, and similarly for 3 and 5. Dijkstra names the general principle: when generating set A without a direct successor function, generate a superset B and filter, but insist that (1) B is cheap to generate, (2) the membership test is cheap, especially on rejection, and (3) B is not unnecessarily large. The trained problem solver looks for a smaller B than the obvious one before writing any code. In the pattern matcher, the obvious B is all positions 0 <= r <= M-N, and the shift table shrinks it.

### Taking a relation outside the repetitive construct

x2, x3, x5 are functions of q. Recomputing them per iteration is the nasty part, so instead the relation P1 (the three candidates are correct for the current q) is established once before the loop and re-established incrementally after each extension. Since q only grows at the top, each candidate can only need increasing, by bumping its index into q. The main loop becomes:

```
aq := (1);  i2, i3, i5 := 1, 1, 1;  x2, x3, x5 := 2, 3, 5
do aq.dom != 1000 ->
   append min(x2, x3, x5) to aq          {P0 restored}
   do x2 <= aq.high -> i2 := i2 + 1; x2 := 2 * aq(i2) od
   do x3 <= aq.high -> i3 := i3 + 1; x3 := 3 * aq(i3) od
   do x5 <= aq.high -> i5 := i5 + 1; x5 := 5 * aq(i5) od
   {P1 restored: x2 > aq.high and x3 > aq.high and x5 > aq.high}
od
```

Each of those inner loops runs zero or one times per iteration (equal candidates get skipped past, which also deduplicates values like 6 = 2*3). Dijkstra defends writing them as loops rather than if statements, and defends keeping them as three separate loops rather than one merged guarded set, because no body affects another's guard. The textual order over-specifies what could happen concurrently, a normal feature of sequential programs.

### Pattern matching without re-reading input (Ch 18)

Count occurrences of pattern p(0..N-1) in text x(0..M-1). Postcondition R: count = (N i: 0 <= i <= M-N: match(i)), where match(i) says the pattern matches at position i (defined false outside the legal range purely for convenience, so one inequality ends the loop). Invariant P1: count = (N i: 0 <= i < r: match(i)) and r >= 0, trivially established by count, r := 0, 0. Increasing r by 1 each time gives the obvious M*N algorithm.

The improvement takes a second relation outside the loop. P2: (A j: 0 <= j < k: p(j) = x(r+j)) and 0 <= k <= N, records a partial match of length k at position r. The scan step extends k while it can:

```
do k != N cand p(k) = x(r + k) -> k := k + 1 od
```

After it stops, match(r) = (k = N). The key question is how far r may then jump using only knowledge of the pattern. Define dif(i, k) = (E j: 0 <= j < k-i: p(j) != p(i+j)), a statement about p alone. If dif(i, k) holds, then P2 forces non match(r+i): the text characters there are already known through the pattern. So r can jump by d(k), the minimum i > 0 with dif(i, k) false, and because d(k) is a self-overlap of the pattern, the assignment r, k := r+d(k), k-d(k) preserves both P1 and P2. No text character is ever examined twice. The three-way choice: k = N (count and shift), 0 < k < N (shift), k = 0 (advance by 1). This is the KMP failure function derived from invariants rather than from automata.

The table d depends only on p, so it is initialized once by matching the pattern against itself. Monotonicity of d(k) in k (proved by weakening the defining universal quantification) means increasing i-values are tried in order and each is recorded as d(k) for a whole run of k-values, giving a linear-time table build. Total running time proportional to M+N.

### Two squares as a two pointer scan (Ch 19)

Generate all pairs x >= y >= 0 with x*x + y*y = r, in increasing x. Invariant P1: arrays xv, yv hold exactly the solutions with x-component below the current x, with xv increasing and yv decreasing. Starting x is the least value with 2*x*x >= r (any solution has 2*x*x >= r since x >= y), and P1 and x*x > r implies all solutions are recorded, so the loop runs while x*x <= r. The inner relation P2: x*x + (y+1)*(y+1) > r pins y to the largest candidate for the current x, reached by decrementing y while x*x + y*y > r. Then x*x + y*y = r means a solution, and x*x + y*y < r means no y completes this x. Either way x increases.

The efficiency step: increasing x does not destroy P2, so P2 too is taken outside the outer loop, and y never resets. Feijen's final program:

```
x, y := 0, 0
do x*x + y*y < r -> x, y := x + 1, y + 1 od   {now 2*x*x >= r, x = y}
xv, yv := empty, empty
do x*x <= r ->
   do x*x + y*y > r -> y := y - 1 od
   if x*x + y*y = r -> append (x, y); x := x + 1
   [] x*x + y*y < r -> x := x + 1
   fi
od
```

x only rises, y only falls, so the whole search is linear in sqrt(r). Dijkstra names both strategies explicitly: shrinking the candidate y-set is a Search for the Small Superset, implemented by taking relation P2 outside the loop. He also remarks this version is distinctly superior to his own program of a few years earlier, whose completeness argument "always required a drawing".

## Derivation playbook

1. Write the postcondition as a counted or ordered set of solutions (P0 for Hamming, R for matching, P1 for squares).
2. Weaken it into an invariant by replacing a constant bound with a variable (first n values, positions below r, solutions with x-component below x).
3. Ask what the loop body recomputes from scratch. If its inputs change slowly, name the derived value, state its defining relation (P1 with x2, x3, x5 in Ch 17, P2 with k in Ch 18, P2 with y in Ch 19), establish it before the loop, and re-establish it incrementally after each change.
4. Ask whether the candidate set being scanned is larger than necessary, and prove a smaller superset still contains every answer (three candidates instead of qq, jumps of d(k) instead of steps of 1, a never-resetting y).
5. Termination: each iteration strictly grows the output or strictly advances a bounded monotone quantity (n up to 1000, r+k never decreasing and bounded, x up while y only falls).

## Applying it in modern code

- Hamming's structure is the standard "ugly numbers" merge: one output list, one lazy index plus cached candidate per generating function. It beats a heap-of-candidates solution precisely because the superset is smaller. Duplicates disappear because every candidate loop uses <= against the new maximum.
- The `r, k := r + d(k), k - d(k)` step is the KMP failure jump. When you use a library string search, this chapter is why it is linear. When you hand-roll scanning code (log parsers, protocol framing), the lesson is: after a partial match fails, reuse what the partial match told you instead of restarting.
- Two pointer algorithms (pair sums in a sorted array, sliding windows) are all instances of taking an inner relation outside the outer loop. The justification is always the same sentence: advancing the outer variable does not destroy the inner invariant.
- Incremental recomputation shows up as memoized aggregates, materialized views, dirty flags, and streaming statistics. State the relation that the cache must satisfy as an assertion, and update the cache at exactly the points where the underlying state changes.
- Write the invariants as comments or assertions at the loop head, e.g. `# x2 is the least 2*aq[i] > aq[-1]`, and assert them after the update block in tests.
- Do not merge independent update loops just to look clever. Three small loops whose guards do not interact are easier to prove and to parallelize than one fused loop.

## Pitfalls

- Maintaining the obvious candidate set (all future multiples, all positions, all y for each x) when a provably sufficient smaller set exists. Correct, but the cost is the difference between quadratic and linear.
- Recomputing a derived value inside the loop "to be safe" instead of proving the incremental update preserves its defining relation. If you cannot state the relation, the cache is a bug waiting to happen.
- Seeding the Hamming-style loop with an empty output. The minimality argument needs q.high to exist, so start with the axiom-1 element already placed.
- Forgetting why the jump d(k) is sound: it must be a fact about the pattern alone (dif is quantified over p only). Jumping based on text characters you have not read is wrong, and jumping less than d(k) is just slow.
- Resetting the inner pointer (y in the squares program, k in the matcher) every outer iteration out of habit. Check first whether the outer step destroys the inner invariant. Often it does not.
- Generalizing generation code beyond the properties actually used. The Hamming derivation needs f(x) > x and monotonicity. Drop those and the "next value is already derivable from output so far" argument collapses.

## Cross-refs

- [[d07-array-variables]] for the array operations (hiext, dom, high, hib) these programs are written in.
- [[d08-search-permutation-flag-file-merging]] for the Linear Search Theorem used to find minimal solutions here, and the "Updating a sequential file" example revisited in Note 1.
- [[d10-prime-factor-villages-spanning-tree]] for the next batch of worked derivations reusing these strategies.
- [[d03-wp-semantics-of-the-language]] for the guarded command and invariant machinery all three derivations rest on.
