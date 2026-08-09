---
unit: "Ch 8"
slug: "d05-formal-treatment-of-small-examples"
title: "The Formal Treatment of Some Small Examples"
book: "A Discipline of Programming"
one_liner: "Dijkstra derives eight small programs from their postconditions, showing the reusable method: weaken the postcondition into an invariant, compute guards from wp, prove termination with a variant."
when_to_use: "Load when writing or reviewing any loop or branch where you want to derive the code from the spec: choosing an invariant, deriving guards, picking a loop condition, or trading time for space without breaking correctness."
topics: [program derivation, loop invariants, guard derivation, postcondition weakening, variant function, termination, integer division, integer square root, exponentiation by squaring, nondeterminacy, representational abstraction, redundant variables, separation of concerns]
key_terms: [invariant relation P, variant function t, guard, weakest precondition, temporary constants, replacing a constant by a variable, dropping a conjunct, redundant variable, representational abstraction, cand, "Dijkstra's Law"]
related: [d03-wp-semantics-of-the-language, d04-termination-and-euclid, d06-nondeterminacy-and-scope, d07-array-variables, d08-search-permutation-flag-file-merging]
---

# The Formal Treatment of Some Small Examples

How to derive a program from its postcondition instead of guessing code and checking it afterwards. **Source:** A Discipline of Programming, Ch 8.

## TLDR

- Start from the postcondition R. The program is calculated backwards from R, not invented forwards. Next to nothing is left to invention.
- For an alternative construct, "push the postcondition through the alternatives": for each candidate assignment, compute R with the assignment substituted in, simplify, and the result is that branch's guard.
- For a loop, choose an invariant P by weakening R so that (P and not BB) => R. The two standard weakening moves are: replace a constant by a fresh variable with a restricted range, or drop one conjunct of R.
- Derive each loop-body guard by computing wp(body, P) and taking as guard exactly the part not already implied by P and the loop condition.
- Prove termination with an integer variant t, bounded below, that every guarded command decreases. Formally: if (P and BB) => wp(IF, P) and (P and BB) => wdec(IF, t), then the whole DO decreases t whenever it executes at least one command.
- Choose guards as weak as possible. Prefer loop guard `j != n` over `j < n`: it lets you conclude j = n on exit without appealing to P, and an overshoot bug then loops forever instead of terminating silently with a wrong answer.
- Efficiency comes after correctness, by the orderly move of adding a redundant variable whose defining relation (e.g. max = f(k)) is added to the invariant and maintained by explicit assignment. A mess is never defensible by appeal to efficiency.
- Abstract variables can be represented by concrete ones under a nontrivial convention (representational abstraction). A change of representation that is a no-op abstractly can turn an O(Y) algorithm into an O(log Y) one.

## When to reach for this

- You are writing a loop and do not know what condition to keep true, what the loop test should be, or how to argue it stops.
- You have a correct but slow loop and want to cache a repeated computation without risking correctness: extend the invariant with `cache = f(state)`.
- You are choosing between `!=` and `<` as a loop condition, or between overlapping branch conditions.
- You need to argue that a piece of branching code cannot abort: show the disjunction of the guards is true under the precondition.
- You are replacing an expensive operation (squaring, exponentiation) by cheap incremental updates and need a systematic way to do it.

## Key concepts

### Fixed inputs as temporary constants

"For fixed x, y" means: any postcondition x = x0 and y = y0 must yield a precondition implying the same. Guaranteed mechanically by never letting those names appear on the left of an assignment. In modern terms: inputs the spec quantifies over are immutable in the program.

### Deriving guards from the postcondition (max of two)

To establish R(m): (m = x or m = y) and m >= x and m >= y, only `m := x` or `m := y` can work. Substitute each into R: R(x) simplifies to x >= y, R(y) to y >= x. Those simplified conditions are the guards:

```
if x >= y -> m := x  []  y >= x -> m := y  fi
```

Since (x >= y or y >= x) is true, no abortion. Since both can hold at once (x = y), the program is nondeterministic, and that is fine because the derivation shows the choice does not matter. The derivation is also an existence proof that a suitable m exists.

### Choosing the invariant by weakening R

A loop is needed exactly when R cannot be reached in a bounded number of steps for all inputs. Then look for P with: P cheap to establish, and (P and not BB) => R. P must be weaker than R, a generalization of the final state. Three standard moves:

