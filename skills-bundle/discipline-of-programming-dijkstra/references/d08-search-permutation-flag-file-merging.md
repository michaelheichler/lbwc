---
unit: "Ch 12-16"
slug: "d08-search-permutation-flag-file-merging"
title: "Linear search, next permutation, Dutch national flag, file update, merging"
book: "A Discipline of Programming"
one_liner: "Five classic problems that turn the invariant discipline into reusable design moves: the Linear Search Theorem, guard-driven loop bodies, zone partitioning, and set-theoretic merge invariants."
when_to_use: "Load when writing search loops for a min/max satisfying a predicate, in-place partitioning or three-way classification, next-permutation logic, or key-ordered merge/update of sorted streams."
topics: [linear search, next permutation, dutch national flag, three-way partition, sequential file update, merging, sorted streams, invariants, guards, sentinels, zones, case analysis, combinatorial explosion, loop design]
key_terms: [linear search theorem, established zones, guard-first design, sentinel value inf, partitioning of a set, current key, lopop, hiext]
related: [d05-formal-treatment-of-small-examples, d06-nondeterminacy-and-scope, d07-array-variables, d04-termination-and-euclid, d09-hamming-pattern-matching-two-squares]
---

# Linear search, next permutation, Dutch national flag, file update, merging

Five worked problems where a small stock of design moves (search direction from the Linear Search Theorem, zone invariants, guard-first loop bodies, sentinel-terminated merges) replaces ad hoc case analysis. **Source:** A Discipline of Programming, Ch 12-16.

## TLDR

