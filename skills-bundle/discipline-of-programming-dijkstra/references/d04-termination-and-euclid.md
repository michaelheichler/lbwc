---
unit: "Ch 6-7"
slug: "d04-termination-and-euclid"
title: "Termination proofs and Euclid derived from invariants"
book: "A Discipline of Programming"
one_liner: "How to design loops so termination is provable by construction (variant function, wdec) and how the invariant-plus-variant method derives Euclid's gcd algorithm from properties of the answer."
when_to_use: "Load when writing or reviewing a loop whose termination is not obvious, or when deriving an iterative algorithm from a specification instead of guessing it."
topics: [termination, variant function, bound function, loop invariant, wdec, guarded commands, repetitive construct, euclid, gcd, program derivation, progress, guard design, defensive precondition]
key_terms: [variant function t, wdec(S, t), tmin, invariant relation P, BB, basic theorem for repetition, guard strengthening rules, massaging the state]
related: [d03-wp-semantics-of-the-language, d05-formal-treatment-of-small-examples, d06-nondeterminacy-and-scope, d08-search-permutation-flag-file-merging]
---

# Termination proofs and Euclid derived from invariants

How to make loops terminate by design rather than by luck, and a full worked derivation of Euclid's algorithm from properties of gcd. **Source:** A Discipline of Programming, Ch 6-7.

## TLDR

- Computing wp(DO, T), the weakest precondition for termination of an arbitrary loop, is in general intractable. So do not analyze termination after the fact: design the loop so a chosen termination proof applies by construction.
- The proof recipe: keep an invariant P, and pick a variant function t, an integer function of the state, such that (P and BB) => t > 0 and every guarded command, when selected, decreases t by at least 1. Then P => wp(DO, T), and with the basic theorem for repetition, P => wp(DO, P and non BB).
- wdec(S, t) names the weakest precondition under which executing S decreases t by at least 1. It is computed from wp: solve wp(S, t <= t0) for the minimal t0 (call it tmin, a function of the state), and wdec(S, t) is then tmin <= t-1.
- The full obligation per guarded command Bj -> SLj is (P and Bj) => (wp(SLj, P) and wdec(SLj, t)). Split it into an invariance half (9a) and a progress half (9b) and handle them separately: separation of concerns.
- Guards are derived, not guessed. Start from the required implication (P and Q) => R and weaken the candidate Q using four simplification rules until it is cheaply computable. If a candidate guard collapses to false, that command is useless and is dropped.
- Danger sign: if the invariance half alone yields a Bj with P => Bj, that guard can never satisfy the progress half, since keeping P would then guarantee nontermination.
- The construction guarantees P and non BB on exit, but that may still be weaker than the desired postcondition R. If so, the problem is not solved: strengthen P, change t, or add commands.
- Euclid's algorithm falls out of this method: from four algebraic properties of GCD, the invariant GCD(X, Y) = GCD(x, y), and the variant t = x+y, the guards x > y -> x := x-y and y > x -> y := y-x are derived, with x = y forced on exit.

## When to reach for this

- You are writing a while loop whose termination argument is anything beyond "the counter obviously hits the bound", for example loops that both grow and shrink a quantity, worklist loops, or convergence loops.
- A reviewer or a proof obligation asks "why does this terminate", and you need the standard variant-function answer.
- You are deriving an iterative algorithm from properties of the desired result (gcd-like state massaging) rather than translating a known recipe.
- A loop you designed exits, but the exit condition does not imply the postcondition you actually wanted, and you need a principled way to fix it.

## Key concepts

### Design for termination, do not verify it afterwards

For an arbitrary loop, wp(DO, T) is hard or impossible to determine. Dijkstra's move is to invert the burden: choose the termination proof first (invariant plus variant function) and write the loop so that it satisfies the proof's assumptions. Termination then holds by construction, not by inspection. This is the same posture as choosing the invariant before the loop body: the proof shapes the program.

### The variant (bound) function t

t is a finite integer function of the current state. Two properties make it work. First, while the loop can still continue (P and BB), t is strictly positive, so it is bounded below. Second, every selected guarded command decreases t by at least 1. An unbounded number of iterations would drive t below any limit, contradiction, so the loop terminates. Intuition is exactly this two-line argument. The chapter also proves it formally by induction over the Hk hierarchy of wp for the loop.

### wdec: progress as a computable predicate

Progress is not hand-waved, it is a predicate computed with the same calculus as everything else. Given a statement S and the variant t, regard wp(S, t <= t0) as an equation in the free variable t0 for a fixed state, take its minimal solution tmin (the lowest upper bound on the final value of t), and define wdec(S, t) as tmin <= t-1. Now "this command makes progress" is an ordinary predicate you can prove implied by P and the guard.

### Deriving guards instead of inventing them

Each command must satisfy (P and Bj) => (wp(SLj, P) and wdec(SLj, t)). This has the shape (P and Q) => R with Q unknown, and there is a small algebra for finding a computable Q:

1. Q = R is always a solution.
2. If Q = (Q1 and Q2) works and P => Q2, drop Q2: Q1 works.
3. If Q = (Q1 or Q2) works and P => not Q2, drop Q2: Q1 works.
4. Any strengthening of a working Q works.

Two corollaries do real work. If a candidate guard simplifies to false under P, the command can never be usefully selected and is deleted from the set: the calculus itself prunes bad design ideas. And splitting the obligation into invariance (9a) and progress (9b) lets you check "does this keep P" and "does this move toward the goal" as separate questions.

### When the construction is not enough

The method guarantees the exit condition P and non BB. If that fails to imply the desired postcondition R, you have built a correct loop for the wrong problem. Chapter 7 shows this failing concretely and shows the repair moves: strengthen the invariant, and above all choose a different variant function, possibly one bounded below only thanks to the invariant.

