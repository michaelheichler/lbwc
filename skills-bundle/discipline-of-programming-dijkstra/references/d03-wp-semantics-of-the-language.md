---
unit: "Ch 4-5"
slug: "d03-wp-semantics-of-the-language"
title: "wp semantics of the guarded command language"
book: "A Discipline of Programming"
one_liner: "Defines the whole language (skip, abort, assignment, semicolon, if-fi, do-od) by giving each construct a weakest-precondition rule, then proves the two theorems that make correctness arguments for alternatives and loops practical."
when_to_use: "Load when reasoning formally about what a statement, conditional, or loop guarantees, when writing or checking a loop invariant, or when translating guarded-command reasoning into if/while code."
topics: [weakest precondition, predicate transformer, skip, abort, assignment, substitution, sequential composition, guarded commands, alternative construct, repetitive construct, nondeterminacy, loop invariant, invariance theorem]
key_terms: [wp, skip, abort, assignment statement, concurrent assignment, cand, semicolon composition, guard, guarded command, if-fi, do-od, BB, Hk(R), basic theorem for the alternative construct, fundamental invariance theorem for loops]
related: [d02-states-and-semantic-characterization, d04-termination-and-euclid, d05-formal-treatment-of-small-examples, d06-nondeterminacy-and-scope]
---

# wp semantics of the guarded command language

How each construct of Dijkstra's mini-language is defined by its predicate transformer, and the two theorems that turn those definitions into a working proof method. **Source:** A Discipline of Programming, Ch 4-5.

## TLDR

- A program text plays two roles: executable code for a machine, and a recipe for building the predicate transformer wp(S, R). A language is well defined when its rules assign a transformer to every program.
- `skip` is the identity: wp(skip, R) = R. `abort` is the everywhere-failing statement: wp(abort, R) = F.
- Assignment is substitution: wp("x := E", R) = R with every occurrence of x replaced by E (guarded by "E is defined" when E is partial).
- The semicolon is functional composition: wp("S1; S2", R) = wp(S1, wp(S2, R)). It is associative, so statement lists need no parentheses.
- A guarded command `B -> SL` runs SL only when guard B holds. `if ... fi` picks any alternative with a true guard and aborts if none is true. `do ... od` keeps picking while some guard is true and terminates cleanly when all are false.
- Basic theorem for the alternative construct: if Q implies some guard is true, and Q with each guard implies wp of that branch, then Q => wp(IF, R). This is how you prove an if without enumerating states.
- Fundamental invariance theorem for loops: if (P and BB) => wp(IF, P), then (P and wp(DO, T)) => wp(DO, P and non BB). An invariant preserved by every guarded branch holds at exit, together with the negation of all guards, provided the loop terminates at all.
- The loop theorem never mentions how many iterations run, which is exactly why it works when the iteration count depends on the input.

## When to reach for this

- You need the exact guarantee of a statement sequence, conditional, or loop, not a hand-wave, for a review, a proof comment, or a tricky bug.
- You are writing a nontrivial loop and want the invariant-plus-exit-condition argument that its result is right.
- You are checking that an if/elif chain handles every input, or deciding whether a missing else is a silent skip or a missing abort.
- You want to derive the precondition a caller must establish, by pushing a postcondition backward through assignments.

## Key concepts

### The program text as a code for a predicate transformer

Ch 4 opens by flipping the usual view. A program is not primarily instructions for a machine, it is a notation from which you can construct the function wp(S, .) that maps any desired postcondition R to the weakest precondition guaranteeing it. The semantic definition of a language is then the set of rules for building that transformer from the text. Any construct admitted into the language must yield transformers satisfying the four healthiness properties of the previous chapter (excluded miracle, monotonicity, distribution over and, distribution over or), otherwise the "preconditions" it produces stop meaning anything.

### skip and abort

Two trivial transformers pass the test. The identity gives `skip` (the empty statement, given a real name for the same reason zero got the digit 0). The constant-F transformer gives `abort`, a statement with no valid initial state at all, even for R = T. Constant-T is forbidden by the Law of the Excluded Miracle. `abort` models failure by definition: activating it is a symptom that the program was run in a state it does not cater to.

