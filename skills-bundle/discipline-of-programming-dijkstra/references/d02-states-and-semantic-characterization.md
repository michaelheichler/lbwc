---
unit: "Ch 2-3"
slug: "d02-states-and-semantic-characterization"
title: "States, Predicates, and Weakest Preconditions"
book: "A Discipline of Programming"
one_liner: "Program state is a point in a Cartesian-product state space, sets of states are characterized by predicates, and a program's meaning is the predicate transformer wp(S, R) mapping each postcondition to its weakest precondition."
when_to_use: "Load when reasoning about what a piece of code guarantees: choosing state representations, writing pre/postconditions or assertions, or arguing that an input set is exactly the one for which the code terminates with the right result."
topics: [state space, cartesian product, variables, predicates, conditions, free variables, weakest precondition, predicate transformer, semantics, nondeterminism, determinism, liberal precondition, termination, postcondition]
key_terms: [state space, cartesian product, predicate, condition, free variable, T and F, post-condition, weakest pre-condition, wp, predicate transformer, law of the excluded miracle, monotonicity, deterministic mechanism, nondeterministic mechanism, weakest liberal pre-condition, wlp]
related: [d01-executional-abstraction-and-languages, d03-wp-semantics-of-the-language, d04-termination-and-euclid, d06-nondeterminacy-and-scope]
---

# States, Predicates, and Weakest Preconditions

How to describe where a computation can be (state spaces, predicates) and what a mechanism means (the predicate transformer wp). **Source:** A Discipline of Programming, Ch 2-3.

## TLDR

- A variable is a thing existing in time whose value stays constant unless changed ("changeable constant" would be the honest name). A system of variables lives in a state space, one point per possible combination of values, built as the Cartesian product of the component spaces.
- Sets of states are characterized by predicates (equations over the coordinates), not by enumeration. A predicate is defined at every point of the state space and is true or false there. T holds everywhere, F nowhere. Two predicates are equal when they characterize the same set.
- How easy a set is to characterize depends on whether it matches the coordinate system. Choosing coordinates that fit the goal is a central programming decision, and often means a state space with more points than values you need (unused points must be disallowed or aliased deliberately).
- Design is goal-directed: start from the desired postcondition R on the final state, then ask which initial states guarantee it. Work backwards.
- wp(S, R) is the weakest precondition: it characterizes exactly the initial states from which activating S is certain to terminate properly in a state satisfying R. Knowing the rule R -> wp(S, R), the predicate transformer, is knowing the semantics of S.
- You rarely need wp(S, R) in closed form. A stronger P with P => wp(S, R) everywhere suffices, and proving that is usually far cheaper than computing wp explicitly.
- Every predicate transformer obeys four properties: wp(S, F) = F (no miracles), monotonicity, distribution over `and` as equality, distribution over `or` as implication only. Determinism is exactly the special case where the `or` rule tightens to equality.
- Dijkstra treats nondeterminacy as the rule and determinism as the exception, partly because "program testing can be quite effective for showing the presence of bugs, but is hopelessly inadequate for showing their absence."

## When to reach for this

- Designing a data representation: deciding which variables (coordinates) make the sets and conditions you care about easy to state, and what to do about unused or impossible states such as (Jun, 31).
- Writing the contract of a function: stating the postcondition first, then finding the precondition under which the code is guaranteed to deliver it, including termination.
- Reviewing code that claims to handle "all valid inputs": checking whether the claimed input set is (a subset of) the set from which success is certain.
- Reasoning about nondeterministic or concurrent behavior, retries, or any mechanism where the same start can lead to different runs, and you need to say what is still guaranteed.
- Deciding what a test suite can and cannot establish, and replacing "we tested it" with an argument about the set of initial states covered by a precondition.

## Key concepts

### State spaces and the Cartesian product

A ten-position wheel in an adding machine is the archetype of a variable: ten stable states, one current value. Eight wheels in a row form a register with 10^8 states, and the register's state space is the Cartesian product of the wheels' spaces. Whether you view the register as one 10^8-valued variable or eight ten-valued ones depends on your interest (the user reads the number, the repair engineer replaces a wheel). A running computation is the system traveling through its state space, the initial state is the starting point. Dijkstra works almost exclusively with Cartesian-product state spaces because they match how variables compose in programming languages, while warning they are not the answer to everything.