## The formal apparatus

Setting: DO is the loop do B1 -> SL1 [] ... [] Bn -> SLn od, IF the corresponding alternative construct, BB = B1 or ... or Bn, T = true.

Termination theorem. Suppose for all states:

1. (P and BB) => wp(IF, P)                    (P is invariant)
2. (P and BB) => (t > 0)                      (t bounded below while running)
3. for any t0: (P and BB and t <= t0+1) => wp(IF, t <= t0)   (each step decreases t)

Then P => wp(DO, T), and combined with the basic theorem for repetition, P => wp(DO, P and non BB).

By the alternative-construct theorem, (3) reduces to a per-command obligation: for each j, (P and Bj and t <= t0+1) => wp(SLj, t <= t0).

wdec. Let tmin(state) be the minimal t0 solving wp(SLj, t <= t0). Then

    wdec(SLj, t) = (tmin <= t-1)

is the weakest precondition that SLj decreases t by at least 1. The full per-command obligation becomes

    (P and Bj) => (wp(SLj, P) and wdec(SLj, t))        (9)

usually split into (9a) invariance, (P and Bj) => wp(SLj, P), and (9b) progress, (P and Bj) => wdec(SLj, t).

## Derivation playbook

The Euclid derivation, as a reusable method.

1. State the postcondition via known properties of the answer. For gcd, four properties suffice for x, y not both zero: GCD is symmetric, unchanged by negating an argument, unchanged by replacing an argument with a sum or difference, and GCD(x, y) = abs(x) when x = y. Property (d) gives the exit shape, (a)-(c) give the permissible "massaging" moves.
2. Choose the invariant by generalizing the postcondition: P1 = (GCD(X, Y) = GCD(x, y)), trivially established by x, y := X, Y. Strengthen with P2 = (x > 0 and y > 0) to prune moves (negation becomes useless) and to make a variant possible.
3. Choose a variant. First attempt: t = abs(x-y), aiming straight at the exit condition x = y. Compute wdec for each candidate move. The swap x, y := y, x gives wdec = false (rejected by calculation, not taste). Additions and subtractions survive with derived guards, but the resulting guard set is incomplete: at (x, y) = (5, 7) all guards are false while x != y, so P and non BB does not imply x = y. A correct loop, wrong problem.
4. Repair: pick t = x+y, bounded below only thanks to P2. Now wdec("x := x+y", t) = (y < 0), excluded by P, so additions are rejected. wdec("x := x-y", t) = (y > 0), implied by P. The invariance half of (9) leaves the guard x > y. Result:

       x, y := X, Y;
       do x > y -> x := x-y
       [] y > x -> y := y-x
       od;
       print(x)

   When both guards are false, x = y, and property (d) delivers the answer. Two further derivable commands (x := y-x and its mirror) add nothing and are omitted.
5. Protect the domain. Called with (0, 0) the loop prints a wrong zero, with a negative argument it never ends. Wrap it in a one-alternative guard, if X > 0 and Y > 0 -> ... fi, so activation outside the domain aborts immediately instead of misbehaving. The exercises probe alternative variants (max(x, y), x + 2*y) and a four-variable version that also yields the least common multiple.

## Applying it in modern code

- For any nontrivial while loop, name the variant explicitly: a comment like "variant: hi-lo, strictly decreases each iteration, stays nonnegative while the guard holds" is the whole termination proof in two clauses.
- Assert progress in debug builds: capture t before the body, assert new_t < old_t and new_t >= 0 after. That is wdec as a runtime check.
- Worklist and fixpoint loops need composite variants (for example, lexicographic pairs or "items not yet settled"). If you cannot write down a quantity that strictly decreases and is bounded below, you do not yet know why the loop terminates.
- Derive loop conditions from the invariant and the goal rather than guessing: the exit condition should satisfy "invariant holds and no guard fires implies the postcondition". Check that implication explicitly, it is the step the Euclid first attempt failed.
- When a branch of your loop turns out never to help (its enabling condition contradicts the invariant), delete it. Dead guards are dead code with a proof attached.
- The final wrapper is input validation: reject arguments outside the loop's proven domain at the boundary (raise, abort, or refuse), instead of letting the loop misbehave quietly.

## Pitfalls

- Verifying termination after writing the loop instead of designing with a variant in mind: for arbitrary loops the question is effectively unanswerable, which is why the burden is inverted.
- Choosing a variant that a legal step can leave unchanged or increase. wdec computed honestly exposes this (the swap in Euclid gives wdec = false), hand-waving does not.
- A guard Bj with P => Bj can never make progress: if the invariant itself keeps the guard true, selecting only that command loops forever. This falls out of splitting (9a) from (9b).
- Confusing "the loop exits" with "the loop solved the problem": P and non BB may be weaker than the required postcondition. The abs(x-y) attempt terminates fine and still fails, since states like (5, 7) exit early.
- Forgetting that the variant may be bounded below only because of the invariant (t = x+y needs x, y > 0). Weaken the invariant and the termination proof silently dies.
- Shipping the algorithm without guarding its domain: gcd on (0, 0) gives a wrong answer, on negatives it diverges. Provable correctness is relative to the stated precondition.

## Cross-refs

- [[d03-wp-semantics-of-the-language]] for the wp calculus, the Hk hierarchy, and the basic theorems for IF and DO that this chapter's proof rests on.
- [[d05-formal-treatment-of-small-examples]] for the next chapter's worked derivations using the same invariant-plus-variant playbook.
- [[d06-nondeterminacy-and-scope]] for why the guard sets here are left nondeterministic rather than forced into a deterministic order.
- [[d08-search-permutation-flag-file-merging]] for larger derivations where variant choice and guard derivation carry more weight.