1. Replace a constant by a variable, with a restricted range. Maximum-position example: R says k is best over [0, n). Replace n by j, add 0 < j <= n, get P: 0 <= k < j <= n and f(k) >= f(i) for all i in [0, j). Then (k, j) := (0, 1) establishes P and (P and j = n) => R.
2. Drop a conjunct. Remainder example: R: 0 <= r < d and d | (a-r). Drop r < d, keep P: 0 <= r and d | (a-r), established by r := a. Square-root example: R: a^2 <= n and (a+1)^2 > n, keep P: a^2 <= n, established by a := 0.
3. Introduce a fresh variable to replace part of R. Square root again: P: a^2 <= n < b^2 and 0 <= a < b gives (P and a+1 = b) => R, and yields binary search.

### Deriving the loop body

Pick the variant t first (n-j, or r, or b-a-1), decide the step that decreases it (j := j+1, r := r-d), then compute wp(step, P). Whatever part of wp is not implied by (P and guard-so-far) becomes an extra guard. In the maximum example, wp("j := j+1", P) needs f(k) >= f(j), so that becomes the guard of one alternative. That alone risks abortion when f(k) < f(j), so find a command that makes progress in that case too: wp("k, j := j, j+1", P) is implied by P and f(k) <= f(j). Two overlapping guards, no abortion, harmless nondeterminacy (any maximizing k may be delivered).

### Weak guards and robustness

Prefer `j != n` to `j < n`. First, on exit `not BB` gives j = n directly. Second, termination then depends on part of the invariant (j <= n): if a bug ever pushes j past n, the `!=` version fails to terminate (an alarm), while the `<` version terminates having established nothing. Moral, in Dijkstra's words: "we should choose our guards as weak as possible."

### Separation of concerns: correctness, then efficiency

The mathematically derived maximum program recomputes f(k) constantly. The orderly fix is a redundant variable: add `max = f(k)` to the invariant, assign to max wherever k changes. Repeat for `h = f(j)`, noting h's relation can only be re-established inside the loop where j != n guarantees f(j) is defined. Efficiency work never justifies mess, and while trading space for time you must still understand the problem well enough to judge whether the change helps.

### Representational abstraction

Write the algorithm over abstract variables, then represent them. Exponentiation: invariant h * z = X^Y with h "squeezed" to 1. Represent h as x^y. Since the representation is not unique, you may rewrite it: if y is even, (x, y) := (x*x, y/2) leaves h unchanged. Inserting this abstract no-op turns the O(Y) loop into O(log Y) binary exponentiation. In the square-root example the transformation p = a*c, q = c^2, r = n-a^2 eliminates squaring entirely: redundancy in the representation buys both time and operations you do not have. Dijkstra notes this discovery undercuts the classic argument that the known exponentiation program needs "intermediate exits".

### Guards from termination alone (sorting four values)

To sort (q1..q4), take the invariant "the qs are a permutation of the inputs" (kept by any swap) and use guards q1 > q2, q2 > q3, q3 > q4 with swap bodies. No guard can ever destroy P, so the guards are dictated purely by termination: on exit not BB is exactly sortedness, and the variant is the number of inversions. Extra alternatives (swap q1, q3 when q1 > q3) may be added but cannot replace the given three.

### Early exit by weakening the exit condition

The allsix accumulator loop (allsix := allsix and f(j) = 6) is correct with guard j != n, but (P and (j = n or not allsix)) => R holds too, so the stronger guard "j != n and allsix" stops as soon as the answer is known. A `cand` (conditional and) handles guards whose right operand is undefined outside the range, as in `j != n cand f(j) = 6`.

## The formal apparatus

Loop schema. Find P, t such that:

1. init establishes P.
2. (P and B_i) => wp(S_i, P) for each guarded command (P is invariant).
3. (P and not BB) => R (exit implies the goal).
4. P => t >= 0, and (P and B_i) => wdec(S_i, t) (each step strictly decreases the bounded variant).

Theorem (loop decreases t). With (P and BB) => wp(IF, P) and (P and BB) => wdec(IF, t), then for all t0: (P and BB and wp(DO, T) and t <= t0) => wp(DO, t < t0). In words: if every selected command effectively decreases t, the whole repetitive construct effectively decreases t whenever it terminates after at least one step. Proved by induction over H_k, the k-step termination predicates.

Guard derivation rule. Given intended command S, compute wp(S, P). Split it into the part implied by P (plus the loop condition) and the rest. The rest is the guard.

Non-abortion rule. An alternative construct aborts when all guards are false, so prove (precondition) => (B_1 or ... or B_n). In the binary-search square root, requiring not (a+d)^2 <= n to imply (b-d)^2 > n forces 2*d <= b-a, giving an upper bound on the step size, and speed argues for the largest allowed d = (b-a) div 2.

Dijkstra's Law (heuristic). Of successive loops at the same level, later ones tend to need more elaborate guarded commands, because each loop adds its "and not BB" to what must now be kept invariant.

## Derivation playbook