Why it matters: the product construction silently creates points you may never want. The (month, day) space has 372 points for at most 366 days. You must either forbid the extras (letting the representation express impossible states) or define them as aliases (for example (Jun, 31) means (Jul, 1)). Unused points are unavoidable whenever the count of values you need is, say, prime. Modern echo: "make illegal states unrepresentable" is one answer to exactly this problem.

### Predicates characterize sets of states

Descartes gives a second way to name states: instead of pointing at one, write an equation whose solution set is the states you mean. `(month = May) and (day = 11)` picks one day, `(day = 23)` picks twelve, far more compactly than a list. Equations over the coordinates are called conditions or predicates (Dijkstra declines to keep the distinction sharp). Each predicate has a truth value at every point of the space and stands for the set of points where it is true. P = Q means the same set. T is the whole space, F the empty set.

The catch: a set is only easy to characterize if it matches the coordinate system. "Days falling on the same weekday as (Jan, 1)" is awkward in (month, day) coordinates. Much of programming is choosing state spaces whose coordinates make the relevant sets cheap to state, even at the price of extra points.

### Free variables relate stages of one computation

Besides coordinates (x, y) and constants (May, 23), predicates may contain free variables, best read as unspecified constants. They tie successive states of one run together: during Euclid's algorithm started at (X, Y), every state satisfies `GCD(x, y) = GCD(X, Y) and 0 < x <= X and 0 < y <= Y`. X and Y are fixed for a given run but unspecified across runs. This is the germ of the invariant technique, and of the "old value" ghost variables in modern contract systems.

### Semantics as a predicate transformer

Dijkstra's machine model is initial state in, final state out, no input/output streams (arguments are encoded in the initial state, answers read off the final state). Design is goal-directed, so the postcondition R comes first, for the GCD machine `x = GCD(X, Y)`. Many final states may satisfy R, and then there is no reason to demand the final state be a function of the initial state. That is exactly where nondeterminism becomes useful rather than scary.

The useful question is then: from which initial states is success certain? That set is wp(S, R), the weakest precondition (weakest because weaker conditions admit more states, and we want all of them). Knowing how to derive wp(S, R) from any R is knowing everything relevant about S, and that rule, a function from predicates to predicates, is the predicate transformer. A table of (R, wp(S, R)) pairs would be unmanageable, so semantics is always given as a derivation rule. In practice we care about one designed-for R, and even then a sufficient precondition P with P => wp(S, R) usually does, provable without ever writing wp(S, R) out.

### Determinism as a special case, and liberal preconditions

A deterministic S reproduces the same happening from the same initial state. Dijkstra deliberately inverts tradition: nondeterminacy is the general case, determinism the exception where Property 4 sharpens to an equality. His motivation is autobiographical (the 1958 I/O-interrupt trauma, then "harmoniously cooperating sequential processes") and methodological: once the math handles nondeterminism, it stops being frightening and becomes a design stepping stone toward a final deterministic mechanism.

For a deterministic S, every initial state falls into exactly one of three sets: leads to R (wp(S, R)), leads to non R (wp(S, non R)), or fails to terminate (non wp(S, T)). For a nondeterministic S one initial state can admit happenings of several kinds, and full characterization needs the weakest liberal precondition wlp(S, R): it guarantees only that a wrong result will not be produced, leaving nontermination open. The three predicates wlp(S, R), wlp(S, non R), wp(S, T) carve the initial space into up to seven regions (guaranteed R, guaranteed non R, guaranteed nontermination, and four mixed ones that exist only under nondeterminism). Practical payoff of wlp: a language implementation is not proven to run every correct program correctly, one settles for "no correct program is processed incorrectly without warning."

## The formal apparatus

Notation: predicates over the state space, `P => Q for all states` means the set of P-states is a subset of the Q-states.

Definition. wp(S, R) characterizes exactly the initial states from which activation of S is certain to result in a properly terminating happening whose final state satisfies R. If the initial state does not satisfy wp(S, R), no such guarantee exists (wrong final state or no final state at all are then possible).