### Assignment as backward substitution

wp("x := E", R) is R with every x replaced by E. This is the deep move of the whole calculus: assignment is understood backward, from postcondition to precondition, not forward as a state change. Examples make it concrete: wp("a := 7", a = 7) = T, wp("a := 7", a = 6) = F, wp("a := a + 1", a > 10) = (a > 9), and wp("a := 7", b = b0) = (b = b0), which encodes that assignment leaves every other variable alone. When E is a partial function of the state the rule sharpens to wp("x := E", R) = D(E) cand (R with E for x), where D(E) means "the state is in the domain of E" and `cand` is conditional conjunction, false as soon as its left operand is false regardless of whether the right one is defined.

The concurrent assignment `x1, x2 := E1, E2` substitutes simultaneously. It is what makes swap `x, y := y, x` a one-liner, it avoids over-specifying an evaluation order, and it can differ semantically from both sequential orderings when the variables and expressions interfere.

### Composition and the meaning of the semicolon

wp("S1; S2", R) = wp(S1, wp(S2, R)). The postcondition of the whole is fed to S2's transformer, and S2's weakest precondition becomes S1's postcondition, mirroring "run S1, then run S2 from S1's final state". Worked example: for the sequence

```
a := a + b
b := a * b
```

pushing a postcondition R(a, b) back through both statements gives R(a + b, (a + b) * b). Because functional composition is associative, a chain "S1; S2; S3" and any longer statement list is unambiguous without bracketing. An exercise result worth keeping: performing `x1 := E1` then `x2 := E2` is equivalent to the reverse order, and both equal the concurrent assignment, exactly when x1 does not occur in E2 and x2 does not occur in E1.

### Guarded commands and the two constructs

Sequencing alone cannot express Euclid's game, where which move fires and how many moves occur depend on the state. The fix is the guarded command `B -> SL`: statement list SL may run only from states where guard B is true. A guarded command is a building block, not a statement, because the guard's truth is necessary but not sufficient, it must also be "its turn". Sets of guarded commands, separated by the bar, become statements in two ways.

`if B1 -> SL1 [] ... [] Bn -> SLn fi`: some alternative with a true guard is selected and run. Overlapping guards give nondeterminacy (harmless if each branch is correct where its guard holds). All guards false means abortion, the construct explicitly refuses states nobody claimed. `if fi` equals abort.

`do B1 -> SL1 [] ... [] Bn -> SLn od`: while some guard is true, select one true-guarded alternative, run it, re-inspect. All guards false means clean termination, so `do od` equals skip. The design rationale for both: when no single statement list works for all initial states satisfying Q, find several, each adequate on a subset, and let guards characterize the subsets so that Q implies at least one guard.

### Why the two theorems matter

The wp definitions are exact but clumsy to apply directly, especially wp(DO, R), which is a quantification over iteration bounds. Ch 5 supplies sufficient conditions that are checkable branch by branch. The loop theorem is the heart of the entire book's method: it separates partial correctness (the invariant argument) from termination (wp(DO, T), handled by variant functions in the next chapter), and it never mentions the iteration count, so it applies when that count is input-dependent or even nondeterministic.

## The formal apparatus

Notation: BB = (E j: 1 <= j <= n: Bj), "some guard is true". (E ...) is existential, (A ...) universal quantification.

Statement semantics:

- wp(skip, R) = R
- wp(abort, R) = F
- wp("x := E", R) = D(E) cand R[E/x]   (R with E substituted for x, D(E) often T and omitted)
- wp("S1; S2", R) = wp(S1, wp(S2, R))
- wp(IF, R) = BB and (A j: 1 <= j <= n: Bj => wp(SLj, R)), for IF = if B1 -> SL1 [] ... [] Bn -> SLn fi, assuming all guards total.
- For DO with the same guarded command set:
  - H0(R) = R and non BB
  - Hk(R) = wp(IF, Hk-1(R)) or H0(R), for k > 0
  - wp(DO, R) = (E k: k >= 0: Hk(R))
  Hk(R) reads: termination in at most k selections, ending in a state satisfying R.