1. Write R precisely, marking fixed inputs as temporary constants (never assigned).
2. If R is reachable in one bounded step, push R through candidate assignments: guard_i = R with assignment_i substituted, simplified. Check the guards' disjunction is true under the precondition.
3. Otherwise weaken R into P: replace a constant by a variable with restricted range, drop a conjunct, or introduce a variable replacing part of R. Check (P and chosen-exit-negation) => R and that P has a trivial initialization.
4. Pick variant t with P => t >= 0. Choose the step by how t decreases.
5. Compute wp(step, P). The unimplied residue is the guard. If the guards can all be false, add commands for the missing cases and rederive.
6. Prefer the weakest exit-detecting guard (`!=` over `<`).
7. Only then optimize: add redundant variables with their defining relations conjoined to P, or change representation of abstract variables, and recheck P after every change.

Worked examples in one line each (problem, invariant, variant):

- Max of two: no loop, guards x >= y and y >= x from R.
- Position of maximum: P: k best on [0, j), 0 < j <= n. t = n-j.
- Remainder and quotient: P: 0 <= r and d | (a-r) (and a = d*q + r). t = r. Speedup: an inner loop grows a step dd by doubling (d, 2d, 4d, ...), P extended with d | dd and dd >= d. A further variant restricts dd to d * 3^i when multiply and divide by 3 are cheap.
- Sort four: P: permutation of inputs. t = number of inversions. Guards from termination alone.
- Square root: linear, P: a^2 <= n, t = n-a^2. Binary, P: a^2 <= n < b^2, t = b-a-1, step d = (b-a) div 2. Power-of-two width c, then the (p, q, r) representation without squaring.
- Exponentiation: P: h * z = X^Y with h = x^y. t = y. Even-y squaring step is an abstract no-op, gives O(log Y).
- All values equal 6: P: allsix correct on [0, j). Early exit by weakening the exit condition to (j = n or not allsix).
- Alphabetic index of a permutation via cardswaps: layered invariants P1: index = s and 0 <= s <= r, P2: k! | s and r < s + k! (rightmost k cards sorted, leftmost n-k final), P3: kfac = k!. Progress in minor steps of k!, each realized by one cardswap.

## Applying it in modern code

- Guarded alternatives become if/else if chains. When guards overlap, the derivation proves either branch is correct, so pick any order and note that the order is arbitrary.
- State the invariant as a comment above the `while`, and assert it: on entry, at the top of each iteration (debug builds), and at exit together with the negated condition. The pair (invariant, not condition) should visibly imply the postcondition.
- Prefer `while (j != n)` to `while (j < n)` when the invariant guarantees j <= n. Off-by-one bugs then hang loudly instead of returning quietly wrong results. Where a hang is unacceptable, keep `!=` and add an assertion j <= n.
- Cache expensive calls the disciplined way: introduce the cached variable, write its defining relation into the invariant comment, and update it at exactly the assignments that change its inputs. This is the derivation-level view of memoization and incremental computation.
- wp thinking gives test oracles: for each branch, the substituted-and-simplified postcondition is a property the branch must satisfy. Property-based tests can check (P and not condition) => R directly on loop exit.
- Make variant functions explicit in review: name the quantity that strictly decreases (or increases toward a bound) and check every path through the body moves it.
- Representational abstraction is today's change-of-representation refactor: keep the abstract invariant fixed, change only the mapping (track running products instead of recomputing powers), and verify each abstract operation translates to allowed concrete operations.

## Pitfalls

- Inventing the loop body first and retrofitting an invariant. The method runs the other way: P and t come from R, the body comes from wp.
- Forgetting the range restriction when replacing a constant by a variable (j <= n, 0 <= a < b). Without it, initialization may be easy but the exit implication (P and not BB) => R fails at the boundary.
- A single derived guard that can be false: the alternative construct aborts. Always check the guards' disjunction, and add commands for the uncovered case rather than widening a guard beyond what wp licenses.
- Maintaining a cached relation like h = f(j) globally when f(j) is undefined at the boundary value. Re-establish it inside the loop, after the loop condition has excluded the bad value.
- Using `<` where `!=` is available, hiding overshoot bugs behind accidental termination.
- Justifying messy optimizations by efficiency. The disciplined route (redundant variable, extended invariant) exists, so "a mess is never defensible."

## Cross-refs

- [[d03-wp-semantics-of-the-language]] for the wp definitions, IF and DO rules, and H_k machinery this chapter exercises.
- [[d04-termination-and-euclid]] for the variant-function termination technique introduced on Euclid's algorithm.
- [[d06-nondeterminacy-and-scope]] for why the overlapping guards derived here are a feature, not a bug.
- [[d07-array-variables]] for extending these derivations from scalars to arrays.
- [[d08-search-permutation-flag-file-merging]] for the next round of larger worked derivations using the same playbook.