- wp(S, T) characterizes the initial states from which termination is certain.
- P is a sufficient precondition for S and R iff P => wp(S, R) for all states.

The four basic properties, for every mechanism S:

1. Law of the Excluded Miracle: `wp(S, F) = F`. Proof by contradiction, a state in wp(S, F) would terminate in a state satisfying F, and no state satisfies F.
2. Monotonicity: if `Q => R` for all states, then `wp(S, Q) => wp(S, R)` for all states.
3. Conjunction: `(wp(S, Q) and wp(S, R)) = wp(S, Q and R)`. Left to right because both guarantees combine, right to left from monotonicity applied to (Q and R) => Q and (Q and R) => R.
4. Disjunction: `(wp(S, Q) or wp(S, R)) => wp(S, Q or R)`. Only an implication in general. Dijkstra's counterexample to the converse: the certainty of a son is nil, of a daughter nil, of a son or a daughter absolute.

4'. For deterministic S the disjunction is an equality: `(wp(S, Q) or wp(S, R)) = wp(S, Q or R)`, because a unique final state satisfies Q or R and forces the initial state into wp(S, Q) or wp(S, R). A mechanism is deterministic iff 4' holds.

Liberal preconditions: wlp(S, R) guarantees no final state violating R, with nontermination allowed. Then `wp(S, R) = (wlp(S, R) and wp(S, T))`, `wlp(S, T) = T`, and `(wlp(S, F) and wp(S, T)) = F` (no state can guarantee both termination and nontermination).

## Applying it in modern code

- Postcondition first. Write the function's success condition before the body, then derive what the caller must guarantee. That derived precondition, not the type signature, is the real contract.
- "Properly terminating and correct" is one property. wp bundles partial correctness with termination, so a contract that is silent on termination (a wlp) is a weaker promise. Be explicit which one your docs make.
- Prefer a provable sufficient precondition over the exact weakest one. `assert n >= 0` at function entry is P => wp(S, R), cheap and checkable, even when the true weakest precondition is unprintable.
- Choose coordinates to match the sets you must characterize. If a validity check or query is awkward, that is evidence the state representation is wrong, not that you need cleverer code. Handle unused product points deliberately: forbid them (types, invariants) or define canonical aliases.
- Free variables become ghost or "old" values: capture inputs at entry (X, Y) so assertions can relate current state to them, as in `gcd(x, y) == gcd(X, Y)`.
- Property 3 licenses splitting a spec: proving wp for Q and for R separately gives Q and R together. Property 4 warns the dual is false under nondeterminism: guaranteeing "some outcome in the union" does not mean any single outcome is guaranteed, which is exactly the trap in reasoning about retries, races, and randomized code.
- Treat tests as sampling the wp(S, R) set, never as establishing it. A green suite shows some initial states behave, an argument P => wp(S, R) covers a whole set.

## Pitfalls

- Trusting reproducibility you do not have. Under concurrency, I/O, or randomness, arguing with Property 4' (deterministic case-split on outcomes) proves things that are false. Use the implication form only.
- Leaving unused state-space points undecided. If (Jun, 31) is neither forbidden nor aliased, the system can quietly contradict itself, the classic invalid-state bug.
- Confusing "will not give a wrong answer" (wlp) with "will give the right answer" (wp). Nontermination, hangs, and swallowed errors live in the gap.
- Claiming a precondition is "the" weakest without argument. Usually you have only a sufficient P. Fine, but do not advertise the guarantee for states outside P.
- Specifying by enumeration when a predicate exists, or fighting a state space whose coordinates do not match your sets. Both produce long, fragile checks in place of one equation.
- Inferring guarantees from tests. Presence of bugs, yes, absence, no.

## Cross-refs

- [[d01-executional-abstraction-and-languages]] for the cardboard GCD machine and the executional abstraction this chapter's state-space picture rests on.
- [[d03-wp-semantics-of-the-language]] where wp is defined concretely for skip, abort, assignment, composition, and the guarded command constructs.
- [[d04-termination-and-euclid]] for how wp(S, T) and variant functions turn the termination half of the guarantee into proof obligations.
- [[d06-nondeterminacy-and-scope]] for the design payoff of taking nondeterminacy as the rule rather than the exception.