Basic theorem for the alternative construct. If for all states
1. Q => BB, and
2. (A j: (Q and Bj) => wp(SLj, R)),
then Q => wp(IF, R). Special case n = 2 with B2 = non B1: BB = T, condition 1 is free, and the rule reduces to Hoare's if-then-else rule, so only condition 2 is needed.

Bridge to the loop theorem. Take R = P and Q = (P and BB). Condition 1 holds automatically and condition 2 becomes (A j: (P and Bj) => wp(SLj, P)), giving

(P and BB) => wp(IF, P)    (each guarded branch preserves P)

Fundamental invariance theorem for loops. If (P and BB) => wp(IF, P) for all states, then

(P and wp(DO, T)) => wp(DO, P and non BB)

In words: if P holds initially and the loop terminates, it terminates in a state satisfying P and non BB. Proof skeleton: show by induction on k that (P and Hk(T)) => Hk(P and non BB), using the Hk recurrences, the fact that wp(IF, X) => BB, the antecedent, and the and-distribution and monotonicity properties of transformers, then take the union over k.

## Applying it in modern code

- Read `if ... fi` as an if/elif chain plus a mandatory final `else: raise`. Dijkstra's construct aborts when no guard holds. A silent fall-through in your code is a `skip` you chose by omission, make that choice explicit.
- `do ... od` is a while loop whose condition is "some guard true". A multi-guard loop becomes `while b1 or b2:` with an if/elif body dispatching on the guards, and the theorem tells you what you know at exit: invariant and not b1 and not b2.
- Use the loop theorem as a checklist for every nontrivial loop: (a) invariant true before entry, (b) each branch preserves it when its guard holds, (c) invariant and negated condition imply the goal, (d) termination argued separately. Write the invariant as a comment or assert at the top of the body.
- Compute preconditions mechanically by backward substitution: to know what must hold before `x = f(x, y)` for `post(x, y)` to hold after, write `post(f(x, y), y)`. This is also how you derive test oracles and property-based-test preconditions.
- The D(E) cand clause is the formal home of "check before you use": index in range, denominator nonzero, pointer non-null. Either prove the context establishes D(E) or guard the statement.
- Prefer tuple assignment `x, y = y, x` where the language has it, it is the concurrent assignment and removes ordering bugs the exercise warns about.
- Overlapping guards are a feature: when two branches are both correct on the overlap, leaving the choice open documents that the correctness argument does not depend on it.

## Pitfalls

- Forgetting that all-guards-false aborts in if-fi. Porting guarded-command reasoning to a plain if/elif without a final else quietly changes abort into skip and hides unhandled states.
- Claiming a loop's result from the invariant alone. The theorem's consequent is gated on wp(DO, T), without a termination argument you have proved nothing about the final state.
- Choosing an invariant that the branches preserve but that, with non BB, does not imply the postcondition. Preservation is only half the obligation.
- Applying the assignment rule forward ("x becomes E, so the state changes...") instead of backward substitution into R. The forward reading invites errors when x occurs in E or in R several times.
- Ignoring D(E). Backward substitution through a partial expression (array access, division) yields a "weakest precondition" that is silently too weak.
- Reordering two assignments that share variables, or replacing a concurrent assignment by an arbitrary sequential order. The equivalence needs the non-interference condition from the exercise.

## Cross-refs

- [[d02-states-and-semantic-characterization]] for the state-space view and the four properties (excluded miracle, monotonicity, and/or distribution) every construct here must satisfy.
- [[d04-termination-and-euclid]] for the variant-function technique that discharges the wp(DO, T) obligation the loop theorem leaves open, worked on Euclid's algorithm.
- [[d05-formal-treatment-of-small-examples]] for the theorems of this unit driving full derivations of small programs.
- [[d06-nondeterminacy-and-scope]] for why the deliberate nondeterminacy of overlapping guards is kept rather than designed away.