- Linear Search Theorem: the loop `i := 0; do B(i) -> i := i + 1 od` terminates at the minimum i >= 0 with `not B(i)`, provided such an i exists. Searching upward finds the smallest witness, searching downward finds the largest. Direction of search is dictated by which extremum you want.
- Next permutation: find the split point i (max i with c(i) < c(i+1), searched downward), find the successor value j in the tail (searched downward because the tail is decreasing), swap, then reverse the tail. Guards come from mechanically negating the goal condition, which makes the program correct even with duplicate values for free.
- Dutch national flag: when you must classify elements in one pass with O(1) extra space, partition the array into a fixed number of consecutive zones, one per category, and shrink the "uninspected" zone by one element per iteration while keeping the zone invariant true.
- Choose which element to inspect by expected cost. Inspecting at the uninspected zone's boundary next to "established white" costs 2/3 swap per pebble on average versus 1 swap for the other end. Such choices are calculable, not matters of taste.
- Sequential file update (Feijen's solution): drive the loop by the guard "there is still a normal record or transaction", and let the body do exactly the work that the guard guarantees is both needed and possible, namely process all records and transactions sharing one current key.
- Merging revisited: the informal guard-first designs are justified after the fact by a set-theoretic invariant, z + (x + y) = Z with z disjoint from x and y, plus a theorem that pins down when partial results partition the answer.
- Resist combinatorial explosion. The "optimized" flag program balloons toward 12 cases. Build the straightforward version first, then let it price any refinement.

## When to reach for this

- Writing a loop that finds the first, last, smallest, or largest index satisfying a predicate, and deciding which direction to scan.
- Implementing an in-place partition into 2, 3, or 4 categories in one pass (the flag problem is the ancestor of 3-way quicksort partitioning).
- Merging or joining two key-sorted streams: file update, merge step of mergesort, set union or intersection over sorted arrays, log or ledger reconciliation.
- Implementing `next_permutation` or its predecessor variant.
- Any loop where you are tempted to enumerate cases: the chapter's uniform-treatment tricks show how to collapse them.

## Key concepts

### The Linear Search Theorem (Ch 12)

For `i := 0; do B(i) -> i := i + 1 od` the invariant is P(i): B(j) holds for all j with 0 <= j < i. It holds at i = 0 vacuously and each step extends it. Termination needs an external fact, the existence of some j >= 0 with `not B(j)`. On exit, `P(i) and not B(i)` says exactly: i is the minimum value >= 0 with `not B(i)`.

The why: scanning in increasing order converts "first found" into "smallest existing". So to compute a minimum satisfying value, scan upward from the lower bound. To compute a maximum, scan downward. The generalized form `x := xnought; do B(x) -> x := F(x) od` searches the orbit x0, F(x0), F(F(x0)), ... for the first element where B fails. Simple, but Dijkstra calls out its "significant heuristic value": it settles search direction before any code is written.

### Next permutation (Ch 13)

Transform array c(1..n), a permutation, into its immediate alphabetic (lexicographic) successor. Structure: determine i, determine j, swap, sort the tail.

- i is the maximum index with c(i) < c(i+1). Maximum wanted, so search downward: `i := n-1; do c(i) >= c(i+1) -> i := i-1 od`.
- j is the index in the tail whose value is the smallest value exceeding c(i). The tail is monotonically decreasing (by how i was chosen), so the smallest qualifying value sits at the largest qualifying index: search downward with `j := n; do c(j) <= c(i) -> j := j-1 od`.
- `swap(i, j)` preserves the tail's monotonic decrease (worth proving), so "sort the tail" reduces to reversing it with two converging indices.

Two instructive remarks. First, the guards with equality included (`>=`, `<=`) come from mechanically negating the goal conditions c(i) < c(i+1) and c(j) > c(i), and precisely because of that the program also works when values repeat. Hand-tightened guards (`>`, `<`) to "save a comparison" break the duplicate case. Second, the tempting formulation `j := i+1; do c(j+1) > c(i) -> j := j+1 od` looks safer ("only advance after checking") but scans in the wrong direction for this goal and can stop at the wrong element, the standing error of programmers unaware of the theorem.

### Dutch national flag (Ch 14)

N buckets each hold one pebble, colored red, white, or blue. Rearrange into red, white, blue order under three constraints: handle any degenerate input (missing colors, N = 0), O(1) extra storage (no arrays), and inspect each pebble's color at most once.

Because inspection is one-at-a-time and single-look, mid-computation there are four categories: established red (ER), established white (EW), established blue (EB), and uninspected (X). With no array to record "who is what", the categories must occupy consecutive zones. Four zones minimum, so try four. Symmetry argues against the naive order ER, EW, EB, X: if ER belongs at the low end, EB belongs at the high end, leaving EW and X in the middle in either order, for instance ER, X, EW, EB.

That "general situation" solves the problem, because both the initial state (everything in X) and the final state (X empty) are special cases of it. Three integer boundary markers r, w, b encode the zones: buckets below r are ER, from r up to w are X, above w up to b are EW, above b are EB. Initialize r, w, b := 1, N, N and repeat while w >= r.

How much work per iteration? Shrink X by one, for three general reasons: (1) it suffices, (2) the guard w >= r only guarantees one uninspected bucket, and (3) inspecting k pebbles multiplies the cases to handle (one pebble gives 3 cases, two give 9), and case multiplication is "a heavy price". Which pebble? Not arbitrary: with equal color probabilities, inspecting at the low end costs on average 1 swap, at the high end (bucket w) only 2/3. So inspect buck(w) and dispatch on its color: red swaps to position r and increments r, white just decrements w, blue swaps with b and decrements both w and b. The alternative construct aborts on any fourth color, a free robustness check.

The chapter then deliberately develops a "refined" version (skip runs of red at the low end, runs of white at the high end) far enough to show it sliding toward a dozen cases before a uniform trick (place the w-pebble first, leaving the r-pebble in the new w slot so one construct handles all colr cases) rescues it. The message: avoid combinatorial explosion "like the plague", and never attempt the refined solution before the straightforward one exists to compete against.

### Updating a sequential file (Ch 15)

The classic business batch job: oldfile is a key-sorted sequence of records, transfile a key-sorted sequence of transactions (update, delete, insert), each file closed by an abnormal sentinel whose key equals a constant inf. Produce newfile by applying transactions to matching records, with per-key semantics (upd and del need an existing record, ins needs none, mismatches emit an error message). Flowchart and decision-table solutions of this problem were notoriously tangled. Feijen's solution is short because it reuses the flag problem's reasoning.

Hold one lookahead record x and one lookahead transaction y (obtained by lopop from each file). Loop guard: `x.norm or y.norm`, that is, some real input remains. The synchronization question (advance per old record? per transaction? per new record?) has no safe single answer, since any one stream can be exhausted. The resolution, same as the flag problem: the guarded statement does exactly as much as needs to be done and can be done when the guard is true. The guard guarantees at least one key below inf among the unprocessed inputs, so the body processes everything with that one key:

1. Alternative construct: ckey := min(x.key, y.key). If the record supplies it, seed the work variable xx with x and pop the next record, else set xx abnormal (no existing record for this key).
2. Repetitive construct: while y.key = ckey, apply y to xx (update, delete, insert, or error message depending on y's kind and xx.norm), popping transactions. All transaction-kind case analysis is concentrated here.
3. Alternative construct: if xx ended normal, hiext it onto newfile, else skip.

A coda appends the abnormal sentinel to newfile. The sentinel convention (abnormal value inside type record, with x.norm) exists precisely so every variable can be initialized with a meaningful value, avoiding the "conditionally significant" paired-variable pattern (xx plus a separate xxnorm flag) that clashes with explicit initialization.

### Merging problems revisited (Ch 16)

Chapters 14 and 15 argued guard-first, the classical direction, without ever stating an invariant. Chapter 16 pays the debt for the merge pattern. To compute Z = X + Y (set union) element by element, partition each set into a processed and an unprocessed part: X = x1 (+) x2, Y = y1 (+) y2, Z = z1 (+) z2, where (+) means disjoint union. The theorem: given z1 = x1 + y1 and z2 = x2 + y2, the pair (z1, z2) partitions Z if and only if x1 * y2 = 0 and y1 * x2 = 0 (with * intersection, 0 the empty set). Sufficient in practice: z1 * x2 = 0 and z1 * y2 = 0, i.e. nothing already emitted may still occur in either unprocessed remainder.

Identify z with z1, x with x2, y with y2. The invariant becomes P: z + (x + y) = Z, trivially established by z, x, y := 0, X, Y, and together with x + y = 0 it implies the postcondition z = Z. So the loop is `do x /= 0 or y /= 0 -> transfer an element from (x + y) to z od`.

Represent each set as a monotonically increasing array closed by the sentinel inf. Then min(ax.low, ay.low) is an element of the union whose membership in x, y, or both is decided by one comparison, and removing it (lorem) preserves sortedness. Emitting only via hiext with strictly larger values keeps az sorted, satisfying the disjointness invariant automatically: everything emitted is smaller than everything remaining. The three-way alternative (ax.low less, greater, or equal to ay.low) emits and pops accordingly, and the equal branch pops both, which is why the output is a set even when an element occurs in both inputs. The chapter closes with a fully formal wp treatment of the transfer step, deriving the guard "e in x and e not in y" for the branch that moves e from x alone, and notes that whether one prefers the informal or the formal account "will depend as much on his needs as on his mood".

## Derivation playbook

1. State what extremum you need (min or max index, smallest exceeding value). The Linear Search Theorem fixes the scan direction: upward for minima, downward for maxima. Write the guard by mechanically negating the goal predicate, keeping equality where negation puts it.
2. For one-pass classification: enumerate the categories that exist mid-computation (including "not yet inspected"), assign each a consecutive zone, pick the zone order by symmetry, and encode boundaries in a few index variables. Invariant: the zone meaning of every index range. Variant: size of the uninspected zone. Guard: uninspected zone nonempty.
3. Decide the step size by three tests: is one unit sufficient, is one unit all the guard guarantees, and does a bigger step multiply cases?
4. When streams can independently run dry, do not synchronize the loop with either stream. Guard on "any real input remains" and let the body consume exactly one key-group across all streams.
5. For merges, the invariant schema is: emitted + remaining = target, emitted disjoint from remaining, and (with sorted streams) everything emitted below everything remaining. Sentinels (inf) keep "front of stream" defined even for empty streams.

## Applying it in modern code

- `while predicate(i): i += 1` returning the first failure index is the Linear Search Theorem. Comment the loop with its exit fact: "i is the least index with not predicate(i)". Scan direction is a correctness decision, record it.
- C++ `std::next_permutation` is exactly Ch 13's algorithm. If you must hand-roll it (or the predecessor variant), keep the >= / <= guards so duplicates work.
- Dutch national flag is the standard three-way partition (used in 3-way quicksort and in "sort colors" interview problems): pointers lo, mid, hi, examine a[mid] or a[hi], swap into zones. The zone invariant belongs in a comment or assertion at the top of the loop body.
- Feijen's file update is the template for merge-joins, batch reconciliation, and CRDT-ish log application: lookahead value per stream, loop while any stream has data, process one whole key-group per iteration. Group-per-iteration keeps the transaction case analysis in one place.
- Use sentinels (or Option types with a max ordering) so "peek at the front" is total even on empty streams, which deletes a whole family of emptiness cases from the merge body.
- When reviewing "optimized" variants, apply the pricing rule: implement the simple version first, measure, and treat every added case in the refined version as cost that the measured gain must pay for.

## Pitfalls

- Scanning in the convenient direction instead of the direction the sought extremum requires. The "check before advancing" formulation of determine-j looks defensive but finds the wrong element.
- Tightening guards by dropping equality "to save a comparison": the mechanically negated guards are what make next-permutation handle duplicates.
- Choosing zone order or inspection side by habit (reading direction) rather than by symmetry and expected swap count.
- Synchronizing a merge loop with one input stream. Any stream can be exhausted while work remains, so the loop must be guarded on the union of remaining work.
- Letting per-iteration work grow "for efficiency" and inheriting a combinatorial explosion of cases. Case multiplication lengthens the text, can hurt efficiency, and reliably hurts reliability.
- Paired "value plus validity flag" variables with conditionally significant values, where a sentinel-bearing type would let every variable be initialized meaningfully.

## Cross-refs

- [[d05-formal-treatment-of-small-examples]] for the invariant-first derivation style that Ch 14-15 deliberately invert and Ch 16 reconciles.
- [[d07-array-variables]] for the array operations used throughout (swap, lopop, lorem, hiext, lob, hib, dom).
- [[d04-termination-and-euclid]] for the variant-function termination argument the Linear Search Theorem leans on.
- [[d06-nondeterminacy-and-scope]] for guarded alternative constructs, abortion on no true guard (the green-pebble robustness), and the block/scope notation (glovar, privar, vir).
- [[d09-hamming-pattern-matching-two-squares]] for the next problems that reuse these searching and merging moves.
